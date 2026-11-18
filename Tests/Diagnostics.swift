import AppKit
import SwiftUI
import QuartzCore
import Network
import Translation

final class ControlledFeedProtocol: URLProtocol {
    static let lock = NSLock()
    static var pending: [ControlledFeedProtocol] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.lock(); Self.pending.append(self); Self.lock.unlock() }
    override func stopLoading() { Self.lock.lock();Self.pending.removeAll{$0 === self};Self.lock.unlock() }
    static func respond(_ data: Data) -> Bool {
        lock.lock(); let item = pending.isEmpty ? nil : pending.removeFirst(); lock.unlock()
        guard let item else { return false }
        item.client?.urlProtocol(item, didReceive: HTTPURLResponse(url: item.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        item.client?.urlProtocol(item, didLoad: data); item.client?.urlProtocolDidFinishLoading(item)
        return true
    }
    static var hasPending: Bool { lock.lock(); defer { lock.unlock() }; return !pending.isEmpty }
}

func selfTest() {
    var checks = 0
    func check(_ value: @autoclosure () -> Bool, _ name: String) { guard value() else { print("FAIL: \(name)"); exit(1) }; checks += 1; print("PASS: \(name)") }
    Localization.language = .english
    check(L("Settings") == "Settings", "English interface lookup")
    check(LF("%ld messages", 1) == "1 message" && LF("%ld messages", 2) == "2 messages", "English plural forms")
    Localization.language = .russian
    check(L("Settings") == "Настройки", "Russian interface lookup")
    check(LF("%ld messages", 1) == "1 сообщение" && LF("%ld messages", 2) == "2 сообщения" && LF("%ld messages", 5) == "5 сообщений" && LF("%ld messages", 21) == "21 сообщение", "Russian plural forms")
    check(LF("%ld headlines · refreshed every %ld min", 2, 3) == "2 новости · обновление каждые 3 мин", "plural format preserves second argument")
    check(L(EventScene.all[0].name) == "Свадьба", "Russian scene lookup")
    Localization.language = .english
    check(L(EventScene.all[0].name) == "Wedding", "scene language is not frozen")
    let rss = Data("""
    <rss><channel><item><title>AI &amp; robots</title><link>https://example.org/a?x=1&amp;y=2</link><pubDate>Fri, 13 Nov 2026 09:00:00 +0000</pubDate></item><item><title><![CDATA[<b>Second</b> headline]]></title><link>https://example.org/b</link></item></channel></rss>
    """.utf8)
    let fixtureDate = Date().addingTimeInterval(-300).formatted(Date.ISO8601FormatStyle())
    let freshRSS = Data(String(data:rss,encoding:.utf8)!.replacingOccurrences(of:"Fri, 13 Nov 2026 09:00:00 +0000",with:fixtureDate).utf8)
    let rows = RSSReader(source: "Fixture").read(rss)
    check(rows.count == 2, "RSS item count"); check(rows[0].text == "AI & robots", "RSS entities"); check(rows[0].link == "https://example.org/a?x=1&y=2", "fragmented link"); check(rows[0].date != nil, "RSS date"); check(rows[1].text == "Second headline", "CDATA and tags")
    let atom = Data("""
    <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Atom headline</title><link rel="alternate" href="https://example.org/atom"/><updated>2026-11-13T10:00:00Z</updated><published>2026-11-12T09:00:00Z</published></entry></feed>
    """.utf8)
    check(parseDate("Fri, 13 Nov 2026 07:55:11 EST") == parseDate("2026-11-13T12:55:11Z"), "RSS named time zone preserves publisher time")
    let entries = RSSReader(source: "Atom").read(atom)
    check(entries.count == 1 && entries[0].link == "https://example.org/atom", "Atom alternate link"); check(entries[0].date == parseDate("2026-11-12T09:00:00Z"), "Atom published date wins"); check(RSSReader(source: "Broken").read(Data("not XML".utf8)).isEmpty, "invalid feed rejected")
    check(parseDate("2026-11-13T10:07:41.749163292Z") != nil, "exchange nanosecond timestamps")
    let suite = "ru.bushe.stroka.tests.\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults); check(model.interfaceLanguage == .english && model.newsLanguage == .english, "fresh install defaults to English"); model.newsLanguage = .all; model.settings.messages = "One\n\nTwo"; model.settings.channel = .message
    check(model.lines == ["One", "Two"], "message queue ignores blank lines")
    model.stories = [Story(id: "1", text: "AI news", source: model.settings.feeds[0].name, date: Date(), link: "")]
    model.settings.channel = .mix; model.settings.mixMarkets = false
    check(model.lines.count == 3 && model.lines[0] == "One" && model.lines[1].contains("AI news") && model.lines[2] == "Two", "mixed feed round robin")
    model.settings.feeds[0].enabled = false
    check(model.availableStories.isEmpty, "disabled source filtered immediately")
    model.settings.feeds[0].enabled = true; model.newsLanguage = .english; check(model.availableStories.isEmpty, "English filter excludes Russian feed"); model.newsLanguage = .russian; check(model.availableStories.count == 1, "Russian language filter"); model.newsLanguage = .all; check(model.availableStories.count == 1, "all languages filter")
    model.savePreset("Test"); model.saveSettingsNow(); let restored = AppModel(defaults: defaults)
    check(restored.presets.count == 1 && restored.settings.messages == "One\n\nTwo", "settings and scene persistence")
    let area = NSRect(x: -1920, y: 100, width: 1920, height: 1080)
    for position in StripPlacement.allCases {
        var settings = Settings(); settings.stripPlacement = position
        let frame = OutputController.stripFrame(in: area, settings: settings)
        check(area.contains(frame) && frame.width > 0 && frame.height > 0, "placement \(position.rawValue) stays on selected display")
    }
    let sideDisplay = TickerView(model: model); sideDisplay.rotated = true; model.reduceMotion = true
    check(sideDisplay.activeMotion == .phrases, "Reduce Motion also applies to vertical edge strips")
    model.reduceMotion = false
    let custom = FeedSource(name: "Custom", url: "https://example.org/rss"); model.settings.feeds.append(custom)
    for scene in EventScene.all {
        model.apply(scene)
        check(model.settings.look == scene.look && model.settings.brand == L(scene.brand) && model.settings.feeds.contains(custom) && model.settings.resolvedPlacement == scene.position && model.previewMode == scene.output, "scene \(scene.id) preserves connections and applies design")
    }
    var legacy = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(model.settings)) as! [String: Any]
    legacy.removeValue(forKey: "stripPlacement"); legacy.removeValue(forKey: "composition"); legacy.removeValue(forKey: "caption")
    let legacyDecoded = try! JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy))
    check(legacyDecoded.messages == model.settings.messages && legacyDecoded.resolvedComposition == .ticker, "older saved settings remain readable")
    defaults.set("ru", forKey: "interfaceLanguage")
    let localized = AppModel(defaults: defaults)
    check(localized.interfaceLanguage == .russian && L("Settings") == "Настройки", "Russian preference restored")
    check(localized.settings.messages == model.settings.messages, "language change preserves user-authored text")
    Localization.language = .english
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ControlledFeedProtocol.self]
    let session = URLSession(configuration: configuration)
    let isolatedSuite = "ru.bushe.stroka.canceltest.\(UUID())"; let isolatedDefaults = UserDefaults(suiteName: isolatedSuite)!
    defer { isolatedDefaults.removePersistentDomain(forName: isolatedSuite); session.invalidateAndCancel() }
    let cancelled = AppModel(defaults: isolatedDefaults, session: session)
    cancelled.settings.feeds = [FeedSource(name: "Fixture", url: "https://fixture.invalid/feed", language: "en")]
    func spin(_ predicate: () -> Bool) { let until = Date().addingTimeInterval(3); while !predicate() && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) } }
    cancelled.refreshNews(); spin { ControlledFeedProtocol.hasPending }
    cancelled.invalidatePendingContent(); cancelled.stories = []; isolatedDefaults.removeObject(forKey: "newsCache")
    spin { !ControlledFeedProtocol.hasPending };check(!ControlledFeedProtocol.hasPending, "obsolete RSS request is cancelled")
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    check(cancelled.stories.isEmpty && isolatedDefaults.data(forKey: "newsCache") == nil && !cancelled.refreshing, "deleted cache is not restored by an in-flight request")
    cancelled.refreshNews(); spin { ControlledFeedProtocol.hasPending }
    check(ControlledFeedProtocol.respond(freshRSS), "new RSS request after deletion")
    spin { !cancelled.refreshing }
    check(cancelled.stories.count == 2 && isolatedDefaults.data(forKey: "newsCache") != nil, "refresh works after data invalidation")
    let beforeCache = cancelled.lineBuildCount
    for _ in 0..<120 { _ = cancelled.lines }
    check(cancelled.lineBuildCount-beforeCache <= 1, "message queue is not rebuilt for each frame")
    cancelled.settings.channel = .message; cancelled.settings.messages = "Changed"
    check(cancelled.lines == ["Changed"], "text changes invalidate queue cache")
    let path = TickerPath(start:CGPoint(x:1000,y:20),end:CGPoint(x:-500,y:20),speed:120,vertical:false)
    check(abs(path.point(at:0.5).x-940)<0.001 && abs(path.point(at:1).x-880)<0.001, "motion uses absolute time and constant speed")
    let slower = TickerPath(start:path.start,end:path.end,speed:60,vertical:false)
    check(abs(slower.point(at:slower.elapsed(at:path.point(at:2))).x-path.point(at:2).x)<0.001, "speed changes preserve the current position")
    let idle = AppModel(defaults: isolatedDefaults); idle.settings.channel = .message; idle.settings.composition = .ticker; idle.start()
    check(idle.newsTimer == nil && idle.idleTimer == nil && !idle.market.isRunning, "unused data services and idle polling stay off")
    idle.settings.idleEnabled = true; check(idle.idleTimer != nil, "idle monitor starts only when enabled")
    idle.settings.idleEnabled = false; check(idle.idleTimer == nil, "idle monitor stops when disabled")
    check(Channel(rawValue:"Threads") == .content && Channel.content.title != "Threads", "legacy Threads selection migrates to Content")
    let library = AppModel(defaults: isolatedDefaults,session:session); library.settings.channel = .content; library.newsLanguage = .english; library.selectPack("jokes")
    check(library.selectedContent.count == 24 && !library.needsContent, "English jokes are available offline")
    library.newsLanguage = .russian
    check(library.selectedContent.count == 24 && library.selectedContent.allSatisfy{$0.language == "ru"}, "Russian content collection")
    library.newsLanguage = .all
    check(library.selectedContent.count == 48 && Set(library.selectedContent.map(\.id)).count == 48, "bilingual collections have unique item identities")
    check(BuiltinCollections.items.values.reduce(0){$0+$1.count} == 96, "96 bilingual collection entries bundled")
    library.newsLanguage = .english; library.selectPack("custom"); let libraryFeed = FeedSource(name:"Fixture",url:"https://fixture.invalid/feed",language:"en"); library.settings.customFeeds = [libraryFeed]
    library.refreshContent(); spin { ControlledFeedProtocol.hasPending }; library.selectPack("jokes");spin { !ControlledFeedProtocol.hasPending };check(!ControlledFeedProtocol.hasPending, "obsolete content request is cancelled"); RunLoop.current.run(until:Date().addingTimeInterval(0.15))
    check(library.contentStories.isEmpty && library.selectedContent.count == 24, "switching to offline content rejects an old RSS response")
    library.selectPack("custom"); library.refreshContent(); spin { ControlledFeedProtocol.hasPending }; check(ControlledFeedProtocol.respond(freshRSS), "custom RSS fixture delivered"); spin { !library.refreshingContent }
    check(library.selectedContent.count == 1, "custom RSS keeps fresh items and excludes unknown dates")
    let record = library.record(for:library.lines[0]); check(record.source == "Fixture" && record.text == "AI & robots" && record.date != nil, "broadcast metadata preserves source and publication date")
    library.setContentSource(libraryFeed,enabled:false); check(library.selectedContent.isEmpty && library.lines.isEmpty, "disabled content source is filtered immediately")
    for look in Look.broadcastLooks {
        library.applyLook(look); check(library.previewMode == .strip && library.settings.look == look && library.settings.resolvedComposition == .ticker, "broadcast look selects a news strip")
        for size in [CGSize(width:1920,height:88),CGSize(width:1080,height:124),CGSize(width:960,height:540)] {
            let g = BroadcastGeometry.make(canvas:CGRect(origin:.zero,size:size),scale:1,showClock:true,look:look)
            check(g.band.contains(g.content) && !g.content.intersects(g.badge) && !g.content.intersects(g.clock), "news text stays clear of fixed labels")
        }
    }
    check(Look.broadcastLooks.count == 4, "four distinct television models are available")
    let logoRect = BroadcastLogo.fitted(image:CGSize(width:400,height:100),in:CGRect(x:0,y:0,width:120,height:60))
    check(logoRect.size == CGSize(width:120,height:30) && logoRect.midY == 30, "wide logos keep their aspect ratio and centre")
    let logo = NSImage(size:NSSize(width:128,height:64)); logo.lockFocus(); NSColor.white.setFill(); NSRect(x:0,y:0,width:128,height:64).fill(); NSColor.blue.setFill(); NSRect(x:16,y:16,width:96,height:32).fill(); logo.unlockFocus()
    let logoPNG = NSBitmapImageRep(data:logo.tiffRepresentation!)!.representation(using:.png,properties:[:])!
    check(BroadcastLogo.normalized(logoPNG) != nil && BroadcastLogo.normalized(Data("bad image".utf8)) == nil, "logo import accepts a valid PNG and rejects invalid image data")
    library.settings.logoData = BroadcastLogo.normalized(logoPNG); let oldLogo = library.displayLogo; let revision = library.logoRevision
    check(oldLogo != nil, "imported logo is available to the renderer")
    let restoredLogo = try! JSONDecoder().decode(Settings.self,from:JSONEncoder().encode(library.settings))
    check(restoredLogo.logoData == library.settings.logoData, "logo is embedded in saved settings and presets")
    library.settings.logoData = nil
    check(library.displayLogo == nil && library.logoRevision > revision, "removing a logo invalidates the cached image")
    for look in Look.broadcastLooks {
        for showClock in [true,false] {
            let geometry = BroadcastGeometry.make(canvas:CGRect(x:0,y:0,width:1280,height:88),scale:1,showClock:showClock,look:look)
            check(geometry.band.contains(geometry.content) && !geometry.content.intersects(geometry.badge) && !geometry.content.intersects(geometry.clock), "compact broadcast geometry reserves fixed brand and clock regions")
        }
    }
    print("\(checks) checks passed")
}

func liveCheck() {
    let suite = "ru.bushe.stroka.livecheck.\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let m = AppModel(defaults: defaults); m.refreshNews(); m.market.start(); m.enableRemote(true)
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline && (m.refreshing || (m.market.updateCounts.values.min() ?? 0) < 2 || m.quotes.filter({ $0.source == "MOEX" }).isEmpty || m.remoteInfo.isEmpty) { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
    var success = true
    for source in m.settings.feeds {
        let rows = m.stories.filter { $0.source == source.name }
        print("RSS \(source.name): \(rows.count) items; dated \(rows.filter { $0.date != nil }.count); \(m.feedStatus[source.id] ?? "none")")
        if rows.isEmpty { success = false }
    }
    for quote in m.quotes { print("QUOTE \(quote.id) \(quote.value) \(quote.source) age=\(Int(Date().timeIntervalSince(quote.time)))s") }
    print("STREAM EVENTS: \(m.market.updateCounts)")
    if m.quotes.filter({ $0.source == "Coinbase" }).isEmpty || m.quotes.filter({ $0.source == "MOEX" }).isEmpty { success = false }
    var remoteDone = false
    if let url = URL(string: m.remoteInfo) {
        URLSession.shared.dataTask(with: url) { data, response, error in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200 && (data.flatMap { String(data: $0, encoding: .utf8) }?.contains("<h1>Stroka</h1>") == true)
            DispatchQueue.main.async { print("REMOTE HTML: \(ok ? "PASS" : "FAIL")"); if !ok { success = false }; remoteDone = true }
        }.resume()
    } else { remoteDone = true; success = false }
    while !remoteDone && Date() < deadline.addingTimeInterval(5) { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    if let base = URL(string: m.remoteInfo) {
        func request(_ path: String, json: [String: String]? = nil, expect: Int, name: String) {
            var done = false; var req = URLRequest(url: base.appendingPathComponent(path))
            if let json { req.httpMethod = "POST"; req.httpBody = try! JSONSerialization.data(withJSONObject: json); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            m.session.dataTask(with: req) { _, response, _ in DispatchQueue.main.async { let ok = (response as? HTTPURLResponse)?.statusCode == expect; print("REMOTE \(name): \(ok ? "PASS" : "FAIL")"); if !ok { success = false }; done = true } }.resume()
            let until = Date().addingTimeInterval(4); while !done && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }; if !done { success = false }
        }
        request("action", json: ["action": "urgent", "text": "Проверка пульта ✓"], expect: 200, name: "urgent")
        if m.urgent != "Проверка пульта ✓" { success = false; print("FAIL: remote unicode command") }
        request("action", json: ["action": "clear"], expect: 200, name: "clear")
        if !m.urgent.isEmpty { success = false }
        request("denied", expect: 404, name: "invalid path rejected")
        request("action", json: ["action": "invalid"], expect: 400, name: "unknown action rejected")
    }
    m.remote?.stop(); m.market.socket?.cancel(with: .goingAway, reason: nil)
    print("LIVE CHECK: \(success && remoteDone ? "PASS" : "FAIL")"); exit(success && remoteDone ? 0 : 1)
}

func renderCheck(_ directory: String) {
    let directory = directory == "auto" ? FileManager.default.temporaryDirectory.appendingPathComponent("StrokaRender-" + UUID().uuidString).path : directory
    print("RENDER DIRECTORY: \(directory)")
    try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let suite = "ru.bushe.stroka.render.\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults); model.settings.channel = .message; model.settings.messages = "Добро пожаловать!\nAI-новости и сообщения на вашем экране"; model.settings.speed = 95; model.reduceMotion = false
    var count = 0
    for (i, look) in Look.allCases.enumerated() { for (j, motion) in Motion.allCases.enumerated() {
        model.settings.look = look; model.settings.motion = motion
        let view = TickerView(model: model, infoFooter: true); view.frame = NSRect(x: 0, y: 0, width: 960, height: 360); view.elapsed = motion == .words ? 0.1 : motion == .phrases ? 1 : motion == .vertical ? 2.8 : 8
        guard let rep = view.snapshot(at: view.elapsed) else { print("FAIL: bitmap"); exit(1) }
        let data = rep.representation(using: .png, properties: [:])!; try! data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(i)-\(j).png")); count += 1
    } }
    print("Rendered \(count) style / motion combinations")
    for scene in EventScene.all {
        model.apply(scene)
        let view = TickerView(model: model, infoFooter: scene.composition == .split); view.frame = NSRect(x: 0, y: 0, width: 1280, height: 720); view.elapsed = scene.motion == .words ? 0.2 : 1
        guard let rep = view.snapshot(at: view.elapsed) else { exit(1) }
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("scene-\(scene.id).png"))
    }
    model.apply(EventScene.all[0]); model.settings.composition = .ticker; model.settings.messages = "Красивый текст вдоль края экрана"; model.settings.motion = .horizontal
    for position in StripPlacement.allCases {
        let view = TickerView(model: model); view.rotated = position.vertical; view.clockwise = position == .left; view.frame = NSRect(x: 0, y: 0, width: position.vertical ? 124 : 960, height: position.vertical ? 800 : 124); view.elapsed = 6
        guard let rep = view.snapshot(at: view.elapsed) else { exit(1) }
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("placement-\(position.rawValue).png"))
    }
    print("Rendered \(EventScene.all.count) scene presets and 6 strip placements"); exit(0)
}

func performanceCheck() { animationCheck() }

func visualUICheck() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaUI-" + UUID().uuidString)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (name, appearance, width, height, language) in [("en-desktop",NSAppearance.Name.aqua,1160.0,860.0,"en"),("ru-desktop",.aqua,1160.0,860.0,"ru"),("en-separator",.aqua,1160.0,1400.0,"en"),("ru-separator",.aqua,1160.0,1400.0,"ru"),("en-light",NSAppearance.Name.aqua,1160.0,860.0,"en"),("en-dark",.darkAqua,1160.0,860.0,"en"),("en-compact",.aqua,1050.0,700.0,"en"),("ru-light",.aqua,1160.0,860.0,"ru"),("ru-dark",.darkAqua,1160.0,860.0,"ru"),("ru-compact",.aqua,1050.0,700.0,"ru")] {
        autoreleasepool {
            NSApp.appearance = NSAppearance(named: appearance)
            let suite = "ru.bushe.stroka.visual.\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(language, forKey: "interfaceLanguage"); defaults.set(language == "en" ? "English" : "Русский", forKey: "newsLanguage")
            let m = AppModel(defaults: defaults); m.applyLook(.bulletin); m.settings.dualTicker = true; m.settings.dualUpperChannel = .content; m.settings.stripHeight = 144; m.settings.channel = .content; m.selectPack(name.contains("desktop") ? "thoughts" : "jokes");if name.contains("desktop") { m.settings.applyDensity(.desktop) }
            let date = Date().addingTimeInterval(-300)
            m.stories = [Story(id:"demo-1",text: language == "en" ? "New ideas for working with artificial intelligence" : "Новые идеи для работы с искусственным интеллектом",source:m.settings.feeds[0].name,date:date,link:"",language:language),Story(id:"demo-2",text: language == "en" ? "How technology helps people create something new" : "Как технологии помогают людям создавать новое",source:m.settings.feeds[0].name,date:date.addingTimeInterval(-600),link:"",language:language)]
            m.quotes = [Quote(id:"BTC-USD",value:69000,change:1.2,time:Date(),received:Date(),source:"Демо")]
            let delegate = AppDelegate(); delegate.model = m
            let w = NSWindow(contentRect: NSRect(x:-10000,y:-10000,width:width,height:height),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            w.isReleasedWhenClosed = false; w.title = "Stroka"; w.titlebarAppearsTransparent = true; w.toolbarStyle = .unified; w.appearance = NSAppearance(named:appearance); delegate.window = w
            w.contentView = NSHostingView(rootView:ControlView(model:m,inspectorTab: name.contains("dark") ? 1 : 0)); delegate.configureToolbar(); w.orderFront(nil); w.setFrame(NSRect(x:-10000,y:-10000,width:width,height:height),display:true); w.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            func prepareTickerViews(_ view: NSView) {
                if let ticker = view as? TickerView { ticker.compositor.refresh(manualElapsed: ticker.elapsed == 0 ? 0.4 : ticker.elapsed) }
                view.subviews.forEach(prepareTickerViews)
            }
            prepareTickerViews(w.contentView!)
            let view = w.contentView!.superview ?? w.contentView!
            let rep = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            w.appearance!.performAsCurrentDrawingAppearance { view.cacheDisplay(in:view.bounds,to:rep) }
            try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name + ".png"))
            w.orderOut(nil); w.contentView = nil; w.close()
        }
    }
    print("UI VISUAL DIRECTORY: \(folder.path)"); exit(0)
}


final class AnimationProbe: NSObject {
    var samples: [Double] = []; var last: Double?
    @objc func frame(_ link: CADisplayLink) { if let last { samples.append(link.timestamp - last) }; last = link.timestamp }
}
func processCPUSeconds() -> Double {
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
}
func pumpApplication(for seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        let next = min(end, Date().addingTimeInterval(0.02))
        if let event = NSApp.nextEvent(matching:.any,until:next,inMode:.default,dequeue:true) { NSApp.sendEvent(event) }
        NSApp.updateWindows()
    }
}
func animationCheck() {
    let suite = "ru.bushe.stroka.animation.\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let m = AppModel(defaults: defaults); m.settings.channel = .message; m.settings.brand = "STROKA / PERFORMANCE CHECK"; m.settings.messages = Array(repeating: "Smooth motion at a constant speed. Плавное движение текста без лишней нагрузки на процессор.", count: 8).joined(separator: "\n"); m.settings.speed = 127; m.settings.fontSize = 76; m.reduceMotion = false
    let screen = NSScreen.main!; let rect = screen.frame
    print("SCREEN: \(rect) backing=\(screen.backingScaleFactor) maxHz=\(screen.maximumFramesPerSecond)")
    struct Scenario { let name: String; let look: Look; let motion: Motion; var frame = false; var live = false; var paused = false; var hidden = false; var dual = false; var strip = false }
    let cases = [Scenario(name:"minimal-desktop-strip",look:.metro,motion:.horizontal,strip:true),Scenario(name:"night-desktop-strip",look:.nightline,motion:.horizontal,strip:true),Scenario(name:"four-information-rows",look:.bulletin,motion:.horizontal,strip:true),Scenario(name:"three-information-markets",look:.glass,motion:.horizontal,live:true,strip:true),Scenario(name:"glass-desktop-strip",look:.glass,motion:.horizontal,live:true,dual:true,strip:true),Scenario(name:"desktop-strip",look:.bulletin,motion:.horizontal,live:true,dual:true,strip:true),Scenario(name:"news-strip",look:.bulletin,motion:.horizontal,live:true,dual:true,strip:true),Scenario(name:"fast-strip",look:.bulletin,motion:.horizontal,strip:true),Scenario(name:"separator-boundaries",look:.bulletin,motion:.horizontal),Scenario(name:"dual-news-markets",look:.bulletin,motion:.horizontal,live:true,dual:true),Scenario(name:"glass-scroll",look:.glass,motion:.horizontal),Scenario(name:"studio-scroll",look:.studio,motion:.horizontal),Scenario(name:"bulletin-scroll",look:.bulletin,motion:.horizontal),Scenario(name:"wire-scroll",look:.wire,motion:.horizontal),Scenario(name:"desk-scroll",look:.desk,motion:.horizontal),Scenario(name:"led-scroll",look:.led,motion:.horizontal),Scenario(name:"neon-credits",look:.neon,motion:.vertical),Scenario(name:"poster-phrases",look:.champagne,motion:.phrases),Scenario(name:"four-edge-frame",look:.studio,motion:.horizontal,frame:true),Scenario(name:"market-stream",look:.studio,motion:.horizontal,live:true),Scenario(name:"paused",look:.bulletin,motion:.horizontal,paused:true),Scenario(name:"hidden",look:.bulletin,motion:.horizontal,hidden:true)]
    let caseIndex = CommandLine.arguments.firstIndex(of:"--animation-case")
    let requested = caseIndex.flatMap { $0+1 < CommandLine.arguments.count ? CommandLine.arguments[$0+1] : nil } ?? "studio-scroll"
    for test in cases.filter({ $0.name == requested }) {
        autoreleasepool {
            m.settings.look = test.look; m.settings.motion = test.motion; m.settings.composition = test.motion == .phrases ? .poster : .ticker; m.settings.channel = test.live ? .markets : .message; m.playing = !test.paused
            if test.name == "separator-boundaries" || test.name == "fast-strip" { m.settings.messages = "One\nTwo\nThree"; m.settings.speed = 260; m.settings.fontSize = 32 }
            m.quotes = [Quote(id:"BTC-USD",value:69000,change:1.2,time:Date(),received:Date(),source:"Fixture")]
            m.settings.dualTicker = test.dual; m.settings.dualUpperChannel = .message; m.settings.marketSpeed = 85
            let multi = test.name == "four-information-rows" || test.name == "three-information-markets"
            if multi {m.settings.channel = .message;m.setRowCount(4);for index in 0..<4 {var row = TickerRow(channel:index == 3 && test.live ? .markets : .message);row.messages = "ROW \(index+1) · Independent information, smooth movement and a compact layout";m.setRow(row,at:index)};m.settings.stripHeight = 112}
            let testRect = multi ? CGRect(x:rect.minX,y:rect.maxY-112,width:rect.width,height:112) : test.strip ? CGRect(x:rect.minX,y:rect.maxY-(test.name.contains("desktop-strip") ? 52 : 144),width:rect.width,height:test.name.contains("desktop-strip") ? 52 : 144) : rect
            let w = NSWindow(contentRect:testRect,styleMask:[.borderless],backing:.buffered,defer:false); w.isReleasedWhenClosed = false; w.level = .floating
            let host: NSView
            if test.frame { m.previewMode = .frame; let canvas = PreviewCanvas(model:m); host = canvas }
            else { m.previewMode = test.strip ? .strip : .full; host = TickerView(model:m, infoFooter:test.live) }
            w.contentView = host; w.orderFrontRegardless(); host.layoutSubtreeIfNeeded(); NSApp.activate(ignoringOtherApps:true)
            let quoteTimer: Timer? = test.live ? Timer.scheduledTimer(withTimeInterval:0.4,repeats:true) { _ in m.quotes[0].value += 0.01; m.quotes[0].time = Date() } : nil
            pumpApplication(for:1)
            if test.hidden { w.orderOut(nil) }
            func draws(_ view:NSView)->Int { (view as? TickerView).map { $0.measuredDraws + $0.extraLanes.reduce(0){$0+$1.measuredDraws} } ?? view.subviews.reduce(0) { $0 + draws($1) } }
            func animations(_ layer:CALayer?)->Int { guard let layer else { return 0 }; return (layer.animationKeys()?.count ?? 0) + (layer.sublayers ?? []).reduce(0) { $0 + animations($1) } }
            print("STATE \(test.name): visible=\(w.isVisible) occluded=\(!w.occlusionState.contains(.visible)) rasterAtWarmup=\(draws(host)) CAAnimations=\(animations(host.layer))")
            if !test.hidden && !w.occlusionState.contains(.visible) { print("INVALID: benchmark window is occluded"); fflush(stdout); exit(2) }
            let probe = AnimationProbe(); let link = host.displayLink(target:probe,selector:#selector(AnimationProbe.frame(_:))); link.add(to:.main,forMode:.common)
            let begin = CACurrentMediaTime(); let cpu = processCPUSeconds(); let before = draws(host)
            pumpApplication(for:6)
            let wall = CACurrentMediaTime()-begin; let utilization = (processCPUSeconds()-cpu)/wall*100
            link.invalidate(); quoteTimer?.invalidate()
            let sorted = probe.samples.sorted(); let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count-1,Int(Double(sorted.count)*0.95))]*1000
            let expected = 1.0/Double(screen.maximumFramesPerSecond); let missed = probe.samples.filter { $0 > expected*1.5 }.count
            print(String(format:"ANIMATION %@: cpu=%.2f%% drawCalls=%d callbacks=%d p95=%.2fms longIntervals=%d",test.name,utilization,draws(host)-before,probe.samples.count,p95,missed)); fflush(stdout)
            w.orderOut(nil); w.contentView = nil; w.close()
        }
    }
    print("CPU: process user+system / wall time, one full core = 100%. Display-link intervals measure callback pacing, not guaranteed compositor FPS. No live network requests."); exit(0)
}

func motionBehaviorCheck() {
    var checks = 0
    func check(_ value: @autoclosure () -> Bool, _ label: String) { if !value() { print("FAIL: \(label)"); fflush(stdout); exit(1) }; checks += 1; print("PASS: \(label)") }
    let suite = "ru.bushe.stroka.motion.\(UUID())"; let defaults = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:defaults); m.settings.channel = .message; m.settings.messages = "Smooth continuous movement in Core Animation. Плавная строка на экране Mac."; m.settings.speed = 120; m.reduceMotion = false
    let w = NSWindow(contentRect:NSRect(x:100,y:100,width:600,height:240),styleMask:[.borderless],backing:.buffered,defer:false); w.isReleasedWhenClosed = false; w.level = .floating
    let v = TickerView(model:m); w.contentView = v; w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); pumpApplication(for:0.5)
    defer { w.orderOut(nil); w.contentView = nil; w.close(); defaults.removePersistentDomain(forName:suite) }
    func x() -> CGFloat { v.compositor.moving.presentation()?.position.x ?? v.compositor.moving.position.x }
    check(w.occlusionState.contains(.visible) && v.compositor.moving.animationKeys()?.contains("translation") == true, "visible text has an active Core Animation translation")
    let before = x(); let rasterBefore = v.measuredDraws
    let begin = CACurrentMediaTime(); while CACurrentMediaTime()-begin < 0.2 { }
    CATransaction.flush(); let after = x(); let distance = before-after
    print(String(format:"PRESENTATION progress during 200ms main-thread stall: %.2f pt (expected about 24)",distance))
    check(distance > 12 && distance < 36 && v.measuredDraws == rasterBefore, "movement continues through a main-thread stall without rasterizing text")
    m.playing = false; pumpApplication(for:0.1); let paused = x(); pumpApplication(for:0.25)
    check(abs(x()-paused) < 0.1 && v.compositor.moving.animationKeys()?.isEmpty != false, "pause freezes the exact position and removes animation")
    m.playing = true; pumpApplication(for:0.25); check(x() < paused-10, "resume continues from the paused position")
    m.settings.channel = .markets; m.quotes = [Quote(id:"BTC-USD",value:69000,change:1.2,time:Date(),received:Date(),source:"Fixture")]; pumpApplication(for:0.3)
    let liveBefore = x(); let start = CACurrentMediaTime(); m.quotes[0].value += 0.01; pumpApplication(for:0.05); let elapsed = CACurrentMediaTime()-start
    check(abs(Double(liveBefore-x())-elapsed*120)<8 && v.compositor.bodyKey.contains(m.quotes[0].formatted), "quote updates refresh the value without resetting position")
    let cover = NSWindow(contentRect:w.frame,styleMask:[.borderless],backing:.buffered,defer:false); cover.isReleasedWhenClosed = false; cover.level = NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+1); cover.backgroundColor = .black; cover.isOpaque = true; cover.orderFrontRegardless(); pumpApplication(for:0.25)
    check(!w.occlusionState.contains(.visible) && v.compositor.wake == nil && v.compositor.moving.animationKeys()?.isEmpty != false, "covered window stops rendering and animations")
    cover.orderOut(nil); cover.close()
    let exposureDeadline = Date().addingTimeInterval(2)
    while Date() < exposureDeadline && (!w.occlusionState.contains(.visible) || v.compositor.moving.animationKeys()?.contains("translation") != true) { pumpApplication(for:0.05) }
    print("EXPOSURE visible=\(w.occlusionState.contains(.visible)) animations=\(v.compositor.moving.animationKeys() ?? [])")
    check(w.occlusionState.contains(.visible) && v.compositor.moving.animationKeys()?.contains("translation") == true, "uncovered window resumes animation")
    w.orderOut(nil); pumpApplication(for:0.1)
    check(v.compositor.wake == nil && v.compositor.moving.animationKeys()?.isEmpty != false, "hidden window stops scheduled work and animations")
    m.settings.channel = .message; m.settings.messages = String(repeating:"Long message with many words. ",count:500)
    _ = v.snapshot(at:100)
    let bytes = v.compositor.tiles.values.reduce(0) { total,tile in guard let contents = tile.contents else { return total }; let image = contents as! CGImage; return total+image.bytesPerRow*image.height }
    print("LONG TEXT: \(v.compositor.tiles.count) retained tiles, \(bytes) bytes")
    check(v.compositor.tiles.count <= 8 && bytes < 16_000_000, "long message textures stay bounded to the visible region")
    print("\(checks) motion behavior checks passed"); fflush(stdout)
}

func previewIntegrationCheck() {
    let suite = "ru.bushe.stroka.preview.\(UUID())"; let defaults = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:defaults); m.settings.channel = .message; m.settings.messages = "Preview should show this text"; m.applyLook(.bulletin); m.reduceMotion = false
    let w = NSWindow(contentRect:NSRect(x:100,y:100,width:1160,height:820),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false); w.isReleasedWhenClosed = false
    w.level = .floating; m.controlWindow = w; w.contentView = NSHostingView(rootView:ControlView(model:m)); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); pumpApplication(for:2)
    func find(_ view:NSView)->[TickerView] { (view as? TickerView).map{[$0]} ?? view.subviews.flatMap(find) }
    let tickers = find(w.contentView!); print("PREVIEW found \(tickers.count) tickers")
    let initialRunning = tickers.allSatisfy { $0.compositor.running }
    let visibleAtCheck = w.occlusionState.contains(.visible)
    for v in tickers {
        print("WINDOW outer=\(v.window === w) class=\(v.window.map{NSStringFromClass(type(of:$0))} ?? "nil") controlVisible=\(m.controlWindow?.occlusionState.rawValue ?? 0)")
        print("MODEL playing=\(m.playing) urgent=\(m.urgent.count) miniature=\(w.isMiniaturized) visibleFlag=\(NSWindow.OcclusionState.visible.rawValue)")
        print("RENDER running=\(v.compositor.running) rootHidden=\(v.layer?.isHidden ?? true) rootOpacity=\(v.layer?.opacity ?? 0) sceneOpacity=\(v.compositor.scene.opacity) chromeOpacity=\(v.compositor.chrome.opacity)")
        print("FRAME \(v.frame) bounds=\(v.bounds) windowVisible=\(v.window?.isVisible == true) occlusion=\(v.window?.occlusionState.rawValue ?? 0) hidden=\(v.isHiddenOrHasHiddenAncestor)")
        print("LAYER installed=\(v.compositor.installed) attached=\(v.compositor.scene.superlayer === v.layer) root=\(v.layer?.bounds ?? .zero) scene=\(v.compositor.scene.frame) chrome=\(v.compositor.chrome.frame) contents=\(v.compositor.chrome.contents != nil) tiles=\(v.compositor.tiles.count) running=\(v.compositor.running) animations=\(v.compositor.moving.animationKeys() ?? [])")
    }
    fflush(stdout)
    let ok = !tickers.isEmpty && tickers.allSatisfy { $0.compositor.chrome.contents != nil && $0.compositor.scene.superlayer === $0.layer } && (visibleAtCheck ? initialRunning : !initialRunning)
    print("PREVIEW CHECK: \(ok ? "PASS" : "FAIL") (initial image and visibility contract; covered windows stay paused)"); fflush(stdout)
    w.orderOut(nil); w.contentView = nil; w.close(); defaults.removePersistentDomain(forName:suite); exit(ok ? 0 : 1)
}

func contentRenderCheck() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaContent-"+UUID().uuidString); try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let suite = "ru.bushe.stroka.contentrender.\(UUID())"; let defaults = UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite) }
    let m = AppModel(defaults:defaults); m.settings.channel = .content; m.settings.contentPackID = "custom"; m.settings.customFeeds = [FeedSource(name:"DEMO RSS",url:"https://example.org/feed",language:"en")]; m.settings.brand = "STROKA"; m.reduceMotion = false
    var count = 0
    for lang in ["en","ru"] {
        m.interfaceLanguage = lang == "en" ? .english : .russian; m.newsLanguage = lang == "en" ? .english : .russian
        m.contentStories = [Story(id:"demo",text:lang == "en" ? "A new public science centre opens its doors to visitors" : "Новый научный центр открывает двери для посетителей",source:"DEMO RSS",date:parseDate("2026-11-13T12:00:00Z"),link:"https://example.org/article",language:lang,packID:"custom")]
        for branded in [false,true] {
        if branded {
            let logo = NSImage(size:NSSize(width:360,height:120)); logo.lockFocus(); NSColor.white.setFill(); NSRect(x:0,y:0,width:360,height:120).fill(); ("YOUR BRAND" as NSString).draw(at:CGPoint(x:18,y:35),withAttributes:[.font:NSFont.systemFont(ofSize:42,weight:.bold),.foregroundColor:NSColor.black]); logo.unlockFocus(); m.settings.logoData = NSBitmapImageRep(data:logo.tiffRepresentation!)!.representation(using:.png,properties:[:])
        } else { m.settings.logoData = nil }
        for look in Look.broadcastLooks {
            m.applyLook(look)
            for (name,size) in [("strip",CGSize(width:1920,height:88)),("full",CGSize(width:1920,height:1080)),("side",CGSize(width:88,height:1080))] {
                let v = TickerView(model:m); v.rotated = name == "side"; v.frame = CGRect(origin:.zero,size:size)
                let canvas = v.renderBounds; let g = BroadcastGeometry.make(canvas:canvas,scale:1,showClock:true,look:look)
                let t = Double(g.content.width-18)/m.settings.speed
                guard let rep = v.snapshot(at:t), let data = rep.representation(using:.png,properties:[:]) else { exit(1) }
                try! data.write(to:folder.appendingPathComponent("\(lang)-\(look.rawValue)-\(name)-\(branded ? "logo" : "text").png")); count += 1
            }
        }
    }
        }
    print("CONTENT RENDER DIRECTORY: \(folder.path)"); print("Rendered \(count) broadcast layouts with clearly labelled demonstration content"); exit(0)
}

func contentSourcesCheck() {
    var models:[AppModel] = []; var suites:[String] = []
    for pack in ContentPack.all where pack.isOnline && pack.id != "custom" {
        let suite = "ru.bushe.stroka.contentcheck.\(UUID())"; suites.append(suite)
        let m = AppModel(defaults:UserDefaults(suiteName:suite)!); m.settings.channel = .content; m.newsLanguage = .all; m.selectPack(pack.id); m.refreshContent(); models.append(m)
    }
    let deadline = Date().addingTimeInterval(35)
    while models.contains(where:{$0.refreshingContent}) && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.1)) }
    var ok = true
    for m in models {
        for source in m.enabledContentSources {
            let rows = m.selectedContent.filter{$0.source == source.name}
            print("CONTENT \(m.selectedPack.id) / \(source.name): \(rows.count) items, dated=\(rows.filter{$0.date != nil}.count), \(m.feedStatus[source.id] ?? "none")")
            if rows.isEmpty { ok = false }
        }
    }
    for suite in suites { UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite) }
    print("CONTENT SOURCES: \(ok ? "PASS" : "FAIL")"); exit(ok ? 0 : 1)
}

func dualCheck() {
    var checks = 0
    func check(_ value: @autoclosure () -> Bool,_ label:String) { guard value() else { print("FAIL: \(label)"); fflush(stdout); exit(1) }; checks += 1; print("PASS: \(label)") }
    let suite = "ru.bushe.stroka.dual.\(UUID())"; let defaults = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:defaults); m.settings.channel = .message; m.settings.messages = "DEMO NEWS: A new science centre opens its doors to visitors\nDEMO NEWS: Technology and research from around the world"; m.applyLook(.bulletin); m.settings.dualTicker = true; m.settings.dualUpperChannel = .message; m.settings.speed = 120; m.settings.marketSpeed = 60; m.settings.graduatedSpeeds = false; m.reduceMotion = false
    m.quotes = [Quote(id:"DEMO-BTC",value:69000,change:1.2,time:Date(),received:Date(),source:"DEMO"),Quote(id:"DEMO-INDEX",value:2800,change:-0.7,time:Date(),received:Date(),source:"DEMO")]
    let w = NSWindow(contentRect:CGRect(x:100,y:100,width:900,height:144),styleMask:[.borderless],backing:.buffered,defer:false); w.isReleasedWhenClosed = false; w.level = .floating
    let v = TickerView(model:m); w.contentView = v; w.orderFrontRegardless(); NSApp.activate(ignoringOtherApps:true); pumpApplication(for:0.6)
    defer { w.orderOut(nil); w.contentView = nil; w.close(); defaults.removePersistentDomain(forName:suite) }
    check((try? JSONDecoder().decode(Settings.self,from:JSONEncoder().encode(m.settings)))?.dualTicker == true,"dual-row mode persists in settings")
    check(m.dualBandActive && m.needsMarkets && m.lines == m.ownLines,"dual mode starts market service demand and keeps quotes out of the upper queue")
    guard let lower = v.marketLane else { check(false,"lower ticker exists"); return }
    func x(_ ticker:TickerView)->CGFloat { ticker.compositor.moving.presentation()?.position.x ?? ticker.compositor.moving.position.x }
    print("DUAL STATE: root=\(v.compositor.running) lower=\(lower.compositor.running) attached=\(lower.compositor.scene.superlayer === v.layer) visible=\(w.occlusionState.contains(.visible))")
    check(v.compositor.running && lower.compositor.running && lower.compositor.scene.superlayer === v.layer,"both rows have active independent Core Animation paths in one composed layer tree")
    let news = x(v), market = x(lower); pumpApplication(for:0.25)
    check(abs((news-x(v))-30)<10 && abs((market-x(lower))-15)<8,"news and markets move at independently selected speeds")
    let before = x(v), oldKey = v.compositor.bodyKey; m.quotes[0].value += 0.01; pumpApplication(for:0.08)
    check(v.compositor.bodyKey == oldKey && abs((before-x(v))-9.6)<8 && lower.compositor.bodyKey.contains(m.quotes[0].formatted),"quote refresh changes only the lower text without restarting news")
    let q = x(lower); m.step(1); pumpApplication(for:0.08)
    check(abs((q-x(lower))-4.8)<8,"browsing news does not restart the market row")
    m.playing = false; pumpApplication(for:0.1); let p = x(v), p2 = x(lower); pumpApplication(for:0.15)
    check(abs(p-x(v))<0.1 && abs(p2-x(lower))<0.1 && !v.compositor.running && !lower.compositor.running,"one pause freezes both rows exactly")
    m.playing = true; pumpApplication(for:0.15)
    check(v.compositor.running && lower.compositor.running,"both rows resume")
    m.settings.dualUpperChannel = .content; m.selectPack("jokes"); m.settings.channel = .markets
    check(m.lines.count == 24 && !m.lines.contains(where:{$0.contains("DEMO-BTC")}),"upper source is independent of the open sidebar section")
    m.settings.dualUpperChannel = .ai
    check(m.needsNews && m.needsMarkets,"AI upper row and lower market row request both services")
    m.settings.dualUpperChannel = .message; m.urgent = "Announcement"; pumpApplication(for:0.1)
    check(v.marketLane == nil,"an announcement replaces the complete dual band")
    m.urgent = ""; pumpApplication(for:0.1)
    check(v.marketLane != nil,"market row returns after the announcement")
    m.settings.dualTicker = false; pumpApplication(for:0.1)
    check(v.marketLane == nil,"turning two rows off removes the lower renderer")
    m.settings.dualTicker = true
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaDual-\(UUID())"); try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for language in ["en","ru"] {
        m.interfaceLanguage = language == "en" ? .english : .russian
        m.settings.messages = language == "en" ? "DEMO NEWS · A new science centre welcomes its first visitors" : "ДЕМОНОВОСТИ · Новый научный центр принимает первых посетителей"
        for look in Look.broadcastLooks {
            m.applyLook(look)
            for (name,size) in [("strip",CGSize(width:1920,height:144)),("full",CGSize(width:1280,height:720)),("side",CGSize(width:144,height:900))] {
                let view = TickerView(model:m); view.rotated = name == "side"; view.clockwise = name == "side"; view.frame = CGRect(origin:.zero,size:size); view.updateMarketLane()
                let g = BroadcastGeometry.make(canvas:view.laneBounds,scale:1,showClock:true,look:look)
                let t = max(0,g.content.width-16)/m.settings.speed
                let qtime = max(0,view.renderBounds.width-128)/(m.settings.marketSpeed ?? 85)
                guard let rep = view.snapshot(at:t,marketTime:qtime), let data = rep.representation(using:.png,properties:[:]) else { check(false,"dual snapshot"); return }
                try! data.write(to:folder.appendingPathComponent("\(language)-\(look.rawValue)-\(name).png"))
            }
        }
    }
    print("DUAL DIRECTORY: \(folder.path)"); print("\(checks) dual-row checks passed; \(Look.broadcastLooks.count*6) layouts rendered"); fflush(stdout); exit(0)
}

func separatorCheck() {
    var checks = 0
    func check(_ value:@autoclosure()->Bool,_ label:String) { guard value() else { print("FAIL: \(label)"); fflush(stdout); exit(1) }; checks += 1; print("PASS: \(label)") }
    var settings = Settings(); check(settings.resolvedSeparator == "│││","default separator is neutral vertical bars")
    settings.separator = " \n "; check(settings.resolvedSeparator == "│││","empty separator falls back to a visible marker")
    settings.separator = "123456789012345"; check(settings.resolvedSeparator.count == 12,"custom separator is bounded")
    settings.separator = "***"; let saved = try! JSONDecoder().decode(Settings.self,from:JSONEncoder().encode(settings)); check(saved.resolvedSeparator == "***","separator persists in presets and settings")
    let font = NSFont.monospacedSystemFont(ofSize:28,weight:.medium)
    for reverse in [false,true] {
        let one = TickerStreamWindow.make(messages:["First","Second","Third"],index:0,separator:"│││",font:font,ink:.black,accent:.red,viewport:900,reverse:reverse)!
        let next = TickerStreamWindow.make(messages:["First","Second","Third"],index:1,separator:"│││",font:font,ink:.black,accent:.red,viewport:900,reverse:reverse)!
        check(one.text.string.contains("First   │││   Second") || reverse,"marker is between adjacent messages")
        check(one.size.width >= 900+one.advance && one.advance > one.currentWidth,"stream window fills viewport beyond outgoing message")
        func offset(_ window:TickerStreamWindow) -> CGFloat {
            let range = (window.text.string as NSString).range(of:"Second",options:reverse ? .backwards : [])
            return range.location == 0 ? 0 : TickerStreamWindow.width(window.text.attributedSubstring(from:NSRange(location:0,length:range.location)))
        }
        // Track the same incoming word before and after replacing the outgoing segment.
        let oldStart:CGFloat = reverse ? 900-one.size.width : 0
        let nextStart:CGFloat = reverse ? 900-next.size.width : 0
        let oldX = oldStart + (reverse ? one.advance : -one.advance) + offset(one)
        let newX = nextStart + offset(next)
        check(abs(oldX-newX)<0.02,"incoming word keeps its exact position across a left/right boundary")
    }
    let suite = "ru.bushe.stroka.separator.\(UUID())"; let defaults = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:defaults); m.settings.channel = .message; m.settings.messages = "FIRST DEMO MESSAGE\nSECOND DEMO MESSAGE\nTHIRD DEMO MESSAGE"; m.applyLook(.bulletin); m.settings.dualTicker = true; m.settings.dualUpperChannel = .message; m.settings.speed = 160; m.settings.marketSpeed = 80; m.settings.separator = "│││"; m.reduceMotion = false
    m.quotes = [Quote(id:"DEMO-BTC",value:69000,change:1.2,time:Date(),received:Date(),source:"DEMO"),Quote(id:"DEMO-INDEX",value:2800,change:-0.7,time:Date(),received:Date(),source:"DEMO")]
    let w = NSWindow(contentRect:CGRect(x:100,y:100,width:1100,height:144),styleMask:[.borderless],backing:.buffered,defer:false); w.isReleasedWhenClosed = false; w.level = .floating
    let v = TickerView(model:m); w.contentView = v; w.orderFrontRegardless(); NSApp.activate(ignoringOtherApps:true); pumpApplication(for:0.4)
    defer { w.orderOut(nil); w.contentView = nil; w.close(); defaults.removePersistentDomain(forName:suite) }
    v.localIndex = 0;v.compositor.seek(0);v.compositor.refresh(manualElapsed:0)
    check(v.compositor.bodyKey.contains("FIRST DEMO MESSAGE   │││   SECOND DEMO MESSAGE"),"upper stream contains adjacent messages and markers")
    check(v.marketLane?.compositor.bodyKey.contains("│││") == true,"lower market row uses the same marker")
    for reverse in [false,true] {
        m.settings.reverse = reverse; pumpApplication(for:0.1)
        v.localIndex = 0; v.compositor.seek(0); v.compositor.refresh(manualElapsed:0)
        let duration = v.compositor.path!.duration
        v.compositor.refresh(manualElapsed:duration+0.03)
        check(v.localIndex == 1 && v.compositor.bodyKey.contains("SECOND DEMO MESSAGE"),"message index advances at the separator boundary in either direction")
        check(v.elapsed < 0.1,"boundary preserves elapsed overshoot instead of inserting a pause")
    }
    m.settings.reverse = false; v.compositor.seek(0); v.compositor.refresh(); pumpApplication(for:0.1)
    let path = v.compositor.path!
    v.compositor.seek(path.duration-0.06); v.compositor.refresh(); CATransaction.flush()
    let stallBefore = v.compositor.moving.presentation()?.position.x ?? 0
    let stallStart = CACurrentMediaTime(); while CACurrentMediaTime()-stallStart < 0.2 { }
    CATransaction.flush()
    let stallAfter = v.compositor.moving.presentation()?.position.x ?? 0
    check(stallBefore-stallAfter > 22 && stallBefore-stallAfter < 42,"CA keeps moving across a boundary during a 200ms main-thread stall")
    v.compositor.refresh(); pumpApplication(for:0.05)
    check(v.localIndex > 0 && v.compositor.moving.animationKeys()?.contains("translation") == true,"renderer catches up after a delayed boundary without losing the next message")
    v.compositor.seek(0); v.compositor.refresh(); pumpApplication(for:0.1)
    let before = v.compositor.moving.presentation()?.position.x ?? 0; m.settings.separator = "•••"; pumpApplication(for:0.08)
    let after = v.compositor.moving.presentation()?.position.x ?? 0
    check(v.compositor.bodyKey.contains("•••") && abs((before-after)-12.8)<10,"changing marker keeps movement position")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaSeparators-\(UUID())"); try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    m.interfaceLanguage = .russian; m.settings.messages = "Новая выставка открывается в субботу\nКонцерт начнётся в 20:00\nДобро пожаловать на наш вечер"; m.settings.showClock = true
    for token in MessageSeparators.options {
        m.settings.separator = token
        let view = TickerView(model:m); view.frame = CGRect(x:0,y:0,width:1920,height:144)
        guard let rep = view.snapshot(at:0,marketTime:0), let png = rep.representation(using:.png,properties:[:]) else { exit(1) }
        let name = "separator-\(MessageSeparators.options.firstIndex(of:token)!)"
        try! png.write(to:folder.appendingPathComponent(name+".png"))
    }
    print("SEPARATOR DIRECTORY: \(folder.path)"); print("\(checks) separator checks passed"); fflush(stdout); exit(0)
}

func newsroomCheck() {
    var count = 0
    func check(_ result:@autoclosure()->Bool,_ name:String) { guard result() else { print("FAIL: \(name)");fflush(stdout);exit(1) };count += 1;print("PASS: \(name)") }
    check(NewsCatalog.all.count >= 50 && NewsCatalog.all.filter{$0.language == "ru"}.count >= 20,"bilingual source catalog is bundled")
    check(Set(NewsCatalog.all.map(\.url)).count == NewsCatalog.all.count,"catalog has unique source URLs")
    check(NewsCatalog.all.allSatisfy{URL(string:$0.url)?.scheme == "https"},"catalog uses HTTPS publisher URLs")
    check(NewsCatalog.all.contains{$0.availability == "timeout"} && NewsCatalog.all.contains{$0.availability == "checked"},"availability distinguishes returned feeds from network timeouts")
    let shares = MarketCatalog.all.filter{$0.kind == "share"};check(shares.count >= 25,"watchlist includes equities rather than only crypto")
    let fixture: [String:Any] = ["securities":["columns":["SECID","PREVPRICE","PREVDATE"],"data":[["SBER",274.0,"2026-11-12"]]],"marketdata":["columns":["SYSTIME","LASTTOPREVPRICE","SECID","LAST"],"data":[["2026-11-13 18:50:00",1.25,"SBER",278.5]]]]
    let sber = shares.first{$0.symbol == "SBER"}!
    let data = try! JSONSerialization.data(withJSONObject:fixture)
    let rows = OpenMarketData.moex(data,kind:"share",selected:[sber])
    check(rows.count == 1 && rows[0].value == 278.5 && rows[0].change == 1.25 && rows[0].cadence == .delayed,"share parser follows column names and labels delayed data")
    check(rows[0].time == OpenMarketData.date("2026-11-13 18:50:00"),"exchange timestamp is preserved rather than receipt time")
    var noPrice = fixture;noPrice["marketdata"] = ["columns":["SECID","LAST"],"data":[["SBER",NSNull()]]]
    let previous = OpenMarketData.moex(try! JSONSerialization.data(withJSONObject:noPrice),kind:"share",selected:[sber])
    check(previous.count == 1 && previous[0].value == 274 && previous[0].cadence == .close,"missing last price uses a dated previous close rather than zero")
    let fx = Data("<ValCurs Date=\"14.11.2026\"><Valute><CharCode>JPY</CharCode><Nominal>100</Nominal><Name>Japanese Yen</Name><Value>53,2500</Value></Valute></ValCurs>".utf8)
    let rates = CBRRateReader().read(fx)
    check(rates.count == 1 && abs(rates[0].value-0.5325)<0.000001,"CBR parser divides by currency nominal")
    check(rates[0].cadence == .daily && rates[0].time == OpenMarketData.date("14.11.2026",format:"dd.MM.yyyy"),"official rate keeps its effective date and daily label")
    let euroFixture = Data("<Envelope><Cube><Cube time=\"2026-11-13\"><Cube currency=\"USD\" rate=\"1.10\"/></Cube></Cube></Envelope>".utf8)
    let euroRates = ECBRateReader().read(euroFixture)
    check(euroRates.count == 1 && euroRates[0].id == "EUR/USD" && euroRates[0].value == 1.1 && euroRates[0].cadence == .daily,"ECB parser preserves base currency and reference-rate date")
    let suite = "ru.bushe.stroka.newsroom.\(UUID())";let defaults = UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
    let m = AppModel(defaults:defaults);m.settings.contentPackID = "custom";m.settings.customFeeds = [FeedSource(name:"A",url:"https://a.example/feed",language:"en"),FeedSource(name:"B",url:"https://b.example/feed",language:"en")];m.newsLanguage = .english
    m.contentStories = (0..<20).map{Story(id:"a-\($0)",text:"A \($0)",source:"A",date:Date(),link:"",language:"en",packID:"custom")}+[Story(id:"b",text:"B",source:"B",date:Date(),link:"",language:"en",packID:"custom")]
    check(m.selectedContent.prefix(2).map(\.source) == ["A","B"],"selected publishers alternate instead of one publisher dominating")
    m.settings.marketInstruments = ["share:SBER","currency:USD"];m.saveSettingsNow();let restored = AppModel(defaults:defaults)
    check(restored.selectedInstruments.count == 2 && restored.selectedMarketIDs == m.selectedMarketIDs,"market selection survives restart")
    m.settings.channel = .message;m.settings.messages = "CONFERENCE 2026\nWelcome to the evening\nNext session starts at 18:30";m.settings.brand = "DESIGN\nFORUM";m.settings.caption = "MOSCOW · 2026";m.reduceMotion = false
    m.quotes = rows+rates+[Quote(id:"IMOEX",value:2800.12,change:0.35,time:Date(),received:Date(),source:"DEMO",currency:"pts",cadence:.index)]
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaNewsroom-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for dual in [false,true] { for look in Look.broadcastLooks {
        m.settings.look = look;m.settings.dualTicker = dual;m.settings.dualUpperChannel = .message;m.settings.showClock = true
        let view = TickerView(model:m);view.frame = CGRect(x:0,y:0,width:1710,height:dual ? 144 : 88)
        guard let rep = view.snapshot(at:0,marketTime:0),let png = rep.representation(using:.png,properties:[:]) else { exit(1) }
        check((rep.colorAt(x:0,y:0)?.alphaComponent ?? 1)<0.05,"rounded strip has transparent outer corners")
        let g = BroadcastGeometry.make(canvas:view.laneBounds,scale:1,showClock:true,look:look)
        check(abs(g.content.midY-g.band.midY)<0.001 && g.badge.minX == 0 && g.clock.maxX == view.frame.width,"headline is centred between left brand and right clock")
        if dual { check(view.compositor.station.contents != nil && view.marketLane?.compositor.clip.frame.minX == g.content.minX,"two rows share full-height side blocks and aligned text bounds") }
        try! png.write(to:folder.appendingPathComponent("\(look.rawValue)-\(dual ? "dual" : "single").png"))
    } }
    m.settings.look = .bulletin;m.settings.dualTicker = true
    let full = TickerView(model:m);full.frame = CGRect(x:0,y:0,width:1710,height:1107);_ = full.snapshot(at:0,marketTime:0)
    check(full.compositor.station.frame.height < 160,"fullscreen side blocks stay within the lower news band")
    if let rep = full.snapshot(at:0,marketTime:0),let png = rep.representation(using:.png,properties:[:]) { try! png.write(to:folder.appendingPathComponent("fullscreen-dual.png")) }
    print("NEWSROOM DIRECTORY: \(folder.path)");print("\(count) newsroom checks passed");fflush(stdout);exit(0)
}

func feedParserCheck() {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let rows = (try? JSONSerialization.jsonObject(with:data)) as? [[String:Any]],rows.allSatisfy({$0["name"] is String && ($0["data"] as? String).flatMap{Data(base64Encoded:$0)} != nil}) else{fputs("Expected a JSON array with name, URL and base64 feed data on stdin.\n",stderr);exit(2)}
    var failures = 0;var audit:[[String:Any]] = []
    for row in rows {
        let data = Data(base64Encoded:row["data"] as! String)!,name = row["name"] as! String
        let feed = FeedSource(name:name,url:row["url"] as? String ?? "https://example.org/feed",language:row["language"] as? String)
        let stories = feed.isTelegram ? TelegramPublicReader.read(data,source:feed) : RSSReader(source:name,language:feed.language).read(data)
        let now = Date(),fresh = stories.filter{EditorialPolicy.accepts($0,now:now,extended:[],allowExtended:false)}
        var record:[String:Any] = ["name":name,"url":feed.url,"parsed":stories.count,"fresh24h":fresh.count,"shortFresh24h":fresh.filter{ShortText.fits($0.text)}.count,"undated":stories.filter{$0.date == nil}.count,"future":stories.filter{($0.date ?? .distantPast)>now}.count]
        if let latest = stories.compactMap(\.date).max(){record["latestPublicationUTC"] = ISO8601DateFormatter().string(from:latest)}
        audit.append(record)
        if stories.isEmpty { failures += 1 }
        if !CommandLine.arguments.contains("--feed-health-audit") { print("\(stories.isEmpty ? "FAIL" : "PASS"): \(name) · \(stories.count) headlines") }
    }
    if CommandLine.arguments.contains("--feed-health-audit") {let output = try! JSONSerialization.data(withJSONObject:audit,options:[.prettyPrinted,.sortedKeys]);FileHandle.standardOutput.write(output);exit(0)}
    print("Native RSS/public-channel parser: \(rows.count-failures)/\(rows.count) passed");fflush(stdout);exit(failures == 0 ? 0 : 1)
}

func openMarketCheck() {
    let suite = "ru.bushe.stroka.marketlive.\(UUID())";let defaults = UserDefaults(suiteName:suite)!;let m = AppModel(defaults:defaults);m.market.start();pumpApplication(for:28)
    for provider in ["MOEX","CBR","ECB","Coinbase"] { print("\(provider): \(m.quotes.filter{$0.source == provider}.count) quotes") }
    print(m.moexStatus);print(m.cryptoStatus);let success = m.quotes.contains{$0.source == "MOEX"} && m.quotes.contains{$0.source == "CBR"};m.market.stop();defaults.removePersistentDomain(forName:suite);fflush(stdout);exit(success ? 0 : 2)
}

func catalogUICheck() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaCatalogUI-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for lang in [InterfaceLanguage.english,.russian] {
        let suite = "ru.bushe.stroka.catalogui.\(UUID())";let defaults = UserDefaults(suiteName:suite)!
        let m = AppModel(defaults:defaults);m.interfaceLanguage = lang
        for kind in ["sources","instruments","collections"] {
            let root:AnyView
            if kind == "sources" { root = AnyView(NewsCatalogView(model:m)) } else if kind == "instruments" { root = AnyView(MarketPickerView(model:m)) } else { root = AnyView(ContentBrowserView(model:m)) }
            let host = NSHostingView(rootView:root.background(Color(nsColor:.windowBackgroundColor)).foregroundStyle(.primary).environment(\.locale,Localization.locale));let size = host.fittingSize
            let w = NSWindow(contentRect:CGRect(origin:CGPoint(x:-10000,y:-10000),size:size),styleMask:[.titled],backing:.buffered,defer:false);w.isReleasedWhenClosed = false;w.contentView = host;w.appearance = NSAppearance(named:.aqua);w.orderFront(nil);host.layoutSubtreeIfNeeded();pumpApplication(for:0.4)
            let frame = host.superview ?? host
            let rep = frame.bitmapImageRepForCachingDisplay(in:frame.bounds)!;w.appearance!.performAsCurrentDrawingAppearance { frame.cacheDisplay(in:frame.bounds,to:rep) }
            try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(kind+"-"+lang.rawValue+".png"))
            w.orderOut(nil);w.contentView = nil;w.close()
        }
        defaults.removePersistentDomain(forName:suite)
    }
    print("CATALOG UI DIRECTORY: \(folder.path)");fflush(stdout);exit(0)
}

func compactCheck() {
    var count = 0
    func check(_ value:@autoclosure()->Bool,_ message:String) { guard value() else { print("FAIL: \(message)");fflush(stdout);exit(1) };count += 1;print("PASS: \(message)") }
    var settings = Settings();settings.dualTicker = true;settings.applyDensity(.desktop);check(settings.stripHeight == 52,"desktop two-row band is 52 pt")
    settings.dualTicker = false;settings.applyDensity(.desktop);check(settings.stripHeight == 50,"desktop single-row band is 50 pt")
    settings.stripHeight = 10;check(settings.resolvedStripHeight == 45,"saved thickness cannot render below 45 pt")
    settings.stripHeight = 999;check(settings.resolvedStripHeight == 180,"saved thickness cannot render above 180 pt")
    settings.applyDensity(.broadcast);check(settings.stripHeight == 88,"broadcast single row remains available")
    settings.dualTicker = true;settings.applyDensity(.broadcast);check(settings.stripHeight == 144,"broadcast two rows remain available")
    settings.stripHeight = 61;settings.applyDensity(.custom);check(settings.stripHeight == 61,"custom thickness is preserved")
    settings.stripPlacement = .top;settings.messages = "Do not replace my messages";settings.look = .bulletin;settings.stripHeight = 64;settings.stripDensity = nil
    let suite = "ru.bushe.stroka.compact.\(UUID())";let defaults = UserDefaults(suiteName:suite)!;defaults.set(8,forKey:"broadcastDesignVersion");defaults.set(try! JSONEncoder().encode(settings),forKey:"settings")
    let m = AppModel(defaults:defaults);defer { defaults.removePersistentDomain(forName:suite) }
    check(m.settings.stripHeight == 52 && m.settings.resolvedPlacement == .top && m.settings.messages == settings.messages,"legacy narrow profile becomes compact without changing placement or text")
    let relaunched = AppModel(defaults:defaults);check(relaunched.settings.stripHeight == 52,"compact migration persists across the next launch")
    m.applyLook(.wire);check(m.settings.stripHeight == 52 && m.settings.resolvedPlacement == .top,"switching TV appearance preserves compact size and top placement")
    let saved = try! JSONDecoder().decode(Settings.self,from:JSONEncoder().encode(m.settings));check(saved.stripDensity == .desktop,"density survives settings/preset persistence")
    m.settings.look = .bulletin;m.settings.channel = .message;m.settings.dualUpperChannel = .message;m.settings.brand = "BUSHE NEWS";m.settings.caption = "EVENT SUBTITLE";m.settings.messages = "Новости вашего дня\nНовая выставка откроется в субботу\nСледите за событиями";m.reduceMotion = false
    m.quotes = [Quote(id:"DEMO-SBER",value:278.5,change:1.25,time:Date(),received:Date(),source:"DEMO",currency:"RUB",cadence:.delayed),Quote(id:"DEMO-EUR/USD",value:1.1,change:nil,time:Date(),received:Date(),source:"DEMO",currency:"USD",cadence:.daily)]
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaCompact-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for look in Look.broadcastLooks { for dual in [false,true] {
        m.settings.look = look;m.settings.dualTicker = dual;m.settings.applyDensity(.desktop)
        let view = TickerView(model:m);view.frame = CGRect(x:0,y:0,width:1710,height:m.settings.stripHeight)
        guard let rep = view.snapshot(at:0,marketTime:0),let png = rep.representation(using:.png,properties:[:]) else { exit(1) }
        check(view.compactBand && view.compositor.clip.frame.width > 1400,"compact side blocks leave more width for text")
        if dual { check(view.marketLane!.compositor.clip.frame.minX == view.compositor.clip.frame.minX && view.marketBandHeight >= 18 && view.laneBounds.height >= 30,"compact rows align and retain readable height") }
        check((rep.colorAt(x:0,y:0)?.alphaComponent ?? 1)<0.05,"compact strip keeps transparent rounded corners")
        try! png.write(to:folder.appendingPathComponent("\(look.rawValue)-\(dual ? "dual" : "single").png"))
        m.playing = false;_ = view.snapshot(at:0,marketTime:0);check(view.compositor.pause.isHidden && (view.marketLane?.compositor.pause.isHidden ?? true),"pause text cannot overlap the ticker")
        m.playing = true
    } }
    m.settings.look = .bulletin;m.settings.dualTicker = true;m.settings.applyDensity(.desktop);m.activeMode = .strip;m.playing = true
    let w = NSWindow(contentRect:CGRect(x:100,y:100,width:1100,height:52),styleMask:[.borderless],backing:.buffered,defer:false);w.isReleasedWhenClosed = false
    let view = TickerView(model:m);w.contentView = view;w.orderFrontRegardless();pumpApplication(for:0.2)
    let down = NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:200,y:20),modifierFlags:[],timestamp:0,windowNumber:w.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
    let up = NSEvent.mouseEvent(with:.leftMouseUp,location:NSPoint(x:200,y:20),modifierFlags:[],timestamp:0.1,windowNumber:w.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
    view.mouseDown(with:down);check(m.playing,"starting a strip gesture does not pause immediately")
    view.mouseUp(with:up);pumpApplication(for:NSEvent.doubleClickInterval+0.05);check(!m.playing,"a completed single click toggles pause after the double-click interval")
    let paused = view.snapshot(at:0,marketTime:0)!;try! paused.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("paused.png"))
    view.stripPressPending = false;view.mouseUp(with:up);check(!m.playing,"mouse release after a drag does not toggle playback")
    w.orderOut(nil);w.contentView = nil;w.close();print("COMPACT DIRECTORY: \(folder.path)");print("\(count) compact checks passed");fflush(stdout);exit(0)
}

func shortContentCheck() {
    var count = 0
    func check(_ value:@autoclosure()->Bool,_ name:String) { guard value() else { print("FAIL: \(name)");fflush(stdout);exit(1) };count += 1;print("PASS: \(name)") }
    check(ShortText.count("One — two /// three") == 3,"word count excludes standalone separators")
    check(ShortText.fits("Раз два три четыре пять шесть семь восемь девять десять одиннадцать"),"eleven Russian words fit")
    check(!ShortText.fits("One two three four five six seven eight nine ten eleven twelve"),"long RSS titles are excluded rather than cut")
    let preview = ShortText.preview("One two three four five six seven eight nine ten eleven twelve\nMore text")
    check(ShortText.count(preview.0) == 11 && preview.1 && preview.0.hasSuffix("…"),"long public posts become labelled word-boundary excerpts")
    check(ShortText.plainHTML("<b>A &amp; B</b><br>Next &#128640;") == "A & B\nNext 🚀","public preview decodes entities and strips markup")
    check(TelegramPublicReader.username("@exploitex") == "exploitex" && TelegramPublicReader.username("https://t.me/s/aiffring") == "aiffring","public channel names normalize")
    check(TelegramPublicReader.username("https://t.me/+privateInvite") == nil,"private invite links are not treated as public feeds")
    let html = Data("""
    <div data-post="exploitex/123"><div class="tgme_widget_message_text js-message_text"><b>New film arrives this Friday</b><br>More details in the full post.</div><time datetime="2026-11-13T14:00:00+00:00"></time></div>
    <div data-post="anotherchannel/999"><div class="tgme_widget_message_text js-message_text">Foreign content</div></div>
    """.utf8)
    let feed = FeedSource(name:"@exploitex",url:"https://t.me/s/exploitex",language:"ru");let stories = TelegramPublicReader.read(html,source:feed)
    check(stories.count == 1 && stories[0].link == "https://t.me/exploitex/123" && stories[0].source == "@exploitex","public reader preserves channel provenance and post link")
    check(stories[0].date == parseDate("2026-11-13T14:00:00+00:00") && stories[0].isExcerpt == true,"public reader keeps source date and excerpt label")
    check((BuiltinCollections.items["thoughts"] ?? []).count == 24 && (BuiltinCollections.items["thoughts"] ?? []).allSatisfy{ShortText.fits($0.en) && ShortText.fits($0.ru)},"all 24 original bilingual thoughts fit eleven words")
    check(NewsCatalog.sources("cinema").count == 50,"expanded cinema collection is bundled")
    let suite = "ru.bushe.stroka.short.\(UUID())";let defaults = UserDefaults(suiteName:suite)!;let m = AppModel(defaults:defaults);defer{defaults.removePersistentDomain(forName:suite)}
    m.settings.channel = .content;m.newsLanguage = .english;m.selectPack("thoughts")
    check(m.selectedContent.count == 24 && !m.needsContent && m.settings.shortHeadlines == true,"thoughts work offline with the short filter")
    m.selectPack("telegram");check(m.newsLanguage == .russian && m.contentSources.map(\.name) == ["@aiffring","@exploitex"],"requested Telegram channels select their original language")
    m.settings.contentPackID = "custom";m.settings.customFeeds = [FeedSource(name:"Fixture",url:"https://example.org/rss",language:"ru")]
    m.contentStories = [Story(id:"one",text:"Короткий заголовок о кино",source:"Fixture",date:Date(),link:"",language:"ru",packID:"custom"),Story(id:"two",text:"Один два три четыре пять шесть семь восемь девять десять одиннадцать двенадцать",source:"Fixture",date:Date(),link:"",language:"ru",packID:"custom")]
    check(m.selectedContent.count == 1 && m.selectedContent[0].id == "one","short filter keeps complete short RSS titles")
    m.settings.shortHeadlines = false;check(m.selectedContent.count == 2,"turning the filter off restores original cached headlines")
    m.saveSettingsNow();let restored = AppModel(defaults:defaults);check(restored.settings.shortHeadlines == false,"short filter survives restart")
    print("\(count) short-content checks passed");fflush(stdout);exit(0)
}

func shortLiveCheck() {
    let suite = "ru.bushe.stroka.shortlive.\(UUID())";let defaults = UserDefaults(suiteName:suite)!;let m = AppModel(defaults:defaults)
    defer { defaults.removePersistentDomain(forName:suite) }
    m.settings.channel = .content;m.selectPack("telegram")
    m.contentStories = (0..<700).map{Story(id:"old-cache-\($0)",text:"Other cached news",source:"Fixture",date:Date().addingTimeInterval(86400),link:"",language:"en",packID:"world")}
    m.refreshContent();let deadline = Date().addingTimeInterval(30)
    while m.refreshingContent && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
    var success = !m.refreshingContent
    for channel in ["@aiffring","@exploitex"] {
        let rows = m.contentStories.filter{$0.packID == "telegram" && $0.source == channel}
        let eligible = m.selectedContent.filter{$0.source == channel}
        let valid = !rows.isEmpty && rows.allSatisfy{ShortText.fits($0.text) && $0.link.hasPrefix("https://t.me/"+channel.dropFirst()+"/")} && eligible.allSatisfy{m.fresh($0)}
        success = success && valid
        print("\(valid ? "PASS" : "FAIL"): \(channel) · \(rows.count) loaded excerpts; \(eligible.count) fresh enough for output")
    }
    success = success && m.contentStories.count <= 700
    print("Active Telegram pack survives a cache of 700 newer stories: \(success ? "PASS" : "FAIL")")
    m.saveSettingsNow();if let data = defaults.data(forKey:"contentCache"),let cached = try? JSONDecoder().decode([Story].self,from:data) { print("Cached public excerpts: \(cached.filter{$0.packID == "telegram"}.count)") }
    print("SHORT LIVE CHECK: \(success ? "PASS" : "FAIL")");fflush(stdout);exit(success ? 0 : 1)
}

func editorialCheck() {
    var count = 0
    func check(_ value:@autoclosure()->Bool,_ name:String) { guard value() else { print("FAIL: \(name)");fflush(stdout);exit(1) };count += 1;print("PASS: \(name)") }
    let now = Date(timeIntervalSince1970:1800000000)
    func story(_ age:Double,id:String = "story")->Story {Story(id:id,text:"AI helps teams test new ideas",source:"Fixture",date:now.addingTimeInterval(-age),link:"https://example.org/"+id,language:"en",packID:"custom")}
    let fresh = story(23*3600),old = story(25*3600),expired = story(48*3600)
    check(EditorialPolicy.accepts(fresh,now:now,extended:[],allowExtended:false),"news under 24 hours is eligible")
    check(!EditorialPolicy.accepts(story(24*3600),now:now,extended:[],allowExtended:false),"news expires at exactly 24 hours")
    check(!EditorialPolicy.accepts(old,now:now,extended:[],allowExtended:true),"48-hour mode does not extend unselected news")
    check(EditorialPolicy.accepts(old,now:now,extended:[old.id],allowExtended:true),"only explicitly marked highlights may last 48 hours")
    check(!EditorialPolicy.accepts(expired,now:now,extended:[expired.id],allowExtended:true),"even marked news expires at exactly 48 hours")
    var unknown = fresh;unknown.date = nil
    check(!EditorialPolicy.accepts(unknown,now:now,extended:[unknown.id],allowExtended:true),"unknown publication dates cannot be treated as fresh")
    check(!EditorialPolicy.accepts(story(-60),now:now,extended:[],allowExtended:false),"future timestamps do not appear as published news")
    check(EditorialPolicy.matches("ИИ помогает командам",include:"розница, команды, ИИ",exclude:"реклама"),"session topic matches any chosen term")
    check(!EditorialPolicy.matches("Реклама ИИ",include:"ИИ",exclude:"реклама"),"excluded topic terms remove unwanted stories")
    let suite = "ru.bushe.stroka.editorial.\(UUID())";let defaults = UserDefaults(suiteName:suite)!;let m = AppModel(defaults:defaults);defer{defaults.removePersistentDomain(forName:suite)}
    m.settings.channel = .content;m.selectPack("custom");m.settings.customFeeds = [FeedSource(name:"Fixture",url:"https://example.org/rss",language:"en")];m.newsLanguage = .all
    var live = fresh;live.date = Date().addingTimeInterval(-3600)
    m.contentStories = [live];m.settings.translateRussian = true
    check(m.selectedContent.isEmpty,"untranslated English is not shown when Russian display is requested")
    m.storeTranslations([live.translationKey:"ИИ помогает командам проверять новые идеи"])
    let translated = m.selectedContent.first!
    check(translated.text.hasPrefix("ИИ") && translated.isTranslated == true && translated.originalText == live.text,"Russian display preserves the original text and translation marker")
    check(translated.date == live.date && translated.id == live.id && translated.link == live.link,"translation preserves original publication date and provenance")
    m.settings.sessionKeywords = "розница";check(m.selectedContent.isEmpty,"session keywords filter the translated visible title")
    m.settings.sessionKeywords = "командам";check(m.selectedContent.count == 1,"relevant translated stories remain eligible")
    m.settings.sessionKeywords = "";m.settings.translateRussian = false
    var near = live;near.id = "will-expire";near.text = "A headline that must disappear";near.date = Date().addingTimeInterval(-24*3600+2)
    m.contentStories = [near]
    let w = NSWindow(contentRect:CGRect(x:100,y:100,width:1000,height:88),styleMask:[.borderless],backing:.buffered,defer:false);w.isReleasedWhenClosed = false
    m.settings.look = .bulletin;m.reduceMotion = false
    let view = TickerView(model:m);w.contentView = view;w.orderFrontRegardless();NSApp.activate(ignoringOtherApps:true);pumpApplication(for:0.25)
    check(m.lines.count == 1,"freshness deadline starts with the current item queued")
    pumpApplication(for:2.1)
    check(m.selectedContent.isEmpty && m.lines.isEmpty && !view.compositor.bodyKey.contains(near.text),"expiry invalidates cached queues and already prepared visible ticker text")
    w.orderOut(nil);w.contentView = nil;w.close()
    m.selectPack("thoughts");check(m.selectedContent.count == 48,"original offline thoughts are not mislabelled or expired as news")
    let marker = TickerStreamWindow.marker("▌▌▌",font:NSFont.systemFont(ofSize:28),accent:.orange)
    let colors = (3...5).compactMap{marker.attribute(.foregroundColor,at:$0,effectiveRange:nil) as? NSColor}
    check(marker.string.contains("│││") && colors.allSatisfy{$0 == .orange},"legacy vertical marker renders neutral bars in one accent color")
    let delegate = AppDelegate();delegate.model = m;let toolbar = NSToolbar(identifier:"EditorialTest")
    let ids = delegate.toolbarDefaultItemIdentifiers(toolbar).map(\.rawValue)
    check(ids.filter{$0 != NSToolbarItem.Identifier.flexibleSpace.rawValue} == ["privacy"],"toolbar keeps only Settings")
    print("\(count) editorial checks passed");fflush(stdout);exit(0)
}

func feedChooserUICheck() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaProducerUI-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for (lang,kind) in [(InterfaceLanguage.english,"sources"),(.russian,"sources"),(.english,"offline"),(.russian,"offline")] {
        let suite = "ru.bushe.stroka.producerui.\(UUID())";let defaults = UserDefaults(suiteName:suite)!;let m = AppModel(defaults:defaults);m.interfaceLanguage = lang;m.settings.sessionTitle = lang == .russian ? "Стратегическая сессия: технологии и команда" : "Strategy session: technology and teams";m.settings.sessionKeywords = lang == .russian ? "ИИ, команда" : "AI, team"
        m.selectPack(kind == "offline" ? "thoughts" : "custom");if kind == "offline" {m.settings.sessionKeywords = ""};m.settings.customFeeds = Array(NewsCatalog.sources("ai").prefix(3));m.settings.translateRussian = true;m.translationStatus = L("Download English and Russian for on-device translation");m.translationNeedsDownload = true
        if kind == "sources",let feed = m.settings.customFeeds?.first {m.sourceLoadState[feed.url] = .failed("HTTP 503");for other in (m.settings.customFeeds ?? []).dropFirst() {m.sourceLoadState[other.url] = .loaded(Date())}}
        let host = NSHostingView(rootView:FeedChooserView(model:m).background(Color(nsColor:.windowBackgroundColor)).foregroundStyle(.primary));let size = host.fittingSize
        let w = NSWindow(contentRect:CGRect(origin:CGPoint(x:-10000,y:-10000),size:size),styleMask:[.titled],backing:.buffered,defer:false);w.appearance = NSAppearance(named:.aqua);w.isReleasedWhenClosed = false;w.contentView = host;w.orderFront(nil);host.layoutSubtreeIfNeeded();pumpApplication(for:0.3)
        let frame = host.superview ?? host,rep = (host.superview ?? host).bitmapImageRepForCachingDisplay(in:(host.superview ?? host).bounds)!
        w.appearance!.performAsCurrentDrawingAppearance{frame.cacheDisplay(in:frame.bounds,to:rep)}
        try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("feed-chooser-"+kind+"-"+lang.rawValue+".png"))
        w.orderOut(nil);w.contentView = nil;w.close();defaults.removePersistentDomain(forName:suite)
    }
    print("PRODUCER UI DIRECTORY: \(folder.path)");fflush(stdout);exit(0)
}

func contentCatalogCheck() {
    var checks = 0
    func check(_ value:@autoclosure()->Bool,_ name:String) { guard value() else{print("FAIL: \(name)");fflush(stdout);exit(1)};checks += 1;print("PASS: \(name)") }
    let ids = ContentCatalog.packs.map(\.id)
    check(ids.count == 18 && Set(ids).count == ids.count,"18 distinct content choices across four groups")
    check(ContentCatalog.navigation == [.message,.content,.markets],"sidebar has My Text, Content and Markets only")
    check(ids.contains("ai") && !ContentCatalog.navigation.contains(.ai),"AI is a topic inside Content, not a separate sidebar mode")
    check(ids.contains("telegram") && ids.contains("custom") && ids.contains("cinema") && ids.contains("jokes"),"channels, own sources, cinema and humour are discoverable")
    let suite = "ru.bushe.stroka.contentcatalog.\(UUID())";let defaults = UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
    var old = Settings();old.channel = .ai;old.contentPackID = "ai";old.dualTicker = true;old.dualUpperChannel = .ai;old.messages = "KEEP MY TEXT";old.brand = "KEEP MY STATION"
    defaults.set(try! JSONEncoder().encode(old),forKey:"settings")
    let m = AppModel(defaults:defaults);let saved = try! JSONDecoder().decode(Settings.self,from:defaults.data(forKey:"settings")!)
    check(m.settings.channel == .content && m.settings.dualUpperChannel == .content,"legacy AI output migrates to Content")
    check(m.selectedPack.id == "ai" && saved.channel == .content,"legacy route migration persists and opens a visible topic")
    check(m.settings.feeds == old.feeds && m.settings.messages == old.messages && m.settings.brand == old.brand,"navigation migration preserves feeds and personal content")
    let language = m.interfaceLanguage
    m.interfaceLanguage = .russian
    check(ContentCatalog.matches(ContentPack.find("cinema"),search:"кино"),"Russian topic search finds cinema")
    check(ContentCatalog.matches(ContentPack.find("world"),search:"BBC"),"search finds a category by publisher")
    check(!ContentCatalog.matches(ContentPack.find("jokes"),search:"no-such-content-123"),"unmatched search has an explicit empty state")
    m.interfaceLanguage = .english
    check(ContentCatalog.matches(ContentPack.find("conversation"),search:"guests"),"English search understands the visible description")
    check(L(ContentPack.find("custom").catalogTitle) == "Your Sources" && Channel.content.title == "Content","navigation uses one consistent Content name")
    m.activateContentPack("thoughts")
    check(m.settings.channel == .content && m.upperChannel == .content && m.selectedPack.id == "thoughts","choosing content targets the actual upper output lane")
    check(!m.selectedContent.isEmpty && !m.needsNews,"offline selection produces content without the old AI news service")
    check(m.settings.messages == old.messages,"choosing a category keeps the user's message queue")
    check(ContentCatalog.packs.allSatisfy{!L($0.catalogDetail).isEmpty && !$0.catalogExamples.isEmpty},"every choice explains its content with real publisher names or an offline example")
    m.settings.translateRussian = true;m.settings.offlineLanguage = NewsLanguage.english.rawValue
    check(m.selectedContent.allSatisfy{$0.language == "en"} && m.settings.translateRussian == true,"offline language selection does not change news translation preferences")
    m.activateContentPack("jokes");m.settings.shortHeadlines = true
    check(!m.selectedContent.isEmpty && m.selectedContent.count == (BuiltinCollections.items["jokes"]?.count ?? 0),"short news filtering does not hide complete offline jokes")
    m.interfaceLanguage = language
    print("\(checks) content catalog checks passed");fflush(stdout);exit(0)
}
func contentGalleryUICheck() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaContentUI-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for (name,width,height,lang,dark) in [("en-content",1180.0,820.0,InterfaceLanguage.english,false),("ru-content",1180.0,820.0,.russian,false),("ru-compact",1070.0,700.0,.russian,false),("en-dark",1180.0,820.0,.english,true),("ru-inspector",1070.0,700.0,.russian,false),("en-inspector",1070.0,700.0,.english,false)] {
        let suite = "ru.bushe.stroka.contentui.\(UUID())";let defaults = UserDefaults(suiteName:suite)!;let m = AppModel(defaults:defaults);m.interfaceLanguage = lang;m.newsLanguage = lang == .russian ? .russian : .english;m.applyLook(.bulletin);m.settings.applyDensity(.desktop);m.activateContentPack("thoughts")
        let delegate = AppDelegate();delegate.model = m
        let w = NSWindow(contentRect:CGRect(x:-10000,y:-10000,width:width,height:height),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);w.isReleasedWhenClosed = false;w.appearance = NSAppearance(named:dark ? .darkAqua : .aqua);w.title = "Stroka";w.titlebarAppearsTransparent = true;w.toolbarStyle = .unified;w.contentView = NSHostingView(rootView:ControlView(model:m));delegate.window = w;delegate.configureToolbar();w.orderFront(nil);w.contentView?.layoutSubtreeIfNeeded();pumpApplication(for:0.3)
        if name.contains("inspector") {NotificationCenter.default.post(name:Notification.Name("StrokaAppearance"),object:nil);pumpApplication(for:0.3);w.contentView?.layoutSubtreeIfNeeded()}
        let frame = w.contentView!.superview ?? w.contentView!,rep = (w.contentView!.superview ?? w.contentView!).bitmapImageRepForCachingDisplay(in:(w.contentView!.superview ?? w.contentView!).bounds)!
        w.appearance!.performAsCurrentDrawingAppearance{frame.cacheDisplay(in:frame.bounds,to:rep)};try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name+".png"))
        w.orderOut(nil);w.contentView = nil;w.close();defaults.removePersistentDomain(forName:suite)
    }
    print("CONTENT UI DIRECTORY: \(folder.path)");fflush(stdout);exit(0)
}

func broadcastEdgeCheck() {
    var count = 0
    func check(_ value:@autoclosure()->Bool,_ name:String) { guard value() else{print("FAIL: \(name)");fflush(stdout);exit(1)};count += 1;print("PASS: \(name)") }
    let suite = "ru.bushe.stroka.edges.\(UUID())";let defaults = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:defaults);defer{defaults.removePersistentDomain(forName:suite)}
    m.settings.channel = .message;m.settings.messages = String(repeating:"M",count:240);m.settings.brand = "BUSHE NEWS";m.settings.broadcastSource = false;m.settings.speed = 120;m.reduceMotion = false
    m.quotes = [Quote(id:String(repeating:"M",count:100),value:120,change:1,time:Date(),received:Date(),source:"Fixture")]
    check(Look.broadcastLooks.count == 4 && Set(Look.broadcastLooks).count == 4,"exactly four selectable broadcast identities")
    check(Set(Look.broadcastLooks.map{ $0.bg.description+"|"+$0.accent.description }).count == 4,"four broadcast palettes are distinct")
    for look in Look.broadcastLooks {
        var edges = true,aligned = true
        for (width,height,previewScale) in [(1710.0,52.0,1.0),(1040.0,144.0,1.0),(630.0,36.0,0.7)] { for dual in [false,true] { for clock in [false,true] { for reverse in [false,true] { for mirror in [false,true] {
            autoreleasepool {
                m.settings.look = look;m.settings.dualTicker = dual;m.settings.dualUpperChannel = .message;m.settings.showClock = clock;m.settings.reverse = reverse;m.settings.mirror = mirror
                let view = TickerView(model:m);if previewScale != 1 {view.previewScale = previewScale};view.frame = CGRect(x:0,y:0,width:width,height:height);_ = view.snapshot(at:0.12,marketTime:0.16)
                let g = BroadcastGeometry.make(canvas:view.laneBounds,scale:previewScale,showClock:clock,look:look,compact:view.compactBand),clip = view.compositor.clip.frame
                edges = edges && abs(clip.minX-g.badge.maxX)<0.001 && abs(clip.maxX-g.clock.minX)<0.001
                if dual,let lower = view.marketLane { aligned = aligned && abs(lower.compositor.clip.frame.minX-clip.minX)<0.001 && abs(lower.compositor.clip.frame.maxX-clip.maxX)<0.001 } else if dual {aligned = false}
            }
        } } } } }
        check(edges,"\(look.rawValue): text meets both block edges in full/preview, either direction, mirror and clock-off")
        check(aligned,"\(look.rawValue): lower and upper rows share exact left/right boundaries")
    }
    m.settings.look = .signal;m.settings.showClock = true;m.settings.mirror = false
    for dual in [false,true] { for reverse in [false,true] {
        m.settings.dualTicker = dual;m.settings.reverse = reverse
        let view = TickerView(model:m);view.frame = CGRect(x:0,y:0,width:1040,height:52)
        var minimum = Int.max,maximum = Int.min,leaks = 0
        for i in 0..<11 {
            view.compositor.clip.isHidden = false;view.marketLane?.compositor.clip.isHidden = false
            let actual = view.snapshot(at:1+Double(i)*0.023,marketTime:1+Double(i)*0.031)!
            view.compositor.clip.isHidden = true;view.marketLane?.compositor.clip.isHidden = true
            let image = view.bitmap(size:view.bounds.size,scale:1){view.layer!.render(in:NSGraphicsContext.current!.cgContext)}!
            let base = NSBitmapImageRep(cgImage:image),left = Int(view.compositor.clip.frame.minX),right = Int(view.compositor.clip.frame.maxX)
            for x in 0..<actual.pixelsWide { for y in 0..<actual.pixelsHigh {
                let a = actual.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!,b = base.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                let difference = abs(a.redComponent-b.redComponent)+abs(a.greenComponent-b.greenComponent)+abs(a.blueComponent-b.blueComponent)
                if difference > 0.12 {minimum = min(minimum,x);maximum = max(maximum,x);if x<left || x>=right {leaks += 1}}
            } }
        }
        let clip = view.compositor.clip.frame
        check(leaks == 0,"pixel render: moving text never paints over station/clock, dual=\(dual) reverse=\(reverse)")
        print("PIXEL COVERAGE: dual=\(dual) reverse=\(reverse) ink=\(minimum)...\(maximum) clip=\(clip.minX)...\(clip.maxX)")
        check(minimum<=Int(clip.minX)+1 && maximum>=Int(clip.maxX)-2,"pixel render: glyphs reach both block seams without blank gutters, dual=\(dual) reverse=\(reverse)")
    } }
    for legacy in Look.legacyBroadcastLooks {
        let name = "ru.bushe.stroka.stylemigration.\(UUID())";let d = UserDefaults(suiteName:name)!
        var old = Settings();old.look = legacy;old.messages = "Keep this message";old.brand = "BUSHE NEWS";old.stripPlacement = .top;old.stripHeight = 52
        d.set(12,forKey:"compactStripVersion");d.set(8,forKey:"broadcastDesignVersion");d.set(try! JSONEncoder().encode(old),forKey:"settings")
        let restored = AppModel(defaults:d)
        check(restored.settings.look == legacy.resolvedBroadcastLook && restored.settings.messages == old.messages && restored.settings.brand == old.brand && restored.settings.stripPlacement == .top && restored.settings.stripHeight == 52,"legacy \(legacy.rawValue) maps to a visible style without replacing personal content")
        d.removePersistentDomain(forName:name)
    }
    print("\(count) broadcast edge/style checks passed");fflush(stdout);exit(0)
}

func stripDoubleClickCheck() {
    var checks = 0
    func check(_ value:@autoclosure()->Bool,_ name:String) {guard value() else{print("FAIL: \(name)");fflush(stdout);exit(1)};checks += 1;print("PASS: \(name)")}
    let suite = "ru.bushe.stroka.doubleclick.\(UUID())";let defaults = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:defaults);m.interfaceLanguage = .russian;m.newsLanguage = .russian;m.activateContentPack("jokes");m.applyLook(.bulletin);m.settings.dualTicker = true;m.settings.applyDensity(.desktop);m.activeMode = .strip;m.playing = true
    defer{defaults.removePersistentDomain(forName:suite)}
    let control = NSWindow(contentRect:CGRect(x:100,y:200,width:1180,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);control.isReleasedWhenClosed = false;control.title = "Stroka";control.appearance = NSAppearance(named:.aqua);control.contentView = NSHostingView(rootView:SimpleSetupView(model:m));m.controlWindow = control
    control.orderFront(nil);pumpApplication(for:0.2);control.orderOut(nil)
    let w = NSWindow(contentRect:CGRect(x:10,y:80,width:1000,height:52),styleMask:[.borderless],backing:.buffered,defer:false);w.isReleasedWhenClosed = false;let view = TickerView(model:m);w.contentView = view;w.orderFrontRegardless();pumpApplication(for:0.15)
    defer{w.orderOut(nil);w.contentView = nil;w.close();control.orderOut(nil);control.contentView = nil;control.close()}
    var requests = 0
    let token = NotificationCenter.default.addObserver(forName:Notification.Name("StrokaDisplaySettings"),object:m,queue:.main){_ in requests += 1};defer{NotificationCenter.default.removeObserver(token)}
    func click(_ number:Int) {
        let time = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:500,y:20),modifierFlags:[],timestamp:time,windowNumber:w.windowNumber,context:nil,eventNumber:number*2,clickCount:number,pressure:1)!
        let up = NSEvent.mouseEvent(with:.leftMouseUp,location:NSPoint(x:500,y:20),modifierFlags:[],timestamp:time+0.03,windowNumber:w.windowNumber,context:nil,eventNumber:number*2+1,clickCount:number,pressure:0)!
        view.mouseDown(with:down);view.mouseUp(with:up)
    }
    click(1);check(m.playing && view.pendingStripClick != nil,"first click waits for the system double-click interval without pausing")
    click(2);pumpApplication(for:NSEvent.doubleClickInterval+0.08)
    check(m.playing && requests == 1 && view.pendingStripClick == nil,"double-click opens settings exactly once and keeps a running strip playing")
    check(control.isVisible && !control.isMiniaturized,"double-click restores the hidden control window")
    control.contentView?.layoutSubtreeIfNeeded();pumpApplication(for:0.15)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaDoubleClick-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let frame = control.contentView!.superview ?? control.contentView!,rep = (control.contentView!.superview ?? control.contentView!).bitmapImageRepForCachingDisplay(in:(control.contentView!.superview ?? control.contentView!).bounds)!
    control.appearance!.performAsCurrentDrawingAppearance{frame.cacheDisplay(in:frame.bounds,to:rep)};try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("opened-display-settings-ru.png"))
    m.playing = false;click(1);click(2);pumpApplication(for:NSEvent.doubleClickInterval+0.08)
    check(!m.playing && requests == 2,"double-click also preserves an already paused strip")
    m.playing = true;click(1);pumpApplication(for:NSEvent.doubleClickInterval+0.08)
    check(!m.playing && requests == 2,"a single click still toggles pause and does not open settings")
    m.playing = true
    let down = NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:500,y:20),modifierFlags:[],timestamp:0,windowNumber:w.windowNumber,context:nil,eventNumber:100,clickCount:1,pressure:1)!
    let up = NSEvent.mouseEvent(with:.leftMouseUp,location:NSPoint(x:500,y:20),modifierFlags:[],timestamp:0.1,windowNumber:w.windowNumber,context:nil,eventNumber:101,clickCount:1,pressure:0)!
    view.mouseDown(with:down);view.stripPressPending = false;view.cancelStripClick();view.mouseUp(with:up);pumpApplication(for:NSEvent.doubleClickInterval+0.06)
    check(m.playing && requests == 2,"a drag-completed release neither pauses nor opens settings")
    click(1);w.contentView = nil;pumpApplication(for:NSEvent.doubleClickInterval+0.06)
    check(m.playing && view.pendingStripClick == nil,"removing the output cancels its delayed single-click action")
    w.contentView = view;click(1);m.activeMode = nil;pumpApplication(for:NSEvent.doubleClickInterval+0.06)
    check(m.playing,"stopping the strip before the click deadline cannot pause another output")
    print("DOUBLE CLICK DIRECTORY: \(folder.path)");print("\(checks) strip double-click checks passed");fflush(stdout);exit(0)
}

final class ReliabilityProtocol:URLProtocol {
    private let lock = NSLock();private var stopped = false
    static let startedLock = NSLock();static var paths:[String] = []
    override class func canInit(with request:URLRequest)->Bool {request.url?.host == "reliability.invalid"}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func stopLoading() {lock.lock();stopped = true;lock.unlock()}
    override func startLoading() {
        let path = request.url!.path
        Self.startedLock.lock();Self.paths.append(path);Self.startedLock.unlock()
        let work = DispatchWorkItem { [self] in
            lock.lock();defer{lock.unlock()};guard !stopped else {return}
            let header = path.contains("header") ? ["Content-Length":"2048"] : [:]
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:header)!,cacheStoragePolicy:.notAllowed)
            if path.contains("header") || path.contains("stream") {
                client?.urlProtocol(self,didLoad:Data(repeating:65,count:800));client?.urlProtocol(self,didLoad:Data(repeating:66,count:800))
            } else if path.contains("language") {
                let ru = path.contains("/ru/")
                let stamp = ISO8601DateFormatter().string(from:Date().addingTimeInterval(-60))
                let xml = "<rss><channel><item><title>\(ru ? "Свежая русская новость" : "Fresh English headline")</title><link>https://reliability.invalid/\(ru ? "ru" : "en")</link><pubDate>\(stamp)</pubDate></item></channel></rss>"
                client?.urlProtocol(self,didLoad:Data(xml.utf8))
            } else { client?.urlProtocol(self,didLoad:Data("bounded payload".utf8)) }
            client?.urlProtocolDidFinishLoading(self)
        }
        DispatchQueue.global().asyncAfter(deadline:.now()+(path.contains("slow") ? 2 : 0.03),execute:work)
    }
    static func hasStarted(_ path:String)->Bool {startedLock.lock();defer{startedLock.unlock()};return paths.contains(path)}
}
func feedReliabilityCheck() {
    var checks = 0
    func check(_ value:@autoclosure()->Bool,_ label:String) {guard value() else{print("FAIL: \(label)");fflush(stdout);exit(1)};checks += 1;print("PASS: \(label)")}
    func spin(_ ready:()->Bool) {let end = Date().addingTimeInterval(4);while !ready() && Date()<end {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}}
    let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [ReliabilityProtocol.self]
    let transport = FeedTransport(configuration:config,limit:1024,concurrency:2);defer{transport.invalidate()}
    var completed = 0;var success = 0;var errors:[Int] = []
    func load(_ path:String,scope:String = "test") {transport.load(URL(string:"https://reliability.invalid"+path)!,scope:scope){data,_,error in DispatchQueue.main.async{completed += 1;if data == Data("bounded payload".utf8){success += 1};if let error {errors.append((error as NSError).code)}}}}
    for i in 0..<6 {load("/ok/\(i)")};spin{completed == 6}
    check(completed == 6 && success == 6,"all queued requests complete with their payload")
    check(transport.maximumActive == 2,"network concurrency never exceeds the configured limit")
    load("/header");load("/stream");spin{completed == 8}
    check(completed == 8 && errors.count == 2 && errors.allSatisfy{$0 == URLError.dataLengthExceedsMaximum.rawValue},"known and unknown response lengths are bounded while receiving")
    transport.load(URL(string:"http://reliability.invalid/insecure")!,scope:"test"){data,_,error in DispatchQueue.main.async{completed += 1;if let error {errors.append((error as NSError).code)};check(data == nil,"insecure request delivers no content")}}
    spin{completed == 9};check(errors.last == URLError.unsupportedURL.rawValue,"HTTP sources are rejected before network access")
    let before = errors.count
    for i in 0..<6 {load("/slow/\(i)",scope:"old")}
    spin{ReliabilityProtocol.hasStarted("/slow/1")};load("/new",scope:"new");transport.cancel(scope:"old");spin{completed == 16}
    check(completed == 16 && errors.count-before == 6 && errors.suffix(6).allSatisfy{$0 == URLError.cancelled.rawValue},"scope cancellation completes active and queued requests exactly once")
    check(success == 7,"cancelling an obsolete scope preserves a new request")
    let reader = RSSReader(source:"Fixture",language:"en")
    let items = (0..<250).map{"<item><title>Item \($0)</title><pubDate>2026-11-14T10:00:00Z</pubDate></item>"}.joined()
    check(reader.read(Data(("<rss><channel>"+items+"</channel></rss>").utf8)).count == 40,"large feeds stop parsing after forty headlines")
    check(reader.read(Data("<rss><channel><item><title>Next</title></item></channel></rss>".utf8)).first?.text == "Next","parser can be safely reused after an early stop")
    check(reader.read(Data(("<rss><channel><item><title>"+String(repeating:"A",count:10000)+"</title></item></channel></rss>").utf8)).isEmpty,"oversized individual fields cannot inflate cached headlines")
    check(reader.read(Data("<rss><channel><item><title>broken".utf8)).isEmpty,"malformed incomplete feeds do not enter the queue")
    let updated = "<feed><entry><title>Edited old article</title><updated>2026-11-14T10:00:00Z</updated></entry></feed>"
    check(reader.read(Data(updated.utf8)).first?.date == nil,"Atom modification time cannot masquerade as publication time")
    let published = updated.replacingOccurrences(of:"</entry>",with:"<published>2026-11-12T10:00:00Z</published></entry>")
    check(reader.read(Data(published.utf8)).first?.date == parseDate("2026-11-12T10:00:00Z"),"original Atom publication date survives a newer modification")
    let dc = "<rss xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><channel><item><title>Dublin Core</title><dc:date>2026-11-14T10:00:00Z</dc:date></item></channel></rss>"
    check(reader.read(Data(dc.utf8)).first?.date != nil,"Dublin Core publication dates remain supported")
    let suite = "ru.bushe.stroka.reliability.\(UUID())";let defaults = UserDefaults(suiteName:suite)!
    let session = URLSession(configuration:config);let m = AppModel(defaults:defaults,session:session)
    defer{m.invalidatePendingContent();m.newsTimer?.invalidate();session.invalidateAndCancel();defaults.removePersistentDomain(forName:suite)}
    m.settings.dualTicker = false;m.settings.channel = .content;m.selectPack("custom");m.settings.shortHeadlines = false
    let en = FeedSource(name:"English",url:"https://reliability.invalid/slow/language/en/feed",language:"en")
    let ru = FeedSource(name:"Russian",url:"https://reliability.invalid/language/ru/feed",language:"ru")
    m.settings.customFeeds = [en,ru];m.newsLanguage = .english;m.start()
    spin{ReliabilityProtocol.hasStarted("/slow/language/en/feed")};m.newsLanguage = .russian
    spin{!m.refreshingContent && m.selectedContent.count == 1}
    check(m.selectedContent.count == 1 && m.selectedContent[0].source == "Russian","language change immediately fetches the newly selected sources")
    check(!m.contentStories.contains{$0.source == "English"},"cancelled old-language content cannot enter the queue")
    check(m.sourceSummary(ru) == LF("%ld eligible headlines",1),"source health reports eligible content instead of raw item count")
    m.settings.sessionKeywords = "missingword";check(m.sourceSummary(ru) == L("No headlines match your topic or length filters"),"source health explains filtering")
    m.sourceLoadState[ru.url] = .failed("HTTP 503");check(m.sourceSummary(ru).contains("HTTP 503"),"source failures remain visible without claiming the feed is empty")
    transport.invalidate();let closedBefore = completed;load("/closed");spin{completed > closedBefore}
    check(completed == closedBefore+1 && errors.last == URLError.cancelled.rawValue,"invalidated transports reject future requests once")
    print("\(checks) feed reliability checks passed");fflush(stdout);exit(0)
}

func simpleSetupCheck() {
    var count = 0
    func check(_ value:@autoclosure()->Bool,_ label:String){guard value() else{print("FAIL: \(label)");fflush(stdout);exit(1)};count += 1;print("PASS: \(label)")}
    let suite = "ru.bushe.stroka.simple.\(UUID())"
    let defaults = UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
    var saved = Settings();saved.look = .desk;saved.brand = "MY EVENT";saved.messages = "Private first\nPrivate second";saved.channel = .content;saved.contentPackID = "custom";saved.customFeeds = [FeedSource(name:"Saved feed",url:"https://example.org/rss",language:"ru")];saved.marketInstruments = ["share:SBER","currency:EUR"];saved.cryptoPairs = "ETH-USD";saved.stripHeight = 50;saved.stripDensity = .custom
    defaults.set(try! JSONEncoder().encode(saved),forKey:"settings");defaults.set(8,forKey:"broadcastDesignVersion");defaults.set(12,forKey:"compactStripVersion")
    let m = AppModel(defaults:defaults);m.prepareSimpleSetup()
    check(Look.broadcastLooks == [.bulletin,.nightline,.metro,.glass],"four deliberate styles in a stable order")
    check(m.settings.look == .nightline && m.previewMode == .strip,"legacy market look opens the simplified strip setup")
    check(m.settings.brand == saved.brand && m.settings.messages == saved.messages && m.settings.customFeeds == saved.customFeeds,"migration preserves name, messages and selected publishers")
    check(m.settings.marketInstruments == saved.marketInstruments && m.settings.cryptoPairs == saved.cryptoPairs,"migration preserves the user's stock/currency/crypto selection")
    check(m.settings.stripHeight == 50 && m.settings.showClock && m.settings.broadcastDate == true,"50 pt height is preserved and the time/date remain enabled")
    check(m.settings.composition == .ticker && m.settings.motion == .horizontal,"initial setup always explains one scrolling ticker")
    m.settings.speed = 111;m.prepareSimpleSetup();check(m.settings.speed == 111,"reopening setup does not reset user tuning")
    m.setSimpleDual(true);check(m.dualBandActive && m.upperChannel == .content && m.needsMarkets,"second-row toggle actually activates market services and preserves the news lane")
    m.chooseOwnText();check(m.upperChannel == .message && m.lines == ["Private first","Private second"],"own messages use the upper row without replacing saved content")
    m.setSimpleDual(false);check(!m.dualBandActive && !m.needsMarkets && m.lines.count == 2,"single row disables unused market services and keeps own messages")
    m.settings.marketInstruments = [];m.settings.cryptoPairs = "";m.setSimpleDual(true);check(m.selectedMarketIDs == ["currency:USD","currency:EUR","currency:CNY"],"an empty second row starts with useful currency defaults")
    m.setSimpleCrypto("BTC-USD",enabled:true);m.setSimpleCrypto("ETH-USD",enabled:true);m.setSimpleCrypto("BTC-USD",enabled:false)
    check(!m.hasCrypto("BTC-USD") && m.hasCrypto("ETH-USD"),"currency chips do not delete other chosen crypto pairs")
    m.activateContentPack("custom");m.settings.customFeeds = [];let feed = FeedSource(name:"New source",url:"https://example.org/new",language:"en");m.newsLanguage = .russian
    let chooser = QuickContentChooser(model:m);chooser.toggle(feed,true);chooser.toggle(feed,true)
    check(m.settings.customFeeds?.count == 1 && m.newsLanguage == .all && m.upperChannel == .content,"publisher selection is deduplicated and visible across source languages")
    m.settings.disabledContentSources = [feed.url];chooser.toggle(feed,true)
    check(m.enabledContentSources.contains{$0.url == feed.url},"reselecting a previously disabled publisher actually enables its content")
    m.newsLanguage = .russian;chooser.toggle(feed,false);check(m.settings.customFeeds?.isEmpty == true && m.newsLanguage == .russian,"removing a publisher preserves source-language selection")
    m.settings.shortHeadlines = true;m.settings.sessionKeywords = "";m.settings.translateRussian = false;m.newsLanguage = .english
    m.contentStories = [Story(id:"new",text:"A useful short headline",source:feed.name,date:Date().addingTimeInterval(-30),link:"https://example.org/new",language:"en",packID:"custom")];chooser.toggle(feed,true)
    check(m.selectedContent.count == 1,"chosen RSS headlines reach the actual ticker queue")
    m.contentStories[0].date = Date().addingTimeInterval(-25*3600);check(m.selectedContent.isEmpty,"simplified setup retains strict news freshness")
    for look in Look.broadcastLooks {m.applyLook(look);check(m.settings.look == look && m.dualBandActive,"\(look.rawValue) supports both news and markets")}
    let appDelegate = AppDelegate();appDelegate.model = m
    check(appDelegate.toolbarDefaultItemIdentifiers(NSToolbar(identifier:"simple")).map(\.rawValue).filter{$0 != NSToolbarItem.Identifier.flexibleSpace.rawValue} == ["privacy"],"only Settings remains in the toolbar")
    let snapshot = try! JSONDecoder().decode(Settings.self,from:try! JSONEncoder().encode(m.settings));check(snapshot.messages == saved.messages,"simplified preferences remain Codable without losing authored messages")
    let freshSuite = "ru.bushe.stroka.firstlaunch.\(UUID())";let freshDefaults = UserDefaults(suiteName:freshSuite)!;defer{freshDefaults.removePersistentDomain(forName:freshSuite)}
    let freshModel = AppModel(defaults:freshDefaults);freshModel.prepareSimpleSetup(firstLaunch:true)
    check(freshModel.settings.stripHeight == 50 && !freshModel.dualBandActive && !freshModel.needsMarkets,"first launch is a 50 pt news strip without unused market services")
    freshModel.setSimpleDual(true);check(freshModel.selectedMarketIDs == ["currency:USD","currency:EUR","currency:CNY"] && freshModel.settings.cryptoPairs.isEmpty,"first-time market opt-in uses deliberate currency defaults without hidden crypto")
    print("\(count) simple setup checks passed");fflush(stdout);exit(0)
}
func simpleSetupUICheck() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaSimpleUI-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for (name,lang,dark,width,height,dual,kind) in [("en-main",InterfaceLanguage.english,false,920.0,660.0,false,"main"),("ru-main",.russian,false,920.0,660.0,true,"main"),("en-dark",.english,true,920.0,660.0,true,"main"),("ru-compact",.russian,false,840.0,600.0,true,"main"),("en-content",.english,false,820.0,900.0,false,"content"),("ru-content",.russian,false,820.0,900.0,false,"content"),("ru-display",.russian,false,600.0,610.0,true,"display")] {
        autoreleasepool {
            let suite = "ru.bushe.stroka.simpleui.\(UUID())";let defaults = UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
            let m = AppModel(defaults:defaults);m.interfaceLanguage = lang;m.prepareSimpleSetup();m.applyLook(.bulletin);m.settings.brand = "BUSHE NEWS";m.settings.caption = "";m.settings.dualTicker = dual;m.settings.dualUpperChannel = .content;m.settings.applyDensity(.desktop);m.activateContentPack("thoughts");m.newsLanguage = lang == .russian ? .russian : .english
            m.settings.marketInstruments = ["currency:USD","currency:EUR","currency:CNY"];m.settings.cryptoPairs = ""
            m.quotes = [Quote(id:"USD/RUB",value:82.15,change:nil,time:Date(),received:Date(),source:"CBR",currency:"RUB",cadence:.daily)]
            NSApp.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
            let root:AnyView = kind == "content" ? AnyView(QuickContentChooser(model:m)) : kind == "display" ? AnyView(SimpleDisplaySettings(model:m)) : AnyView(SimpleSetupView(model:m))
            let w = NSWindow(contentRect:CGRect(x:100,y:100,width:width,height:height),styleMask:kind == "main" ? [.titled,.closable,.resizable] : [.borderless],backing:.buffered,defer:false);w.isReleasedWhenClosed = false;w.appearance = NSApp.appearance;w.title = "Stroka";w.contentView = NSHostingView(rootView:root);m.controlWindow = w
            let delegate = AppDelegate();delegate.window = w;delegate.model = m;if kind == "main"{w.titlebarAppearsTransparent = true;w.toolbarStyle = .unified;delegate.configureToolbar()}
            w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);w.contentView?.layoutSubtreeIfNeeded();pumpApplication(for:0.5)
            func prepare(_ view:NSView){if let v = view as? TickerView{_ = v.snapshot(at:1.2,marketTime:0.5)};view.subviews.forEach(prepare)};prepare(w.contentView!)
            let frame = w.contentView!.superview ?? w.contentView!,rep = (w.contentView!.superview ?? w.contentView!).bitmapImageRepForCachingDisplay(in:(w.contentView!.superview ?? w.contentView!).bounds)!
            w.appearance!.performAsCurrentDrawingAppearance{frame.cacheDisplay(in:frame.bounds,to:rep)};try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name+".png"))
            w.orderOut(nil);w.contentView = nil;w.close()
        }
    }
    print("SIMPLE UI DIRECTORY: \(folder.path)");fflush(stdout);exit(0)
}

func desktopEdgeCheck() {
    var checks = 0
    func check(_ value:@autoclosure()->Bool,_ label:String){guard value() else{print("FAIL: \(label)");fflush(stdout);exit(1)};checks += 1;print("PASS: \(label)")}
    check(StripPlacement.desktopEdges == [.bottom,.top],"only bottom and top are selectable positions")
    for area in [CGRect(x:0,y:80,width:1710,height:990),CGRect(x:-1920,y:24,width:1920,height:1000),CGRect(x:800,y:-900,width:1280,height:800)] {
        for placement in StripPlacement.allCases {for h in [45.0,180.0] {
            var s = Settings();s.stripPlacement = placement;s.stripDensity = .custom;s.stripHeight = h
            let frame = OutputController.stripFrame(in:area,settings:s)
            check(area.contains(frame) && frame.minX == area.minX && frame.width == area.width && frame.height == h && (placement == .top ? frame.maxY == area.maxY : frame.minY == area.minY),"\(placement.rawValue) resolves to a safe full-width horizontal edge at \(h) pt")
        }}
    }
    let suite = "ru.bushe.stroka.edgescope.\(UUID())"
    let d = UserDefaults(suiteName:suite)!;defer{d.removePersistentDomain(forName:suite)}
    var old = Settings();old.look = .bulletin;old.messages = "Keep my messages";old.brand = "MY NAME";old.stripPlacement = .left;old.stripHeight = 63;old.stripDensity = .custom;old.idleEnabled = true;old.motion = .vertical;old.composition = .poster;old.customFeeds = [FeedSource(name:"My publisher",url:"https://example.org/rss")];old.marketInstruments = ["currency:EUR"];old.cryptoPairs = "ETH-USD"
    d.set(try! JSONEncoder().encode(old),forKey:"settings");d.set(8,forKey:"broadcastDesignVersion");d.set(12,forKey:"compactStripVersion");d.set(17,forKey:"simpleSetupVersion")
    let m = AppModel(defaults:d);m.prepareDesktopTicker()
    check(m.settings.stripPlacement == .bottom && m.previewMode == .strip && m.settings.composition == .ticker && m.settings.motion == .horizontal && !m.settings.idleEnabled,"old side/poster/idle configuration migrates to a personal desktop strip")
    check(m.settings.messages == old.messages && m.settings.brand == old.brand && m.settings.customFeeds == old.customFeeds && m.settings.marketInstruments == old.marketInstruments && m.settings.cryptoPairs == old.cryptoPairs && m.settings.stripHeight == 63,"migration preserves authored content, publishers, instruments and requested height")
    m.settings.stripPlacement = .top;m.prepareDesktopTicker(force:true);check(m.settings.stripPlacement == .top,"an existing top placement is preserved")
    defer{m.outputs.stop()}
    for mode in OutputMode.allCases {
        m.outputs.show(mode);pumpApplication(for:0.08)
        let screen = NSScreen.screens[min(m.selectedScreen,NSScreen.screens.count-1)]
        check(m.activeMode == .strip && m.previewMode == .strip && m.outputs.extraWindows.isEmpty && m.outputs.window?.frame == OutputController.stripFrame(in:screen.visibleFrame,settings:m.settings),"legacy \(mode.rawValue) request produces exactly one correctly anchored strip")
    }
    let window = m.outputs.window!
    m.settings.stripPlacement = .bottom;pumpApplication(for:0.08)
    check(m.outputs.window === window && window.frame.minY == window.screen!.visibleFrame.minY,"changing top to bottom repositions the existing window")
    m.settings.stripPlacement = .top;pumpApplication(for:0.08)
    check(m.outputs.window === window && window.frame.maxY == window.screen!.visibleFrame.maxY,"changing bottom to top places the strip below the system-reserved menu area")
    let beforeDrag = window.frame,view = window.contentView as! TickerView
    let down = NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:150,y:20),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
    let drag = NSEvent.mouseEvent(with:.leftMouseDragged,location:NSPoint(x:300,y:100),modifierFlags:[],timestamp:0.1,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:1)!
    view.mouseDown(with:down);view.mouseDragged(with:drag)
    check(window.frame == beforeDrag && !view.stripPressPending && view.pendingStripClick == nil && m.playing,"dragging cannot detach the strip or accidentally pause it")
    let was = m.outputs.window;m.outputs.show(.full,idle:true)
    check(m.outputs.window === was && m.activeMode == .strip,"legacy idle requests cannot replace a working strip")
    let delegate = AppDelegate();delegate.model = m;delegate.configureMenu()
    func titles(_ menu:NSMenu)->[String]{menu.items.flatMap{[$0.title]+($0.submenu.map(titles) ?? [])}}
    let labels = titles(NSApp.mainMenu!)
    check(!labels.contains(L("Full Screen")) && !labels.contains(L("Screen Frame")) && labels.contains(L("Ticker at Top")) && labels.contains(L("Ticker at Bottom")),"application menu exposes only the two ticker positions")
    print("\(checks) desktop edge scope checks passed");fflush(stdout);exit(0)
}

func multiRowCheck() {
    var count = 0
    func check(_ ok:@autoclosure()->Bool,_ label:String) {guard ok() else {print("FAIL: \(label)");fflush(stdout);exit(1)};count += 1;print("PASS: \(label)")}
    let suite = "ru.bushe.stroka.multiline.\(UUID())";let defaults = UserDefaults(suiteName:suite)!
    let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [ReliabilityProtocol.self]
    let m = AppModel(defaults:defaults,session:URLSession(configuration:config));m.prepareSimpleSetup(firstLaunch:true);m.newsLanguage = .all;m.reduceMotion = false
    defer {m.outputs.stop();m.feedTransport.invalidate();m.editorialWake?.invalidate();m.pendingSave?.cancel();defaults.removePersistentDomain(forName:suite)}
    m.settings.dualTicker = true;m.settings.dualUpperChannel = .message;m.settings.channel = .content;m.settings.messages = "Preserved first\nPreserved second"
    m.setRowCount(3)
    check(m.tickerRows.count == 3 && m.tickerRows[0].messages == m.settings.messages && m.tickerRows[1].channel == .markets,"existing news + market layout survives adding a third row")
    m.setRowCount(4);check(m.tickerRows.count == 4 && m.settings.resolvedStripHeight >= 112,"four rows retain a readable minimum height")
    var own = TickerRow(channel:.message);own.messages = "A separate lower message"
    m.setRow(own,at:1);m.setRow(TickerRow(packID:"thoughts"),at:2);m.setRow(TickerRow(channel:.markets),at:3)
    check(m.rowLines(0) == ["Preserved first","Preserved second"] && m.rowLines(1) == ["A separate lower message"],"own text is isolated between rows")
    check(!m.rowLines(2).isEmpty && m.needsMarkets && !m.needsContent,"offline rows do not demand an RSS connection")
    m.quotes = [Quote(id:"DEMO-INDEX",value:2800,change:0.7,time:Date(),received:Date(),source:"DEMO")]
    let w = NSWindow(contentRect:CGRect(x:80,y:120,width:1100,height:144),styleMask:[.borderless],backing:.buffered,defer:false);w.isReleasedWhenClosed = false;w.level = .floating
    let v = TickerView(model:m);w.contentView = v;w.makeKeyAndOrderFront(nil);w.orderFrontRegardless();NSApp.activate(ignoringOtherApps:true);pumpApplication(for:0.6)
    check(v.extraLanes.count == 3 && v.marketLane?.rowIndex == 3,"four distinct renderers share one strip")
    let all = [v]+v.extraLanes
    if w.occlusionState.contains(.visible) {check(all.allSatisfy{$0.compositor.running},"all four rows animate")} else {print("SKIP: live animation and pause acceptance require an unlocked visible desktop")}
    let clips = all.map{$0.compositor.clip.frame}
    check(clips.allSatisfy{abs($0.minX-clips[0].minX)<0.1 && abs($0.maxX-clips[0].maxX)<0.1},"every row enters and exits exactly at the side blocks")
    check(abs(v.rowFrames.map(\.height).reduce(0,+)-144)<0.1 && zip(v.rowFrames,v.rowFrames.dropFirst()).allSatisfy{abs($0.minY-$1.maxY)<0.1},"row frames tile the strip without gaps or overlap")
    _ = v.snapshot(at:0.1)
    let keys = all.prefix(3).map{$0.compositor.bodyKey};m.quotes[0].value += 10;pumpApplication(for:0.05)
    check(Array(all.prefix(3).map{$0.compositor.bodyKey}) == keys,"live quotes update without replacing or restarting content")
    m.playing = false;pumpApplication(for:0.05);if w.occlusionState.contains(.visible) {check(all.allSatisfy{!$0.compositor.running},"pause freezes every row")}
    m.playing = true;m.reduceMotion = true;pumpApplication(for:0.05);_ = v.snapshot(at:0.1);check(all.allSatisfy{$0.activeMotion == .phrases && $0.compositor.moving.animation(forKey:"translation") == nil && $0.compositor.path == nil},"Reduce Motion replaces scrolling with stationary phrases on every row")
    m.reduceMotion = false
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaMultiline-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for look in Look.broadcastLooks {m.applyLook(look);if let image = v.snapshot(at:0.2){try! image.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("four-\(look.rawValue).png"))}}
    m.settings.translateRussian = false
    let en = FeedSource(name:"English",url:"https://reliability.invalid/language/en/feed",language:"en"),ru = FeedSource(name:"Russian",url:"https://reliability.invalid/language/ru/feed",language:"ru")
    var first = TickerRow(packID:"custom");first.customFeeds = [en];first.language = .english
    var second = TickerRow(packID:"custom");second.customFeeds = [ru];second.language = .russian
    m.setRow(first,at:0);m.setRow(second,at:1);m.setRow(first,at:2)
    check(m.requestedRowFeeds.count == 2,"shared feed URLs are fetched once across multiple rows")
    m.refreshContent();let end = Date().addingTimeInterval(4);while m.refreshingContent && Date()<end {pumpApplication(for:0.02)}
    check(m.rowLines(0).count == 1 && m.rowLines(1).count == 1 && m.rowLines(2) == m.rowLines(0),"one fetch serves three independently selected RSS rows")
    check(m.rowLines(0)[0].contains("Fresh English") && m.rowLines(1)[0].contains("Свежая русская"),"row-specific languages and publishers remain isolated")
    for i in m.contentStories.indices {m.contentStories[i].date = Date().addingTimeInterval(-25*3600)}
    check(m.rowLines(0).isEmpty && m.rowLines(1).isEmpty,"24-hour expiry removes stale news from every row")
    let encoded = try! JSONEncoder().encode(m.settings),decoded = try! JSONDecoder().decode(Settings.self,from:encoded)
    check(decoded.tickerRows == m.settings.tickerRows && decoded.resolvedTickerRows.count == 4,"row selections survive save and reload")
    do {let draft = RowEditorState(parent:m,index:1);draft.draft.chooseOwnText();draft.draft.settings.messages = "Unsaved draft";check(m.tickerRows[1].channel == .content,"cancelling a row draft leaves live content untouched")}
    m.setRowCount(1);pumpApplication(for:0.05)
    check(v.extraLanes.isEmpty && !m.needsMarkets,"returning to one row releases extra renderers and market demand")
    m.setRowCount(4);for i in 0..<4 {m.setRow(TickerRow(packID:"thoughts"),at:i)};pumpApplication(for:0.05)
    check(m.tickerRows.count == 4 && !m.needsMarkets && !m.needsContent,"four information rows work without any quotes")
    for language in [InterfaceLanguage.english,.russian] {
        m.interfaceLanguage = language
        let host = NSHostingView(rootView:SimpleSetupView(model:m));host.frame = CGRect(x:0,y:0,width:920,height:758)
        let ui = NSWindow(contentRect:host.frame,styleMask:[.titled],backing:.buffered,defer:false);ui.isReleasedWhenClosed = false;ui.contentView = host;ui.orderFrontRegardless();pumpApplication(for:0.3)
        host.layoutSubtreeIfNeeded();if let rep = host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:rep);try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("setup-\(language.rawValue).png"))};ui.orderOut(nil);ui.contentView = nil;ui.close()
    }
    w.orderOut(nil);w.contentView = nil;w.close();print("MULTILINE DIRECTORY: \(folder.path)");print("\(count) multiline checks passed");fflush(stdout);exit(0)
}

func onboardingCheck() {
    var count = 0
    func check(_ value:@autoclosure()->Bool,_ label:String) {guard value() else {print("FAIL: \(label)");fflush(stdout);exit(1)};count += 1;print("PASS: \(label)")}
    let suite = "ru.bushe.stroka.setup.\(UUID())";let d = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:d);m.prepareSimpleSetup(firstLaunch:true);m.prepareOnboarding(firstLaunch:true)
    check(m.showOnboarding && d.string(forKey:"onboardingState") == "pending" && !m.servicesStarted,"first launch enters setup before fetching or launching a ticker")
    let reopened = AppModel(defaults:d);reopened.prepareOnboarding(firstLaunch:false)
    check(reopened.showOnboarding,"unfinished setup returns after reopening")
    let draft = PersonalFeedDraft(parent:m,fresh:true)
    check(draft.interests.isEmpty && !draft.canContinue && draft.makeSettings() == nil,"new users choose their own interests and cannot start an empty feed")
    draft.interests = ["world","technology","sport"];draft.step = 1
    check(draft.canContinue && draft.rows.count == 1 && Set(draft.rows[0].topicIDs ?? []) == draft.interests,"three interests combine into one personal feed by default")
    check(Set(draft.selectedSources.map(\.url)).count == draft.selectedSources.count,"topic publishers are deduplicated by URL")
    let removed = draft.selectedSources[0];draft.toggleSource(removed,false)
    check(!draft.selectedSources.contains{$0.url == removed.url},"publisher removal affects the assembled feed")
    draft.toggleSource(removed,true);draft.language = .russian
    check(!draft.selectedSources.isEmpty && draft.selectedSources.allSatisfy{$0.language == nil || $0.language == "ru"},"source-language choice changes the actual publisher selection")
    draft.interests.insert("moscow");draft.language = .english
    check(draft.unavailableTopics.contains{$0.id == "moscow"} && !draft.canContinue && draft.makeSettings() == nil,"a topic without selected-language sources is explained rather than silently dropped")
    draft.interests.remove("moscow");draft.language = .all;draft.infoRows = 3
    check(draft.rows.count == 3 && Set(draft.rows.flatMap{$0.topicIDs ?? []}) == draft.interests,"separate rows retain every selected interest")
    draft.toggleMarkets(true)
    check(draft.rows.count == 4 && draft.rows.last?.channel == .markets && !draft.instruments.isEmpty,"optional quotes occupy the final fourth row with explicit instruments")
    draft.interests = ["world","business","moscow","technology","science","sport","cinema","culture"];draft.infoRows = 99
    check(draft.rows.count == 4 && Set(draft.rows.flatMap{$0.topicIDs ?? []}) == draft.interests,"more than four topics are grouped without dropping interests or exceeding four rows")
    draft.sourceName = "Telegram test";draft.sourceAddress = "@exploitex";draft.addSource()
    check(draft.sourceError.isEmpty && draft.selectedSources.contains{$0.url == "https://t.me/s/exploitex"} && draft.interests.contains("custom"),"Telegram input joins the selected feed through the same source step")
    let sourceCount = draft.ownSources.count;draft.sourceName = "Duplicate";draft.sourceAddress = "https://t.me/exploitex";draft.addSource()
    check(draft.ownSources.count == sourceCount && !draft.sourceError.isEmpty,"duplicate Telegram links cannot create duplicate sources")
    draft.sourceName = "Invalid";draft.sourceAddress = "http://example.org/feed";draft.addSource()
    check(draft.ownSources.count == sourceCount && !draft.sourceError.isEmpty,"insecure custom source addresses are rejected")
    m.settings.messages = "Retained authored message";let before = try! JSONSerialization.jsonObject(with:JSONEncoder().encode(m.settings)) as! NSDictionary
    do {let cancelled = PersonalFeedDraft(parent:m,fresh:false);cancelled.interests = ["sport"];cancelled.brand = "Not saved";cancelled.look = .nightline;cancelled.refreshPreview()}
    check((try! JSONSerialization.jsonObject(with:JSONEncoder().encode(m.settings)) as! NSDictionary) == before,"editing or cancelling setup never changes the live profile")
    let saving = PersonalFeedDraft(parent:m,fresh:true);saving.interests = ["world","technology","sport"];saving.infoRows = 3;saving.toggleMarkets(true);saving.brand = "MY FEED";saving.look = .nightline;saving.edge = .top;saving.language = .all;saving.step = 3
    check(saving.finish(on:m,start:false),"final confirmation applies the reviewed profile atomically")
    check(m.settings.brand == "MY FEED" && m.settings.look == .nightline && m.settings.desktopEdge == .top && m.settings.messages == "Retained authored message","appearance and position apply while authored messages are retained")
    check(m.tickerRows.count == 4 && m.tickerRows.last?.channel == .markets && Set(m.tickerRows.flatMap{$0.topicIDs ?? []}) == saving.interests,"committed rows contain the complete selected topic set")
    check(!m.showOnboarding && d.string(forKey:"onboardingState") == "complete" && !m.servicesStarted,"successful setup is remembered and the isolated check starts no network service")
    let reload = AppModel(defaults:d);reload.prepareOnboarding(firstLaunch:false)
    check(!reload.showOnboarding && reload.tickerRows.map(\.topicIDs) == m.tickerRows.map(\.topicIDs),"next launch opens the saved profile without repeating onboarding")
    for (index,row) in m.tickerRows.enumerated() where row.channel == .content {
        guard let source = row.customFeeds.first else {continue}
        m.contentStories.append(Story(id:"setup-\(index)",text:"Fresh story for row \(index)",source:source.name,date:Date().addingTimeInterval(-60),link:"https://example.org/\(index)",language:source.language,sourceURL:source.url,packID:"custom"))
    }
    check((0..<3).allSatisfy{!m.rowLines($0).isEmpty},"selected publishers reach each actual ticker queue")
    check((0..<3).allSatisfy{m.tickerRows[$0].title != L("Your Sources")},"row labels show chosen interests instead of an opaque RSS bucket")
    let existingSuite = "ru.bushe.stroka.setup-existing.\(UUID())";let old = UserDefaults(suiteName:existingSuite)!;let existing = AppModel(defaults:old);existing.settings.brand = "Existing profile";existing.prepareOnboarding(firstLaunch:false)
    check(!existing.showOnboarding && existing.settings.brand == "Existing profile","existing installations keep their profile and opt into the new setup")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaOnboarding-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for lang in [InterfaceLanguage.english,.russian] {
        m.interfaceLanguage = lang
        let flow = PersonalFeedDraft(parent:m,fresh:true);flow.interests = ["world","technology","sport"];flow.infoRows = 3;flow.toggleMarkets(true);flow.brand = "MY FEED"
        for step in 0...3 {
            flow.step = step;flow.refreshPreview()
            let root = NSHostingView(rootView:PersonalFeedSetup(model:m,draft:flow));root.frame = CGRect(x:0,y:0,width:920,height:690)
            let window = NSWindow(contentRect:root.frame,styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed = false;window.appearance = NSAppearance(named:.aqua);window.contentView = root;window.orderFrontRegardless();pumpApplication(for:0.2);root.layoutSubtreeIfNeeded()
            if let rep = root.bitmapImageRepForCachingDisplay(in:root.bounds){root.cacheDisplay(in:root.bounds,to:rep);try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("\(lang.rawValue)-step-\(step+1).png"))}
            window.orderOut(nil);window.contentView = nil;window.close()
        }
    }
    m.pendingSave?.cancel();reopened.pendingSave?.cancel();reload.pendingSave?.cancel();existing.pendingSave?.cancel();m.editorialWake?.invalidate();d.removePersistentDomain(forName:suite);old.removePersistentDomain(forName:existingSuite)
    print("ONBOARDING DIRECTORY: \(folder.path)");print("\(count) onboarding checks passed");fflush(stdout);exit(0)
}

func quickFeedCheck() {
    var count = 0
    func check(_ value:@autoclosure()->Bool,_ label:String) {guard value() else{print("FAIL: \(label)");fflush(stdout);exit(1)};count += 1;print("PASS: \(label)")}
    let suite = "ru.bushe.stroka.quick.\(UUID())";let d = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:d);m.prepareSimpleSetup(firstLaunch:true);m.prepareOnboarding(firstLaunch:true);m.interfaceLanguage = .russian
    let state = QuickFeedState(model:m,fresh:true)
    check(state.selected.isEmpty && state.visible.count == 6 && !state.canFinish,"first screen shows six suggestions without preselecting or fetching publishers")
    check(Set(state.visible.map{state.topic($0)}).count == 6,"default suggestions cover distinct interests instead of six near-identical news feeds")
    let feeds = state.visible
    check(Set(state.suggestions.map(\.url)) == Set(state.pool.map(\.url)),"all catalog sources remain discoverable, including the dedicated AI topic")
    do {let cleared = QuickFeedState(model:m,fresh:true);cleared.toggle(feeds[0]);cleared.selectedOnly = true;cleared.toggle(feeds[0]);check(!cleared.selectedOnly && !cleared.visible.isEmpty,"removing the last selection restores discovery instead of trapping an empty grid")}
    state.toggle(feeds[0]);check(state.selected.count == 1 && state.canFinish,"one explicit source is enough to create a feed")
    state.toggle(feeds[1]);state.toggle(feeds[3]);let picked = Set(state.selected.map(\.url))
    state.toggleTopic("cinema");state.search = "nothing matches";state.browseLanguage = .english
    check(Set(state.selected.map(\.url)) == picked && state.visible.isEmpty,"topic, language and search filters never remove selected publishers")
    state.selectedOnly = true
    check(Set(state.visible.map(\.url)) == picked,"Selected only reveals every selected publisher even when discovery filters hide it")
    state.toggle(feeds[0]);check(state.selected.count == 2 && !state.selectedURLs.contains(feeds[0].url),"unselecting a card removes exactly that publisher")
    state.selectedOnly = false;state.search = "";state.filters = ["sport"];state.browseLanguage = .all
    check(state.visible.allSatisfy{state.topic($0) == "sport"},"topic suggestions use the chosen topic")
    let beforeSuggestions = state.selected.count;state.chooseSuggestions()
    check(state.selected.count >= beforeSuggestions && Set(state.selected.map(\.url)).count == state.selected.count,"Choose for me adds a bounded deduplicated suggestion set")
    state.draft.sourceName = "Telegram";state.draft.sourceAddress = "@exploitex";state.addSource()
    check(state.selectedURLs.contains("https://t.me/s/exploitex") && state.selectedOnly,"a pasted Telegram channel becomes a visible selected source")
    let afterTelegram = state.selected.count;state.draft.sourceName = "Duplicate";state.draft.sourceAddress = "https://t.me/exploitex";state.addSource()
    check(state.selected.count == afterTelegram && !state.draft.sourceError.isEmpty,"duplicate aliases cannot add a channel twice")
    state.draft.sourceName = "Custom HTTPS";state.draft.sourceAddress = "https://example.org/custom.xml";state.addSource()
    check(state.selected.contains{$0.url == "https://example.org/custom.xml"},"custom RSS participates in the same explicit selection")
    state.draft.sourceName = "Invalid";state.draft.sourceAddress = "http://example.org/insecure.xml";state.addSource()
    check(!state.selected.contains{$0.url.contains("insecure.xml")},"insecure custom sources remain rejected")
    state.draft.sourceName = "";state.draft.sourceAddress = "https://optional.example.org/rss.xml";state.addSource()
    check(state.selected.contains{$0.name == "optional.example.org"},"custom feed names are optional and default to the host")
    let settings = state.makeSettings()!
    check(settings.resolvedTickerRows.count == 1 && Set(settings.customFeeds!.map(\.url)) == Set(state.selected.map(\.url)),"ready state assembles one feed from exactly the chosen sources")
    check(Set(settings.contentTopicIDs ?? []) == Set(state.selectedTopics),"the resulting feed retains descriptive topic names")
    state.draft.toggleMarkets(true);check(state.makeSettings()?.resolvedTickerRows.count == 2 && state.makeSettings()?.resolvedTickerRows.last?.channel == .markets,"optional quotes add one row without another setup screen")
    state.draft.toggleMarkets(false);m.settings.messages = "My authored text";let parentBefore = try! JSONSerialization.jsonObject(with:JSONEncoder().encode(m.settings)) as! NSDictionary
    do {let cancelled = QuickFeedState(model:m,fresh:false);cancelled.chooseSuggestions();cancelled.draft.brand = "Unsaved";cancelled.refreshPreview()}
    check((try! JSONSerialization.jsonObject(with:JSONEncoder().encode(m.settings)) as! NSDictionary) == parentBefore,"back, discovery and cancellation leave the live profile intact")
    let saving = QuickFeedState(model:m,fresh:true)
    for feed in feeds.prefix(3){saving.toggle(feed)}
    saving.draft.brand = "MY SOURCES";saving.page = 1
    check(saving.finish(on:m,start:false),"the second screen saves the personal feed directly")
    check(m.settings.messages == "My authored text" && m.settings.brand == "MY SOURCES" && !m.showOnboarding,"confirmation preserves authored text and remembers completion")
    for (index,feed) in saving.selected.enumerated(){m.contentStories.append(Story(id:"quick-\(index)",text:"Fresh headline \(index)",source:feed.name,date:Date().addingTimeInterval(-30),link:"https://example.org/\(index)",language:feed.language,sourceURL:feed.url,packID:"custom"))}
    m.contentStories.append(Story(id:"unselected",text:"An unselected headline",source:"Unselected",date:Date(),link:"https://example.org/unselected",language:"en",sourceURL:"https://example.org/unselected.xml",packID:"custom"))
    check(m.rowLines(0).count == saving.selected.count && !m.rowLines(0).contains{$0.contains("An unselected headline")},"chosen publishers reach the moving queue and unrelated publishers stay out")
    for index in m.contentStories.indices{m.contentStories[index].date = Date().addingTimeInterval(-25*3600)}
    check(m.rowLines(0).isEmpty,"the simpler selection preserves the 24-hour expiry rule")
    let again = QuickFeedState(model:m,fresh:false)
    check(Set(again.selected.map(\.url)) == Set(saving.selected.map(\.url)),"reopening source selection restores the selected publisher URLs")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaQuickFeed-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for (lang,width,height,dark) in [(InterfaceLanguage.english,920.0,690.0,false),(.russian,920,690,false),(.russian,840,620,false),(.english,920,690,true)] {
        m.interfaceLanguage = lang;let flow = QuickFeedState(model:m,fresh:true);flow.chooseSuggestions()
        for page in 0...1 {
            flow.page = page;flow.refreshPreview()
            let root = NSHostingView(rootView:QuickFeedSetup(model:m,state:flow));root.frame = CGRect(x:0,y:0,width:width,height:height)
            let w = NSWindow(contentRect:root.frame,styleMask:[.titled],backing:.buffered,defer:false);w.isReleasedWhenClosed = false;w.appearance = NSAppearance(named:dark ? .darkAqua : .aqua);w.contentView = root;w.orderFrontRegardless();pumpApplication(for:0.2);root.layoutSubtreeIfNeeded()
            if let rep = root.bitmapImageRepForCachingDisplay(in:root.bounds){w.appearance!.performAsCurrentDrawingAppearance{root.cacheDisplay(in:root.bounds,to:rep)};try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("\(lang.rawValue)-\(Int(width))-\(dark ? "dark" : "light")-page-\(page+1).png"))}
            w.orderOut(nil);w.contentView = nil;w.close()
        }
    }
    m.pendingSave?.cancel();m.editorialWake?.invalidate();d.removePersistentDomain(forName:suite)
    print("QUICK FEED DIRECTORY: \(folder.path)");print("\(count) quick-feed checks passed");fflush(stdout);exit(0)
}

func rowSpeedCheck() {
    var checks = 0
    func check(_ ok:@autoclosure()->Bool,_ label:String){guard ok() else{print("FAIL: \(label)");fflush(stdout);exit(1)};checks += 1;print("PASS: \(label)")}
    let suite = "ru.bushe.stroka.row-speed.\(UUID())";let defaults = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:defaults);m.prepareSimpleSetup(firstLaunch:true);m.reduceMotion = false;m.settings.speed = 100
    defer{m.outputs.stop();m.pendingSave?.cancel();defaults.removePersistentDomain(forName:suite)}
    for count in 1...4 {
        m.setRowCount(count)
        for index in 0..<count {var row = TickerRow(channel:.message);row.messages = "Row \(index+1) · A long continuous message to measure steady ticker movement without wrapping";m.setRow(row,at:index)}
        let speeds = (0..<count).map{m.speedForRow($0)}
        check(zip(speeds,speeds.dropFirst()).allSatisfy{$0 < $1} && speeds.last == 100,"\(count) rows have increasing speeds, ending at the selected tempo")
        check(abs(speeds[0]-(100-10*Double(count-1)))<0.001,"\(count) rows use a gentle ten-percent speed step")
    }
    m.setRow(TickerRow(channel:.markets),at:2);check(m.speedForRow(2) == 90 && m.speedForRow(3) == 100,"quotes follow their position even when above the final content row")
    m.setRow(TickerRow(channel:.markets),at:3);m.settings.marketSpeed = 60
    check(m.speedForRow(3) == 100,"automatic mode applies to quotes despite an older custom quote speed")
    let encoded = try! JSONEncoder().encode(m.settings),decoded = try! JSONDecoder().decode(Settings.self,from:encoded)
    check(decoded.graduatedSpeeds == nil,"older saved profiles enable automatic graduation without a destructive migration")
    m.settings.graduatedSpeeds = false;check(m.speedForRow(0) == 100 && m.speedForRow(3) == 60,"advanced opt-out retains the former independent quote speed")
    m.settings.graduatedSpeeds = true;m.settings.speed = 20;check(abs(m.speedForRow(0)-14)<0.001 && m.speedForRow(3) == 20,"slowest slider setting preserves the full row hierarchy")
    m.settings.speed = 200
    for index in 0..<4 {var row = TickerRow(channel:.message);row.messages = "Row \(index) · "+String(repeating:"Continuous smooth motion. ",count:30);m.setRow(row,at:index)}
    let w = NSWindow(contentRect:CGRect(x:80,y:140,width:1100,height:144),styleMask:[.borderless],backing:.buffered,defer:false);w.isReleasedWhenClosed = false;w.level = .floating
    let v = TickerView(model:m);w.contentView = v;w.orderFrontRegardless();NSApp.activate(ignoringOtherApps:true);pumpApplication(for:0.6)
    let lanes = [v]+v.extraLanes
    func x(_ v:TickerView)->CGFloat{v.compositor.moving.presentation()?.position.x ?? v.compositor.moving.position.x}
    check(lanes.count == 4,"all four renderers are created")
    if w.occlusionState.contains(.visible) {
        check(lanes.allSatisfy{$0.compositor.running},"all four rows animate on the visible desktop")
        let start = lanes.map{x($0)};let began = CACurrentMediaTime();pumpApplication(for:0.45);let elapsed = CACurrentMediaTime()-began
        let distances = zip(start,lanes.map{x($0)}).map{$0-$1}
        check(zip(distances,distances.dropFirst()).allSatisfy{$0<$1},"measured on-screen travel increases from top to bottom")
        check(distances.enumerated().allSatisfy{abs(Double($0.element)/elapsed-m.speedForRow($0.offset))<18},"measured movement agrees with the requested row speeds")
        let keys = lanes.map{$0.compositor.bodyKey},before = lanes.map{x($0)}
        m.settings.speed = 120;pumpApplication(for:0.05)
        check(zip(before,lanes.map{x($0)}).allSatisfy{abs($0-$1)<20},"changing the master slider preserves current text positions")
        check(lanes.map{$0.compositor.bodyKey} == keys,"changing tempo keeps every row's content")
    } else {print("SKIP: visible movement requires an unlocked desktop")}
    let tv = m.televisionState();check(tv.rows.enumerated().allSatisfy{abs($0.element.speed-m.speedForRow($0.offset))<0.001},"TV export uses exactly the same speed hierarchy")
    w.orderOut(nil);w.contentView = nil;w.close()
    print("\(checks) row speed checks passed");fflush(stdout);exit(0)
}

func tvBridgeCheck() {
    var count = 0
    func check(_ ok:@autoclosure()->Bool,_ label:String){guard ok() else{print("FAIL: \(label)");fflush(stdout);exit(1)};count += 1;print("PASS: \(label)")}
    let suite = "ru.bushe.stroka.tv.\(UUID())";let defaults = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:defaults);m.prepareSimpleSetup(firstLaunch:true);m.setRowCount(4);m.settings.speed = 100
    defer{m.setTVSharing(false);m.pendingSave?.cancel();defaults.removePersistentDomain(forName:suite)}
    var own = TickerRow(channel:.message);own.messages = "A shared test message";m.setRow(own,at:0)
    m.setRow(TickerRow(packID:"thoughts"),at:1);m.setRow(TickerRow(channel:.markets),at:2);m.setRow(own,at:3)
    m.quotes = [Quote(id:"FRESH",value:100,change:1,time:Date(),received:Date(),source:"DEMO"),Quote(id:"OLD",value:100,change:1,time:Date().addingTimeInterval(-2000),received:Date().addingTimeInterval(-2000),source:"DEMO")]
    let state = m.televisionState()
    check(state.rows.count == 4 && state.rows[0].items.first?.text == own.messages,"TV snapshot contains the four chosen rows")
    check(state.rows[1].items.allSatisfy{$0.expiresAt == nil},"original offline content has no fabricated publication time")
    check(state.rows[1].items.allSatisfy{!$0.text.contains("Stroka")},"offline TV content has no repeated internal collection credit")
    check(state.rows[2].items.count == 1 && state.rows[2].items[0].id == "FRESH" && state.rows[2].items[0].expiresAt != nil,"stale quotes are removed and fresh quotes carry an expiry")
    check(!m.tvSharing && m.tvBridge == nil,"TV sharing is off until explicitly enabled")
    check(TVBridgeServer.privateIPv4("192.168.1.3") && TVBridgeServer.privateIPv4("10.1.2.3") && TVBridgeServer.privateIPv4("172.16.0.2") && !TVBridgeServer.privateIPv4("172.32.0.1") && !TVBridgeServer.privateIPv4("8.8.8.8") && !TVBridgeServer.privateIPv4("127.0.0.1") && !TVBridgeServer.privateIPv4("192.168.bad.1"),"TV listener accepts only private IPv4 networks")
    m.setTVSharing(true);let end = Date().addingTimeInterval(5);while m.tvAddress.isEmpty && m.tvSharing && Date()<end{pumpApplication(for:0.02)}
    check(m.tvSharing && !m.tvAddress.isEmpty && m.tvPairCode.count == 6,"read-only server offers a local address and expiring pairing code")
    let session = URLSession(configuration:.ephemeral)
    func request(_ path:String,method:String = "GET",body:[String:String]? = nil,address:String? = nil)->(Int,Data) {
        var req = URLRequest(url:URL(string:"http://"+(address ?? m.tvAddress)+path)!);req.httpMethod = method;req.timeoutInterval = 4
        if let body{req.httpBody = try! JSONSerialization.data(withJSONObject:body);req.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        var result:(Int,Data)?;session.dataTask(with:req){data,response,_ in DispatchQueue.main.async{result = ((response as? HTTPURLResponse)?.statusCode ?? 0,data ?? Data())}}.resume()
        let timeout = Date().addingTimeInterval(5);while result == nil && Date()<timeout{pumpApplication(for:0.01)};return result ?? (0,Data())
    }
    check(request("/state").0 == 404 && request("/control",method:"POST",body:["action":"stop"]).0 == 404,"unpaired clients cannot read the feed or control playback")
    check(request("/pair",method:"POST",body:["code":"invalid"]).0 == 403,"incorrect pairing code is rejected")
    let paired = request("/pair",method:"POST",body:["code":m.tvPairCode]);let payload = (try? JSONSerialization.jsonObject(with:paired.1)) as? [String:String]
    guard let path = payload?["statePath"] else{check(false,"pairing response contains a capability path");return}
    check(paired.0 == 200 && path.range(of:"^/[0-9a-f]{32}/state$",options:.regularExpression) != nil,"correct pairing issues a dedicated read-only session")
    let received = request(path);let snapshot = try? JSONDecoder().decode(TVState.self,from:received.1)
    check(received.0 == 200 && snapshot?.rows.count == 4 && snapshot?.rows[0].items.first?.text == own.messages,"paired TV retrieves the actual selected ticker state")
    check(request(path,method:"POST",body:["action":"stop"]).0 == 404 && m.playing,"the TV capability cannot mutate the Mac")
    check(request("/pair",method:"POST",body:["code":"invalid"]).0 == 403,"one pairing code cannot create a second TV session")
    for _ in 0..<8 {_ = request("/pair",method:"POST",body:["code":"invalid"])}
    check(request("/pair",method:"POST",body:["code":"invalid"]).0 == 429,"repeated pairing attempts are rate limited")
    let oldAddress = m.tvAddress,oldBridge = m.tvBridge!
    m.setTVSharing(true);let restart = Date().addingTimeInterval(5);while m.tvAddress.isEmpty && Date()<restart{pumpApplication(for:0.02)}
    check(m.tvSharing && !m.tvAddress.isEmpty && m.tvPairCode.count == 6,"renewing pairing starts a current server and ignores old listener callbacks")
    check(request(path).0 == 404 && oldBridge.activeConnectionCount == 0,"an old TV capability cannot read the new listener and old connections are closed")
    let rePair = request("/pair",method:"POST",body:["code":m.tvPairCode]);let rePayload = (try? JSONSerialization.jsonObject(with:rePair.1)) as? [String:String]
    guard let newPath = rePayload?["statePath"] else{check(false,"new pairing response contains a capability path");return}
    check(rePair.0 == 200 && newPath != path && request(newPath).0 == 200,"a fresh pairing works after renewal and receives a different read-only capability")
    m.setTVSharing(false);pumpApplication(for:0.1)
    check(m.tvBridge == nil && m.tvAddress.isEmpty && m.tvPairCode.isEmpty,"turning sharing off revokes the listener and clears pairing details")
    check(request(path,address:oldAddress).0 == 0 && oldBridge.activeConnectionCount == 0,"disabled sharing cannot serve the prior session")
    session.invalidateAndCancel();print("\(count) TV bridge checks passed");fflush(stdout);exit(0)
}

final class TelegramAddProtocol:URLProtocol {
    override class func canInit(with request:URLRequest)->Bool{request.url?.host == "t.me"}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func stopLoading(){}
    override func startLoading(){
        let name = request.url!.lastPathComponent
        if name == "unreachable" {client?.urlProtocol(self,didFailWithError:URLError(.notConnectedToInternet));return}
        let stamp = ISO8601DateFormatter().string(from:Date().addingTimeInterval(-60))
        let body = name == "privatechannel" ? "<html><title>Join Telegram</title></html>" : "<html><meta property=\"og:title\" content=\"Технологии &amp; наука\"><div data-post=\"\(name)/1\"><div class=\"tgme_widget_message_text\">Новые технологии помогают учёным лучше понимать устройство мира</div><a href=\"https://t.me/\(name)/1\"><time datetime=\"\(stamp)\"></time></a></div></html>"
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)
    }
}
func expandedCatalogCheck() {
    var count = 0
    func check(_ ok:@autoclosure()->Bool,_ label:String){guard ok() else{print("FAIL: \(label)");fflush(stdout);exit(1)};count += 1;print("PASS: \(label)")}
    check(NewsCatalog.all.count == 550,"550 unique news feeds are bundled")
    check(Set(NewsCatalog.all.map(\.url)).count == 550 && Set(NewsCatalog.all.map(\.id)).count == 550,"catalog identities and source URLs are unique")
    for topic in NewsCatalog.topics {check(NewsCatalog.sources(topic).count == 50,"\(topic) has exactly 50 sources")}
    check(NewsCatalog.all.filter{$0.url.hasPrefix("https://t.me/")}.allSatisfy{$0.feed.isTelegram},"all catalog channels route through the Telegram reader")
    check(TelegramPublicReader.username("@khl") == "khl","short established channel handles are accepted and verified online")
    check(NewsCatalog.all.allSatisfy{$0.availability == "checked" && ["en","ru"].contains($0.language)},"only checked English/Russian sources are included")
    let suite = "ru.bushe.stroka.catalog22.\(UUID())";let d = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:d);m.prepareSimpleSetup(firstLaunch:true);m.interfaceLanguage = .russian
    defer{m.pendingSave?.cancel();m.feedTransport.invalidate();d.removePersistentDomain(forName:suite)}
    let state = QuickFeedState(model:m,fresh:true);state.toggleTopic("ai")
    check(state.matches.count == 50 && state.visible.count == 50,"choosing AI reveals all fifty feed cards without repeated More clicks")
    state.toggle(state.visible[0]);let selected = state.selectedURLs;state.toggleTopic("science")
    check(state.selectedURLs == selected,"browsing the expanded catalog retains chosen publishers")
    state.filters = ["telegram"];check(state.matches.count >= 50 && state.matches.allSatisfy(\.isTelegram),"Telegram discovery includes at least fifty open channels across topics")
    m.activateContentPack("ai");check(m.selectedPack.id == "ai" && m.contentSources.count >= 50,"AI is a content topic with the full expanded collection")
    let fixture = URLSessionConfiguration.ephemeral;fixture.protocolClasses = [TelegramAddProtocol.self]
    func add(_ input:String,accept:Bool = true)->(TelegramAddState,FeedSource?) {
        let s = TelegramAddState(configuration:fixture);s.handle = input;var added:FeedSource?
        s.add{feed in added = feed;return accept};let end = Date().addingTimeInterval(4);while s.busy && Date()<end{pumpApplication(for:0.01)};return (s,added)
    }
    check(TelegramPublicReader.username("@Exploitex") == "exploitex" && TelegramPublicReader.username("t.me/aiffring") == "aiffring" && TelegramPublicReader.username("https://telegram.me/s/exploitex/10") == "exploitex","handles and copied Telegram links normalize to one public URL")
    check(TelegramPublicReader.username("https://evil.example/t.me/exploitex") == nil && TelegramPublicReader.username("https://t.me/+private") == nil && TelegramPublicReader.username("@bad name") == nil,"private invites and invalid handles are rejected")
    let good = add("@publicchannel")
    check(good.0.error.isEmpty && good.0.handle.isEmpty && good.1?.url == "https://t.me/s/publicchannel","one handle resolves and adds without a name or RSS address")
    check(good.1?.name == "Технологии & наука · @publicchannel" && good.1?.language == "ru","public name is decoded automatically and post language is detected")
    check(!add("@privatechannel").0.error.isEmpty,"unavailable private previews are explained without adding a fake feed")
    check(!add("@unreachable").0.error.isEmpty,"network failures remain actionable and do not report success")
    check(!add("@publicchannel",accept:false).0.error.isEmpty,"duplicate insertion is reported explicitly")
    let cancelled = TelegramAddState(configuration:fixture);cancelled.handle = "@publicchannel";var inserted = false;cancelled.add{_ in inserted = true;return true};cancelled.cancel();pumpApplication(for:0.1)
    check(!inserted && !cancelled.busy,"closing the editor cancels insertion and ignores late responses")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaCatalog22-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for language in [InterfaceLanguage.english,.russian] {
        m.interfaceLanguage = language
        let s = QuickFeedState(model:m,fresh:true);s.toggleTopic("ai")
        let host = NSHostingView(rootView:QuickFeedSetup(model:m,state:s));host.frame = CGRect(x:0,y:0,width:920,height:750)
        let w = NSWindow(contentRect:host.frame,styleMask:[.titled],backing:.buffered,defer:false);w.isReleasedWhenClosed = false;w.contentView = host;w.orderFrontRegardless();pumpApplication(for:0.25);host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:rep);try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("ai-\(language.rawValue).png"))}
        w.orderOut(nil);w.contentView = nil;w.close()
        let chooser = NSHostingView(rootView:QuickContentChooser(model:m).background(Color(nsColor:.windowBackgroundColor)));chooser.frame = CGRect(x:0,y:0,width:820,height:ContentChooserLayout.editorHeight)
        let c = NSWindow(contentRect:chooser.frame,styleMask:[.titled],backing:.buffered,defer:false);c.isReleasedWhenClosed = false;c.contentView = chooser;c.orderFrontRegardless();pumpApplication(for:0.2);chooser.layoutSubtreeIfNeeded()
        if let rep = chooser.bitmapImageRepForCachingDisplay(in:chooser.bounds){chooser.cacheDisplay(in:chooser.bounds,to:rep);try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("telegram-\(language.rawValue).png"))}
        c.orderOut(nil);c.contentView = nil;c.close()
    }
    print("CATALOG22 DIRECTORY: \(folder.path)");print("\(count) expanded catalog and Telegram checks passed");fflush(stdout);exit(0)
}
func telegramLiveAddCheck() {
    var checks = 0
    for name in ["aiffring","exploitex"] {
        let state = TelegramAddState();state.handle = "@"+name;var result:FeedSource?
        state.add{result = $0;return true};let end = Date().addingTimeInterval(25);while state.busy && Date()<end{pumpApplication(for:0.02)}
        guard result != nil,state.error.isEmpty else{print("FAIL: live @\(name): \(state.error)");fflush(stdout);exit(1)}
        print("PASS: @\(name) resolves to a public text feed with an automatic channel title");checks += 1
    }
    print("\(checks) live Telegram add checks passed");fflush(stdout);exit(0)
}

func offlineLabelCheck() {
    var count = 0
    func check(_ ok:@autoclosure()->Bool,_ label:String){guard ok() else{print("FAIL: \(label)");fflush(stdout);exit(1)};count += 1;print("PASS: \(label)")}
    let suite = "ru.bushe.stroka.offline-label.\(UUID())";let defaults = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:defaults);m.prepareSimpleSetup(firstLaunch:true);m.settings.brand = "MY STATION";m.settings.broadcastSource = true;m.settings.translateRussian = false
    defer{m.outputs.stop();m.editorialWake?.invalidate();m.pendingSave?.cancel();defaults.removePersistentDomain(forName:suite)}
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaOfflineLabel-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for language in [InterfaceLanguage.english,.russian] {
        m.interfaceLanguage = language;m.newsLanguage = language == .english ? .english : .russian;m.settings.offlineLanguage = m.newsLanguage.rawValue
        for pack in ContentPack.all.filter(\.offline) {
            m.setRowCount(1);m.setRow(TickerRow(packID:pack.id),at:0)
            var clean = true
            for look in Look.broadcastLooks {
                m.settings.look = look
                let v = TickerView(model:m);v.frame = CGRect(x:0,y:0,width:1100,height:80)
                let record = v.broadcastRecord
                guard let stream = v.streamWindow(fontSize:28,look:look,viewport:900,reverse:false) else{check(false,"offline stream exists");return}
                clean = clean && record.isOffline && stream.text.string.hasPrefix(record.text) && !stream.text.string.contains(L("Stroka Collection")) && v.currentLine == record.text && stream.text.string.contains(m.settings.resolvedSeparator)
            }
            check(clean,"\(language.rawValue) \(pack.id): all four styles begin with the actual text and retain separators")
        }
    }
    m.interfaceLanguage = .english;m.newsLanguage = .english;m.settings.offlineLanguage = NewsLanguage.english.rawValue
    let feed = FeedSource(name:"Publisher fixture",url:"https://fixture.invalid/news.rss",language:"en")
    var news = TickerRow(packID:"custom");news.customFeeds = [feed];news.language = .english
    m.setRowCount(4);m.setRow(TickerRow(packID:"thoughts"),at:0);m.setRow(TickerRow(packID:"jokes"),at:1);m.setRow(TickerRow(packID:"riddles"),at:2);m.setRow(news,at:3)
    m.contentStories = [Story(id:"fixture-news",text:"Fresh news fixture",source:feed.name,date:Date().addingTimeInterval(-60),link:"https://fixture.invalid/story",language:"en",sourceURL:feed.url,packID:"custom")]
    m.settings.look = .bulletin;m.settings.broadcastSource = true
    let v = TickerView(model:m);v.frame = CGRect(x:0,y:0,width:1100,height:144);v.updateMarketLane()
    let lanes = [v]+v.extraLanes
    check(lanes.count == 4 && lanes.prefix(3).allSatisfy{lane in let stream = lane.streamWindow(fontSize:22,look:.bulletin,viewport:900,reverse:false);return stream?.text.string.hasPrefix(lane.broadcastRecord.text) == true && stream?.text.string.contains(L("Stroka Collection")) == false},"three offline rows have no repeated internal label in a mixed four-row strip")
    check(lanes[3].streamWindow(fontSize:22,look:.bulletin,viewport:900,reverse:false)?.text.string.hasPrefix(feed.name+" · Fresh news fixture") == true,"actual news keeps its publisher attribution")
    m.settings.broadcastSource = false
    check(lanes[3].streamWindow(fontSize:22,look:.bulletin,viewport:900,reverse:false)?.text.string.hasPrefix("Fresh news fixture") == true,"the existing Show Source toggle still works for news")
    check(m.settings.brand == "MY STATION" && m.settings.resolvedSeparator != "","personal station name and separator settings remain unchanged")
    for pack in ["thoughts","jokes","riddles"] {
        m.interfaceLanguage = .russian;m.newsLanguage = .russian;m.settings.offlineLanguage = NewsLanguage.russian.rawValue;m.setRowCount(1);m.setRow(TickerRow(packID:pack),at:0);m.settings.look = .metro
        let view = TickerView(model:m);view.frame = CGRect(x:0,y:0,width:1100,height:70)
        if let rep = view.snapshot(at:0.12){try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(pack+"-ru.png"))}
    }
    print("OFFLINE LABEL DIRECTORY: \(folder.path)");print("\(count) offline label checks passed");fflush(stdout);exit(0)
}

func phoneRemoteCheck() {
    var count = 0
    func check(_ ok:@autoclosure()->Bool,_ label:String){guard ok() else{print("FAIL: \(label)");fflush(stdout);exit(1)};count += 1;print("PASS: \(label)")}
    let suite = "ru.bushe.stroka.remote-audit.\(UUID())";let defaults = UserDefaults(suiteName:suite)!
    let m = AppModel(defaults:defaults)
    defer{m.enableRemote(false);m.pendingSave?.cancel();defaults.removePersistentDomain(forName:suite)}
    check(RemoteServer.privateIPv4("192.168.1.2") && RemoteServer.privateIPv4("10.1.2.3") && RemoteServer.privateIPv4("172.31.0.2") && !RemoteServer.privateIPv4("172.32.0.1") && !RemoteServer.privateIPv4("127.0.0.1") && !RemoteServer.privateIPv4("8.8.8.8"),"phone remote binds only to a private LAN interface")
    check(!m.remoteEnabled && m.remote == nil,"phone remote starts disabled")
    m.enableRemote(true);let deadline = Date().addingTimeInterval(5);while !m.remoteInfo.hasPrefix("http://") && m.remoteEnabled && Date()<deadline{pumpApplication(for:0.01)}
    guard let base = URL(string:m.remoteInfo),let server = m.remote else{check(false,"local remote is ready");return}
    let session = URLSession(configuration:.ephemeral)
    defer{session.invalidateAndCancel()}
    func request(_ url:URL,_ method:String = "GET",_ body:Data? = nil,type:String = "application/json")->Int {
        var req = URLRequest(url:url);req.httpMethod = method;req.httpBody = body;req.timeoutInterval = 3;if body != nil{req.setValue(type,forHTTPHeaderField:"Content-Type")}
        var status:Int?;session.dataTask(with:req){_,response,_ in DispatchQueue.main.async{status = (response as? HTTPURLResponse)?.statusCode ?? 0}}.resume();let end = Date().addingTimeInterval(4);while status == nil && Date()<end{pumpApplication(for:0.01)};return status ?? 0
    }
    check(request(base) == 200,"paired link serves the phone controls")
    var root = URLComponents(url:base,resolvingAgainstBaseURL:false)!;root.path = "/"
    check(request(root.url!) == 404,"anonymous requests do not expose controls")
    let action = base.appendingPathComponent("action"),pause = try! JSONSerialization.data(withJSONObject:["action":"pause"])
    let playing = m.playing
    check(request(action,"POST",pause,type:"text/plain") == 415 && m.playing == playing,"cross-origin form/text requests cannot execute actions")
    check(request(action,"POST",Data("{\"action\":\"unsupported\"}".utf8)) == 400,"unsupported actions are rejected")
    check(request(action,"POST",Data(repeating:65,count:5000)) == 413,"remote action bodies are bounded")
    check(request(action,"POST",pause) == 200 && m.playing != playing,"valid paired commands reach playback")
    m.enableRemote(false)
    check(server.activeConnectionCount == 0 && m.remoteInfo.isEmpty,"disabling remote closes active connections and clears the capability link")
    let stateAfterStop = m.playing
    check(request(action,"POST",pause) != 200 && m.playing == stateAfterStop,"old capabilities cannot control playback after shutdown")
    m.enableRemote(true);let again = Date().addingTimeInterval(5);while !m.remoteInfo.hasPrefix("http://") && m.remoteEnabled && Date()<again{pumpApplication(for:0.01)}
    check(m.remoteInfo != base.absoluteString && request(action,"POST",pause) != 200,"reenabling creates a fresh capability and does not revive the old one")
    let malformed:[String:Any] = ["columns":["SECID","SECID"],"data":[["first","last"]]]
    check(OpenMarketData.table(malformed).first?["SECID"] as? String == "last","repeated provider column names are handled without crashing")
    print("\(count) phone remote and provider robustness checks passed");fflush(stdout);exit(0)
}

func translationLiveCheck() {
    if #available(macOS 15,*) {translationLiveCheckModern()}
    else{print("SKIP: Apple Translation requires macOS 15 or later");fflush(stdout);exit(0)}
}
@available(macOS 15,*)
func translationLiveCheckModern() {
    var availability:LanguageAvailability.Status?
    Task{@MainActor in availability = await LanguageAvailability().status(from:Locale.Language(identifier:"en"),to:Locale.Language(identifier:"ru"))}
    let wait = Date().addingTimeInterval(8);while availability == nil && Date()<wait{pumpApplication(for:0.02)}
    guard availability == .installed else{print("SKIP: English/Russian system translation models are not installed; no download was started");fflush(stdout);exit(0)}
    let suite = "ru.bushe.stroka.translation-audit.\(UUID())";let d = UserDefaults(suiteName:suite)!,m = AppModel(defaults:UserDefaults(suiteName:suite)!)
    m.settings.channel = .content;m.settings.contentPackID = "custom";m.settings.customFeeds = [FeedSource(name:"Translation fixture",url:"https://fixture.invalid/feed",language:"en")];m.newsLanguage = .all;m.settings.translateRussian = true
    let text = "A new science museum opens this weekend"
    let story = Story(id:"translation-live-fixture",text:text,source:"Translation fixture",date:Date().addingTimeInterval(-60),link:"https://fixture.invalid/story",language:"en",sourceURL:"https://fixture.invalid/feed",packID:"custom")
    m.contentStories = [story]
    let host = NSHostingView(rootView:VStack{Text("Translation verification");RussianTranslationHost(model:m)}.padding(20).background(Color(nsColor:.windowBackgroundColor)))
    let w = NSWindow(contentRect:CGRect(x:150,y:150,width:300,height:100),styleMask:[.titled],backing:.buffered,defer:false);w.isReleasedWhenClosed = false;w.contentView = host;w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    let end = Date().addingTimeInterval(35);while m.translationCache[story.translationKey] == nil && Date()<end{pumpApplication(for:0.03)}
    let result = m.translationCache[story.translationKey] ?? "",shown = m.selectedContent.first
    let passed = result != text && result.range(of:"[А-Яа-яЁё]",options:.regularExpression) != nil && shown?.isTranslated == true && shown?.originalText == text && shown?.date == story.date
    w.orderOut(nil);w.contentView = nil;w.close();m.pendingSave?.cancel();m.editorialWake?.invalidate();d.removePersistentDomain(forName:suite)
    print(passed ? "PASS: native Apple Translation produced Russian text, retained original/date and reached the selected ticker queue" : "FAIL: native translation was not delivered to the selected ticker queue")
    if passed{print("SYNTHETIC TRANSLATION: \(result)")}
    fflush(stdout);exit(passed ? 0 : 1)
}

func savedSettingsCheck() {
    var count = 0
    func check(_ value:@autoclosure()->Bool,_ label:String){guard value() else{print("FAIL: \(label)");fflush(stdout);exit(1)};count += 1;print("PASS: \(label)")}
    let suite = "ru.bushe.stroka.savedsettings.\(UUID())"
    let defaults = UserDefaults(suiteName:suite)!
    defer{defaults.removePersistentDomain(forName:suite)}
    let m = AppModel(defaults:defaults);m.prepareSimpleSetup(firstLaunch:true);m.prepareDesktopTicker();m.interfaceLanguage = .english;m.newsLanguage = .russian
    let delegate = AppDelegate();delegate.model = m
    check(delegate.toolbarDefaultItemIdentifiers(NSToolbar(identifier:"saved")).filter{$0 != .flexibleSpace}.map(\.rawValue) == ["privacy"],"main toolbar contains only Settings")
    check(m.presets.isEmpty && !m.saveNamedSettings("  \n "),"empty state rejects a blank name without creating a save")
    m.settings.messages = "First authored message\nSecond message";m.settings.channel = .message;m.settings.brand = "MY EVENT";m.settings.stripPlacement = .top;m.settings.stripTop = true;m.setRowCount(3)
    m.settings.marketInstruments = ["currency:USD","share:SBER"];m.settings.customFeeds = [FeedSource(name:"My feed",url:"https://fixture.invalid/feed",language:"ru")]
    let encoder = JSONEncoder();encoder.outputFormatting = [.sortedKeys]
    let before = try! encoder.encode(m.settings)
    check(m.saveNamedSettings("  Work  ") && m.presets.count == 1 && m.presets[0].name == "Work","saving captures the current setup and trims the name")
    let id = m.presets[0].id
    check(!m.saveNamedSettings("work") && !m.saveNamedSettings(" Work ") && m.presets.count == 1,"duplicate names cannot silently replace or duplicate a save")
    m.settings.brand = "CHANGED";m.settings.messages = "Other text";m.newsLanguage = .english;m.playing = false
    check(m.loadSavedSettings(id) && (try! encoder.encode(m.settings)) == before,"loading restores rows, source choices, text, name, placement and appearance")
    check(m.newsLanguage == .russian && m.interfaceLanguage == .english,"news language is restored without changing the interface language")
    check(!m.playing && m.activeMode == nil,"loading preserves pause and does not start an output unexpectedly")
    let restored = AppModel(defaults:defaults)
    check(restored.presets.first?.id == id && restored.presets.first?.newsLanguage == .russian && (try! encoder.encode(restored.settings)) == before,"saved settings and loaded configuration persist across model restart")
    var legacy = try! JSONSerialization.jsonObject(with:encoder.encode(m.presets[0])) as! [String:Any];legacy.removeValue(forKey:"newsLanguage")
    let old = try! JSONDecoder().decode(ScenePreset.self,from:JSONSerialization.data(withJSONObject:legacy))
    check(old.id == id && old.newsLanguage == nil && old.name == "Work","older saved sets decode without requiring a migration or losing names")
    m.presets.append(ScenePreset(name:"Older event",settings:old.settings));m.persistPresets();let oldID = m.presets.last!.id
    check(m.loadSavedSettings(oldID) && m.newsLanguage == .russian,"loading an older set preserves the current news-language selection")
    let loaded = try! encoder.encode(m.settings)
    m.deleteSavedSettings(id)
    check(m.presets.count == 1 && m.presets[0].id == oldID && (try! encoder.encode(m.settings)) == loaded,"deleting one saved setup keeps the others and the current ticker")
    check(!m.loadSavedSettings(id) && (try! encoder.encode(m.settings)) == loaded,"a deleted or missing setup cannot alter the ticker")
    check(AppModel(defaults:defaults).presets.map(\.id) == [oldID],"individual deletion is persisted")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StrokaSavedSettings-\(UUID())");try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for (name,language,empty,dark) in [("en-saved",InterfaceLanguage.english,false,false),("ru-saved",.russian,false,false),("ru-empty",.russian,true,false),("en-dark",.english,false,true)] {
        m.interfaceLanguage = language;if empty {m.presets = []} else if m.presets.isEmpty {m.presets = [ScenePreset(name:"Work",settings:m.settings),ScenePreset(name:"Event",settings:m.settings)]}
        NSApp.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView:SettingsView(model:m));let w = NSWindow(contentRect:CGRect(x:120,y:120,width:620,height:620),styleMask:[.titled,.closable],backing:.buffered,defer:false);w.isReleasedWhenClosed = false;w.appearance = NSApp.appearance;w.contentView = host;w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);pumpApplication(for:0.4);host.layoutSubtreeIfNeeded()
        let frame = host.superview ?? host
        let rep = frame.bitmapImageRepForCachingDisplay(in:frame.bounds)!
        w.appearance!.performAsCurrentDrawingAppearance{frame.cacheDisplay(in:frame.bounds,to:rep)}
        try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name+".png"));w.orderOut(nil);w.contentView = nil;w.close()
    }
    if CommandLine.arguments.contains("--interactive-ui") {
        m.presets = [];m.persistPresets();m.interfaceLanguage = .russian;m.settings.brand = "QA ORIGINAL";m.chooseOwnText();m.setRowCount(1);NSApp.appearance = NSAppearance(named:.aqua)
        let window = NSWindow(contentRect:CGRect(x:100,y:150,width:920,height:700),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);window.isReleasedWhenClosed = false;window.title = "Stroka · Saved settings QA";window.contentView = NSHostingView(rootView:SimpleSetupView(model:m));m.controlWindow = window
        delegate.window = window;delegate.configureToolbar();delegate.configureMenu()
        let lifecycle = SavedSettingsQAWindowDelegate {
            let report:[String:Any] = ["savedCount":m.presets.count,"loadedOriginalBrand":m.settings.brand == "QA ORIGINAL","saveName":m.presets.first?.name ?? "","testDomainRemoved":true]
            if let at = CommandLine.arguments.firstIndex(of:"--ui-report"),CommandLine.arguments.indices.contains(at+1) {try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[at+1]))}
            defaults.removePersistentDomain(forName:suite);exit(0)
        }
        window.delegate = lifecycle;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        print("ISOLATED SAVED SETTINGS UI READY");fflush(stdout)
        withExtendedLifetime((lifecycle,delegate)){NSApp.run()}
    }
    defaults.removePersistentDomain(forName:suite)
    print("SAVED SETTINGS DIRECTORY: \(folder.path)");print("\(count) saved settings checks passed");fflush(stdout);exit(0)
}

final class SavedSettingsQAWindowDelegate:NSObject,NSWindowDelegate {
    let finish:()->Void
    init(finish:@escaping()->Void){self.finish = finish}
    func windowWillClose(_ notification:Notification){finish()}
}

// Regression fixture for the reported three-feed stalls. No live feeds or user content.
func largeFeedRenderCheck() {
    let suite = "ru.bushe.stroka.large-feed.\(UUID())";let defaults = UserDefaults(suiteName:suite)!
    defer {defaults.removePersistentDomain(forName:suite)}
    let m = AppModel(defaults:defaults);m.newsLanguage = .all;m.reduceMotion = false
    var settings = m.settings;settings.look = .nightline;settings.channel = .content;settings.translateRussian = false;settings.stripHeight = 84
    let feeds = (0..<3).map{FeedSource(name:"Fixture \($0)",url:"https://fixture.invalid/row-\($0)",language:"ru")}
    let rows = feeds.map{feed -> TickerRow in var row = TickerRow(packID:"custom");row.customFeeds = [feed];return row}
    rows[0].apply(to:&settings);settings.tickerRows = rows;m.settings = settings
    let count = 600
    m.contentStories = feeds.enumerated().flatMap{row,feed in (0..<count).map{index in
        Story(id:"\(row)-\(index)",text:NSString(format:"Новость %ld: %@",index,"Проверка длинной русской строки, источника и плавного перехода к следующему сообщению") as String,source:feed.name,date:Date().addingTimeInterval(-60),link:"https://fixture.invalid/item-\(row)-\(index)",language:"ru",sourceURL:feed.url,packID:"custom")
    }}
    let views = (0..<3).map{row -> TickerView in let view = TickerView(model:m);view.rowIndex=row;return view}
    var times:[Double] = []
    for row in 0..<3 {for index in 0..<4 {
        views[row].localIndex = index
        let start = CACurrentMediaTime()
        guard let stream = views[row].streamWindow(fontSize:20,look:.nightline,viewport:1500,reverse:false),stream.text.string.contains("Новость \(index):"),stream.text.string.contains(feeds[row].name) else{print("FAIL: selected row text or source missing");exit(1)}
        times.append((CACurrentMediaTime()-start)*1000)
    }}
    let maximum = times.max() ?? 0
    print(String(format:"LARGE FEED: rows=3 itemsPerRow=%d transitions=%d total=%.2fms max=%.2fms",count,times.count,times.reduce(0,+),maximum));fflush(stdout)
    m.contentStories[0].text = "Updated fixture headline"
    let updated = m.rowLines(0)
    guard let first=updated.first,m.rowRecord(first,index:0).text == "Updated fixture headline" else{print("FAIL: edited source did not invalidate rendered text");exit(1)}
    m.contentStories[0].date = Date().addingTimeInterval(-25*3600)
    guard !m.rowLines(0).contains(where:{$0.contains("Updated fixture headline")}) else{print("FAIL: expired source retained in render cache");exit(1)}
    m.pendingSave?.cancel();m.editorialWake?.invalidate();m.feedTransport.invalidate();defaults.removePersistentDomain(forName:suite)
    if CommandLine.arguments.contains("--require-fast") && maximum>100 {print("FAIL: a single transition blocked the main thread for over 100 ms");exit(1)}
    print("PASS: large-feed text, source attribution, update and expiry checks");fflush(stdout);exit(0)
}
