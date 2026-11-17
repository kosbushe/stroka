import SwiftUI
import AppKit

struct ContentPack: Identifiable {
    let id: String; let name: String; let detail: String; let symbol: String; let section: String
    var sources: [FeedSource] = []; var offline = false
    var isOnline: Bool { !offline }
    var languages: [String] { offline || id == "custom" ? ["en","ru"] : Array(Set(sources.compactMap(\.language))).sorted() }
    static let all: [ContentPack] = [
        ContentPack(id:"world",name:"World Headlines",detail:"The world in headlines, with links to the original reporting.",symbol:"globe.europe.africa",section:"WORLD",sources:NewsCatalog.sources("world")),
        ContentPack(id:"business",name:"Business & Economy",detail:"Business, finance and the economy from original publishers.",symbol:"chart.bar.xaxis",section:"BUSINESS",sources:NewsCatalog.sources("business")),
        ContentPack(id:"moscow",name:"Moscow",detail:"City news, transport and events in Moscow.",symbol:"building.2",section:"MOSCOW",sources:NewsCatalog.sources("moscow")),
        ContentPack(id:"ai",name:"AI & Research",detail:"Artificial intelligence, new tools, and research.",symbol:"sparkles",section:"AI",sources:NewsCatalog.sources("ai")),
        ContentPack(id:"technology",name:"Technology",detail:"Computers, software, engineering, and the people building them.",symbol:"desktopcomputer",section:"TECHNOLOGY",sources:NewsCatalog.sources("technology")),
        ContentPack(id:"science",name:"Science",detail:"Discoveries and research from science publications.",symbol:"atom",section:"SCIENCE",sources:NewsCatalog.sources("science")),
        ContentPack(id:"space",name:"Space",detail:"Missions, exploration and astronomy.",symbol:"moon.stars",section:"SPACE",sources:NewsCatalog.sources("space")),
        ContentPack(id:"culture",name:"Arts & Culture",detail:"Film, books, music and culture.",symbol:"theatermasks",section:"CULTURE",sources:NewsCatalog.sources("culture")),
        ContentPack(id:"sport",name:"Sport",detail:"Sport headlines and results from original publishers.",symbol:"sportscourt",section:"SPORT",sources:NewsCatalog.sources("sport")),
        ContentPack(id:"environment",name:"Environment",detail:"Climate, nature and our changing planet.",symbol:"leaf",section:"ENVIRONMENT",sources:NewsCatalog.sources("environment")),
        ContentPack(id:"cinema",name:"Cinema & Premieres",detail:"Film announcements, premieres and cinema news. Original headlines in English.",symbol:"film",section:"CINEMA",sources:NewsCatalog.sources("cinema")),
        ContentPack(id:"telegram",name:"Your Telegram Channels",detail:"Short previews from @aiffring and @exploitex, linked to the original posts.",symbol:"paperplane",section:"TELEGRAM",sources:[FeedSource(name:"@aiffring",url:"https://t.me/s/aiffring",language:"ru"),FeedSource(name:"@exploitex",url:"https://t.me/s/exploitex",language:"ru")]),
        ContentPack(id:"thoughts",name:"Thoughts for Today",detail:"Original short thoughts for a little perspective. Up to eleven words.",symbol:"quote.bubble",section:"THOUGHTS",offline:true),
        ContentPack(id:"jokes",name:"Just for Laughs",detail:"Short, clean jokes about work, technology, and everyday life.",symbol:"face.smiling",section:"HUMOUR",offline:true),
        ContentPack(id:"riddles",name:"Quick Riddles",detail:"A small puzzle and its answer, in one message.",symbol:"puzzlepiece.extension",section:"RIDDLES",offline:true),
        ContentPack(id:"conversation",name:"Conversation Starters",detail:"Questions for a room, a table, or a new acquaintance.",symbol:"bubble.left.and.bubble.right",section:"CONVERSATION",offline:true),
        ContentPack(id:"ideas",name:"Creative Sparks",detail:"Small prompts for fresh ideas and a different point of view.",symbol:"lightbulb",section:"IDEAS",offline:true),
        ContentPack(id:"custom",name:"Your RSS Feeds",detail:"Add the RSS or Atom sources you want on your screen.",symbol:"dot.radiowaves.left.and.right",section:"YOUR FEED")
    ]
    static func find(_ id: String?) -> ContentPack { all.first { $0.id == id } ?? all[0] }
}

struct CollectionText: Decodable { var id: String; var en: String; var ru: String }
enum BuiltinCollections {
    static let items: [String:[CollectionText]] = {
        guard let url = Bundle.main.url(forResource:"Collections",withExtension:"json"), let data = try? Data(contentsOf:url) else { return [:] }
        return (try? JSONDecoder().decode([String:[CollectionText]].self,from:data)) ?? [:]
    }()
    static func stories(pack: ContentPack, language: NewsLanguage) -> [Story] {
        (items[pack.id] ?? []).flatMap { item -> [Story] in
            let languages = language == .all ? ["en","ru"] : [language == .english ? "en" : "ru"]
            return languages.map { lang in Story(id:"\(pack.id):\(item.id):\(lang)",text:lang == "en" ? item.en : item.ru,source:L("Stroka Collection"),date:nil,link:"",language:lang,packID:pack.id) }
        }
    }
}
struct BroadcastRecord {
    var text: String; var source: String; var date: Date?; var section: String; var isQuote = false; var isOffline = false; var isTranslated = false
    var stamp: String { date.map { $0.formatted(Date.FormatStyle(date:.abbreviated,time:.shortened).locale(Localization.locale)) } ?? (isOffline ? L("Offline Collection") : L("Selected Feed")) }
}

extension AppModel {
    func openDisplaySettings() {
        if let window = controlWindow {
            if window.isMiniaturized {window.deminiaturize(nil)}
            window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        }
        NotificationCenter.default.post(name:Notification.Name("StrokaDisplaySettings"),object:self)
    }
    var selectedPack: ContentPack { ContentPack.find(settings.contentPackID) }
    var contentSources:[FeedSource] {
        let rows = selectedPack.id == "custom" ? (settings.customFeeds ?? []) : selectedPack.id == "ai" ? settings.feeds+NewsCatalog.sources("ai") : selectedPack.sources
        var seen = Set<String>();return rows.filter{seen.insert($0.url).inserted}
    }
    var enabledContentSources: [FeedSource] { let disabled = Set(settings.disabledContentSources ?? []); return contentSources.filter { $0.enabled && !disabled.contains($0.url) } }
    var selectedContent: [Story] {
        if let cachedContent { return cachedContent }
        let pack = selectedPack
        let result: [Story]
        result = currentRawStories.compactMap{displayStory($0,offline:pack.offline)}
        let groups = Dictionary(grouping:result,by:{$0.source}); let names = groups.keys.sorted()
        var balanced:[Story] = []
        for index in 0..<(groups.values.map(\.count).max() ?? 0) { for name in names { if let rows = groups[name],index < rows.count { balanced.append(rows[index]) } } }
        cachedContent = balanced; return balanced
    }
    func selectPack(_ id:String) {
        settings.contentTopicIDs = nil
        settings.contentPackID = id
        if ["cinema","thoughts","telegram"].contains(id) {
            settings.shortHeadlines = true
            let languages = ContentPack.find(id).languages
            if newsLanguage != .all && !languages.contains(newsLanguage == .english ? "en" : "ru") { newsLanguage = languages.first == "ru" ? .russian : .english }
        }
        if !selectedPack.offline,newsLanguage != .all {
            let languages = selectedPack.languages
            if !languages.isEmpty && !languages.contains(newsLanguage == .russian ? "ru" : "en") { newsLanguage = languages.first == "ru" ? .russian : .english }
        }
        sequence += 1
    }
    func setContentSource(_ feed: FeedSource, enabled: Bool) {
        if selectedPack.id == "ai",let index = settings.feeds.firstIndex(where:{$0.url == feed.url}) { settings.feeds[index].enabled = enabled }
        var disabled = Set(settings.disabledContentSources ?? []); if enabled { disabled.remove(feed.url) } else { disabled.insert(feed.url) }; settings.disabledContentSources = disabled.sorted()
    }
    @discardableResult func normalizeBroadcastStyle()->Bool {
        let resolved = settings.look.resolvedBroadcastLook
        guard resolved != settings.look else { return false };settings.look = resolved;return true
    }
    func applyLook(_ requested: Look) {
        let look = requested.resolvedBroadcastLook
        let density = settings.resolvedStripDensity
        settings.look = look
        if look.isBroadcast {
            settings.composition = .ticker;settings.motion = .horizontal;settings.fontSize = 32
            settings.applyDensity(density);settings.stripPlacement = settings.resolvedPlacement;previewMode = .strip
        }
    }
    func rebuildRecords() {
        recordCache = [:]
        if upperChannel == .ai || (upperChannel == .mix && settings.mixAI) { for story in availableStories { recordCache[story.line] = BroadcastRecord(text:story.text,source:story.source,date:story.date,section:"AI",isTranslated:story.isTranslated ?? false) } }
        if upperChannel == .content || (upperChannel == .mix && settings.mixThreads) { for story in selectedContent { recordCache[story.line] = BroadcastRecord(text:story.text,source:story.source,date:story.date,section:L(selectedPack.section),isOffline:selectedPack.offline,isTranslated:story.isTranslated ?? false) } }
        if upperChannel == .markets || (upperChannel == .mix && settings.mixMarkets) { for quote in quotes { recordCache[quote.line] = BroadcastRecord(text:"\(quote.id)   \(quote.formatted)\(quote.change.map { String(format:"   %+.2f%%",locale:Localization.locale,$0) } ?? "")",source:quote.source,date:quote.time,section:L("MARKETS"),isQuote:true) } }
    }
    func record(for raw: String) -> BroadcastRecord {
        _ = lines
        let section = upperChannel == .content ? L(selectedPack.section) : upperChannel == .ai ? "AI" : upperChannel == .markets ? L("MARKETS") : L("MESSAGES")
        return recordCache[raw] ?? BroadcastRecord(text:raw,source:settings.brand,date:nil,section:section)
    }
    func refreshContent() {
        guard !refreshingContent, selectedPack.isOnline || settings.tickerRows != nil else { return }
        let pack = selectedPack; let selected = settings.tickerRows != nil ? requestedRowFeeds : enabledContentSources.filter { newsLanguage == .all || $0.language == nil || $0.language == (newsLanguage == .english ? "en" : "ru") }
        guard !selected.isEmpty else { return }
        refreshingContent = true; lastContentRefresh = Date(); let generation = contentGeneration; let dataGen = dataGeneration; let group = DispatchGroup()
        for feed in selected {
            guard let url = URL(string:feed.url), url.scheme == "https", url.host != nil else { continue }
            group.enter(); feedStatus[feed.id] = L("Refreshing…");sourceLoadState[feed.url] = .loading
            feedTransport.load(url,scope:"content") { [weak self] data,response,error in
                var rows:[Story] = []; var failure:String?
                if let error { failure = LF("Network error (%ld). Check your connection.",(error as NSError).code) }
                else if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 { failure = "HTTP \(code)" }
                else if let data, data.count <= 5_000_000 { rows = (feed.isTelegram ? TelegramPublicReader.read(data,source:feed) : RSSReader(source:feed.name,language:feed.language).read(data)).map { var story = $0; story.packID = pack.id;story.sourceURL = feed.url; return story }; if rows.isEmpty { failure = feed.isTelegram ? L("No public posts found in this channel") : L("No RSS or Atom headlines in this feed") } }
                else { failure = L("The source returned an empty or oversized response") }
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let self, self.contentGeneration == generation, self.dataGeneration == dataGen else { return }
                    if let failure { self.feedStatus[feed.id] = LF("Couldn’t refresh: %@",failure);self.sourceLoadState[feed.url] = .failed(failure) }
                    else {
                        self.contentStories.removeAll { $0.sourceURL == feed.url || ($0.sourceURL == nil && $0.packID == pack.id && $0.source == feed.name) }; self.contentStories += rows
                        self.contentStories.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                        // Keep a bounded, fair cache so a busy feed cannot evict every other row.
                        let groups = Dictionary(grouping:self.contentStories,by:{$0.sourceURL ?? $0.source})
                        let allowance = min(120,max(1,2800/max(1,groups.count)))
                        self.contentStories = groups.values.flatMap{Array($0.prefix(allowance))}.sorted{($0.date ?? .distantPast)>($1.date ?? .distantPast)}
                        self.feedStatus[feed.id] = LF("%ld headlines",rows.count); self.feedUpdated[feed.id] = Date();self.sourceLoadState[feed.url] = .loaded(Date())
                    }
                }
            }
        }
        group.notify(queue:.main) { [weak self] in
            guard let self, self.contentGeneration == generation, self.dataGeneration == dataGen else { return }
            self.refreshingContent = false
            if let data = try? JSONEncoder().encode(self.contentStories) { self.defaults.set(data,forKey:"contentCache") }
        }
    }
}

struct ContentLibraryView:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { VStack(alignment:.leading,spacing:4) { Text(L(model.selectedPack.name)).font(.headline);if let title = model.settings.sessionTitle,!title.isEmpty { Text(title).font(.caption).foregroundStyle(.secondary) } };Spacer();Button{NotificationCenter.default.post(name:Notification.Name("StrokaContentSources"),object:nil)}label:{Label(L("Choose Your Feed…"),systemImage:"newspaper")} }
            HStack { Text(model.selectedPack.offline ? L("Offline Collection") : L("News · 24 hours")).font(.caption).foregroundStyle(.secondary);if model.settings.translateRussian == true {Text(L("Russian Translation")).font(.caption).foregroundStyle(.secondary)};Spacer();if model.refreshingContent {ProgressView().controlSize(.small)} }
            if model.settings.translateRussian == true && model.translationNeedsDownload { HStack { Text(model.translationStatus).font(.caption).foregroundStyle(.secondary);Spacer();Button(L("Prepare Translation…")){NotificationCenter.default.post(name:Notification.Name("StrokaPrepareTranslation"),object:nil)} } }
            if model.selectedContent.isEmpty { emptyState(model.refreshingContent ? L("Loading your feed…") : L("No eligible messages yet"),detail:L("Check sources, topic filters, publication dates and translation readiness.")) }
            else { ScrollView { LazyVStack(alignment:.leading,spacing:0) { ForEach(model.selectedContent){story in EditorialStoryRow(model:model,story:story);Divider()} }.padding(.trailing,6) } }
        }
    }
}
struct ContentBrowserView: View {
    @ObservedObject var model: AppModel; @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { VStack(alignment:.leading,spacing:5) { Text(L("Something Worth Showing")).font(.system(size:27,weight:.semibold)); Text(L("News, a little humour, or a conversation waiting to happen.")).foregroundStyle(.secondary) }; Spacer(); Button(L("Done")) { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollView { LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:16),count:3),spacing:16) {
                ForEach(ContentPack.all) { pack in
                    Button { model.selectPack(pack.id); dismiss() } label: {
                        VStack(alignment:.leading,spacing:10) {
                            HStack { Image(systemName:pack.symbol).font(.system(size:23)).foregroundStyle(.tint); Spacer(); if model.selectedPack.id == pack.id { Image(systemName:"checkmark.circle.fill").foregroundStyle(.tint) } }
                            Text(L(pack.name)).font(.system(size:16,weight:.semibold))
                            Text(L(pack.detail)).font(.system(size:12)).foregroundStyle(.secondary).frame(height:48,alignment:.topLeading)
                            Text(pack.offline ? L("Offline · English & Russian") : pack.id == "telegram" ? L("Telegram · Russian") : pack.id == "custom" ? "RSS / Atom" : pack.languages == ["en"] ? L("RSS · English") : pack.languages == ["ru"] ? L("RSS · Russian") : L("RSS · English & Russian")).font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                        }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(model.selectedPack.id == pack.id ? Color.accentColor : Color(nsColor:.separatorColor),lineWidth:model.selectedPack.id == pack.id ? 2 : 0.5))
                    }.buttonStyle(.plain)
                }
            }.padding(3) }
        }.padding(28).frame(width:900,height:690)
    }
}
struct CustomFeedsView: View {
    @ObservedObject var model: AppModel; @Environment(\.dismiss) var dismiss
    @State private var name = ""; @State private var address = ""; @State private var error = ""
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(L("Your RSS Feeds")).font(.title2.weight(.semibold))
            Text(L("Add a public HTTPS RSS or Atom URL. Headlines keep their original language.")).foregroundStyle(.secondary)
            ScrollView { VStack(alignment:.leading,spacing:12) { ForEach(model.settings.customFeeds ?? []) { feed in HStack { VStack(alignment:.leading) { Text(feed.name).font(.headline); Text(feed.url).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { model.settings.customFeeds?.removeAll{$0.id == feed.id} } label: { Image(systemName:"minus.circle") }.accessibilityLabel(L("Remove source")) }; Divider() } } }.frame(height:160)
            TextField(L("Name"),text:$name); TextField("https://…",text:$address)
            if !error.isEmpty { Text(error).font(.callout).foregroundStyle(.red) }
            HStack { Button(L("Add")) { add() }; Spacer(); Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width:620)
    }
    func add() {
        let title = name.trimmingCharacters(in:.whitespacesAndNewlines)
        let raw = address.trimmingCharacters(in:.whitespacesAndNewlines)
        let channelInput = raw.hasPrefix("@") || ["t.me","telegram.me"].contains(URL(string:raw)?.host?.lowercased() ?? "")
        let input = channelInput ? TelegramPublicReader.username(raw).map { "https://t.me/s/"+$0 } ?? raw : raw
        guard !title.isEmpty, let url = URL(string:input), url.scheme == "https", url.host != nil else { error = L("Enter a name and the full HTTPS feed URL."); return }
        guard !(model.settings.customFeeds ?? []).contains(where:{$0.url == input || $0.name == title}) else { error = L("This source has already been added."); return }
        model.settings.customFeeds = (model.settings.customFeeds ?? []) + [FeedSource(name:title,url:input)]; model.selectPack("custom"); name = ""; address = ""; error = ""
    }
}
