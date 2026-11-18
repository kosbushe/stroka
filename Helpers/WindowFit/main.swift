import AppKit
import ApplicationServices

// This direct-download-only helper has its own explicit Accessibility grant.
// The ticker itself retains App Sandbox. No window titles, contents, or keys
// are read, logged, or transmitted; only standard window frames are used.
final class WindowFitHelper:NSObject,NSApplicationDelegate {
    struct Change {var window:AXUIElement;var original:CGRect;var applied:CGRect}
    var configURL:URL?
    var config:WindowFitConfiguration?
    var timer:Timer?
    var observer:AXObserver?
    var observedApp:AXUIElement?
    var observedPID:pid_t = 0
    var observedWindows:[AXUIElement] = []
    var changes:[Change] = []
    var pending:DispatchWorkItem?
    var tokens:[NSObjectProtocol] = []
    var permissionWindow:NSWindow?
    var permissionLabel:NSTextField?
    var trusted = false
    var russian:Bool {config?.language != "en"}
    func text(_ ru:String,_ en:String)->String {russian ? ru:en}
    func applicationDidFinishLaunching(_ notification:Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of:"--config"),i+1<args.count {configURL = URL(fileURLWithPath:args[i+1])}
        // Accept only the fixed private configuration owned by the parent app.
        let home = getpwuid(getuid()).map{URL(fileURLWithPath:String(cString:$0.pointee.pw_dir))} ?? FileManager.default.homeDirectoryForCurrentUser
        let expected = home.appendingPathComponent("Library/Containers/ru.bushe.stroka/Data/Library/Application Support/Stroka/window-fit.json").standardizedFileURL
        if configURL == nil {configURL = expected}
        guard configURL?.standardizedFileURL.path == expected.path else{NSLog("Window fitting: rejected configuration path");NSApp.terminate(nil);return}
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,NSWorkspace.activeSpaceDidChangeNotification] {
            tokens.append(center.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in self?.observeFrontmost();self?.schedule()})
        }
        timer = Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in self?.refresh()}
        timer?.tolerance = 0.4
        refresh()
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
        if !AXIsProcessTrusted(){showPermission()};return false
    }
    func refresh() {
        guard let url = configURL,let data = try? Data(contentsOf:url),let next = try? JSONDecoder().decode(WindowFitConfiguration.self,from:data),
              next.height.isFinite,(1...180).contains(next.height),
              let owner = NSRunningApplication(processIdentifier:next.ownerPID),!owner.isTerminated,
              owner.bundleIdentifier == "ru.bushe.stroka",
              owner.bundleURL?.standardizedFileURL.path == Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path,
              owner.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath:next.ownerBundlePath).standardizedFileURL.path
        else{NSLog("Window fitting: configuration or running parent unavailable");restore();NSApp.terminate(nil);return}
        if let old = config,old.screenID != next.screenID || old.top != next.top || old.height != next.height {restore()}
        config = next
        guard next.enabled else{
            restore()
            if CommandLine.arguments.contains("--permission") && !AXIsProcessTrusted(){showPermission()}
            else{NSApp.terminate(nil)}
            return
        }
        trusted = AXIsProcessTrusted()
        guard trusted else{showPermission();return}
        permissionWindow?.orderOut(nil);permissionWindow = nil;permissionLabel = nil
        observeFrontmost();schedule()
    }
    func showPermission() {
        if permissionWindow == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:510,height:240),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            window.title = "Stroka Windows";window.isReleasedWhenClosed = false
            let label = NSTextField(wrappingLabelWithString:text("Окна над строкой","Windows above the ticker"));label.font = .systemFont(ofSize:21,weight:.semibold)
            let body = NSTextField(wrappingLabelWithString:text("Разрешите Stroka Windows в Системных настройках → Конфиденциальность и безопасность → Универсальный доступ. Помощник меняет только положение и размер обычных окон. Настройка вступит в силу автоматически после разрешения.","Allow Stroka Windows in System Settings → Privacy & Security → Accessibility. The helper adjusts only ordinary window positions and sizes. It will start automatically after permission is granted."))
            let button = NSButton(title:text("Открыть Универсальный доступ","Open Accessibility"),target:self,action:#selector(openPermission))
            let stack = NSStackView(views:[label,body,button]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing = 18;stack.translatesAutoresizingMaskIntoConstraints = false
            window.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:24)])
            permissionWindow = window;permissionLabel = body;window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        }
    }
    @objc func openPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func read(_ element:AXUIElement,_ attribute:String)->CFTypeRef? {
        var value:CFTypeRef?;guard AXUIElementCopyAttributeValue(element,attribute as CFString,&value) == .success else{return nil};return value
    }
    func frame(_ window:AXUIElement)->CGRect? {
        guard let p = read(window,kAXPositionAttribute),let s = read(window,kAXSizeAttribute),CFGetTypeID(p) == AXValueGetTypeID(),CFGetTypeID(s) == AXValueGetTypeID() else{return nil}
        var point = CGPoint.zero,size = CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size) else{return nil}
        return CGRect(origin:point,size:size)
    }
    @discardableResult func setFrame(_ rect:CGRect,window:AXUIElement)->Bool {
        var size = rect.size,point = rect.origin
        guard let s = AXValueCreate(.cgSize,&size),let p = AXValueCreate(.cgPoint,&point) else{return false}
        // Shrink first so the subsequent move cannot leave the title bar offscreen.
        let resized = AXUIElementSetAttributeValue(window,kAXSizeAttribute as CFString,s)
        let moved = AXUIElementSetAttributeValue(window,kAXPositionAttribute as CFString,p)
        return resized == .success && moved == .success
    }
    func clearObserver() {
        if let observer {CFRunLoopRemoveSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)}
        observer = nil;observedApp = nil;observedWindows = [];observedPID = 0
    }
    func observeFrontmost() {
        guard trusted,let app = NSWorkspace.shared.frontmostApplication,app.activationPolicy == .regular,
              app.processIdentifier != config?.ownerPID,app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !["com.apple.systempreferences","com.apple.loginwindow"].contains(app.bundleIdentifier ?? "") else{return}
        if observedPID != app.processIdentifier {
            clearObserver();let element = AXUIElementCreateApplication(app.processIdentifier);observedApp = element;observedPID = app.processIdentifier
            AXUIElementSetMessagingTimeout(element,0.15)
            var created:AXObserver?
            guard AXObserverCreate(app.processIdentifier,{_,_,_,context in
                guard let context else{return};Unmanaged<WindowFitHelper>.fromOpaque(context).takeUnretainedValue().schedule()
            },&created) == .success,let created else{return}
            observer = created;CFRunLoopAddSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(created),.commonModes)
            for name in [kAXWindowCreatedNotification,kAXFocusedWindowChangedNotification] {AXObserverAddNotification(created,element,name as CFString,Unmanaged.passUnretained(self).toOpaque())}
        }
        guard let element = observedApp,let observer else{return}
        let windows = read(element,kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows where !observedWindows.contains(where:{CFEqual($0,window)}) {
            observedWindows.append(window)
            for name in [kAXMovedNotification,kAXResizedNotification] {AXObserverAddNotification(observer,window,name as CFString,Unmanaged.passUnretained(self).toOpaque())}
        }
    }
    func schedule() {
        pending?.cancel();let task = DispatchWorkItem{[weak self] in self?.fitFrontmost()};pending = task
        DispatchQueue.main.asyncAfter(deadline:.now()+0.18,execute:task)
    }
    func fitFrontmost() {
        guard trusted,config?.enabled == true,let config,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == observedPID,
              let screen = NSScreen.screens.first(where:{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == config.screenID}),
              let primary = NSScreen.screens.first else{return}
        observeFrontmost()
        let area = WindowFitGeometry.available(screen.visibleFrame,height:CGFloat(config.height),top:config.top)
        for window in observedWindows {
            guard read(window,kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                  read(window,kAXMinimizedAttribute) as? Bool != true,
                  read(window,"AXFullScreen") as? Bool != true,
                  let originalAX = frame(window) else{continue}
            let original = WindowFitGeometry.flip(originalAX,primaryTop:primary.frame.maxY)
            // Do not pull a window belonging to another display toward this strip.
            let overlap = original.intersection(screen.frame)
            guard !overlap.isNull,overlap.width*overlap.height >= original.width*original.height*0.5,
                  let fitted = WindowFitGeometry.fit(original,in:area),!WindowFitGeometry.equal(original,fitted) else{continue}
            var writable:DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(window,kAXSizeAttribute as CFString,&writable) == .success,writable.boolValue else{continue}
            let fittedAX = WindowFitGeometry.flip(fitted,primaryTop:primary.frame.maxY)
            let prior = changes.firstIndex(where:{CFEqual($0.window,window)})
            let restoreTo = prior.flatMap{WindowFitGeometry.equal(changes[$0].applied,originalAX) ? changes[$0].original:nil} ?? originalAX
            _ = setFrame(fittedAX,window:window)
            guard let actual = frame(window),!WindowFitGeometry.equal(actual,originalAX) else{continue}
            let change = Change(window:window,original:restoreTo,applied:actual)
            if let prior{changes[prior] = change}else{changes.append(change)}
        }
    }
    func restore() {
        pending?.cancel();pending = nil;clearObserver()
        for change in changes {
            if let current = frame(change.window),WindowFitGeometry.equal(current,change.applied) {_ = setFrame(change.original,window:change.window)}
        }
        changes = []
    }
    func applicationWillTerminate(_ notification:Notification){timer?.invalidate();restore()}
}
let app = NSApplication.shared
let delegate = WindowFitHelper()
app.setActivationPolicy(.accessory);app.delegate = delegate;app.run()
