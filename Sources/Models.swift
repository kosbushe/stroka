import AppKit
import SwiftUI
import Foundation

enum Channel: String, CaseIterable, Codable, Identifiable {
    case message = "Мой текст", ai = "AI-новости", content = "Threads", markets = "Котировки", mix = "Микс"
    var id: String { rawValue }
    var icon: String { switch self { case .message: return "text.alignleft"; case .ai: return "sparkles"; case .content: return "rectangle.stack"; case .markets: return "chart.line.uptrend.xyaxis"; case .mix: return "shuffle" } }
}
enum Look: String, CaseIterable, Codable, Identifiable {
    case glass = "Glass", white = "White", black = "Black"
    case metro = "Metro", pulse = "Bulletin Duo", editorial = "Editorial", nightline = "Nightline", signal = "Signal Blue", minimal = "Clean Line"
    case bulletin = "TV Bulletin", wire = "News Wire", desk = "Market Desk"
    case studio = "Студия", led = "LED", neon = "Неон", paper = "Бумага", ribbon = "Лента", champagne = "Шампань", graphite = "Графит", electric = "Электро"
    var id: String { rawValue }
    static let broadcastLooks:[Look] = [.bulletin,.nightline,.metro,.glass]
    static let legacyBroadcastLooks:[Look] = [.wire,.desk,.signal,.pulse,.editorial,.minimal]
    var isBroadcast:Bool { Self.broadcastLooks.contains(self) || Self.legacyBroadcastLooks.contains(self) }
    var resolvedBroadcastLook:Look { switch self { case .pulse:return .bulletin;case .editorial,.minimal:return .metro;case .wire,.signal:return .glass;case .desk:return .nightline;default:return self } }
    var broadcastDetail:String { switch self {
    case .bulletin:return "White ticker · red station"
    case .wire:return "Navy ticker · teal station"
    case .desk:return "Black ticker · gold accents"
    case .metro:return "Black and white · editorial type"
    case .nightline:return "Charcoal ticker · quiet blue"
    case .signal:return "Blue ticker · light station"
    default:return ""
    } }
    var bg: NSColor { switch self { case .metro,.editorial,.minimal: return hex(0xFAFAFA); case .pulse: return .white; case .nightline: return hex(0x111418); case .signal: return hex(0x143E8E); case .glass: return BusheDesign.midnight; case .white: return .white; case .black: return .black; case .bulletin: return hex(0xF5F6F8); case .wire: return hex(0x081C2C); case .desk: return hex(0x101820); case .studio: return hex(0x132D46); case .led: return hex(0x101716); case .neon: return hex(0x201331); case .paper: return hex(0xF0EDE5); case .ribbon: return hex(0x303F83); case .champagne: return hex(0xF4EFE7); case .graphite: return hex(0x171719); case .electric: return hex(0xE8F963) } }
    var ink: NSColor { switch self { case .signal: return .white; case .metro,.pulse,.editorial,.minimal: return hex(0x151A22); case .nightline: return hex(0xFAFAFA); case .glass: return hex(0xFAFBFF); case .white: return .black; case .black: return .white; case .bulletin: return hex(0x171B20); case .wire, .desk: return hex(0xF7F9FB); case .studio: return hex(0xF5F7FA); case .led: return hex(0xFFC663); case .neon: return hex(0xF4A8ED); case .paper: return hex(0x243D4E); case .ribbon: return hex(0xF5E7B7); case .champagne: return hex(0x5B493F); case .graphite: return hex(0xF5F5F7); case .electric: return hex(0x20231B) } }
    var accent: NSColor { switch self { case .metro: return hex(0x151A22); case .pulse: return hex(0xB7172B); case .editorial: return hex(0x34465D); case .nightline: return hex(0x7BADE0); case .signal: return hex(0xDFEAFF); case .minimal: return hex(0x202B38); case .glass: return hex(0xC1D2F2); case .white: return hex(0x474747); case .black: return hex(0xC7C7CC); case .bulletin: return hex(0xC9162D); case .wire: return hex(0x57D9CC); case .desk: return hex(0xFFC53D); case .studio: return hex(0x7BD8D0); case .led: return hex(0xFFC663); case .neon: return hex(0xB5B4FF); case .paper: return hex(0x376E85); case .ribbon: return hex(0xF5E7B7); case .champagne: return hex(0x8C5C43); case .graphite: return hex(0xC3CBD5); case .electric: return hex(0x6B3FBC) } }
}
enum Motion: String, CaseIterable, Codable, Identifiable {
    case horizontal = "Бегущая строка", vertical = "Титры", phrases = "Целые фразы", words = "По словам"
    var id: String { rawValue }
}
enum OutputMode: String, CaseIterable, Identifiable {
    case full = "Полный экран", strip = "Полоса", frame = "Рамка экрана"
    var id: String { rawValue }
}
enum StripPlacement: String, Codable, CaseIterable, Identifiable {
    case bottom = "Снизу", top = "Сверху", left = "Слева", right = "Справа", center = "По центру", floating = "Свободно"
    var id: String { rawValue }
    var vertical: Bool { self == .left || self == .right }
}
enum Composition: String, Codable, CaseIterable, Identifiable {
    case ticker = "Лента", poster = "Афиша", split = "Две зоны"
    var id: String { rawValue }
}
enum NewsLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "English", russian = "Русский", all = "Все языки"
    var id: String { rawValue }
}
struct FeedSource: Codable, Identifiable, Equatable {
    var id = UUID(); var name: String; var url: String; var enabled = true
    var language: String? = nil
    static let defaults = [
        FeedSource(name: "Habr · AI", url: "https://habr.com/ru/rss/hubs/artificial_intelligence/all/?fl=ru", language: "ru"),
        FeedSource(name: "TechCrunch · AI", url: "https://techcrunch.com/category/artificial-intelligence/feed/", language: "en"),
        FeedSource(name: "The Verge · AI", url: "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml", language: "en"),
        FeedSource(name: "Google · AI", url: "https://blog.google/technology/ai/rss/", language: "en")
    ]
}
struct Story: Codable, Identifiable, Equatable {
    var id: String; var text: String; var source: String; var date: Date?; var link: String
    var language: String? = nil
    var sourceURL: String? = nil
    var packID: String? = nil
    var isExcerpt:Bool? = nil
    var isTranslated:Bool? = nil
    var originalText:String? = nil
    var translationKey:String { id+"|"+text }
    var wordCount:Int { ShortText.count(text) }
    var line: String { "\(source.uppercased())  /  \(text)" }
}
struct Quote: Identifiable, Equatable {
    var id: String; var value: Double; var change: Double?; var time: Date; var received: Date; var source: String
    var currency:String? = nil; var label:String? = nil; var cadence:QuoteCadence? = nil; var instrumentID:String? = nil
    var formatted: String { value.formatted(.number.precision(.fractionLength(value < 1 ? 4 : 2)).locale(Localization.locale)) }
    var line:String { "\(id)  \(displayValue)\(change.map { String(format:"  %+.2f%%",$0) } ?? "")  ·  \(source) · \(dataNote) · \(timeLabel)" }
}
enum StripDensity:String,Codable,CaseIterable,Identifiable {
    case desktop, broadcast, custom
    var id:String { rawValue }
    var title:String { L(self == .desktop ? "Desktop" : self == .broadcast ? "Broadcast" : "Custom") }
}
struct Settings: Codable {
    var channel: Channel = .content; var look: Look = .glass; var motion: Motion = .horizontal
    var messages = L("Welcome!\nWe’ll begin in 5 minutes\nQuestions are welcome after the talk")
    var speed: Double = 95; var fontSize: Double = 48; var holdSeconds: Double = 7
    var reverse = false; var mirror = false; var stripTop = false; var stripHeight: Double = 144
    var idleEnabled = false; var idleMinutes: Double = 5
    var feeds = FeedSource.defaults
    var rssMinutes: Double = 3
    var brand = L("STROKA"); var showClock = true
    var mixOwn = true; var mixAI = true; var mixThreads = false; var mixMarkets = true
    var cryptoPairs = "BTC-USD, ETH-USD"
    var stripPlacement: StripPlacement? = nil
    var composition: Composition? = nil
    var caption: String? = nil
    var contentPackID: String? = nil
    var contentTopicIDs: [String]? = nil
    var customFeeds: [FeedSource]? = nil
    var disabledContentSources: [String]? = nil
    var logoData: Data? = nil
    var logoName: String? = nil
    var logoPlate: Bool? = nil
    var broadcastSource: Bool? = nil
    var broadcastDate: Bool? = nil
    var dualTicker: Bool? = nil
    var dualUpperChannel: Channel? = nil
    var tickerRows: [TickerRow]? = nil
    var graduatedSpeeds:Bool? = nil
    var fitWindows:Bool? = nil
    var marketSpeed: Double? = nil
    var marketInstruments:[String]? = nil
    var roundedStrip:Bool? = nil
    var stripDensity:StripDensity? = nil
    var shortHeadlines:Bool? = nil
    var allowExtended:Bool? = nil
    var extendedStories:[String]? = nil
    var sessionTitle:String? = nil
    var sessionKeywords:String? = nil
    var excludedKeywords:String? = nil
    var offlineLanguage:String? = nil
    var translateRussian:Bool? = nil
    var resolvedStripDensity:StripDensity { stripDensity ?? ((stripHeight == 52 || stripHeight == 50) ? .desktop : (stripHeight == 88 || stripHeight == 144 ? .broadcast : .custom)) }
    mutating func applyDensity(_ value:StripDensity) { stripDensity = value;if value != .custom { stripHeight = value == .desktop ? (dualTicker == true ? 52 : 50) : (dualTicker == true ? 144 : 88) } }
    var separator: String? = nil
    var resolvedSeparator: String { MessageSeparators.resolve(separator) }
    var resolvedStripHeight:Double { min(180,max(45,stripHeight)) }
    var resolvedPlacement: StripPlacement { stripPlacement ?? (stripTop ? .top : .bottom) }
    var resolvedComposition: Composition { composition ?? .ticker }
}
struct ScenePreset: Codable, Identifiable {
    var id = UUID(); var name: String; var settings: Settings; var newsLanguage: NewsLanguage? = nil
}
func hex(_ value: UInt32) -> NSColor { NSColor(srgbRed: CGFloat((value >> 16) & 255)/255, green: CGFloat((value >> 8) & 255)/255, blue: CGFloat(value & 255)/255, alpha: 1) }
let teal = Color.accentColor

class AppModel: ObservableObject {
    let defaults: UserDefaults
    @Published var interfaceLanguage: InterfaceLanguage {
        didSet {
            guard oldValue != interfaceLanguage else { return }
            Localization.language = interfaceLanguage
            invalidateTextCache()
            defaults.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage")
            invalidatePendingContent()
            feedStatus = [:]
            cryptoStatus = L("Connecting…"); moexStatus = L("Waiting for data")
            sequence += 1
            NotificationCenter.default.post(name: Notification.Name("StrokaLanguageChanged"), object: nil)
            if servicesStarted { synchronizeServices(force: true) }
        }
    }
    private var cachedLines: [String]?
    private var cachedStories: [Story]?
    var cachedContent: [Story]?
    var recordCache: [String: BroadcastRecord] = [:]
    var rowStoryCache: [Int:[Story]] = [:]
    var rowLineCache: [Int:[String]] = [:]
    var rowRecordCache: [Int:[String:BroadcastRecord]] = [:]
    var textRevision = 0
    var lineBuildCount = 0
    func invalidateTextCache() { cachedLines = nil; cachedStories = nil; cachedContent = nil; recordCache = [:]; rowStoryCache = [:];rowLineCache = [:];rowRecordCache = [:];textRevision &+= 1 }
    var editorialWake:Timer?
    @Published var translationCache:[String:String] = [:]
    @Published var translationSignal = 0
    @Published var translationStatus = ""
    @Published var translationNeedsDownload = false
    var translationFailures = Set<String>()
    @Published var marketUniverse:[MarketInstrument] = MarketCatalog.all
    @Published var marketCatalogStatus = ""
    var marketSequence = 0
    var logoRevision = 0
    var cachedLogo: NSImage?
    @Published var settings: Settings {
        didSet {
            if oldValue.tickerRows != settings.tickerRows { sequence += 1;translationSignal += 1 }
            if oldValue.cryptoPairs != settings.cryptoPairs { marketSequence += 1 }
            if oldValue.dualTicker != settings.dualTicker || oldValue.dualUpperChannel != settings.dualUpperChannel { sequence += 1 }
            if oldValue.logoData != settings.logoData { logoRevision += 1; cachedLogo = nil }
            invalidateTextCache(); saveSettings()
            if oldValue.fitWindows != settings.fitWindows { synchronizeWindowFit() }
            if oldValue.allowExtended != settings.allowExtended || oldValue.extendedStories != settings.extendedStories { scheduleEditorialExpiry();translationSignal += 1 }
            if oldValue.translateRussian != settings.translateRussian || oldValue.contentPackID != settings.contentPackID { translationSignal += 1 }
            if oldValue.tickerRows != settings.tickerRows || oldValue.contentPackID != settings.contentPackID || (settings.contentPackID == "custom" && oldValue.customFeeds != settings.customFeeds) || oldValue.disabledContentSources != settings.disabledContentSources {
                contentGeneration += 1; refreshingContent = false; lastContentRefresh = .distantPast;storedFeedTransport?.cancel(scope:"content")
            }
            if oldValue.feeds != settings.feeds {dataGeneration += 1;refreshing = false;lastNewsRefresh = .distantPast;storedFeedTransport?.cancel(scope:"news")}
            if oldValue.channel != settings.channel || oldValue.messages != settings.messages { sequence += 1 }
            if servicesStarted {
                synchronizeServices()
                if oldValue.marketInstruments != settings.marketInstruments && needsMarkets { market.refreshWatchlist() }
                if oldValue.cryptoPairs != settings.cryptoPairs && needsMarkets { market.connect(pairs: settings.cryptoPairs) }
            }
            if oldValue.resolvedPlacement != settings.resolvedPlacement || oldValue.resolvedStripHeight != settings.resolvedStripHeight || oldValue.resolvedComposition != settings.resolvedComposition { outputs?.updateConfiguration() }
        }
    }
    @Published var stories: [Story] = [] { didSet { invalidateTextCache();scheduleEditorialExpiry();translationSignal += 1 } }
    @Published var contentStories: [Story] = [] { didSet { invalidateTextCache();scheduleEditorialExpiry();translationSignal += 1 } }
    @Published var refreshingContent = false
    @Published var quotes: [Quote] = [] { didSet { cachedLines = nil } }
    @Published var feedStatus: [UUID: String] = [:]
    @Published var sourceLoadState:[String:FeedLoadState] = [:]
    @Published var feedUpdated: [UUID: Date] = [:]
    @Published var refreshing = false
    @Published var cryptoStatus = L("Connecting…")
    @Published var moexStatus = L("Waiting for data")
    @Published var playing = true
    @Published var urgent = ""
    @Published var sequence = 0
    @Published var showOnboarding = false
    @Published var activeMode: OutputMode?
    @Published var previewMode: OutputMode = .full
    @Published var selectedScreen = 0
    @Published var screens = NSScreen.screens
    @Published var presets: [ScenePreset] = []
    @Published var remoteInfo = ""
    @Published var tvSharing = false
    @Published var tvAddress = ""
    @Published var tvPairCode = ""
    @Published var tvStatus = ""
    var tvBridge:TVBridgeServer?
    @Published var remoteEnabled = false
    @Published var newsLanguage: NewsLanguage { didSet { guard oldValue != newsLanguage else {return};invalidateTextCache(); defaults.set(newsLanguage.rawValue, forKey: "newsLanguage"); sequence += 1;translationSignal += 1;invalidatePendingContent();lastNewsRefresh = .distantPast;lastContentRefresh = .distantPast;if servicesStarted {synchronizeServices()} } }
    @Published var reduceMotion: Bool { didSet { defaults.set(reduceMotion, forKey: "reduceMotion"); sequence += 1 } }
    var effectiveMotion: Motion { reduceMotion ? .phrases : settings.motion }
    weak var controlWindow: NSWindow?
    var outputs: OutputController!
    lazy var market = MarketService(model: self)
    var remote: RemoteServer?
    var servicesStarted = false
    var dualBandActive: Bool { settings.resolvedTickerRows.count > 1 && settings.look.isBroadcast }
    var upperChannel: Channel { if settings.tickerRows != nil {return settings.resolvedTickerRows[0].channel};return dualBandActive ? ([Channel.message,.ai,.content].contains(settings.dualUpperChannel ?? .content) ? settings.dualUpperChannel ?? .content : .content) : settings.channel }
    var needsNews: Bool { upperChannel == .ai || (upperChannel == .mix && settings.mixAI) }
    var needsContent: Bool { if settings.tickerRows != nil {return !requestedRowFeeds.isEmpty};return (upperChannel == .content || (upperChannel == .mix && settings.mixThreads)) && selectedPack.isOnline }
    var needsMarkets: Bool { if settings.tickerRows != nil {return settings.resolvedTickerRows.contains{$0.channel == .markets}};return dualBandActive || settings.channel == .markets || (settings.channel == .mix && settings.mixMarkets) || settings.resolvedComposition == .split }
    var newsTimer: Timer?; var idleTimer: Timer?; var idleOutput = false
    var dataGeneration = 0; var contentGeneration = 0
    var lastNewsRefresh = Date.distantPast
    var lastContentRefresh = Date.distantPast
    var lastObservedIdle: TimeInterval = 0
    var pendingSave: DispatchWorkItem?
    private var storedFeedTransport:FeedTransport?
    var feedTransport:FeedTransport { if let storedFeedTransport {return storedFeedTransport};let transport = FeedTransport(configuration:session.configuration);storedFeedTransport = transport;return transport }
    deinit { storedFeedTransport?.invalidate() }
    let session: URLSession
    static func makeSession() -> URLSession { URLSession(configuration: {
        let c = URLSessionConfiguration.default; c.timeoutIntervalForRequest = 15; c.timeoutIntervalForResource = 25
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
        c.httpAdditionalHeaders = ["User-Agent": "Stroka/\(version) macOS RSS reader"]
        return c
    }()) }
    init(defaults: UserDefaults = .standard, session: URLSession? = nil) {
        let compactMigration = defaults.integer(forKey:"compactStripVersion") < 12
        self.defaults = defaults
        self.session = session ?? Self.makeSession()
        let language = InterfaceLanguage(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "en") ?? .english
        interfaceLanguage = language
        Localization.language = language
        newsLanguage = NewsLanguage(rawValue: defaults.string(forKey: "newsLanguage") ?? "") ?? .english
        reduceMotion = defaults.object(forKey: "reduceMotion") == nil ? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion : defaults.bool(forKey: "reduceMotion")
        settings = defaults.data(forKey: "settings").flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        presets = defaults.data(forKey: "presets").flatMap { try? JSONDecoder().decode([ScenePreset].self, from: $0) } ?? []
        stories = defaults.data(forKey: "newsCache").flatMap { try? JSONDecoder().decode([Story].self, from: $0) } ?? []
        if defaults.integer(forKey: "feedDefaultsVersion") < 1 {
            if !settings.feeds.contains(where: { $0.url.contains("habr.com") }), let russian = FeedSource.defaults.first { settings.feeds.insert(russian, at: 0) }
            defaults.set(1, forKey: "feedDefaultsVersion")
        }
        cryptoStatus = L("Connecting…"); moexStatus = L("Waiting for data")
        contentStories = defaults.data(forKey: "contentCache").flatMap { try? JSONDecoder().decode([Story].self, from: $0) } ?? []
        if defaults.integer(forKey:"broadcastDesignVersion") < 8 {
            if settings.look.isBroadcast { settings.stripHeight = 88; settings.fontSize = 32 }
            defaults.set(8,forKey:"broadcastDesignVersion")
        }
        if compactMigration {
            if settings.look.isBroadcast && settings.stripHeight <= 64 { settings.applyDensity(.desktop) }
            defaults.set(12,forKey:"compactStripVersion")
        }
        let heightNeedsNormalization = settings.stripHeight != settings.resolvedStripHeight
        settings.stripHeight = settings.resolvedStripHeight
        if settings.look.isBroadcast { previewMode = .strip }
        if let cache = defaults.data(forKey:"marketCatalog"),let rows = try? JSONDecoder().decode([MarketInstrument].self,from:cache),!rows.isEmpty { marketUniverse = rows }
        translationCache = defaults.data(forKey:"translationCache").flatMap { try? JSONDecoder().decode([String:String].self,from:$0) } ?? [:]
        outputs = OutputController(model: self)
        scheduleEditorialExpiry()
        let navigationMigration = normalizeContentNavigation()
        let broadcastMigration = normalizeBroadcastStyle()
        if compactMigration || heightNeedsNormalization || navigationMigration || broadcastMigration { saveSettingsNow() }
    }
    func start() {
        servicesStarted = true; synchronizeServices(force: true)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; self.screens = NSScreen.screens; self.selectedScreen = min(self.selectedScreen, max(0, self.screens.count - 1)); self.outputs.stop()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.outputs.stop() }
    }
    func synchronizeServices(force: Bool = false) {
        guard servicesStarted else { return }
        if needsMarkets { market.start(); if force { market.fetchMOEX() } } else { market.stop() }
        if needsNews && (force || Date().timeIntervalSince(lastNewsRefresh) >= settings.rssMinutes*60) { refreshNews() }
        if needsContent && (force || Date().timeIntervalSince(lastContentRefresh) >= settings.rssMinutes*60) { refreshContent() }
        if needsNews || needsContent {
            if newsTimer == nil {
                let timer = Timer.scheduledTimer(withTimeInterval:15,repeats:true) { [weak self] _ in
                    guard let self else { return }
                    if self.needsNews && Date().timeIntervalSince(self.lastNewsRefresh) >= self.settings.rssMinutes*60 { self.refreshNews() }
                    if self.needsContent && Date().timeIntervalSince(self.lastContentRefresh) >= self.settings.rssMinutes*60 { self.refreshContent() }
                }; timer.tolerance = 2; newsTimer = timer
            }
        } else { newsTimer?.invalidate(); newsTimer = nil }
        if settings.idleEnabled {
            if idleTimer == nil { let timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in self?.checkIdle() }; timer.tolerance = 0.2; idleTimer = timer }
        } else { idleTimer?.invalidate(); idleTimer = nil; if idleOutput { outputs?.stop() } }
    }
    func saveSettings() {
        pendingSave?.cancel(); let work = DispatchWorkItem { [weak self] in self?.saveSettingsNow() }; pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func saveSettingsNow() { pendingSave?.cancel(); pendingSave = nil; if let d = try? JSONEncoder().encode(settings) { defaults.set(d, forKey: "settings") } }
    var ownLines: [String] { settings.messages.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    var availableStories: [Story] {
        if let cachedStories { return cachedStories }
        let names = Set(settings.feeds.filter(\.enabled).map(\.name))
        let result = stories.filter { names.contains($0.source) && sourceLanguageMatches($0) }.compactMap{displayStory($0)}
        cachedStories = result; return result
    }
    var lines: [String] {
        if let cachedLines { return cachedLines }
        lineBuildCount += 1; let result = buildLines(); cachedLines = result; rebuildRecords(); return result
    }
    private func buildLines() -> [String] {
        switch upperChannel {
        case .message: return ownLines
        case .ai: return availableStories.map(\.line)
        case .content: return selectedContent.map(\.line)
        case .markets: return quotes.map(\.line)
        case .mix:
            let groups = [settings.mixOwn ? ownLines : [], settings.mixAI ? availableStories.map(\.line) : [], settings.mixThreads ? selectedContent.map(\.line) : [], settings.mixMarkets ? quotes.map(\.line) : []]
            var result: [String] = []
            for i in 0..<(groups.map(\.count).max() ?? 0) { for group in groups where i < group.count { result.append(group[i]) } }
            return result
        }
    }
    var emptyMessage: String {
        switch upperChannel {
        case .message: return L("Enter a message in the control window")
        case .ai: return refreshing ? L("Loading AI headlines…") : L("No headlines · check your sources")
        case .content: return refreshingContent ? L("Loading your feed…") : L("Choose a feed or add an RSS source")
        case .markets: return L("Waiting for market data · check your connection")
        case .mix: return L("Choose sources for your mix")
        }
    }
    func step(_ delta: Int) { sequence += delta; playing = true }
    func refreshNews() {
        guard !refreshing else { return }; refreshing = true; lastNewsRefresh = Date()
        let selected = settings.feeds.filter(\.enabled)
        guard !selected.isEmpty else { refreshing = false; return }
        let generation = dataGeneration
        let group = DispatchGroup()
        for feed in selected {
            guard let url = URL(string: feed.url), url.scheme == "https" else { feedStatus[feed.id] = L("Enter an HTTPS URL"); continue }
            group.enter(); feedStatus[feed.id] = L("Refreshing…");sourceLoadState[feed.url] = .loading
            feedTransport.load(url,scope:"news") { [weak self] data, response, error in
                var parsed: [Story] = []; var failure: String?
                if let error { failure = LF("Network error (%ld). Check your connection.", (error as NSError).code) }
                else if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 { failure = "HTTP \(code)" }
                else if let data, data.count <= 5_000_000 {
                    let reader = RSSReader(source: feed.name, language: feed.language); parsed = reader.read(data)
                    if parsed.isEmpty { failure = L("No RSS or Atom headlines in this feed") }
                } else { failure = L("The source returned an empty or oversized response") }
                DispatchQueue.main.async {
                    defer { group.leave() }; guard let self, self.dataGeneration == generation else { return }
                    if let failure { self.feedStatus[feed.id] = LF("Couldn’t refresh: %@", failure);self.sourceLoadState[feed.url] = .failed(failure) }
                    else {
                        self.stories.removeAll { $0.source == feed.name }; self.stories += parsed
                        self.stories.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                        self.stories = Array(self.stories.prefix(200)); self.feedStatus[feed.id] = LF("%ld headlines", parsed.count); self.feedUpdated[feed.id] = Date();self.sourceLoadState[feed.url] = .loaded(Date())
                    }
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.dataGeneration == generation else { return }; self.refreshing = false
            if let data = try? JSONEncoder().encode(self.stories) { self.defaults.set(data, forKey: "newsCache") }
        }
    }
    func invalidatePendingContent() { dataGeneration += 1; contentGeneration += 1; refreshing = false; refreshingContent = false;sourceLoadState = sourceLoadState.filter{if case .loading = $0.value {return false};return true};storedFeedTransport?.cancel(scope:"news");storedFeedTransport?.cancel(scope:"content") }
    func savePreset(_ name: String) { presets.append(ScenePreset(name: name, settings: settings, newsLanguage: newsLanguage)); persistPresets() }
    func persistPresets() { if let d = try? JSONEncoder().encode(presets) { defaults.set(d, forKey: "presets") } }
    func apply(_ scene: EventScene) {
        var s = settings; s.channel = scene.channel; s.look = scene.look; s.motion = scene.motion; s.messages = L(scene.text); s.brand = L(scene.brand); s.caption = L(scene.caption); s.composition = scene.composition; s.stripPlacement = scene.position; s.fontSize = scene.fontSize; s.speed = scene.speed; s.holdSeconds = scene.hold; s.reverse = false; s.mirror = false
        if let pack = scene.contentPack { s.contentPackID = pack }
        if scene.look.isBroadcast { s.applyDensity(s.resolvedStripDensity); s.fontSize = 32 }
        settings = s; sequence += 1; urgent = ""; playing = true
        previewMode = scene.output
        saveSettingsNow()
    }
    func checkIdle() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        defer { lastObservedIdle = idle }
        if idleOutput && (!settings.idleEnabled || idle < 1.5 || idle < lastObservedIdle) { outputs.stop(); idleOutput = false; return }
        guard settings.idleEnabled, activeMode == nil, idle >= settings.idleMinutes * 60 else { return }
        idleOutput = true; outputs.show(.full, idle: true)
    }
    func enableRemote(_ enabled: Bool) {
        remote?.stop(); remote = nil; remoteEnabled = enabled
        if enabled { let server = RemoteServer(model: self); remote = server; server.start() } else { remoteInfo = "" }
    }
}

func parseDate(_ input: String) -> Date? {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let value = iso.date(from: input) { return value }; iso.formatOptions = [.withInternetDateTime]
    if let value = iso.date(from: input) { return value }
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "yyyy-MM-dd'T'HH:mm:ssZ"] { formatter.dateFormat = format; if let date = formatter.date(from: input) { return date } }
    return nil
}
