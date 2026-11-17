import AppKit
import SwiftUI
import Combine

// Discovery filters change the cards, never the user's selected publishers.
final class QuickFeedState:ObservableObject {
    let draft:PersonalFeedDraft
    private let initialPool:[FeedSource]
    private var changes:AnyCancellable?
    @Published var page = 0
    @Published var search = ""
    @Published var filters:Set<String> = []
    @Published var browseLanguage:NewsLanguage = .all
    @Published var selectedOnly = false
    @Published var visibleCount = 6
    @Published var preferredLanguage:InterfaceLanguage
    @Published var addedSources:[FeedSource] = []
    @Published var selectedURLs:Set<String> = [] {didSet{if selectedURLs.isEmpty{selectedOnly = false};synchronize()}}
    static let topicOrder = ["world","technology","ai","business","sport","moscow","science","culture","cinema","space","environment","telegram","custom"]
    init(model:AppModel,fresh:Bool) {
        draft = PersonalFeedDraft(parent:model,fresh:fresh);preferredLanguage = model.interfaceLanguage
        let old = model.tickerRows.filter{$0.channel == .content}.flatMap{$0.customFeeds}
        var seen = Set<String>()
        initialPool = (old+NewsCatalog.all.map(\.feed)+ContentPack.find("telegram").sources).filter{seen.insert($0.url).inserted}
        _selectedURLs = Published(initialValue:fresh ? [] : Set(model.requestedRowFeeds.map(\.url)))
        changes = draft.objectWillChange.sink{[weak self] _ in self?.objectWillChange.send()}
        synchronize()
    }
    var pool:[FeedSource] {var seen = Set<String>();return (initialPool+addedSources).filter{seen.insert($0.url).inserted}}
    func topic(_ feed:FeedSource)->String {let category = NewsCatalog.byURL[feed.url]?.category ?? (feed.isTelegram ? "telegram" : "custom");return category}
    func topicTitle(_ id:String)->String {L(id == "world" ? "News" : ContentPack.find(id).catalogTitle)}
    var selected:[FeedSource] {pool.filter{selectedURLs.contains($0.url)}.map{feed in var copy = feed;copy.enabled = true;return copy}}
    var selectedTopics:[String] {Self.topicOrder.filter{id in selected.contains{topic($0) == id}}}
    var matches:[FeedSource] {
        if selectedOnly {return selected}
        return pool.filter{feed in
            (filters.isEmpty || filters.contains(topic(feed)) || (filters.contains("telegram") && feed.isTelegram)) &&
            (browseLanguage == .all || feed.language == nil || feed.language == (browseLanguage == .russian ? "ru" : "en")) &&
            (search.isEmpty || (feed.name+" "+feed.url+" "+topicTitle(topic(feed))).localizedCaseInsensitiveContains(search))
        }
    }
    var suggestions:[FeedSource] {
        let matches = matches
        let grouped = Dictionary(grouping:matches,by:{topic($0)})
        var result:[FeedSource] = []
        let preference = preferredLanguage == .russian ? "ru" : "en"
        let groups = Self.topicOrder.compactMap {id -> [FeedSource]? in
            guard let group = grouped[id] else{return nil}
            return group.enumerated().sorted {a,b in
                let ar = a.element.language == preference ? 0 : 1,br = b.element.language == preference ? 0 : 1
                return ar == br ? a.offset < b.offset : ar < br
            }.map(\.element)
        }
        for offset in 0..<(groups.map(\.count).max() ?? 0) {for group in groups where offset < group.count {result.append(group[offset])}}
        return result
    }
    var visible:[FeedSource] {Array(suggestions.prefix(visibleCount))}
    var canFinish:Bool {!selected.isEmpty && (!draft.markets || !draft.instruments.isEmpty || !draft.crypto.isEmpty)}
    var previewKey:String {draft.previewKey+selectedURLs.sorted().joined()}
    func toggle(_ feed:FeedSource) {if selectedURLs.contains(feed.url){selectedURLs.remove(feed.url)}else{selectedURLs.insert(feed.url)}}
    func toggleTopic(_ id:String) {if filters.contains(id){filters.remove(id)}else{filters.insert(id)};selectedOnly = false;visibleCount = filters.isEmpty ? 6 : 50}
    func chooseSuggestions() {selectedURLs.formUnion(suggestions.prefix(6).map(\.url))}
    func synchronize() {
        draft.interests = selected.isEmpty ? [] : ["custom"];draft.ownSources = selected
        draft.excluded = [];draft.language = .all;draft.infoRows = 1;draft.step = 3
        refreshPreview()
    }
    func refreshPreview() {
        draft.refreshPreview()
        let names = selected.prefix(5).map(\.name).joined(separator:"   ·   ")
        draft.preview.settings.messages = names.isEmpty ? L("Your selected sources") : names
        draft.preview.settings.tickerRows?[0].messages = draft.preview.settings.messages
    }
    func insertSource(_ feed:FeedSource)->Bool {
        guard !selectedURLs.contains(feed.url) else{return false}
        if !pool.contains(where:{$0.url == feed.url}) {addedSources.append(feed)}
        selectedURLs.insert(feed.url);filters = [];selectedOnly = true;search = ""
        return true
    }
    func addSource() {
        let raw = draft.sourceAddress.trimmingCharacters(in:.whitespacesAndNewlines)
        let address = TelegramPublicReader.username(raw).map{"https://t.me/s/"+$0} ?? raw
        if draft.sourceName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {draft.sourceName = TelegramPublicReader.username(raw).map{"@"+$0} ?? URL(string:address)?.host ?? ""}
        if let known = pool.first(where:{$0.url == address}) {
            guard !selectedURLs.contains(address) else{draft.sourceError = L("This source has already been added.");return}
            selectedURLs.insert(known.url);draft.sourceName = "";draft.sourceAddress = "";draft.sourceError = ""
        } else {
            draft.addSource();guard draft.sourceError.isEmpty,let added = draft.ownSources.last else{return}
            addedSources.append(added);selectedURLs.insert(added.url)
        }
        filters = [];selectedOnly = true;search = ""
    }
    func makeSettings()->Settings? {
        guard canFinish,var settings = draft.makeSettings() else{return nil}
        settings.contentTopicIDs = selectedTopics
        settings.tickerRows?[0].topicIDs = selectedTopics
        return settings
    }
    @discardableResult func finish(on model:AppModel,start:Bool = true)->Bool {
        guard let settings = makeSettings() else{return false}
        let wasStarted = model.servicesStarted;model.servicesStarted = false
        model.settings = settings;model.newsLanguage = .all
        model.defaults.set("complete",forKey:"onboardingState");model.saveSettingsNow();model.showOnboarding = false;model.servicesStarted = wasStarted
        if start {if wasStarted {model.synchronizeServices(force:true)}else{model.start()};model.outputs.show(.strip)}
        return true
    }
}

struct PublisherPickCard:View {
    let feed:FeedSource;let topic:String;let selected:Bool;let action:()->Void
    var initials:String {String(feed.name.replacingOccurrences(of:"@",with:"").prefix(3)).uppercased()}
    var body:some View {
        Button(action:action){HStack(spacing:12){Text(initials).font(.system(size:17,weight:.bold,design:.rounded)).minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(Color.accentColor).frame(width:48,height:48).background(Color.accentColor.opacity(selected ? 0.13 : 0.06),in:RoundedRectangle(cornerRadius:15));VStack(alignment:.leading,spacing:6){Text(feed.name).font(.system(size:13,weight:.semibold)).lineLimit(2).multilineTextAlignment(.leading);Text(topic+" · "+(feed.language?.uppercased() ?? "RSS")).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)};Spacer(minLength:0);Image(systemName:selected ? "checkmark.circle.fill" : "plus.circle").font(.system(size:19)).foregroundStyle(selected ? Color.accentColor : Color(nsColor:.tertiaryLabelColor))}.frame(maxWidth:.infinity,minHeight:64,alignment:.leading).padding(14).background(selected ? Color.accentColor.opacity(0.055) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).strokeBorder(selected ? Color.accentColor.opacity(0.65) : Color(nsColor:.separatorColor).opacity(0.35),lineWidth:selected ? 1.5 : 0.5))}.buttonStyle(.plain).accessibilityLabel(feed.name+", "+topic).accessibilityValue(selected ? L("Selected Feed") : L("Add")).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct QuickFeedSetup:View {
    @ObservedObject var model:AppModel
    @StateObject var state:QuickFeedState
    @State private var instruments = false
    @State private var optionsExpanded = false
    init(model:AppModel,state:QuickFeedState? = nil){self.model = model;_state = StateObject(wrappedValue:state ?? QuickFeedState(model:model,fresh:model.defaults.string(forKey:"onboardingState") == "pending"))}
    var body:some View {
        VStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    HStack(alignment:.top){VStack(alignment:.leading,spacing:8){Text(L(state.page == 0 ? "Pick the sources you like" : "Your personal feed is ready")).font(.system(size:27,weight:.semibold));Text(L(state.page == 0 ? "Tap a few publishers. Their headlines become your ticker." : "One feed from your choices. Start now, or adjust the look.")).font(.system(size:13)).foregroundStyle(.secondary)};Spacer();Picker(L("Interface Language"),selection:$model.interfaceLanguage){ForEach(InterfaceLanguage.allCases){Text($0.title).tag($0)}}.labelsHidden().frame(width:108)}
                    if state.page == 0 {sourcePicker}else{ready}
                }.padding(28).frame(maxWidth:.infinity,alignment:.leading)
            }
            Divider()
            HStack {
                if state.page == 1 {Button(L("Change sources")){state.page = 0}.keyboardShortcut(.cancelAction)}
                else if model.defaults.string(forKey:"onboardingState") == "complete" {Button(L("Cancel")){model.showOnboarding = false}.keyboardShortcut(.cancelAction)}
                Spacer()
                Text(LF("%ld sources",state.selected.count)).font(.system(size:12)).foregroundStyle(.secondary)
                Button(state.page == 0 ? L("Create my feed") : L("Start ticker")){if state.page == 0 {state.page = 1;state.refreshPreview()}else{state.finish(on:model)}}.buttonStyle(.borderedProminent).controlSize(.large).disabled(state.page == 0 ? state.selected.isEmpty : !state.canFinish).keyboardShortcut(.defaultAction)
            }.padding(.horizontal,28).padding(.vertical,18)
        }.background(Color(nsColor:.windowBackgroundColor)).frame(minWidth:780,minHeight:580)
        .onChange(of:state.previewKey){_,_ in state.refreshPreview()}
        .onChange(of:state.page){_,page in if page == 1 && !state.canFinish {optionsExpanded = true}}
        .onChange(of:model.interfaceLanguage){_,value in state.preferredLanguage = value;state.draft.preview.interfaceLanguage = value;state.refreshPreview()}
        .sheet(isPresented:$instruments){OnboardingInstruments(draft:state.draft)}
    }
    var sourcePicker:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(spacing:10){TextField(L("Find a publisher or topic"),text:$state.search).textFieldStyle(.roundedBorder);Picker(L("Browse language"),selection:$state.browseLanguage){ForEach(NewsLanguage.allCases){Text($0.title).tag($0)}}.labelsHidden().frame(width:145);if !state.selected.isEmpty {Toggle(L("Selected only"),isOn:$state.selectedOnly).toggleStyle(.button).controlSize(.small)}}
            TelegramChannelField{state.insertSource($0)}
            ScrollView(.horizontal,showsIndicators:false){HStack(spacing:8){topicChip(L("All Topics"),selected:state.filters.isEmpty){state.filters = [];state.selectedOnly = false;state.visibleCount = 6};ForEach(QuickFeedState.topicOrder.filter{$0 != "custom"},id:\.self){id in topicChip(state.topicTitle(id),selected:state.filters.contains(id)){state.toggleTopic(id)}}}}
            HStack{Text(state.filters.isEmpty ? L("Start with these sources") : LF("%ld sources",state.matches.count)).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary);Spacer();if state.selected.isEmpty && !state.suggestions.isEmpty {Button(L("Choose for me")){state.chooseSuggestions()}.buttonStyle(.borderless)}}
            if state.visible.isEmpty {Text(L("No matching sources. Try another topic or language.")).font(.callout).foregroundStyle(.secondary).padding(.vertical,18)}
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:3),spacing:12){ForEach(state.visible){feed in PublisherPickCard(feed:feed,topic:state.topicTitle(state.topic(feed)),selected:state.selectedURLs.contains(feed.url)){state.toggle(feed)}}}
            if state.suggestions.count > state.visibleCount {Button(L("More sources…")){state.visibleCount += 9}.buttonStyle(.borderless)}
            DisclosureGroup(L("Add RSS feed…")){VStack(alignment:.leading,spacing:10){Text(L("Paste the HTTPS RSS or Atom address. The name is optional.")).font(.caption).foregroundStyle(.secondary);HStack{TextField(L("Name (optional)"),text:Binding(get:{state.draft.sourceName},set:{state.draft.sourceName = $0})).frame(width:150);TextField("https://…",text:Binding(get:{state.draft.sourceAddress},set:{state.draft.sourceAddress = $0}));Button(L("Add")){state.addSource()}}.textFieldStyle(.roundedBorder);if !state.draft.sourceError.isEmpty{Text(state.draft.sourceError).font(.caption).foregroundStyle(.red)}}.padding(.top,10)}.font(.system(size:12)).foregroundStyle(.secondary)
        }
    }
    func topicChip(_ title:String,selected:Bool,action:@escaping()->Void)->some View {
        Button(action:action){Text(title).font(.system(size:11,weight:.medium)).padding(.horizontal,13).padding(.vertical,8).foregroundStyle(selected ? Color.white : Color.primary).background(selected ? Color.accentColor : Color(nsColor:.controlBackgroundColor),in:Capsule())}.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    var ready:some View {
        VStack(alignment:.leading,spacing:20) {
            Text(state.selected.map(\.name).joined(separator:" · ")).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(2)
            Text(L("Layout preview · your selected sources")).font(.caption).foregroundStyle(.secondary)
            SimpleTickerPreview(model:state.draft.preview).frame(height:state.draft.markets ? 90 : 70).clipShape(RoundedRectangle(cornerRadius:state.draft.look == .glass ? 28 : 12))
            HStack{Text(L("Your name")).font(.system(size:13,weight:.medium)).frame(width:98,alignment:.leading);TextField(L("For example: Bushe News"),text:Binding(get:{state.draft.brand},set:{state.draft.brand = $0})).textFieldStyle(.roundedBorder)}
            HStack(spacing:10){ForEach(Look.broadcastLooks){look in SimpleStyleCard(look:look,selected:state.draft.look == look){state.draft.look = look}}}
            DisclosureGroup(L("Optional settings"),isExpanded:$optionsExpanded){options.padding(.top,14)}.font(.system(size:12)).foregroundStyle(.secondary)
            Text(L("Extra rows and individual source settings are available after setup.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    var options:some View {
        VStack(alignment:.leading,spacing:16){
            Picker(L("Ticker position"),selection:Binding(get:{state.draft.edge},set:{state.draft.edge = $0})){ForEach(StripPlacement.desktopEdges){Text($0.title).tag($0)}}.pickerStyle(.segmented).frame(width:280)
            HStack(spacing:20){Toggle(L("Rounded Corners"),isOn:Binding(get:{state.draft.rounded},set:{state.draft.rounded = $0})).toggleStyle(.checkbox);Toggle(L("Show Clock"),isOn:Binding(get:{state.draft.showClock},set:{state.draft.showClock = $0})).toggleStyle(.checkbox);Toggle(L("Show date"),isOn:Binding(get:{state.draft.showDate},set:{state.draft.showDate = $0})).toggleStyle(.checkbox)}
            Toggle(L("Translate to Russian"),isOn:Binding(get:{state.draft.translate},set:{state.draft.translate = $0})).toggleStyle(.checkbox)
            Toggle(L("Add a market row"),isOn:Binding(get:{state.draft.markets},set:{state.draft.toggleMarkets($0)})).toggleStyle(.switch).controlSize(.small)
            if state.draft.markets {Button(L("Choose instruments…")){instruments = true}.buttonStyle(.borderless);if !state.canFinish {Text(L("Choose at least one instrument or turn off the market row.")).font(.caption)}}
            HStack{Button(state.draft.logoData == nil ? L("Upload Logo…") : L("Replace Logo…")){BroadcastBrandControls(model:state.draft.preview).chooseLogo();state.draft.logoData = state.draft.preview.settings.logoData;state.draft.logoName = state.draft.preview.settings.logoName};if state.draft.logoData != nil {Button(L("Remove")){state.draft.logoData = nil;state.draft.logoName = nil}}}
            if state.draft.translate {Text(L("Russian translation may require downloading Apple language models after setup.")).font(.caption)}
        }
    }
}
