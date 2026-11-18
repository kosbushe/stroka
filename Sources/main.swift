import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate {
    var window: NSWindow!; var model: AppModel!; var statusItem: NSStatusItem!
    var keyMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let firstLaunch = UserDefaults.standard.data(forKey:"settings") == nil
        model = AppModel();model.prepareSimpleSetup(firstLaunch:firstLaunch);model.prepareDesktopTicker()
        model.prepareOnboarding(firstLaunch:firstLaunch)
        if CommandLine.arguments.contains("--setup") {model.showOnboarding = true}
        if CommandLine.arguments.contains("--russian-news") { model.settings.translateRussian = true;model.newsLanguage = .all }
        if CommandLine.arguments.contains("--open-content") { model.settings.channel = .content }
        model.saveSettingsNow()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Stroka"; window.titlebarAppearsTransparent = true; window.toolbarStyle = .unified; window.minSize = NSSize(width: 840, height: 700); window.center(); window.delegate = self; window.isReleasedWhenClosed = false
        model.controlWindow = window
        window.contentView = NSHostingView(rootView: StrokaRootView(model: model))
        configureToolbar(); configureMenu(); configureStatus(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53, self?.model.activeMode != nil { self?.model.outputs.stop(); return nil }; return event
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("StrokaLanguageChanged"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.configureToolbar(); self.configureMenu(); self.configureStatus()
        }
        if !model.showOnboarding || model.defaults.string(forKey:"onboardingState") == "complete" {model.start()}
        if CommandLine.arguments.contains("--prepare-translation") { DispatchQueue.main.asyncAfter(deadline:.now()+1) { NotificationCenter.default.post(name:Notification.Name("StrokaPrepareTranslation"),object:nil) } }
        #if STROKA_DIAGNOSTICS
        if CommandLine.arguments.contains("--ui-smoke") {
            model.settings.channel = .message; model.settings.messages = L("Stroka is running on Mac\nAI headlines · markets · messages"); model.settings.motion = .phrases
        }
        #endif
    }
    func configureToolbar() {
        let toolbar = NSToolbar(identifier: "StrokaToolbar"); toolbar.delegate = self; toolbar.displayMode = .iconAndLabel; toolbar.allowsUserCustomization = false; window.toolbar = toolbar
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("privacy")] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        let title: String; let symbol: String; let action: Selector
        switch id.rawValue {
        case "feeds": title = L("Content"); symbol = "rectangle.grid.2x2"; action = #selector(openFeeds)
        case "appearance": title = L("Appearance"); symbol = "paintbrush"; action = #selector(openAppearance)
        case "remote": title = L("Remote"); symbol = "iphone"; action = #selector(openRemote)
        case "urgent": title = L("Announcement"); symbol = "megaphone"; action = #selector(openUrgent)
        case "privacy": title = L("Settings"); symbol = "gearshape"; action = #selector(showPrivacy)
        default: return nil
        }
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.target = self; item.action = action
        item.label = title.isEmpty ? L("Privacy") : title; item.paletteLabel = item.label; item.toolTip = item.label
        return item
    }
    @objc func openFeeds() { post("StrokaChooseFeed") }
    @objc func openAppearance() { post("StrokaAppearance") }
    @objc func openRemote() { post("StrokaRemote") }
    @objc func openUrgent() { post("StrokaUrgent") }
    @objc func resetData() { post("StrokaReset") }
    func post(_ name: String) { showControl(); NotificationCenter.default.post(name: Notification.Name(name), object: nil) }
    func configureMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(); appItem.submenu = appMenu; main.addItem(appItem)
        let about = NSMenuItem(title: L("About Stroka"), action: #selector(aboutApp), keyEquivalent: ""); about.target = self; appMenu.addItem(about)
        let privacy = NSMenuItem(title: L("Settings…"), action: #selector(showPrivacy), keyEquivalent: ","); privacy.target = self; appMenu.addItem(privacy)
        let reset = NSMenuItem(title: L("Delete Local Data…"), action: #selector(resetData), keyEquivalent: ""); reset.target = self; appMenu.addItem(reset)
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: L("Hide Stroka"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: L("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"); hideOthers.keyEquivalentModifierMask = [.command, .option]; appMenu.addItem(withTitle: L("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""); appMenu.addItem(.separator()); appMenu.addItem(withTitle: L("Quit Stroka"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); editItem.title = L("Edit"); let edit = NSMenu(title: L("Edit")); editItem.submenu = edit
        edit.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z"); let redo = edit.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "Z"); redo.keyEquivalentModifierMask = [.command, .shift]; edit.addItem(.separator()); edit.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"); edit.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"); edit.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"); edit.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"); main.addItem(editItem)
        let show = NSMenuItem(); show.title = L("Display"); let showMenu = NSMenu(title: L("Display")); show.submenu = showMenu
        for (title, action, key) in [(L("Open Controls"), #selector(showControl), "0"), (L("Ticker at Top"), #selector(showTop), "1"), (L("Ticker at Bottom"), #selector(showBottom), "2"), (L("Stop Display"), #selector(stopOutput), ".")] { let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; showMenu.addItem(item) }; main.addItem(show)
        showMenu.addItem(.separator())
        for (title,action) in [(L("Choose Your Feed…"),#selector(openFeeds)),(L("Appearance"),#selector(openAppearance)),(L("Show Announcement…"),#selector(openUrgent)),(L("Phone Remote"),#selector(openRemote))] { let item = NSMenuItem(title:title,action:action,keyEquivalent:"");item.target = self;showMenu.addItem(item) }
        let windowsItem = NSMenuItem(); let windows = NSMenu(title: L("Window")); windowsItem.title = L("Window"); windowsItem.submenu = windows
        windows.addItem(withTitle: L("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"); windows.addItem(withTitle: L("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"); main.addItem(windowsItem); NSApp.windowsMenu = windows
        #if STROKA_DIAGNOSTICS
        let themeItem = NSMenuItem(); let themeMenu = NSMenu(title: L("Appearance Check")); themeItem.title = L("Appearance Check"); themeItem.submenu = themeMenu
        for (title, action) in [(L("Dark Appearance"), #selector(debugDark)), (L("System Appearance"), #selector(debugSystem))] { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; themeMenu.addItem(item) }; main.addItem(themeItem)
        #endif
        let helpItem = NSMenuItem(); helpItem.title = L("Help"); let helpMenu = NSMenu(title: L("Help")); helpItem.submenu = helpMenu
        let help = NSMenuItem(title: L("Stroka Help"), action: #selector(showHelp), keyEquivalent: "?"); help.target = self; helpMenu.addItem(help); main.addItem(helpItem); NSApp.helpMenu = helpMenu
        NSApp.mainMenu = main
    }
    func configureStatus() {
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) }
        statusItem.button?.image = NSImage(systemSymbolName: "text.line.first.and.arrowtriangle.forward", accessibilityDescription: L("Stroka"))
        let menu = NSMenu()
        for (title, action) in [(L("Open Controls"), #selector(showControl)), (L("Ticker at Top"), #selector(showTop)), (L("Ticker at Bottom"), #selector(showBottom)), (L("Pause / Resume"), #selector(togglePlay)), (L("Stop Display"), #selector(stopOutput))] { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
        menu.addItem(.separator()); menu.addItem(withTitle: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""); statusItem.menu = menu
    }
    @objc func aboutApp() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: L("Stroka"), .applicationVersion: Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "", .credits: NSAttributedString(string: L("Live text for every screen\nYour feeds, messages and market data.\nPreview release."))]) }
    @objc func showHelp() { post("StrokaHelp") }
    @objc func showPrivacy() { showControl(); NotificationCenter.default.post(name: Notification.Name("StrokaPrivacy"), object: nil) }
    @objc func showControl() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func showTop() {model.settings.stripPlacement = .top;model.outputs.show(.strip)}
    @objc func showStrip() { model.outputs.show(.strip) }
    @objc func showBottom() {model.settings.stripPlacement = .bottom;model.outputs.show(.strip)}
    @objc func togglePlay() { model.playing.toggle() }
    @objc func stopOutput() { model.outputs.stop(); showControl() }
    #if STROKA_DIAGNOSTICS
    @objc func debugDark() { NSApp.appearance = NSAppearance(named: .darkAqua) }
    @objc func debugSystem() { NSApp.appearance = nil }
    #endif
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showControl(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.saveSettingsNow();model?.tvBridge?.stop(); model?.outputs.stop(); model?.remote?.stop(); model?.market.socket?.cancel(with: .goingAway, reason: nil) }
}

let app = NSApplication.shared
#if STROKA_DIAGNOSTICS
if CommandLine.arguments.contains("--phone-remote-check") {app.setActivationPolicy(.regular);phoneRemoteCheck()}
if CommandLine.arguments.contains("--translation-live-check") {app.setActivationPolicy(.regular);translationLiveCheck()}
if CommandLine.arguments.contains("--offline-label-check") {app.setActivationPolicy(.regular);offlineLabelCheck()}
if CommandLine.arguments.contains("--expanded-catalog-check") {app.setActivationPolicy(.regular);expandedCatalogCheck()}
if CommandLine.arguments.contains("--telegram-live-add-check") {app.setActivationPolicy(.regular);telegramLiveAddCheck()}
if CommandLine.arguments.contains("--saved-settings-check") {app.setActivationPolicy(.regular);savedSettingsCheck()}
if CommandLine.arguments.contains("--large-feed-render-check") {app.setActivationPolicy(.regular);largeFeedRenderCheck()}
if CommandLine.arguments.contains("--row-speed-check") {app.setActivationPolicy(.regular);rowSpeedCheck()}
if CommandLine.arguments.contains("--tv-bridge-check") {app.setActivationPolicy(.regular);tvBridgeCheck()}
if CommandLine.arguments.contains("--quick-feed-check") {app.setActivationPolicy(.regular);quickFeedCheck()}
if CommandLine.arguments.contains("--onboarding-check") {app.setActivationPolicy(.regular);onboardingCheck()}
if CommandLine.arguments.contains("--multi-row-check") {app.setActivationPolicy(.regular);multiRowCheck()}
if CommandLine.arguments.contains("--desktop-edge-check") {app.setActivationPolicy(.regular);desktopEdgeCheck()}
if CommandLine.arguments.contains("--simple-setup-check") {app.setActivationPolicy(.regular);simpleSetupCheck()}
if CommandLine.arguments.contains("--simple-setup-ui-check") {app.setActivationPolicy(.regular);simpleSetupUICheck()}
if CommandLine.arguments.contains("--strip-double-click-check") { app.setActivationPolicy(.regular);stripDoubleClickCheck() }
if CommandLine.arguments.contains("--broadcast-edge-check") { broadcastEdgeCheck() }
if CommandLine.arguments.contains("--content-catalog-check") { contentCatalogCheck() }
if CommandLine.arguments.contains("--content-gallery-ui-check") { contentGalleryUICheck() }
if CommandLine.arguments.contains("--editorial-check") { app.setActivationPolicy(.regular);editorialCheck() }
if CommandLine.arguments.contains("--feed-chooser-ui-check") { feedChooserUICheck() }
if CommandLine.arguments.contains("--short-live-check") { shortLiveCheck() }
if CommandLine.arguments.contains("--short-content-check") { shortContentCheck() }
if CommandLine.arguments.contains("--compact-check") { app.setActivationPolicy(.regular);compactCheck() }
if CommandLine.arguments.contains("--catalog-ui-check") { catalogUICheck() }
if CommandLine.arguments.contains("--newsroom-check") { app.setActivationPolicy(.regular); newsroomCheck() }
if CommandLine.arguments.contains("--feed-reliability-check") { feedReliabilityCheck() }
if CommandLine.arguments.contains("--feed-parser-check") { feedParserCheck() }
if CommandLine.arguments.contains("--open-market-check") { openMarketCheck() }
if CommandLine.arguments.contains("--separator-check") { app.setActivationPolicy(.regular); separatorCheck() }
if CommandLine.arguments.contains("--dual-check") { app.setActivationPolicy(.regular); dualCheck() }
if CommandLine.arguments.contains("--self-test") { app.setActivationPolicy(.prohibited); selfTest(); exit(0) }
if CommandLine.arguments.contains("--check-sources") { app.setActivationPolicy(.prohibited); liveCheck() }
if CommandLine.arguments.contains("--check-content-sources") { app.setActivationPolicy(.prohibited); contentSourcesCheck() }
if CommandLine.arguments.contains("--content-render-check") { app.setActivationPolicy(.prohibited); contentRenderCheck() }
if CommandLine.arguments.contains("--preview-integration-check") { app.setActivationPolicy(.regular); previewIntegrationCheck() }
if CommandLine.arguments.contains("--motion-behavior-check") { app.setActivationPolicy(.regular); motionBehaviorCheck(); exit(0) }
if CommandLine.arguments.contains("--animation-check") { app.setActivationPolicy(.regular); animationCheck() }
if CommandLine.arguments.contains("--performance-check") { app.setActivationPolicy(.prohibited); performanceCheck() }
if CommandLine.arguments.contains("--ui-visual-check") { app.setActivationPolicy(.prohibited); visualUICheck() }
if let index = CommandLine.arguments.firstIndex(of: "--render-check"), index + 1 < CommandLine.arguments.count { app.setActivationPolicy(.prohibited); renderCheck(CommandLine.arguments[index + 1]) }
#endif
app.setActivationPolicy(.regular)
let delegate = AppDelegate(); app.delegate = delegate; app.run()
