import AppKit
import SwiftUI

extension AppModel {
    func prepareOnboarding(firstLaunch:Bool) {
        if defaults.string(forKey:"onboardingState") == nil {defaults.set(firstLaunch ? "pending" : "complete",forKey:"onboardingState")}
        showOnboarding = defaults.string(forKey:"onboardingState") != "complete"
    }
}
struct StrokaRootView:View {
    @ObservedObject var model:AppModel
    @State private var privacy = false
    var body:some View {
        Group {if model.showOnboarding {QuickFeedSetup(model:model)} else {SimpleSetupView(model:model)}}
            .environment(\.locale,Localization.locale)
            .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaPrivacy"))){_ in if model.showOnboarding {privacy = true}}
            .sheet(isPresented:$privacy){SettingsView(model:model)}
    }
}

// Topics are combined into explicit publisher selections. No recommendation service,
// tracking profile, semantic ranking or account is required.
final class PersonalFeedDraft:ObservableObject {
    static var topics:[ContentPack] {ContentPack.all.filter{$0.isOnline && $0.id != "ai"}}
    let base:Settings
    let preview:AppModel
    let suite:String
    @Published var step = 0
    @Published var interests:Set<String> = []
    @Published var excluded:Set<String> = []
    @Published var ownSources:[FeedSource] = []
    @Published var language:NewsLanguage
    @Published var translate:Bool
    @Published var infoRows:Int
    @Published var markets:Bool
    @Published var instruments:[String]
    @Published var crypto:[String]
    @Published var brand:String
    @Published var look:Look
    @Published var edge:StripPlacement
    @Published var rounded:Bool
    @Published var showClock:Bool
    @Published var showDate:Bool
    @Published var logoData:Data?
    @Published var logoName:String?
    @Published var sourceName = ""
    @Published var sourceAddress = ""
    @Published var sourceError = ""
    init(parent:AppModel,fresh:Bool) {
        base = parent.settings;language = fresh ? .all : parent.newsLanguage
        translate = parent.settings.translateRussian ?? false
        infoRows = fresh ? 1 : max(1,parent.tickerRows.filter{$0.channel != .markets}.count)
        markets = !fresh && parent.needsMarkets;instruments = parent.settings.marketInstruments ?? []
        crypto = parent.settings.cryptoPairs.components(separatedBy:CharacterSet(charactersIn:", \n")).filter{!$0.isEmpty}
        brand = parent.settings.brand;look = parent.settings.look.simpleLook;edge = parent.settings.desktopEdge
        logoData = parent.settings.logoData;logoName = parent.settings.logoName
        rounded = parent.settings.roundedStrip ?? true;showClock = parent.settings.showClock;showDate = parent.settings.broadcastDate ?? true
        suite = "ru.bushe.stroka.onboarding.\(UUID())"
        let defaults = UserDefaults(suiteName:suite)!
        defaults.set(8,forKey:"broadcastDesignVersion");defaults.set(12,forKey:"compactStripVersion")
        defaults.set(parent.interfaceLanguage.rawValue,forKey:"interfaceLanguage")
        preview = AppModel(defaults:defaults);preview.reduceMotion = false;preview.playing = false
        if !fresh {
            let valid = Set(Self.topics.map(\.id));var selected = Set<String>(),seen = Set<String>()
            for row in parent.tickerRows where row.channel == .content {
                selected.formUnion((row.topicIDs ?? [row.packID]).filter{valid.contains($0)})
                if row.packID == "custom" {ownSources += row.customFeeds.filter{$0.enabled && !row.disabledSources.contains($0.url) && seen.insert($0.url).inserted}}
            }
            interests = selected
            if !ownSources.isEmpty {interests.insert("custom")}
        }
        refreshPreview()
    }
    deinit {preview.pendingSave?.cancel();preview.editorialWake?.invalidate();preview.defaults.removePersistentDomain(forName:suite)}
    var topics:[ContentPack] {Self.topics.filter{interests.contains($0.id)}}
    func sources(for pack:ContentPack)->[FeedSource] {pack.id == "custom" ? ownSources : pack.sources}
    var candidates:[FeedSource] {var seen = Set<String>();return topics.flatMap{sources(for:$0)}.filter{seen.insert($0.url).inserted}}
    var selectedSources:[FeedSource] {candidates.filter{!excluded.contains($0.url) && (language == .all || $0.language == nil || $0.language == (language == .russian ? "ru" : "en"))}}
    var activeTopics:[ContentPack] {let urls = Set(selectedSources.map(\.url));return topics.filter{sources(for:$0).contains{urls.contains($0.url)}}}
    var unavailableTopics:[ContentPack] {let ids = Set(activeTopics.map(\.id));return topics.filter{!ids.contains($0.id)}}
    var maximumInfoRows:Int {max(1,min(markets ? 3 : 4,activeTopics.count))}
    var resolvedInfoRows:Int {min(maximumInfoRows,max(1,infoRows))}
    var groups:[[ContentPack]] {
        guard !activeTopics.isEmpty else {return []}
        var groups = Array(repeating:[ContentPack](),count:resolvedInfoRows)
        for (index,topic) in activeTopics.enumerated() {groups[index % groups.count].append(topic)}
        return groups
    }
    var rows:[TickerRow] {
        let selected = Set(selectedSources.map(\.url))
        var rows = groups.map {group -> TickerRow in
            var row = TickerRow(packID:"custom");row.topicIDs = group.map(\.id);row.language = language;row.shortHeadlines = base.shortHeadlines ?? false
            var seen = Set<String>()
            row.customFeeds = group.flatMap{sources(for:$0)}.filter{selected.contains($0.url) && seen.insert($0.url).inserted}
            return row
        }
        if markets {rows.append(TickerRow(channel:.markets))}
        return rows
    }
    var canContinue:Bool {step == 0 ? !interests.isEmpty : !selectedSources.isEmpty && unavailableTopics.isEmpty && !rows.isEmpty && (!markets || !instruments.isEmpty || !crypto.isEmpty)}
    var previewKey:String {interests.sorted().joined()+excluded.sorted().joined()+ownSources.map(\.url).joined()+language.rawValue+String(infoRows)+String(markets)+brand+look.rawValue+edge.rawValue+String(rounded)+String(showClock)+String(showDate)+String(logoData?.hashValue ?? 0)}
    func toggleInterest(_ id:String) {if interests.contains(id){interests.remove(id)}else{interests.insert(id)}}
    func toggleSource(_ feed:FeedSource,_ enabled:Bool) {if enabled {excluded.remove(feed.url)} else {excluded.insert(feed.url)}}
    func toggleMarkets(_ enabled:Bool) {markets = enabled;if enabled && instruments.isEmpty && crypto.isEmpty {instruments = ["currency:USD","currency:EUR","currency:CNY"]}}
    func addSource() {
        let title = sourceName.trimmingCharacters(in:.whitespacesAndNewlines),raw = sourceAddress.trimmingCharacters(in:.whitespacesAndNewlines)
        let address = TelegramPublicReader.username(raw).map{"https://t.me/s/"+$0} ?? raw
        guard !title.isEmpty,let url = URL(string:address),url.scheme == "https",url.host != nil else {sourceError = L("Enter a name and the full HTTPS feed URL.");return}
        guard !ownSources.contains(where:{$0.url == address}) else {sourceError = L("This source has already been added.");return}
        ownSources.append(FeedSource(name:title,url:address));interests.insert("custom");excluded.remove(address);sourceName = "";sourceAddress = "";sourceError = ""
    }
    func makeSettings()->Settings? {
        guard !selectedSources.isEmpty,unavailableTopics.isEmpty,let first = rows.first,rows.count <= 4,(!markets || !instruments.isEmpty || !crypto.isEmpty) else {return nil}
        var settings = base;first.apply(to:&settings);settings.tickerRows = rows
        settings.brand = brand.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "STROKA" : String(brand.prefix(100))
        settings.look = look;settings.stripPlacement = edge;settings.stripTop = edge == .top
        settings.logoData = logoData;settings.logoName = logoName
        settings.roundedStrip = rounded;settings.showClock = showClock;settings.broadcastDate = showDate;settings.translateRussian = translate
        settings.messages = base.messages
        settings.marketInstruments = instruments;settings.cryptoPairs = crypto.joined(separator:", ");settings.composition = .ticker;settings.motion = .horizontal;settings.idleEnabled = false
        settings.stripHeight = settings.resolvedStripHeight
        return settings
    }
    func refreshPreview() {
        var settings = base
        let plan = rows.isEmpty ? [TickerRow()] : rows
        var samples = plan.map {row -> TickerRow in
            if row.channel == .markets {return row}
            var sample = TickerRow(channel:.message);sample.messages = row.topicIDs?.map{L(ContentPack.find($0).catalogTitle)}.joined(separator:"   ·   ") ?? L("Your selected topics")
            return sample
        }
        if samples.isEmpty {samples = [TickerRow(channel:.message)]}
        samples[0].apply(to:&settings);settings.tickerRows = samples
        settings.logoData = logoData;settings.logoName = logoName
        settings.look = look;settings.brand = brand;settings.showClock = showClock;settings.broadcastDate = showDate;settings.roundedStrip = rounded
        preview.settings = settings
    }
    @discardableResult func finish(on model:AppModel,start:Bool = true)->Bool {
        guard let settings = makeSettings(),canContinue else {return false}
        let wasStarted = model.servicesStarted;model.servicesStarted = false
        model.settings = settings;model.newsLanguage = language
        model.defaults.set("complete",forKey:"onboardingState");model.saveSettingsNow();model.showOnboarding = false
        model.servicesStarted = wasStarted
        if start {if wasStarted {model.synchronizeServices(force:true)} else {model.start()};model.outputs.show(.strip)}
        return true
    }
}

#if STROKA_DIAGNOSTICS
struct PersonalFeedSetup:View {
    @ObservedObject var model:AppModel
    @StateObject var draft:PersonalFeedDraft
    @State private var instruments = false
    init(model:AppModel,draft:PersonalFeedDraft? = nil) {self.model = model;_draft = StateObject(wrappedValue:draft ?? PersonalFeedDraft(parent:model,fresh:model.defaults.string(forKey:"onboardingState") == "pending"))}
    private let steps = ["Interests","Sources","Rows","Appearance"]
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:12) {ForEach(Array(steps.enumerated()),id:\.offset){index,title in
                HStack(spacing:7){Text(index < draft.step ? "✓" : String(index+1)).font(.system(size:11,weight:.semibold)).frame(width:23,height:23).background(index == draft.step ? Color.accentColor : Color(nsColor:.controlBackgroundColor),in:Circle()).foregroundStyle(index == draft.step ? .white : .secondary);Text(L(title)).font(.system(size:12,weight:index == draft.step ? .semibold : .regular)).foregroundStyle(index == draft.step ? .primary : .secondary).lineLimit(1).fixedSize(horizontal:true,vertical:false)}.fixedSize(horizontal:true,vertical:false)
                if index < 3 {Rectangle().fill(Color(nsColor:.separatorColor)).frame(height:0.5)}
            };Picker(L("Interface Language"),selection:$model.interfaceLanguage){ForEach(InterfaceLanguage.allCases){Text($0.title).tag($0)}}.labelsHidden().frame(width:108)}.padding(.horizontal,32).padding(.top,24).padding(.bottom,20)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    VStack(alignment:.leading,spacing:8){Text(L(title)).font(.system(size:27,weight:.semibold));Text(L(detail)).font(.system(size:13)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
                    switch draft.step {case 0: interests;case 1:sources;case 2:layout;default:appearance}
                }.padding(32).frame(maxWidth:.infinity,alignment:.leading)
            }
            Divider()
            HStack {
                if draft.step > 0 {Button(L("Back")){draft.step -= 1}.keyboardShortcut(.cancelAction)}
                else if model.defaults.string(forKey:"onboardingState") == "complete" {Button(L("Cancel")){model.showOnboarding = false}.keyboardShortcut(.cancelAction)}
                Spacer()
                Text(draft.step == 0 ? LF("%ld topics selected",draft.interests.count) : LF("%ld sources",draft.selectedSources.count)).font(.caption).foregroundStyle(.secondary)
                Button(draft.step == 3 ? L("Start my ticker") : L("Continue")) {if draft.step < 3 {draft.step += 1}else{draft.finish(on:model)}}.buttonStyle(.borderedProminent).controlSize(.large).disabled(!draft.canContinue).keyboardShortcut(.defaultAction)
            }.padding(.horizontal,32).padding(.vertical,18)
        }.background(Color(nsColor:.windowBackgroundColor)).frame(minWidth:780,minHeight:580)
        .onChange(of:draft.previewKey){_,_ in draft.refreshPreview()}
        .onChange(of:model.interfaceLanguage){_,value in draft.preview.interfaceLanguage = value;draft.refreshPreview()}
        .sheet(isPresented:$instruments){OnboardingInstruments(draft:draft)}
    }
    var title:String {switch draft.step {case 0:return "What do you want to follow?";case 1:return "Choose your sources";case 2:return "One feed or separate rows?";default:return "Make it yours"}}
    var detail:String {switch draft.step {case 0:return "Select several interests. Stroka will build your personal feed from them.";case 1:return "Publishers are selected for your interests. Keep what you like, or add a Telegram channel or RSS feed.";case 2:return "Mix your interests in one row or spread them across up to four. Market prices are optional.";default:return "Add your name, choose a look and position, then start your ticker."}}
    var interests:some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:3),spacing:12) {
            ForEach(PersonalFeedDraft.topics){pack in
                let selected = draft.interests.contains(pack.id)
                Button{draft.toggleInterest(pack.id)}label:{VStack(alignment:.leading,spacing:9){HStack{Image(systemName:pack.symbol).font(.system(size:20)).foregroundStyle(Color.accentColor);Spacer();Image(systemName:selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : Color(nsColor:.tertiaryLabelColor))};Text(L(pack.catalogTitle)).font(.system(size:14,weight:.semibold));Text(pack.id == "custom" ? L("Add Telegram or RSS") : pack.sources.prefix(2).map(\.name).joined(separator:" · ")).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2)}.frame(maxWidth:.infinity,minHeight:84,alignment:.topLeading).padding(16).background(selected ? Color.accentColor.opacity(0.06) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:13)).overlay(RoundedRectangle(cornerRadius:13).strokeBorder(selected ? Color.accentColor.opacity(0.7) : Color(nsColor:.separatorColor).opacity(0.4),lineWidth:selected ? 1.5 : 0.5))}.buttonStyle(.plain).accessibilityLabel(L(pack.catalogTitle)).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
    var sources:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Picker(L("Source Language"),selection:$draft.language){ForEach(NewsLanguage.allCases){Text($0.title).tag($0)}}.frame(maxWidth:320);Toggle(L("Translate to Russian"),isOn:$draft.translate).toggleStyle(.checkbox)}
            Text(L("Only sources in the selected languages enter your feed.")).font(.caption).foregroundStyle(.secondary)
            ForEach(draft.topics){pack in
                DisclosureGroup {
                    VStack(alignment:.leading,spacing:12){ForEach(draft.sources(for:pack)){feed in Toggle(isOn:Binding(get:{!draft.excluded.contains(feed.url)},set:{draft.toggleSource(feed,$0)})){HStack{Text(feed.name).font(.system(size:12));Spacer();Text((feed.language ?? "").uppercased()).font(.caption).foregroundStyle(.secondary)}}.toggleStyle(.checkbox)}}.padding(.top,10)
                } label:{HStack{Text(L(pack.catalogTitle)).font(.system(size:13,weight:.semibold));Spacer();Text(LF("%ld sources",draft.sources(for:pack).filter{feed in draft.selectedSources.contains{$0.url == feed.url}}.count)).font(.caption).foregroundStyle(.secondary)}}.padding(.vertical,5)
                Divider()
            }
            Text(L("Add Telegram or RSS")).font(.headline)
            Text(L("Public Telegram: @channel or t.me link. Websites: the HTTPS RSS or Atom address.")).font(.caption).foregroundStyle(.secondary)
            HStack{TextField(L("Name"),text:$draft.sourceName).frame(width:150);TextField("https://… / @channel",text:$draft.sourceAddress);Button(L("Add")){draft.addSource()}}.textFieldStyle(.roundedBorder)
            if !draft.sourceError.isEmpty {Text(draft.sourceError).font(.caption).foregroundStyle(.red)}
            if !draft.unavailableTopics.isEmpty {Text(LF("No selected sources for: %@. Change the language, enable sources, or go back to remove these topics.",draft.unavailableTopics.map{L($0.catalogTitle)}.joined(separator:", "))).font(.callout).foregroundStyle(.secondary)}
            if draft.selectedSources.isEmpty {Text(L("Select a source in your language or add your own.")).font(.callout).foregroundStyle(.secondary)}
        }
    }
    var layout:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack{Text(L("Information rows")).font(.system(size:13,weight:.medium));Picker(L("Information rows"),selection:Binding(get:{draft.resolvedInfoRows},set:{draft.infoRows = $0})){ForEach(1...draft.maximumInfoRows,id:\.self){Text(String($0)).tag($0)}}.labelsHidden().pickerStyle(.segmented).frame(width:200)}
            Toggle(L("Add a market row"),isOn:Binding(get:{draft.markets},set:{draft.toggleMarkets($0)})).toggleStyle(.switch).controlSize(.small)
            if draft.markets {HStack{Text(LF("%ld instruments",draft.instruments.count+draft.crypto.count)).font(.caption).foregroundStyle(.secondary);Button(L("Choose instruments…")){instruments = true}.buttonStyle(.borderless)};if draft.instruments.isEmpty && draft.crypto.isEmpty {Text(L("Choose at least one instrument or turn off the market row.")).font(.caption).foregroundStyle(.secondary)}}
            rowSummary
            Text(L("Each interest appears in your feed. You can change any row later.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    var rowSummary:some View {
        VStack(spacing:0){ForEach(Array(draft.rows.enumerated()),id:\.offset){index,row in HStack{Text(LF("Row %ld",index+1)).font(.system(size:12)).foregroundStyle(.secondary).frame(width:80,alignment:.leading);Image(systemName:row.channel == .markets ? "chart.xyaxis.line" : "newspaper").foregroundStyle(Color.accentColor).frame(width:20);Text(row.title).font(.system(size:13,weight:.medium));Spacer();Text(row.channel == .markets ? L("Market prices") : LF("%ld sources",row.customFeeds.count)).font(.caption).foregroundStyle(.secondary)}.padding(14);if index < draft.rows.count-1{Divider()}}}.background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
    }
    var appearance:some View {
        VStack(alignment:.leading,spacing:20) {
            Text(L("Layout preview · your selected topics")).font(.caption).foregroundStyle(.secondary)
            SimpleTickerPreview(model:draft.preview).frame(height:max(64,CGFloat(draft.rows.count)*29)).clipShape(RoundedRectangle(cornerRadius:draft.look == .glass ? 28 : 12))
            HStack{Text(L("Your name")).font(.system(size:13,weight:.medium)).frame(width:100,alignment:.leading);TextField(L("For example: Bushe News"),text:$draft.brand).textFieldStyle(.roundedBorder);Button(draft.logoData == nil ? L("Upload Logo…") : L("Replace Logo…")){BroadcastBrandControls(model:draft.preview).chooseLogo();draft.logoData = draft.preview.settings.logoData;draft.logoName = draft.preview.settings.logoName}.buttonStyle(.borderless);if draft.logoData != nil{Button(L("Remove")){draft.logoData = nil;draft.logoName = nil}.buttonStyle(.borderless)}}
            HStack(spacing:10){ForEach(Look.broadcastLooks){look in SimpleStyleCard(look:look,selected:draft.look == look){draft.look = look}}}
            HStack{Text(L("Ticker position")).font(.system(size:13,weight:.medium)).frame(width:100,alignment:.leading);Picker(L("Ticker position"),selection:$draft.edge){ForEach(StripPlacement.desktopEdges){Text($0.title).tag($0)}}.labelsHidden().pickerStyle(.segmented).frame(width:174);Spacer()}
            HStack(spacing:22){Toggle(L("Rounded Corners"),isOn:$draft.rounded).toggleStyle(.checkbox);Toggle(L("Show Clock"),isOn:$draft.showClock).toggleStyle(.checkbox);if draft.showClock{Toggle(L("Show date"),isOn:$draft.showDate).toggleStyle(.checkbox)}}
            DisclosureGroup(L("Your personal feed")){rowSummary}.font(.system(size:12)).foregroundStyle(.secondary)
            if draft.translate {Text(L("Russian translation may require downloading Apple language models after setup.")).font(.caption).foregroundStyle(.secondary)}
        }
    }
}
#endif
struct OnboardingInstruments:View {
    @ObservedObject var draft:PersonalFeedDraft
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    var body:some View {
        VStack(alignment:.leading,spacing:16){HStack{Text(L("Choose instruments…")).font(.title2.weight(.semibold));Spacer();Button(L("Done")){dismiss()}};TextField(L("Search"),text:$search).textFieldStyle(.roundedBorder);ScrollView{LazyVStack(alignment:.leading,spacing:12){ForEach(Array(Set(["BTC-USD","ETH-USD","SOL-USD"]+draft.crypto)).sorted().filter{search.isEmpty || $0.localizedCaseInsensitiveContains(search)},id:\.self){symbol in Toggle(symbol,isOn:Binding(get:{draft.crypto.contains(symbol)},set:{on in if on{draft.crypto.append(symbol)}else{draft.crypto.removeAll{$0 == symbol}}})).toggleStyle(.checkbox)};ForEach(MarketCatalog.all.filter{search.isEmpty || ($0.symbol+" "+$0.name).localizedCaseInsensitiveContains(search)}){item in Toggle(isOn:Binding(get:{draft.instruments.contains(item.id)},set:{on in if on{draft.instruments.append(item.id)}else{draft.instruments.removeAll{$0 == item.id}}})){Text(item.symbol+" · "+item.name).font(.system(size:12))}.toggleStyle(.checkbox)}}}}.padding(24).frame(width:570,height:520)
    }
}
