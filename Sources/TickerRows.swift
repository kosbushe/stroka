import AppKit
import SwiftUI
import Combine

// A row owns its selection. Appearance, clock, playback and translation remain shared.
struct TickerRow: Codable, Equatable, Identifiable {
    var id = UUID()
    var channel: Channel = .content
    var packID: String = "world"
    var topicIDs: [String]? = nil
    var messages: String = ""
    var customFeeds: [FeedSource] = []
    var disabledSources: [String] = []
    var language: NewsLanguage = .all
    var shortHeadlines = false
    var keywords = ""
    var excludedKeywords = ""
    var offlineLanguage: String? = nil
    init(channel:Channel = .content,packID:String = "world") {self.channel = channel;self.packID = packID}
    init(settings:Settings,language:NewsLanguage) {
        channel = settings.channel == .message ? .message : settings.channel == .markets ? .markets : .content
        packID = settings.contentPackID ?? "world";topicIDs = settings.contentTopicIDs;messages = settings.messages
        customFeeds = settings.customFeeds ?? [];disabledSources = settings.disabledContentSources ?? []
        self.language = language;shortHeadlines = settings.shortHeadlines ?? false
        keywords = settings.sessionKeywords ?? "";excludedKeywords = settings.excludedKeywords ?? "";offlineLanguage = settings.offlineLanguage
    }
    var title:String {channel == .markets ? L("Market prices") : channel == .message ? L("My Text") : (topicIDs?.isEmpty == false ? topicIDs!.map{L(ContentPack.find($0).catalogTitle)}.joined(separator:" · ") : L(ContentPack.find(packID).catalogTitle))}
    var feeds:[FeedSource] {
        guard channel == .content else {return []}
        let pack = ContentPack.find(packID);guard !pack.offline else {return []}
        var seen = Set<String>()
        return (packID == "custom" ? customFeeds : pack.sources).filter{$0.enabled && !disabledSources.contains($0.url) && seen.insert($0.url).inserted}
    }
    func apply(to settings:inout Settings) {
        settings.channel = channel;settings.dualUpperChannel = channel;settings.contentPackID = packID;settings.contentTopicIDs = topicIDs;settings.messages = messages
        settings.customFeeds = customFeeds;settings.disabledContentSources = disabledSources
        settings.shortHeadlines = shortHeadlines;settings.sessionKeywords = keywords;settings.excludedKeywords = excludedKeywords;settings.offlineLanguage = offlineLanguage
    }
}
extension Settings {
    var resolvedTickerRows:[TickerRow] {
        let first = TickerRow(settings:self,language:.all)
        if let tickerRows,!tickerRows.isEmpty {return [first]+Array(tickerRows.dropFirst().prefix(3))}
        var primary = first
        if dualTicker == true {primary.channel = dualUpperChannel == .message ? .message : .content;return [primary,TickerRow(channel:.markets)]}
        return [primary]
    }
}
extension AppModel {
    func speedForRow(_ index:Int)->Double {
        let rows = tickerRows,base = min(260,max(20,settings.speed))
        if rows.count > 1 && settings.graduatedSpeeds != false {
            let position = min(max(0,index),rows.count-1)
            return base * (1-0.1*Double(rows.count-1-position))
        }
        return index > 0 && rows.indices.contains(index) && rows[index].channel == .markets ? settings.marketSpeed ?? 85 : base
    }
    var tickerRows:[TickerRow] {var rows = settings.resolvedTickerRows;rows[0].language = newsLanguage;return rows}
    var requestedRowFeeds:[FeedSource] {
        var seen = Set<String>()
        return tickerRows.flatMap{row in row.feeds.filter{row.language == .all || $0.language == nil || $0.language == (row.language == .russian ? "ru" : "en")}}.filter{seen.insert($0.url).inserted}
    }
    func setRowCount(_ count:Int) {
        var rows = tickerRows
        let wasCompact = settings.resolvedStripDensity == .desktop
        let count = min(4,max(1,count))
        while rows.count < count {rows.append(TickerRow(packID:rows.count == 1 ? "technology" : rows.count == 2 ? "telegram" : "cinema"))}
        rows = Array(rows.prefix(count));var updated = settings;rows[0].apply(to:&updated);updated.tickerRows = rows;settings = updated
        if wasCompact {settings.stripHeight = count >= 3 ? Double(count*28) : (count == 2 ? 52 : 50)}
        settings.stripHeight = settings.resolvedStripHeight
    }
    func setRow(_ row:TickerRow,at index:Int) {
        var rows = tickerRows;guard rows.indices.contains(index) else {return}
        rows[index] = row
        if index == 0 {var s = settings;row.apply(to:&s);s.tickerRows = rows;settings = s;newsLanguage = row.language}
        else {var updated = settings;rows[0].apply(to:&updated);updated.tickerRows = rows;settings = updated}
        if row.channel == .markets && selectedMarketIDs.isEmpty && settings.cryptoPairs.isEmpty {settings.marketInstruments = ["currency:USD","currency:EUR","currency:CNY"]}
        settings.stripHeight = settings.resolvedStripHeight
    }
    func rawStories(for row:TickerRow)->[Story] {
        let pack = ContentPack.find(row.packID)
        if pack.offline {return BuiltinCollections.stories(pack:pack,language:row.offlineLanguage.flatMap(NewsLanguage.init(rawValue:)) ?? (settings.translateRussian == true ? .russian : row.language))}
        let names = Set(row.feeds.map(\.name)),urls = Set(row.feeds.map(\.url));var seen = Set<String>()
        return contentStories.filter{story in
            let belongs = story.sourceURL.map{urls.contains($0)} ?? (story.packID == pack.id && names.contains(story.source))
            return belongs && (row.language == .all || originalLanguage(story) == (row.language == .russian ? "ru" : "en")) && seen.insert(story.id).inserted
        }
    }
    func rowStories(_ index:Int)->[Story] {
        if let cached = rowStoryCache[index] {return cached}
        guard tickerRows.indices.contains(index) else {return []}
        let row = tickerRows[index],offline = ContentPack.find(row.packID).offline
        let result = rawStories(for:row).compactMap{story -> Story? in
            guard var result = displayStory(story,offline:offline,applyRules:false),offline || fresh(story) else {return nil}
            if !offline && row.shortHeadlines && !ShortText.fits(result.text) {return nil}
            guard EditorialPolicy.matches(result.text,include:row.keywords,exclude:row.excludedKeywords) else {return nil}
            result.packID = row.packID;return result
        }
        let grouped = Dictionary(grouping:result,by:{$0.source}),names = grouped.keys.sorted();var balanced:[Story] = []
        for i in 0..<(grouped.values.map(\.count).max() ?? 0) {for name in names {if let items = grouped[name],i < items.count {balanced.append(items[i])}}}
        rowStoryCache[index] = balanced;return balanced
    }
    func rowLines(_ index:Int)->[String] {
        guard tickerRows.indices.contains(index) else {return []}
        let row = tickerRows[index]
        if row.channel == .markets {return quotes.map(\.line)}
        if row.channel == .message {return row.messages.components(separatedBy:.newlines).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter{!$0.isEmpty}}
        return rowStories(index).map(\.line)
    }
    func rowRecord(_ raw:String,index:Int)->BroadcastRecord {
        if let story = rowStories(index).first(where:{$0.line == raw}) {return BroadcastRecord(text:story.text,source:story.source,date:story.date,section:L(ContentPack.find(story.packID).section),isOffline:ContentPack.find(story.packID).offline,isTranslated:story.isTranslated ?? false)}
        return BroadcastRecord(text:raw,source:settings.brand,date:nil,section:L("MESSAGES"))
    }
}

// The existing chooser edits a temporary selection; Cancel never alters a live row.
final class RowEditorState:ObservableObject {
    let draft:AppModel
    private var changes:AnyCancellable?
    let suite:String
    init(parent:AppModel,index:Int) {
        suite = "ru.bushe.stroka.row-editor.\(UUID())"
        let defaults = UserDefaults(suiteName:suite)!
        defaults.set(8,forKey:"broadcastDesignVersion");defaults.set(12,forKey:"compactStripVersion")
        var settings = parent.settings;settings.tickerRows = nil;settings.dualTicker = false
        parent.tickerRows[index].apply(to:&settings)
        defaults.set(try! JSONEncoder().encode(settings),forKey:"settings")
        defaults.set(parent.interfaceLanguage.rawValue,forKey:"interfaceLanguage");defaults.set(parent.tickerRows[index].language.rawValue,forKey:"newsLanguage")
        draft = AppModel(defaults:defaults);draft.contentStories = parent.contentStories;draft.translationCache = parent.translationCache
        draft.sourceLoadState = parent.sourceLoadState
        changes = draft.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    deinit {draft.pendingSave?.cancel();draft.editorialWake?.invalidate();draft.feedTransport.invalidate();draft.defaults.removePersistentDomain(forName:suite)}
}
struct TickerRowTarget:Identifiable {let index:Int;var id:Int {index}}
struct TickerRowEditor:View {
    @ObservedObject var model:AppModel
    let index:Int
    @Environment(\.dismiss) var dismiss
    @StateObject private var state:RowEditorState
    init(model:AppModel,index:Int) {self.model = model;self.index = index;_state = StateObject(wrappedValue:RowEditorState(parent:model,index:index))}
    var body:some View {
        VStack(spacing:0) {
            HStack {Text(LF("Row %ld",index+1)).font(.headline);Spacer();Button(L("Cancel")){dismiss()};Button(L("Save")){save();dismiss()}.buttonStyle(.borderedProminent)}.padding(.horizontal,24).padding(.vertical,14)
            Divider()
            Picker(L("Content"),selection:Binding(get:{state.draft.settings.channel},set:{state.draft.settings.channel = $0})) {Text(L("Content")).tag(Channel.content);Text(L("My Text")).tag(Channel.message);Text(L("Market prices")).tag(Channel.markets)}.pickerStyle(.segmented).padding(20)
            if state.draft.settings.channel == .markets {VStack(spacing:16){Image(systemName:"chart.xyaxis.line").font(.system(size:30)).foregroundStyle(.secondary);Text(L("Uses the instruments selected for your ticker.")).foregroundStyle(.secondary);Button(L("All instruments…")){save();NotificationCenter.default.post(name:Notification.Name("StrokaRowInstruments"),object:model);dismiss()}}.frame(width:640,height:420)}
            else if state.draft.settings.channel == .message {VStack(alignment:.leading,spacing:12){Text(L("One message per line")).font(.callout).foregroundStyle(.secondary);TextEditor(text:Binding(get:{state.draft.settings.messages},set:{state.draft.settings.messages = $0})).font(.system(size:14)).frame(minHeight:240)}.padding(24).frame(width:640,height:420)}
            else {QuickContentChooser(model:state.draft,embedded:true)}
        }.background{RussianTranslationHost(model:state.draft)}
    }
    private func save() {
        model.settings.translateRussian = state.draft.settings.translateRussian
        model.settings.extendedStories = state.draft.settings.extendedStories
        model.settings.allowExtended = state.draft.settings.allowExtended
        model.setRow(TickerRow(settings:state.draft.settings,language:state.draft.newsLanguage),at:index)
        model.refreshContent()
    }
}
