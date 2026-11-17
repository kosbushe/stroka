import SwiftUI
import AppKit

// Four choices for a daily ticker. Legacy raw values remain decodable in saved presets.
extension Look {
    var simpleLook:Look {
        switch self {
        case .bulletin,.pulse:return .bulletin
        case .metro,.editorial,.minimal,.white,.paper,.champagne:return .metro
        case .glass,.wire,.signal,.ribbon,.electric:return .glass
        default:return .nightline
        }
    }
    var simpleTitle:String {
        switch simpleLook {case .bulletin:return L("News");case .nightline:return L("Night");case .metro:return L("Minimal");default:return L("Glass")}
    }
}
extension StripPlacement {
    static let desktopEdges:[StripPlacement] = [.bottom,.top]
}
extension Settings {
    var desktopEdge:StripPlacement {resolvedPlacement == .top ? .top : .bottom}
}
extension AppModel {
    func prepareDesktopTicker(force:Bool = false) {
        guard force || defaults.integer(forKey:"desktopTickerVersion") < 1 else {previewMode = .strip;return}
        var s = settings;s.stripPlacement = s.desktopEdge;s.stripTop = s.desktopEdge == .top
        s.composition = .ticker;s.motion = .horizontal;s.idleEnabled = false
        settings = s;previewMode = .strip;defaults.set(1,forKey:"desktopTickerVersion");saveSettingsNow()
    }
    func prepareSimpleSetup(force:Bool = false,firstLaunch:Bool = false) {
        guard force || defaults.integer(forKey:"simpleSetupVersion") < 17 else {return}
        var s = settings;s.look = s.look.simpleLook;s.motion = .horizontal;s.composition = .ticker
        s.showClock = true;s.broadcastDate = true
        if s.channel != .message {s.channel = .content}
        if s.dualUpperChannel != .message {s.dualUpperChannel = .content}
        s.stripHeight = min(180,max(45,s.resolvedStripHeight))
        if firstLaunch {s.look = .bulletin;s.dualTicker = false;s.marketInstruments = ["currency:USD","currency:EUR","currency:CNY"];s.cryptoPairs = "";s.applyDensity(.desktop)}
        settings = s;previewMode = .strip;defaults.set(17,forKey:"simpleSetupVersion");saveSettingsNow()
    }
    func setSimpleDual(_ enabled:Bool) {
        let density = settings.resolvedStripDensity
        settings.dualTicker = enabled;settings.dualUpperChannel = settings.channel == .message ? .message : .content
        if enabled && selectedMarketIDs.isEmpty && settings.cryptoPairs.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {settings.marketInstruments = ["currency:USD","currency:EUR","currency:CNY"]}
        settings.applyDensity(density)
    }
    func chooseOwnText() {settings.channel = .message;settings.dualUpperChannel = .message;sequence += 1}
    func hasCrypto(_ symbol:String)->Bool {settings.cryptoPairs.uppercased().components(separatedBy:CharacterSet(charactersIn:", \n")).contains(symbol)}
    func setSimpleCrypto(_ symbol:String,enabled:Bool) {
        var pairs = Set(settings.cryptoPairs.uppercased().components(separatedBy:CharacterSet(charactersIn:", \n")).filter{!$0.isEmpty})
        if enabled {pairs.insert(symbol)} else {pairs.remove(symbol)};settings.cryptoPairs = pairs.sorted().joined(separator:", ")
    }
    var simpleContentName:String {tickerRows[0].title}
    var simpleContentStatus:String {
        if upperChannel == .message {return LF("%ld messages",ownLines.count)}
        if refreshingContent {return L("Loading your feed…")}
        if selectedContent.isEmpty {return settings.translateRussian == true ? L("Check sources or prepare Russian translation") : L("Choose sources with recent headlines")}
        return LF("%ld messages",selectedContent.count)
    }
}
struct SimpleTickerPreview:NSViewRepresentable {
    @ObservedObject var model:AppModel
    func makeNSView(context:Context)->TickerView {TickerView(model:model,preview:true)}
    func updateNSView(_ view:TickerView,context:Context) {view.previewScale = 0.8;view.requestRefresh()}
}
struct SimpleStyleCard:View {
    let look:Look;let selected:Bool;let action:()->Void
    var body:some View {
        Button(action:action) {
            VStack(spacing:9) {
                HStack(spacing:0) {
                    Text("S").font(.system(size:12,weight:.bold)).foregroundStyle(.white).frame(width:28,height:38).background(Color(nsColor:look == .glass ? hex(0x2C3644) : look == .nightline ? hex(0x222A36) : look.accent))
                    VStack(alignment:.leading,spacing:4) {RoundedRectangle(cornerRadius:1).fill(Color(nsColor:look.ink).opacity(0.35)).frame(height:2);RoundedRectangle(cornerRadius:1).fill(Color(nsColor:look.ink)).frame(height:3)}.padding(.horizontal,8)
                    Text("9:41").font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(.white).frame(width:38,height:38).background(Color(nsColor:hex(0x20252D)))
                }.background(Color(nsColor:look.bg)).clipShape(RoundedRectangle(cornerRadius:look == .glass ? 19 : 7))
                HStack(spacing:5) {Text(look.simpleTitle).font(.system(size:12,weight:selected ? .semibold : .regular));if selected {Image(systemName:"checkmark.circle.fill").font(.system(size:11)).foregroundStyle(Color.accentColor)}}
            }.padding(10).frame(maxWidth:.infinity).background(selected ? Color.accentColor.opacity(0.07) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(selected ? Color.accentColor.opacity(0.7) : Color(nsColor:.separatorColor).opacity(0.45),lineWidth:selected ? 1.5 : 0.5)).contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).accessibilityLabel(look.simpleTitle).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct SimpleSetupView:View {
    @ObservedObject var model:AppModel
    @State private var rowTarget:TickerRowTarget?
    @State private var contentSheet = false;@State private var advanced = false;@State private var settingsSheet = false
    @State private var instruments = false;@State private var help = false;@State private var remote = false;@State private var announcement = false
    @State private var announcementText = ""
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack(alignment:.firstTextBaseline) {
                    VStack(alignment:.leading,spacing:5) {Text(L("Set up your ticker")).font(.system(size:27,weight:.semibold));Text(L("Choose your feed, then press Start ticker.")).font(.system(size:13)).foregroundStyle(.secondary)}
                    Spacer()
                    Button(L("Build my feed…")){model.showOnboarding = true}.buttonStyle(.borderless)
                    Picker(L("Ticker position"),selection:Binding(get:{model.settings.desktopEdge},set:{model.settings.stripPlacement = $0;model.settings.stripTop = $0 == .top})) {ForEach(StripPlacement.desktopEdges){Text($0.title).tag($0)}}.labelsHidden().pickerStyle(.segmented).controlSize(.small).frame(width:174).accessibilityLabel(L("Ticker position"))
                    if model.activeMode != nil {Button {model.playing.toggle()} label:{Image(systemName:model.playing ? "pause.fill" : "play.fill")}.accessibilityLabel(model.playing ? L("Pause") : L("Resume"))}
                }
                SimpleTickerPreview(model:model).frame(height:max(80,CGFloat(model.tickerRows.count)*29)).clipShape(RoundedRectangle(cornerRadius:model.settings.look == .glass ? 30 : 13)).overlay(RoundedRectangle(cornerRadius:model.settings.look == .glass ? 30 : 13).strokeBorder(Color(nsColor:.separatorColor).opacity(0.3)))
                VStack(spacing:0) {
                    HStack(spacing:18) {
                        rowLabel(L("Your name"))
                        TextField(L("For example: Bushe News"),text:Binding(get:{model.settings.brand},set:{model.settings.brand = String($0.prefix(100))})).textFieldStyle(.roundedBorder).accessibilityLabel(L("Your name"))
                    }.frame(minHeight:52)
                    Divider()
                    HStack(spacing:18) {
                        rowLabel(L("Rows"))
                        Picker(L("Number of rows"),selection:Binding(get:{model.tickerRows.count},set:{model.setRowCount($0)})) {ForEach(1...4,id:\.self){Text(String($0)).tag($0)}}.pickerStyle(.segmented).frame(width:200).labelsHidden()
                        Spacer()
                        Text(L("Up to four independent feeds")).font(.system(size:11)).foregroundStyle(.secondary)
                    }.frame(minHeight:52)
                    ForEach(Array(model.tickerRows.enumerated()),id:\.offset) {index,row in
                        Divider()
                        HStack(spacing:18) {
                            rowLabel(LF("Row %ld",index+1))
                            Button {rowTarget = TickerRowTarget(index:index)} label:{HStack {
                                Image(systemName:row.channel == .markets ? "chart.xyaxis.line" : row.channel == .message ? "text.alignleft" : ContentPack.find(row.packID).symbol).foregroundStyle(Color.accentColor).frame(width:20)
                                Text(row.title).font(.system(size:13,weight:.medium))
                                Spacer();Image(systemName:"chevron.right").font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary)
                            }}.buttonStyle(.plain).accessibilityLabel(LF("Row %ld",index+1)+": "+row.title)
                        }.frame(minHeight:48)
                    }
                    Divider()
                    HStack(spacing:18){rowLabel(L("Speed"));Slider(value:$model.settings.speed,in:20...260).accessibilityLabel(L("Speed"));Text(String(Int(model.settings.speed))).font(.system(size:12,design:.monospaced)).foregroundStyle(.secondary).frame(width:34)}.frame(minHeight:48)
                    if model.tickerRows.count > 1 && model.settings.graduatedSpeeds != false {HStack{Spacer().frame(width:116);Text(L("Upper rows are slower. Each lower row moves a little faster.")).font(.system(size:11)).foregroundStyle(.secondary);Spacer()}.padding(.bottom,10)}
                    if model.needsMarkets {
                        Divider()
                        HStack(spacing:8) {rowLabel(L("Instruments"));currency("USD/RUB",id:"currency:USD");currency("EUR/RUB",id:"currency:EUR");currency("CNY/RUB",id:"currency:CNY");Spacer();Button(L("All instruments…")){instruments = true}.buttonStyle(.borderless)}.frame(minHeight:48)
                    }

                }
                VStack(alignment:.leading,spacing:10) {Text(L("Appearance")).font(.system(size:12,weight:.semibold)).foregroundStyle(.secondary);HStack(spacing:10) {ForEach(Look.broadcastLooks){look in SimpleStyleCard(look:look,selected:model.settings.look == look){model.applyLook(look)}}}}
            }.padding(28)
        }
        .safeAreaInset(edge:.bottom,spacing:0) {
            VStack(spacing:0) {Divider();HStack {Button {advanced = true} label:{Label(L("More settings…"),systemImage:"slider.horizontal.3")}.buttonStyle(.borderless);Spacer();if model.activeMode != nil {Button(L("Stop Display")){model.outputs.stop()}.buttonStyle(.borderless).foregroundStyle(.secondary)};Button {model.saveSettingsNow();model.outputs.show(.strip)} label:{Label(model.activeMode == nil ? L("Start ticker") : L("Update ticker"),systemImage:"play.fill").padding(.horizontal,14).padding(.vertical,4)}.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return,modifiers:[])}.padding(.horizontal,28).padding(.vertical,18)}.background(Color(nsColor:.windowBackgroundColor))
        }
        .frame(minWidth:780,minHeight:580).background(Color(nsColor:.windowBackgroundColor)).environment(\.locale,Localization.locale)
        .background {RussianTranslationHost(model:model)}
        .sheet(isPresented:$contentSheet){QuickContentChooser(model:model)}
        .sheet(item:$rowTarget){target in TickerRowEditor(model:model,index:target.index)}
        .sheet(isPresented:$advanced){SimpleDisplaySettings(model:model)}
        .sheet(isPresented:$settingsSheet){SettingsView(model:model)}
        .sheet(isPresented:$instruments){MarketPickerView(model:model)}
        .sheet(isPresented:$help){HelpView()}
        .sheet(isPresented:$remote){RemoteView(model:model)}
        .sheet(isPresented:$announcement){VStack(alignment:.leading,spacing:18){Text(L("Announcement")).font(.title2.weight(.semibold));TextEditor(text:$announcementText).frame(width:450,height:100);HStack{Button(L("Cancel")){announcement = false};Spacer();Button(L("Show Announcement…")){model.urgent = announcementText;announcement = false}.buttonStyle(.borderedProminent)}}.padding(24)}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaDisplaySettings"))) {note in guard let sender = note.object as? AppModel,sender === model else{return};rowTarget = nil;contentSheet = false;advanced = false;settingsSheet = false;instruments = false;help = false;remote = false;announcement = false}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaRowInstruments"))){_ in DispatchQueue.main.asyncAfter(deadline:.now()+0.3){instruments = true}}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaChooseFeed"))){_ in contentSheet = true}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaContentSources"))){_ in contentSheet = true}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaAppearance"))){_ in advanced = false}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaPrivacy"))){_ in settingsSheet = true}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaHelp"))){_ in help = true}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaRemote"))){_ in remote = true}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaUrgent"))){_ in announcementText = model.urgent;announcement = true}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaSavePreset"))){_ in ControlView(model:model).saveScene()}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaReset"))){_ in ControlView(model:model).resetData()}
    }
    func rowLabel(_ title:String)->some View {Text(title).font(.system(size:13,weight:.medium)).frame(width:98,alignment:.leading)}
    func currency(_ title:String,id:String)->some View {Toggle(title,isOn:Binding(get:{model.selectedMarketIDs.contains(id)},set:{model.selectInstrument(id,enabled:$0)})).toggleStyle(.button).controlSize(.small)}
}
struct QuickContentChooser:View {
    @ObservedObject var model:AppModel;@Environment(\.dismiss) var dismiss
    var embedded = false
    @State private var publishers = false;@State private var search = "";@State private var address = "";@State private var sourceName = "";@State private var sourceError = "";@State private var reviewHeadlines = false
    var feeds:[FeedSource] {var seen = Set<String>();return ((model.settings.customFeeds ?? [])+NewsCatalog.all.map(\.feed)+ContentPack.find("telegram").sources).filter{seen.insert($0.url).inserted && (search.isEmpty || ($0.name+" "+$0.url).localizedCaseInsensitiveContains(search))}.sorted{(selected($0) ? 0 : 1,$0.name)<(selected($1) ? 0 : 1,$1.name)}}
    func selected(_ feed:FeedSource)->Bool {model.enabledContentSources.contains{$0.url == feed.url}}
    func toggle(_ feed:FeedSource,_ enabled:Bool) {
        if model.selectedPack.id != "custom" {model.settings.customFeeds = model.enabledContentSources;model.selectPack("custom")}
        if enabled {
            var chosen = feed;chosen.enabled = true;var rows = model.settings.customFeeds ?? []
            if let index = rows.firstIndex(where:{$0.url == feed.url}) {rows[index].enabled = true} else {rows.append(chosen)}
            model.settings.disabledContentSources = (model.settings.disabledContentSources ?? []).filter{$0 != feed.url}
            model.settings.customFeeds = rows
        } else {model.settings.customFeeds?.removeAll{$0.url == feed.url}}
        model.activateContentPack("custom")
        if enabled,let lang = feed.language,model.newsLanguage != .all,lang != (model.newsLanguage == .russian ? "ru" : "en") {model.newsLanguage = .all}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {Text(L("Choose your content")).font(.system(size:23,weight:.semibold));Spacer();if !embedded {Button(L("Done")){dismiss()}.keyboardShortcut(.defaultAction)}}
            Picker(L("Choose content"),selection:$publishers){Text(L("Topics")).tag(false);Text(L("Publishers")).tag(true)}.pickerStyle(.segmented).labelsHidden()
            TextField(L("Search topics or publishers"),text:$search).textFieldStyle(.roundedBorder)
            TelegramChannelField{feed in
                guard !selected(feed) else{return false};toggle(feed,true);publishers = true;search = "";return true
            }
            if publishers {
                if feeds.isEmpty {Text(L("No search results")).font(.callout).foregroundStyle(.secondary)}
                ScrollView {LazyVStack(spacing:0){ForEach(feeds){feed in Toggle(isOn:Binding(get:{selected(feed)},set:{toggle(feed,$0)})){HStack{VStack(alignment:.leading,spacing:4){Text(feed.name).font(.system(size:13,weight:.medium));if selected(feed){Text(model.sourceSummary(feed)).font(.caption).foregroundStyle(.secondary)}};Spacer();Text((feed.language ?? "").uppercased()).font(.caption).foregroundStyle(.secondary)}}.toggleStyle(.checkbox).padding(.vertical,11);Divider()}}}
                HStack{Text(LF("%ld sources",model.enabledContentSources.count)).font(.caption).foregroundStyle(.secondary);Spacer();Button(L("Clear Selection")){model.settings.customFeeds = [];model.activateContentPack("custom")}.buttonStyle(.borderless)}
                DisclosureGroup(L("Add RSS feed…")){HStack{TextField(L("Name (optional)"),text:$sourceName);TextField("https://…",text:$address);Button(L("Add")){addFeed()}}.textFieldStyle(.roundedBorder);if !sourceError.isEmpty{Text(sourceError).font(.caption).foregroundStyle(.red)}}
            } else {
                ScrollView {LazyVStack(alignment:.leading,spacing:0) {
                    Button{model.chooseOwnText()}label:{HStack{Label(L("My Text"),systemImage:"text.alignleft");Spacer();if model.upperChannel == .message{Image(systemName:"checkmark").foregroundStyle(Color.accentColor)}}.padding(.vertical,12)}.buttonStyle(.plain)
                    if model.upperChannel == .message {TextEditor(text:$model.settings.messages).font(.system(size:13)).frame(height:110).border(Color(nsColor:.separatorColor)).padding(.bottom,12);Text(L("One message per line")).font(.caption).foregroundStyle(.secondary)}
                    if !search.isEmpty && !ContentCatalog.packs.contains(where:{ContentCatalog.matches($0,search:search)}) {Text(L("No search results")).foregroundStyle(.secondary).padding(.vertical,12)}
                    ForEach(ContentCatalog.groups){group in
                        let packs = group.packs.filter{ContentCatalog.matches($0,search:search)}
                        if !packs.isEmpty {Text(L(group.title)).font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary).padding(.top,14).padding(.bottom,6)}
                        ForEach(packs){pack in Button{model.activateContentPack(pack.id)}label:{HStack(spacing:12){Image(systemName:pack.symbol).frame(width:22).foregroundStyle(Color.accentColor);Text(L(pack.catalogTitle)).font(.system(size:13));Spacer();if !pack.offline && pack.id != "custom"{Text(LF("%ld sources",pack.sources.count)).font(.caption).foregroundStyle(.secondary)};if model.upperChannel != .message && model.selectedPack.id == pack.id{Image(systemName:"checkmark").foregroundStyle(Color.accentColor)}}.padding(.vertical,10).contentShape(Rectangle())}.buttonStyle(.plain);Divider()}
                    }
                }}
            }
            if model.upperChannel != .message {
                Divider()
                if model.selectedPack.offline {Picker(L("Language"),selection:Binding(get:{model.settings.offlineLanguage.flatMap(NewsLanguage.init(rawValue:)) ?? model.newsLanguage},set:{model.settings.offlineLanguage = $0.rawValue})){ForEach(NewsLanguage.allCases){Text($0.title).tag($0)}}}
                else {HStack{Picker(L("Source Language"),selection:$model.newsLanguage){ForEach(NewsLanguage.allCases){Text($0.title).tag($0)}};Toggle(L("Translate to Russian"),isOn:Binding(get:{model.settings.translateRussian ?? false},set:{model.settings.translateRussian = $0;if $0{model.newsLanguage = .all}})).toggleStyle(.checkbox)}
                    if model.settings.translateRussian == true {HStack{Text(model.translationStatus.isEmpty ? L("Fresh English headlines are translated on this Mac") : model.translationStatus).font(.caption).foregroundStyle(.secondary);Spacer();Button(L("Prepare Translation…")){NotificationCenter.default.post(name:Notification.Name("StrokaPrepareTranslation"),object:nil)}}}
                    DisclosureGroup(L("Topic filters")){VStack(alignment:.leading,spacing:10){TextField(L("Keywords, separated by commas"),text:Binding(get:{model.settings.sessionKeywords ?? ""},set:{model.settings.sessionKeywords = $0}));TextField(L("Exclude keywords, separated by commas"),text:Binding(get:{model.settings.excludedKeywords ?? ""},set:{model.settings.excludedKeywords = $0}));Toggle(L("Short headlines · up to 11 words"),isOn:Binding(get:{model.settings.shortHeadlines ?? false},set:{model.settings.shortHeadlines = $0})).toggleStyle(.checkbox)}.textFieldStyle(.roundedBorder).padding(.top,8)}
                }
            }
            HStack{if model.upperChannel != .message {Button(L("Preview headlines…")){reviewHeadlines = true}.buttonStyle(.borderless)};Text(model.simpleContentStatus).font(.caption).foregroundStyle(.secondary);Spacer();Button{model.refreshContent()}label:{Image(systemName:"arrow.clockwise")}.disabled(model.refreshingContent || model.selectedPack.offline || model.upperChannel == .message).accessibilityLabel(L("Refresh feeds"))}
        }.padding(24).frame(width:640,height:embedded ? 520 : 650).environment(\.locale,Localization.locale)
        .sheet(isPresented:$reviewHeadlines){VStack(alignment:.leading,spacing:16){HStack{Text(L("Recent headlines")).font(.title2.weight(.semibold));Spacer();Button(L("Done")){reviewHeadlines = false}};ScrollView{LazyVStack(alignment:.leading){if model.selectedPack.offline{ForEach(model.selectedContent){story in EditorialStoryRow(model:model,story:story);Divider()}}else{ForEach(model.editorialReviewStories){story in EditorialStoryRow(model:model,story:model.displayStory(story,applyRules:false) ?? story,review:true);Divider()}}}};Text(L("News expires after 24 hours. Starred highlights never exceed 48 hours.")).font(.caption).foregroundStyle(.secondary)}.padding(24).frame(width:600,height:540)}
    }
    func addFeed() {
        let raw = address.trimmingCharacters(in:.whitespacesAndNewlines)
        let url = TelegramPublicReader.username(raw).map{"https://t.me/s/"+$0} ?? raw
        guard let parsed = URL(string:url),parsed.scheme == "https",parsed.host != nil else{sourceError = L("Enter a name and the full HTTPS feed URL.");return}
        toggle(FeedSource(name:sourceName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? URL(string:url)!.host! : sourceName,url:url),true);address = "";sourceName = "";sourceError = ""
    }
}
struct SimpleDisplaySettings:View {
    @ObservedObject var model:AppModel;@Environment(\.dismiss) var dismiss
    var body:some View {
        VStack(spacing:0) {
            HStack{Text(L("Display Settings")).font(.title2.weight(.semibold));Spacer();Button(L("Done")){dismiss()}.keyboardShortcut(.defaultAction)}.padding(24)
            Form {
                Section(L("Display")) {
                    Picker(L("Screen"),selection:$model.selectedScreen){ForEach(Array(model.screens.enumerated()),id:\.offset){index,screen in Text(screen.localizedName).tag(index)}}
                    HStack{Text(L("Strip Thickness"));Slider(value:Binding(get:{model.settings.resolvedStripHeight},set:{model.settings.stripDensity = .custom;model.settings.stripHeight = $0.rounded()}),in:45...180);Text(String(Int(model.settings.resolvedStripHeight))+" pt").monospacedDigit().frame(width:52)}
                    HStack{Text(L("Speed"));Slider(value:$model.settings.speed,in:20...260);Text(String(Int(model.settings.speed))).monospacedDigit().frame(width:36)}
                    if model.needsMarkets && model.settings.graduatedSpeeds == false {HStack{Text(L("Markets Speed"));Slider(value:Binding(get:{model.settings.marketSpeed ?? 85},set:{model.settings.marketSpeed = $0}),in:20...260)}}
                }
                // TV setup is deferred and is not exposed in the desktop release.
                Section(L("Appearance")) {
                    Toggle(L("Rounded Corners"),isOn:Binding(get:{model.settings.roundedStrip ?? true},set:{model.settings.roundedStrip = $0}))
                    Toggle(L("Show Source"),isOn:Binding(get:{model.settings.broadcastSource ?? true},set:{model.settings.broadcastSource = $0}))
                    if model.tickerRows.count > 1 {Toggle(L("Faster lower rows"),isOn:Binding(get:{model.settings.graduatedSpeeds != false},set:{model.settings.graduatedSpeeds = $0}))}
                    Toggle(L("Reduce Motion"),isOn:$model.reduceMotion)
                    Picker(L("Message Separator"),selection:Binding(get:{model.settings.resolvedSeparator},set:{model.settings.separator = $0})){ForEach(["▌▌▌","///","•••","***","◆"],id:\.self){Text($0 == "▌▌▌" ? L("Tricolor Stripes") : $0).tag($0)};if !["▌▌▌","///","•••","***","◆"].contains(model.settings.resolvedSeparator){Text(model.settings.resolvedSeparator).tag(model.settings.resolvedSeparator)}}
                    HStack{Text(L("Station logo"));Spacer();Button(model.settings.logoData == nil ? L("Upload Logo…") : L("Replace Logo…")){BroadcastBrandControls(model:model).chooseLogo()};if model.settings.logoData != nil{Button(L("Remove")){model.settings.logoData = nil;model.settings.logoName = nil}}}
                }
            }.formStyle(.grouped)
        }.frame(width:600,height:610).environment(\.locale,Localization.locale)
    }
}
