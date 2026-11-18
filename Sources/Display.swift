import AppKit
import SwiftUI
import Combine
import QuartzCore

// AppKit prepares text only when it changes. Core Animation owns continuous movement.
final class TickerView: NSView {
    weak var model: AppModel?; var preview = false; var infoFooter = false
    var isMarketLane = false
    var rowIndex = 0
    var extraLanes: [TickerView] = []
    var marketLane: TickerView? { extraLanes.first(where:{$0.isMarketLane}) }
    var auxiliaryLane: Bool {parentTicker != nil}
    weak var parentTicker: TickerView?
    weak var renderRoot: CALayer?
    weak var hostedWindow: NSWindow?
    var localIndex = 0; var elapsed: Double = 0
    var seenSequence = Int.min; var seenChannel: Channel?; var seenMotion: Motion?
    var streamKey: TickerStreamKey?
    var cachedStream: TickerStreamWindow?
    var cachedText = ""; var cachedSize: CGFloat = 0; var cachedLook: Look?; var cached = NSAttributedString(); var textSize = NSSize.zero
    var measuredDraws = 0; var subscriptions = Set<AnyCancellable>(); var refreshPending = false
    var compositor: TickerCompositor!
    var rotated = false; var clockwise = false; var previewScale: CGFloat?
    var renderBounds: NSRect { rotated ? NSRect(x: 0, y: 0, width: bounds.height, height: bounds.width) : bounds }
    var activeMotion: Motion { model?.reduceMotion == true ? .phrases : (isMarketLane || model?.dualBandActive == true || rotated ? .horizontal : (model?.effectiveMotion ?? .horizontal)) }
    var sequenceToken: Int { isMarketLane ? model?.marketSequence ?? 0 : model?.sequence ?? 0 }
    var channelToken: Channel {guard let model else {return .message};return model.settings.tickerRows != nil ? (model.tickerRows.indices.contains(rowIndex) ? model.tickerRows[rowIndex].channel : .content) : isMarketLane ? .markets : model.upperChannel}
    var compactBand:Bool {
        if let parentTicker { return parentTicker.compactBand }
        let scale = previewScale ?? (preview ? min(1,renderBounds.width/1100) : 1)
        return renderBounds.height <= 72*scale
    }
    var stripPressPending = false
    var pendingStripClick:DispatchWorkItem?
    func cancelStripClick() { pendingStripClick?.cancel();pendingStripClick = nil }
    var rowFrames:[CGRect] {
        guard !auxiliaryLane,let m = model,m.dualBandActive,m.urgent.isEmpty else {return [renderBounds]}
        let count = m.tickerRows.count
        if m.settings.tickerRows == nil && count == 2 {
            let scale = previewScale ?? (preview ? min(1,renderBounds.width/1100) : 1)
            let h = compactBand ? min(24*scale,max(18*scale,renderBounds.height*0.36)) : min(44*scale,max(24*scale,renderBounds.height*0.31))
            return [CGRect(x:0,y:h,width:renderBounds.width,height:renderBounds.height-h),CGRect(x:0,y:0,width:renderBounds.width,height:h)]
        }
        let weights = m.tickerRows.map{$0.channel == .markets ? CGFloat(0.85) : 1}
        let total = weights.reduce(0,+);var top = renderBounds.height
        return weights.map {weight in let h = renderBounds.height*weight/total;top -= h;return CGRect(x:0,y:top,width:renderBounds.width,height:h)}
    }
    var marketBandHeight: CGFloat {auxiliaryLane ? 0 : rowFrames[0].minY}
    var laneBounds: CGRect {CGRect(x:0,y:0,width:renderBounds.width,height:auxiliaryLane ? renderBounds.height : rowFrames[0].height)}
    func updateMarketLane() {
        guard !auxiliaryLane,let model else {return}
        let frames = rowFrames
        while extraLanes.count > frames.count-1 {let child = extraLanes.removeLast();child.compositor.stop();child.compositor.scene.removeFromSuperlayer()}
        while extraLanes.count < frames.count-1 {let child = TickerView(model:model,preview:preview);child.parentTicker = self;extraLanes.append(child)}
        for (offset,child) in extraLanes.enumerated() {
            child.rowIndex = offset+1;child.isMarketLane = model.tickerRows[child.rowIndex].channel == .markets
            child.renderRoot = layer
            if child.hostedWindow !== presentationWindow {child.hostedWindow = presentationWindow;child.compositor.attach(to:presentationWindow)}
            child.rotated = rotated;child.clockwise = clockwise;child.previewScale = previewScale
            child.frame = frames[offset+1];child.compositor.refresh()
        }
    }
    var presentationWindow: NSWindow? { parentTicker?.presentationWindow ?? (preview ? (model?.controlWindow ?? window) : window) }
    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override var isOpaque: Bool { model?.settings.look.isBroadcast != true }
    init(model: AppModel, preview: Bool = false, infoFooter: Bool = false) {
        self.model = model; self.preview = preview; self.infoFooter = infoFooter; super.init(frame: .zero)
        compositor = TickerCompositor(view: self)
        wantsLayer = true; layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel(preview ? L("Display preview") : L("Display"))
        model.objectWillChange.sink { [weak self] _ in self?.requestRefresh() }.store(in: &subscriptions)
    }
    required init?(coder: NSCoder) { fatalError() }
    func requestRefresh() {
        guard !refreshPending else { return }; refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.refreshPending = false
            self.setAccessibilityLabel(self.preview ? L("Display preview") : L("Display"))
            self.updateMarketLane(); self.compositor.refresh()
        }
    }
    override func updateLayer() { compositor.refresh() }
    override func layout() { super.layout(); updateMarketLane(); compositor.refresh() }
    override func viewDidMoveToWindow() { if window == nil {stripPressPending = false;cancelStripClick()};compositor.attach(to: presentationWindow); updateMarketLane(); compositor.refresh() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); compositor.invalidate(); compositor.refresh() }
    var currentLine: String {
        guard let model, model.settings.look.isBroadcast else { return rawLine }
        if isMarketLane { return rawLine }
        let record = broadcastRecord
        if !record.isOffline && (model.settings.look == .metro || model.settings.look == .minimal) && (model.settings.broadcastSource ?? true) && !record.source.isEmpty && record.source != model.settings.brand { return record.source + " · " + record.text }
        return record.text
    }
    func resetPreviewPosition() {
        guard preview, let m = model else { return }
        let scale = previewScale ?? max(0.08, renderBounds.width / 1100)
        let speed = max(1, CGFloat(m.speedForRow(rowIndex)) * scale)
        switch activeMotion {
        case .horizontal: elapsed = 0
        case .vertical: elapsed = Double(renderBounds.height * 0.5 / (speed * 0.65))
        case .phrases: elapsed = 0.4
        case .words: elapsed = 0
        }
        localIndex = sequenceToken; seenSequence = sequenceToken; seenChannel = channelToken; seenMotion = activeMotion
        compositor.seek(elapsed)
    }
    func bitmap(size: NSSize, scale: CGFloat, draw: () -> Void) -> CGImage? {
        let width = max(1, Int(ceil(size.width * scale))); let height = max(1, Int(ceil(size.height * scale)))
        guard width <= 16384, height <= 16384, width * height <= 32_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw(); NSGraphicsContext.restoreGraphicsState(); measuredDraws += 1
        return context.makeImage()
    }
    func snapshot(at time: Double, marketTime: Double? = nil) -> NSBitmapImageRep? {
        updateMarketLane(); compositor.refresh(manualElapsed: time)
        for child in extraLanes {child.compositor.refresh(manualElapsed:child.isMarketLane ? marketTime ?? time : time)}
        guard let image = bitmap(size: bounds.size, scale: 1, draw: { self.layer?.render(in: NSGraphicsContext.current!.cgContext) }) else { return nil }
        return NSBitmapImageRep(cgImage: image)
    }
    func prepare(text: String, size: CGFloat, look: Look) {
        guard text != cachedText || size != cachedSize || look != cachedLook else { return }
        cachedText = text; cachedSize = size; cachedLook = look
        let font = displayFont(size: size, look: look)
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: look.ink]
        if look == .neon { let shadow = NSShadow(); shadow.shadowColor = look.ink.withAlphaComponent(0.8); shadow.shadowBlurRadius = 16; shadow.shadowOffset = .zero; attrs[.shadow] = shadow }
        cached = NSAttributedString(string: text, attributes: attrs); textSize = cached.size()
    }
    func drawCentered(_ text: String, in rect: NSRect, look: Look, preferred: CGFloat, alpha: Double = 1) {
        var fontSize = min(preferred, rect.height * 0.6); let style = NSMutableParagraphStyle(); style.alignment = .center
        var attrs: [NSAttributedString.Key: Any] = [:]; var attr = NSAttributedString(); var measured = NSRect.zero
        repeat {
            attrs = [.font: displayFont(size: fontSize, look: look), .foregroundColor: look.ink.withAlphaComponent(alpha), .paragraphStyle: style]
            attr = NSAttributedString(string: String(text.prefix(6000)), attributes: attrs)
            measured = attr.boundingRect(with: NSSize(width: rect.width, height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading])
            if measured.height <= rect.height { break }; fontSize *= 0.9
        } while fontSize > 10
        attr.draw(with: NSRect(x: rect.minX, y: rect.midY - measured.height / 2, width: rect.width, height: measured.height + 4), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
    func drawUrgent(_ text: String, in rect: NSRect, look: Look) {
        L("ANNOUNCEMENT").draw(at: NSPoint(x: rect.minX, y: rect.maxY - 22), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: look.accent, .kern: 3])
        drawCentered(text, in: rect.insetBy(dx: 10, dy: 40), look: look, preferred: min(110, rect.height * 0.3))
    }
    func displayFont(size: CGFloat, look: Look) -> NSFont {
        if look == .glass { return .systemFont(ofSize:size,weight:.medium) }
        if look == .white || look == .black { return NSFont(name:"AvenirNext-Medium",size:size) ?? .systemFont(ofSize:size,weight:.medium) }
        if look == .desk { return .monospacedSystemFont(ofSize:size,weight:.medium) }
        if look == .metro { return NSFont(name:"AvenirNext-Medium",size:size) ?? .systemFont(ofSize:size,weight:.medium) }
        if look == .bulletin, let font = NSFont(name:"HelveticaNeue-CondensedBold",size:size) { return font }
        if look == .signal { return .systemFont(ofSize:size,weight:.regular) }
        if look == .wire { return .systemFont(ofSize:size,weight:.medium) }
        if look == .editorial { return NSFont(name:"AvenirNext-Medium",size:size) ?? .systemFont(ofSize:size,weight:.medium) }
        if look.isBroadcast { return .systemFont(ofSize:size,weight:look == .minimal || look == .nightline ? .medium : .semibold) }
        if look == .desk { return .monospacedSystemFont(ofSize:size,weight:.semibold) }
        if look == .bulletin, let font = NSFont(name:"HelveticaNeue-CondensedBold",size:size) { return font }
        if look == .led { return .monospacedSystemFont(ofSize: size, weight: .heavy) }
        if look == .champagne, let descriptor = NSFont.systemFont(ofSize: size, weight: .regular).fontDescriptor.withDesign(.serif), let font = NSFont(descriptor: descriptor, size: size) { return font }
        return .systemFont(ofSize: size, weight: look == .electric ? .black : look == .paper ? .medium : .semibold)
    }
    func drawPoster(in rect: NSRect, look: Look, scale: CGFloat) -> NSRect {
        guard let m = model else { return rect }
        if look == .champagne {
            look.accent.withAlphaComponent(0.2).setStroke()
            let size = min(rect.width * 0.17, rect.height * 0.32)
            for offset in [CGFloat(0), size * 0.55] { let path = NSBezierPath(ovalIn: NSRect(x: rect.midX - size * 0.75 + offset, y: rect.height * 0.79, width: size, height: size)); path.lineWidth = max(1, scale); path.stroke() }
        }
        let title = NSRect(x: rect.width * 0.08, y: rect.height * 0.43, width: rect.width * 0.84, height: rect.height * 0.29)
        drawCentered(m.settings.brand, in: title, look: look, preferred: min(180 * max(0.45, scale), rect.height * 0.2))
        let caption = m.settings.caption ?? ""
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: max(11, min(23 * max(0.6, scale), rect.height * 0.045))), .foregroundColor: look.accent, .paragraphStyle: paragraph, .kern: look == .champagne ? 1.5 : 0.5]
        (caption as NSString).draw(in: NSRect(x: rect.width * 0.08, y: rect.height * 0.33, width: rect.width * 0.84, height: rect.height * 0.08), withAttributes: attrs)
        return NSRect(x: 0, y: rect.height * 0.07, width: rect.width, height: rect.height * 0.2)
    }
    func drawMarketFooter(in rect: NSRect, look: Look, scale: CGFloat) {
        guard let m = model else { return }; look.accent.withAlphaComponent(0.25).setFill(); NSRect(x: rect.minX, y: rect.maxY, width: rect.width, height: 1).fill()
        let text = m.quotes.isEmpty ? "" : m.quotes.prefix(2).map { "\($0.id)  \($0.formatted)" }.joined(separator: "     ")
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: max(9, 22 * scale), weight: .medium), .foregroundColor: look.accent]
        text.draw(at: NSPoint(x: rect.minX, y: rect.midY - 11 * scale), withAttributes: attrs)
    }
    override func keyDown(with event: NSEvent) {
        guard let m = model else { return }
        switch event.keyCode { case 53: m.outputs.stop(); case 49: cancelStripClick();m.playing.toggle(); case 124: m.step(1); case 123: m.step(-1); default: super.keyDown(with: event) }
    }
    override func mouseDown(with event:NSEvent) {
        if model?.idleOutput == true { cancelStripClick();model?.outputs.stop() }
        else if model?.activeMode == .strip && !preview {
            if event.clickCount >= 2 { stripPressPending = false;cancelStripClick();model?.openDisplaySettings() }
            else { stripPressPending = true }
        }
        else { model?.playing.toggle() }
    }
    override func mouseUp(with event:NSEvent) {
        guard stripPressPending,event.clickCount == 1 else { return };stripPressPending = false
        cancelStripClick()
        let action = DispatchWorkItem { [weak self] in
            guard let self else { return };self.pendingStripClick = nil
            guard self.model?.activeMode == .strip,self.window?.isVisible == true else { return }
            self.model?.playing.toggle()
        }
        pendingStripClick = action
        DispatchQueue.main.asyncAfter(deadline:.now()+NSEvent.doubleClickInterval,execute:action)
    }
    override func mouseDragged(with event:NSEvent) {
        guard model?.activeMode == .strip,!preview,stripPressPending else { return }
        stripPressPending = false;cancelStripClick() // The strip stays attached to its chosen edge.
    }
    override func scrollWheel(with event: NSEvent) { guard let m = model else { return }; m.settings.speed = min(260, max(20, m.settings.speed - event.scrollingDeltaY)) }
    deinit { pendingStripClick?.cancel();compositor?.stop() }
}

struct PreviewDisplay: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> PreviewCanvas { PreviewCanvas(model: model) }
    func updateNSView(_ nsView: PreviewCanvas, context: Context) { nsView.setAccessibilityLabel(L("Selected display preview")); nsView.updateConfigurationIfNeeded() }
}

final class PreviewCanvas: NSView {
    let model: AppModel; var tickers: [TickerView] = []; private var configurationKey = ""
    init(model: AppModel) { self.model = model; super.init(frame: .zero); wantsLayer = true; setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel(L("Selected display preview")) }
    required init?(coder: NSCoder) { fatalError() }
    func updateConfigurationIfNeeded() {
        let screen = model.screens.indices.contains(model.selectedScreen) ? model.screens[model.selectedScreen] : NSScreen.main
        let key = "\(model.previewMode.rawValue)|\(model.settings.resolvedPlacement.rawValue)|\(model.settings.stripHeight)|\(model.settings.resolvedComposition.rawValue)|\(screen?.frame ?? .zero)|\(screen?.visibleFrame ?? .zero)"
        guard key != configurationKey else { return }; configurationKey = key; needsLayout = true; needsDisplay = true
    }
    override func layout() {
        super.layout()
        let screen = model.screens.indices.contains(model.selectedScreen) ? model.screens[model.selectedScreen] : NSScreen.main
        let native = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = screen?.visibleFrame ?? native
        let scale = min(bounds.width / native.width, bounds.height / native.height)
        let offset = NSPoint(x: (bounds.width - native.width * scale) / 2, y: (bounds.height - native.height * scale) / 2)
        let mode = model.previewMode
        var specs: [(NSRect, Bool, Bool)] = []
        if mode == .frame {
            let t = min(72, CGFloat(model.settings.stripHeight)); let a = visible
            specs = [(NSRect(x: a.minX, y: a.maxY - t, width: a.width, height: t),false,false),(NSRect(x: a.minX, y: a.minY, width: a.width, height: t),false,false),(NSRect(x: a.minX,y:a.minY+t,width:t,height:a.height-2*t),true,true),(NSRect(x:a.maxX-t,y:a.minY+t,width:t,height:a.height-2*t),true,false)]
        } else if mode == .strip { specs = [(OutputController.stripFrame(in: visible, settings: model.settings), model.settings.resolvedPlacement.vertical, model.settings.resolvedPlacement == .left)] }
        else { specs = [(native,false,false)] }
        while tickers.count > specs.count { tickers.removeLast().removeFromSuperview() }
        while tickers.count < specs.count { let view = TickerView(model: model, preview: true); tickers.append(view); addSubview(view) }
        for (view, spec) in zip(tickers, specs) {
            view.rotated = spec.1; view.clockwise = spec.2; view.previewScale = scale
            view.infoFooter = mode == .full && model.settings.resolvedComposition == .split
            view.frame = NSRect(x: offset.x + (spec.0.minX - native.minX) * scale, y: offset.y + (spec.0.minY - native.minY) * scale, width: spec.0.width * scale, height: spec.0.height * scale)
            if view.seenSequence != model.sequence || view.seenMotion != view.activeMotion { view.resetPreviewPosition() }
            view.needsDisplay = true
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        if model.previewMode == .strip || model.previewMode == .frame {
            let p = NSMutableParagraphStyle(); p.alignment = .center
            (L("Screen area") as NSString).draw(in: NSRect(x: 0, y: bounds.midY - 9, width: bounds.width, height: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: p])
        }
    }
}

final class DisplayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class OutputController {
    weak var model: AppModel?; var window: DisplayWindow?; var activity: NSObjectProtocol?; var extraWindows: [DisplayWindow] = []
    init(model: AppModel) { self.model = model }
    static func stripFrame(in area: NSRect, settings: Settings) -> NSRect {
        let h = min(CGFloat(settings.resolvedStripHeight), min(area.width, area.height) * 0.35)
        return NSRect(x:area.minX,y:settings.desktopEdge == .top ? area.maxY-h : area.minY,width:area.width,height:h)
    }
    // Older mode requests are intentionally confined to the personal desktop strip.
    func show(_ requestedMode:OutputMode = .strip,idle:Bool = false) {
        guard !idle,let m = model,!NSScreen.screens.isEmpty else {return};stop()
        m.prepareDesktopTicker(force:true)
        let screen = NSScreen.screens[min(max(0,m.selectedScreen),NSScreen.screens.count-1)]
        window = makeWindow(frame:Self.stripFrame(in:screen.visibleFrame,settings:m.settings),screen:screen)
        m.activeMode = .strip;m.previewMode = .strip;m.idleOutput = false;m.playing = true
        m.synchronizeWindowFit()
        activity = ProcessInfo.processInfo.beginActivity(options:[.idleDisplaySleepDisabled,.userInitiated],reason:L("Stroka display is active"))
    }

    private func makeWindow(frame:NSRect,screen:NSScreen)->DisplayWindow {
        let m = model!;let w = DisplayWindow(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false,screen:screen)
        w.title = LF("Stroka · %@",OutputMode.strip.title);w.level = .floating;w.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary];w.isReleasedWhenClosed = false;w.hidesOnDeactivate = false;w.hasShadow = false;w.backgroundColor = .clear;w.isOpaque = false
        let view = TickerView(model:m);w.contentView = view;w.makeFirstResponder(view);w.makeKeyAndOrderFront(nil);return w
    }
    func updateConfiguration() {
        guard let m = model,m.activeMode == .strip,let screen = window?.screen,let view = window?.contentView as? TickerView else {return}
        window?.setFrame(Self.stripFrame(in:screen.visibleFrame,settings:m.settings),display:true)
        view.rotated = false;view.clockwise = false;view.requestRefresh()
        m.synchronizeWindowFit()
    }

    func stop() {
        window?.orderOut(nil); window?.contentView = nil; window?.close(); window = nil
        for w in extraWindows { w.orderOut(nil); w.contentView = nil; w.close() }; extraWindows = []
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        model?.activeMode = nil; model?.idleOutput = false
        model?.synchronizeWindowFit()
    }
}

struct TickerPath: Equatable {
    var start: CGPoint; var end: CGPoint; var speed: Double; var vertical: Bool
    var distance: Double { Double(vertical ? abs(end.y-start.y) : abs(end.x-start.x)) }
    var duration: Double { distance / max(1, speed) }
    func point(at elapsed: Double) -> CGPoint {
        let fraction = min(1, max(0, elapsed / max(0.001, duration)))
        return CGPoint(x: start.x + (end.x-start.x)*fraction, y: start.y + (end.y-start.y)*fraction)
    }
    func elapsed(at point: CGPoint) -> Double {
        let traveled = vertical ? abs(point.y-start.y) : abs(point.x-start.x)
        return min(duration, max(0, Double(traveled) / max(1, speed)))
    }
}

final class TickerSurface {
    let size: CGSize; let draw: (CGRect) -> Void
    init(size: CGSize, draw: @escaping (CGRect) -> Void) { self.size = size; self.draw = draw }
}

final class TickerCompositor {
    weak var view: TickerView?
    let scene = CALayer(), chrome = CALayer(), clip = CALayer(), mirror = CALayer(), moving = CALayer(), grid = CALayer(), footer = CALayer(), pause = CALayer(), station = CALayer()
    var observers: [NSObjectProtocol] = []; var wake: Timer?
    var anchor = CACurrentMediaTime(); var phase: Double = 0; var running = false
    var stationKey = ""
    var path: TickerPath?; var bodyKey = ""; var chromeKey = ""; var gridKey = ""; var footerKey = ""; var pauseKey = ""; var animationKey = ""
    var surface: TickerSurface?; var tiles: [String: CALayer] = [:]
    var installed = false; var suspended = false; var backing: CGFloat = 1
    var hasSeenVisible = false; var visibilityAttempts = 0; var visibilityRetry: DispatchWorkItem?
    init(view: TickerView) { self.view = view }
    func stop() { visibilityRetry?.cancel(); visibilityRetry = nil; wake?.invalidate(); wake = nil; observers.forEach(NotificationCenter.default.removeObserver); observers = []; moving.removeAllAnimations(); running = false }
    func attach(to window: NSWindow?) {
        stop(); animationKey = ""; hasSeenVisible = false; visibilityAttempts = 0
        guard let window else { return }
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.didChangeScreenNotification, NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.refresh() })
        }
    }
    func retryInitialVisibility() {
        guard !hasSeenVisible, visibilityAttempts < 6, visibilityRetry == nil, view?.presentationWindow?.isVisible == true else { return }
        visibilityAttempts += 1
        let work = DispatchWorkItem { [weak self] in self?.visibilityRetry = nil; self?.refresh() }
        visibilityRetry = work; DispatchQueue.main.asyncAfter(deadline:.now()+0.1,execute:work)
    }
    func invalidate() { bodyKey = ""; chromeKey = ""; gridKey = ""; footerKey = ""; pauseKey = ""; animationKey = "" }
    func seek(_ time: Double) { phase = time; anchor = CACurrentMediaTime(); animationKey = "" }
    func install() {
        guard let layer = view?.renderRoot ?? view?.layer else { return }
        if installed {
            if scene.superlayer !== layer { scene.removeFromSuperlayer(); layer.addSublayer(scene); invalidate() }
            return
        }
        installed = true
        layer.masksToBounds = true; scene.anchorPoint = .zero
        for item in [scene, chrome, clip, mirror, moving, grid, footer, pause, station] { item.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "opacity": NSNull(), "transform": NSNull(), "hidden": NSNull()]; item.isGeometryFlipped = false }
        chrome.isOpaque = true; layer.addSublayer(scene); scene.addSublayer(chrome); scene.addSublayer(clip); clip.masksToBounds = true; clip.addSublayer(mirror); mirror.anchorPoint = .zero; mirror.addSublayer(moving); moving.anchorPoint = .zero
        scene.addSublayer(grid); scene.addSublayer(footer); scene.addSublayer(pause); scene.addSublayer(station)
    }
    func refresh(manualElapsed: Double? = nil) {
        guard let v = view, let m = v.model, v.bounds.width > 0, v.bounds.height > 0 else { return }
        install(); guard installed else { return }
        let now = CACurrentMediaTime(); if running { phase += max(0, now-anchor) }; anchor = now
        let visible = v.presentationWindow?.isVisible == true && v.presentationWindow?.isMiniaturized == false && v.presentationWindow?.occlusionState.contains(.visible) == true && !v.isHiddenOrHasHiddenAncestor && v.parentTicker?.isHiddenOrHasHiddenAncestor != true
        let shouldRun = visible && m.playing && m.urgent.isEmpty && manualElapsed == nil
        let wasRunning = running; running = shouldRun
        if visible { hasSeenVisible = true; visibilityRetry?.cancel(); visibilityRetry = nil }
        if !visible && manualElapsed == nil && chrome.contents != nil {
            // Occluded and closed windows do not poll, redraw, or animate.
            moving.removeAllAnimations(); animationKey = ""; wake?.invalidate(); wake = nil; suspended = true; retryInitialVisibility(); return
        }
        if suspended { suspended = false; animationKey = "" }
        let reset = v.seenSequence != v.sequenceToken || v.seenChannel != v.channelToken || v.seenMotion != v.activeMotion
        if reset {
            v.localIndex = v.sequenceToken; phase = 0; path = nil; animationKey = ""
            v.seenSequence = v.sequenceToken; v.seenChannel = v.channelToken; v.seenMotion = v.activeMotion
            if v.preview { v.resetPreviewPosition(); phase = v.elapsed }
        }
        if let manualElapsed { phase = manualElapsed; animationKey = "" }
        var s = m.settings
        if v.isMarketLane { s.look = .desk; s.speed = m.settings.marketSpeed ?? 85; s.fontSize = 23; s.showClock = false; s.composition = .ticker }
        s.speed = m.speedForRow(v.rowIndex)
        var cycle = false
        let motion = v.activeMotion
        // A word/phrase changes only at its own deadline. No 60 Hz application callbacks.
        let wordSeconds = max(0.15,18/s.speed)
        if m.urgent.isEmpty && motion == .phrases && phase >= s.holdSeconds { v.localIndex += Int(phase/s.holdSeconds); phase = phase.truncatingRemainder(dividingBy:s.holdSeconds); cycle = true }
        var line = String(v.currentLine.prefix(6000))
        var words = motion == .words ? line.split(whereSeparator:{$0.isWhitespace}).map(String.init) : []
        if m.urgent.isEmpty && motion == .words && phase >= Double(max(1,words.count))*wordSeconds {
            phase = phase.truncatingRemainder(dividingBy:Double(max(1,words.count))*wordSeconds); v.localIndex += 1; cycle = true; line = String(v.currentLine.prefix(6000)); words = line.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        }
        let wordIndex = min(max(0,Int(phase/wordSeconds)),max(0,words.count-1))
        let text = !m.urgent.isEmpty ? m.urgent : motion == .words ? (words.isEmpty ? "…" : words[wordIndex]) : line
        let canvas = v.laneBounds
        backing = max(1, v.window?.backingScaleFactor ?? v.parentTicker?.window?.backingScaleFactor ?? 1)
        let scale = v.previewScale ?? (v.preview ? min(1, canvas.width/1100) : 1)
        let inset: CGFloat = v.preview ? max(8,48*scale) : 48
        let poster = !s.look.isBroadcast && s.resolvedComposition == .poster && canvas.height > 200
        let showFooter = !s.look.isBroadcast && v.infoFooter && !poster && !m.quotes.isEmpty && m.urgent.isEmpty
        let footerHeight: CGFloat = showFooter ? max(56*scale,canvas.height*0.16) : 0
        let top: CGFloat = canvas.height > 220*scale && !v.rotated ? 48*max(v.preview ? 0.42 : 1,scale) : 0
        var content = NSRect(x:0,y:footerHeight,width:canvas.width,height:canvas.height-footerHeight-top)
        if poster { content = NSRect(x:0,y:canvas.height*0.07,width:canvas.width,height:canvas.height*0.2) }
        if s.look.isBroadcast { content = BroadcastGeometry.make(canvas:canvas,scale:scale,showClock:s.showClock,look:s.look,compact:v.compactBand).content }
        if v.isMarketLane { let g = BroadcastGeometry.make(canvas:canvas,scale:scale,showClock:m.settings.showClock,compact:v.compactBand);content = CGRect(x:g.content.minX,y:0,width:g.content.width,height:canvas.height) }
        if !m.urgent.isEmpty { content = canvas.insetBy(dx:inset,dy:inset) }
        let fontSize = min(CGFloat(s.fontSize)*max(v.preview ? 0.08 : 1,scale),max(1,content.height*0.75))
        let stream = m.urgent.isEmpty && motion == .horizontal ? v.streamWindow(fontSize:fontSize,look:s.look,viewport:content.width,reverse:s.reverse) : nil
        let geometry = "\(canvas.size)|\(scale)|\(backing)|\(content)|\(v.rotated)|\(v.clockwise)"
        let minute = Int(Date().timeIntervalSince1970/60)
        CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
        if !v.auxiliaryLane {
            let compact = v.renderBounds.height <= 320*scale
            v.layer?.cornerRadius = s.look.isBroadcast && compact && (s.roundedStrip ?? true) ? (s.look == .glass ? min(v.renderBounds.width,v.renderBounds.height)*0.5 : min(22*scale,v.renderBounds.height*0.21)) : 0
            v.layer?.cornerCurve = .continuous
        }
        scene.zPosition = v.auxiliaryLane ? 0 : 1
        scene.bounds = canvas
        scene.position = v.rotated ? (v.clockwise ? CGPoint(x:0,y:v.bounds.height) : CGPoint(x:v.bounds.width,y:0)) : .zero
        if v.marketBandHeight > 0 {
            scene.position = v.rotated ? (v.clockwise ? CGPoint(x:v.marketBandHeight,y:v.bounds.height) : CGPoint(x:v.bounds.width-v.marketBandHeight,y:0)) : CGPoint(x:0,y:v.marketBandHeight)
        }
        if v.renderRoot != nil { scene.position.x += v.frame.minX; scene.position.y += v.frame.minY }
        scene.setAffineTransform(v.rotated ? CGAffineTransform(rotationAngle:v.clockwise ? -.pi/2 : .pi/2) : .identity)
        clip.frame = content; mirror.bounds = CGRect(origin:.zero,size:content.size); mirror.position = CGPoint(x:s.mirror ? content.width : 0,y:0); mirror.setAffineTransform(CGAffineTransform(scaleX:s.mirror ? -1 : 1,y:1))
        let record = v.broadcastRecord
        station.isHidden = v.auxiliaryLane || !m.dualBandActive || !m.urgent.isEmpty
        if !station.isHidden {
            let band = BroadcastGeometry.make(canvas:canvas,scale:scale,showClock:s.showClock,look:s.look,compact:v.compactBand).band
            let full = CGRect(x:0,y:0,width:canvas.width,height:band.height+v.marketBandHeight)
            let key = "\(m.playing)|\(full)|\(scale)|\(backing)|\(s.look)|\(s.brand)|\(s.caption ?? "")|\(m.logoRevision)|\(s.logoPlate ?? true)|\(s.showClock)|\(s.broadcastDate ?? true)|\(minute)|\(Localization.language)"
            station.frame = CGRect(x:0,y:-v.marketBandHeight,width:full.width,height:full.height)
            if key != stationKey { stationKey = key;station.contentsScale = backing;station.contents = v.bitmap(size:full.size,scale:backing) { v.drawStation(in:full,scale:scale) } }
        }
        let attribution = s.look.isBroadcast && !v.isMarketLane ? "\(record.source)|\(record.stamp)|\(record.section)|" + (canvas.height > 320*scale && !record.isQuote ? record.text : "") : ""
        let newChrome = "\(m.playing)|\(geometry)|\(s.look.rawValue)|\(s.brand)|\(s.caption ?? "")|\(s.channel.rawValue)|\(Localization.language.rawValue)|\(poster)|\(s.showClock ? minute : 0)|\(m.urgent.isEmpty)|\(attribution)|\(m.logoRevision)|\(s.logoPlate ?? true)|\(s.broadcastSource ?? true)|\(s.broadcastDate ?? true)"
        if newChrome != chromeKey {
            chromeKey = newChrome; chrome.frame = canvas; chrome.contentsScale = backing
            chrome.contents = v.bitmap(size:canvas.size,scale:backing) {
                if s.look == .glass { BusheDesign.tickerGlass(in:canvas) } else { s.look.bg.setFill(); canvas.fill() }
                guard m.urgent.isEmpty else { return }
                if v.isMarketLane { v.drawMarketRail(in:canvas,scale:scale) }
                else if v.auxiliaryLane {s.look.ink.withAlphaComponent(0.12).setFill();CGRect(x:content.minX,y:canvas.maxY-max(0.5,scale),width:content.width,height:max(0.5,scale)).fill()}
                else if s.look.isBroadcast { v.drawBroadcast(in:canvas,scale:scale,record:record) }
                else if poster { _ = v.drawPoster(in:canvas,look:s.look,scale:scale) }
                else if top > 0 {
                    let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:max(10,12*scale),weight:.semibold),.foregroundColor:s.look.accent,.kern:2]
                    (s.brand+"  /  "+s.channel.title.uppercased()).draw(at:CGPoint(x:inset,y:canvas.height-top+10*scale),withAttributes:attrs)
                    if s.showClock { let clock = Date().formatted(Date.FormatStyle(date:.omitted,time:.shortened).locale(Localization.locale)); let width = (clock as NSString).size(withAttributes:attrs).width; clock.draw(at:CGPoint(x:canvas.width-inset-width,y:canvas.height-top+10*scale),withAttributes:attrs) }
                }
            }
        }
        let newFooter = "\(geometry)|\(s.look.rawValue)|\(showFooter)|"+m.quotes.prefix(2).map { "\($0.id) \($0.formatted)" }.joined(separator:"|")
        footer.isHidden = !showFooter
        if showFooter && newFooter != footerKey {
            footerKey = newFooter; let rect = NSRect(x:inset,y:12*scale,width:canvas.width-inset*2,height:footerHeight-20*scale)
            footer.frame = CGRect(x:rect.minX,y:rect.minY,width:rect.width,height:rect.height+2); footer.contentsScale = backing
            footer.contents = v.bitmap(size:footer.bounds.size,scale:backing) { v.drawMarketFooter(in:NSRect(origin:.zero,size:rect.size),look:s.look,scale:scale) }
        }
        pause.isHidden = s.look.isBroadcast || m.playing || !m.urgent.isEmpty
        let newPause = "\(geometry)|\(s.look.rawValue)|\(Localization.language.rawValue)"
        if !pause.isHidden && newPause != pauseKey {
            pauseKey = newPause; pause.frame = CGRect(x:inset,y:max(8,footerHeight+8),width:180,height:22); pause.contentsScale = backing
            pause.contents = v.bitmap(size:pause.bounds.size,scale:backing) { L("PAUSED").draw(at:.zero,withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:.semibold),.foregroundColor:s.look.accent]) }
        }
        let newBody = "\(geometry)|\(s.look.rawValue)|\(fontSize)|\(motion.rawValue)|\(m.urgent.isEmpty)|\(stream?.text.string ?? text)|\(m.settings.resolvedSeparator)"
        if newBody != bodyKey {
            bodyKey = newBody; tiles.values.forEach{$0.removeFromSuperlayer()}; tiles = [:]
            if !m.urgent.isEmpty {
                surface = TickerSurface(size:content.size) { [weak v] _ in v?.drawUrgent(text,in:NSRect(origin:.zero,size:content.size),look:s.look) }
            } else if motion == .phrases || motion == .words {
                surface = TickerSurface(size:content.size) { [weak v] _ in v?.drawCentered(text,in:NSRect(origin:.zero,size:content.size).insetBy(dx:inset,dy:12),look:s.look,preferred:fontSize*(motion == .words ? 1.35 : 1)) }
            } else if let stream {
                let pad:CGFloat = s.look == .neon ? 20 : 2
                surface = TickerSurface(size:CGSize(width:stream.size.width+2*pad,height:stream.size.height+2*pad)) { _ in stream.text.draw(at:CGPoint(x:pad,y:pad)) }
            } else {
                v.prepare(text:text,size:fontSize,look:s.look); let attr = v.cached
                let pad:CGFloat = s.look == .neon ? 20 : 2
                if motion == .horizontal {
                    let size = CGSize(width:ceil(v.textSize.width)+2*pad,height:ceil(v.textSize.height)+2*pad)
                    surface = TickerSurface(size:size) { _ in attr.draw(at:CGPoint(x:pad,y:pad)) }
                } else {
                    let width = max(10,content.width-2*inset)
                    let height = ceil(attr.boundingRect(with:CGSize(width:width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height)
                    surface = TickerSurface(size:CGSize(width:width+2*pad,height:height+2*pad+10)) { _ in attr.draw(with:NSRect(x:pad,y:pad,width:width,height:height+10),options:[.usesLineFragmentOrigin,.usesFontLeading]) }
                }
            }
        }
        guard let surface else { return }
        moving.bounds = CGRect(origin:.zero,size:surface.size)
        let pad:CGFloat = s.look == .neon ? 20 : 2
        let speed = max(1,Double(s.speed*scale)*(motion == .vertical ? 0.65 : 1))
        var newPath:TickerPath?
        if m.urgent.isEmpty && motion == .horizontal {
            let y = content.height/2-surface.size.height/2
            if let stream {
                let start = s.reverse ? content.width-stream.size.width-pad : -pad
                newPath = TickerPath(start:CGPoint(x:start,y:y),end:CGPoint(x:start+(s.reverse ? stream.advance : -stream.advance),y:y),speed:speed,vertical:false)
            } else {
                newPath = TickerPath(start:CGPoint(x:s.reverse ? -surface.size.width+pad : content.width-pad,y:y),end:CGPoint(x:s.reverse ? content.width+100-pad : -surface.size.width-100+pad,y:y),speed:speed,vertical:false)
            }
        } else if m.urgent.isEmpty && motion == .vertical {
            newPath = TickerPath(start:CGPoint(x:inset-pad,y:s.reverse ? content.height : -surface.size.height),end:CGPoint(x:inset-pad,y:s.reverse ? -surface.size.height-40 : content.height+40),speed:speed,vertical:true)
        }
        if let old = path, let newPath, old != newPath && !reset && !cycle && manualElapsed == nil { phase = newPath.elapsed(at:old.point(at:phase)) }
        path = newPath
        if let path, phase >= path.duration {
            phase = stream == nil ? phase.truncatingRemainder(dividingBy:path.duration) : phase-path.duration; v.localIndex += 1; bodyKey = ""; animationKey = ""; running = false
            v.elapsed = phase; anchor = now; self.path = nil; refresh(manualElapsed:manualElapsed == nil ? nil : phase); return
        }
        let position = newPath?.point(at:phase) ?? .zero
        let wave:CGFloat = s.look == .ribbon && motion == .horizontal && m.urgent.isEmpty ? min(18,content.height*0.08) : 0
        let actual = CGPoint(x:position.x,y:position.y+sin(phase*0.7)*wave)
        syncTiles(surface:surface,visible:CGRect(x:-actual.x,y:-actual.y,width:content.width,height:content.height),scale:backing)
        let newAnimation = "\(geometry)|\(newPath.map{String(describing:$0)} ?? "static")|\(wave)|\(shouldRun)|\(m.urgent.isEmpty)"
        if newAnimation != animationKey || cycle || wasRunning != shouldRun || manualElapsed != nil {
            animationKey = newAnimation; moving.removeAllAnimations(); moving.opacity = 1; moving.position = actual
            if shouldRun, let path = newPath {
                // Continue within the prefetched stream if a boundary wake is a few frames late.
                // The next segment replaces this at the same position, without stopping CA.
                let continuation:CGFloat = stream == nil ? 0 : 64
                let end = CGPoint(x:path.end.x+(s.reverse ? continuation : -continuation),y:path.end.y)
                moving.position = end
                let animation = CABasicAnimation(keyPath:"position.x"); animation.fromValue = position.x; animation.toValue = end.x; animation.duration = max(0.001,path.duration-phase+Double(continuation)/speed); animation.timingFunction = CAMediaTimingFunction(name:.linear)
                if path.vertical { animation.keyPath = "position.y"; animation.fromValue = position.y; animation.toValue = path.end.y }
                moving.add(animation,forKey:"translation")
                if wave > 0 {
                    let bob = CAKeyframeAnimation(keyPath:"position.y"); bob.values = (0...64).map { sin(Double($0)/64*2*Double.pi)*Double(wave) }; bob.duration = 2*Double.pi/0.7; bob.repeatCount = .infinity; bob.isAdditive = true; bob.timeOffset = phase.truncatingRemainder(dividingBy:bob.duration); bob.calculationMode = .linear; moving.add(bob,forKey:"ribbon")
                }
            } else if motion == .phrases && m.urgent.isEmpty {
                moving.opacity = Float(min(1,phase/0.3))
                if shouldRun && phase < 0.3 { let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = moving.opacity; fade.toValue = 1; fade.duration = 0.3-phase; fade.timingFunction = CAMediaTimingFunction(name:.linear); moving.opacity = 1; moving.add(fade,forKey:"fade") }
            }
        }
        grid.isHidden = s.look != .led || !m.urgent.isEmpty
        let newGrid = "\(geometry)|\(s.look.rawValue)"
        if !grid.isHidden && newGrid != gridKey {
            gridKey = newGrid; grid.frame = content; grid.contentsScale = backing
            grid.contents = v.bitmap(size:content.size,scale:backing) {
                s.look.bg.withAlphaComponent(0.7).setFill()
                for x in stride(from:CGFloat(0),to:content.width,by:5) { NSRect(x:x,y:0,width:1.6,height:content.height).fill() }
                for y in stride(from:CGFloat(0),to:content.height,by:5) { NSRect(x:0,y:y,width:content.width,height:1.6).fill() }
            }
        }
        v.elapsed = phase
        wake?.invalidate(); wake = nil
        if manualElapsed == nil && visible {
            var delay = Double.infinity
            if shouldRun {
                if let path = newPath { delay = min(max(0.01,path.duration-phase),path.vertical ? 0.75 : 1.5) }
                else if motion == .phrases { delay = max(0.01,s.holdSeconds-phase) }
                else if motion == .words { delay = max(0.01,wordSeconds-phase.truncatingRemainder(dividingBy:wordSeconds)) }
            }
            if s.showClock && (top > 0 || s.look.isBroadcast) && !poster && m.urgent.isEmpty { delay = min(delay,60-Date().timeIntervalSince1970.truncatingRemainder(dividingBy:60)+0.02) }
            if delay.isFinite { let timer = Timer(timeInterval:delay,repeats:false) { [weak self] _ in self?.refresh() }; timer.tolerance = min(0.02,delay*0.02); wake = timer; RunLoop.main.add(timer,forMode:.common) }
        }
        if !visible && manualElapsed == nil { suspended = true; retryInitialVisibility() }
    }
    func syncTiles(surface:TickerSurface,visible:CGRect,scale:CGFloat) {
        guard let v = view else { return }
        // Bounded tiles: a long message never becomes one enormous GPU texture.
        let width:CGFloat = min(1024,surface.size.width), height:CGFloat = min(256,surface.size.height)
        let visible = visible.insetBy(dx:-width,dy:-height).intersection(CGRect(origin:.zero,size:surface.size))
        var keep = Set<String>()
        if !visible.isNull && width > 0 && height > 0 {
            let xs = Int(max(0,floor(visible.minX/width)))...Int(max(0,ceil(visible.maxX/width)-1))
            let ys = Int(max(0,floor(visible.minY/height)))...Int(max(0,ceil(visible.maxY/height)-1))
            for y in ys { for x in xs {
                let key = "\(x):\(y)"; keep.insert(key); guard tiles[key] == nil else { continue }
                let rect = CGRect(x:CGFloat(x)*width,y:CGFloat(y)*height,width:min(width,surface.size.width-CGFloat(x)*width),height:min(height,surface.size.height-CGFloat(y)*height))
                guard rect.width > 0, rect.height > 0 else { continue }
                let tile = CALayer(); tile.frame = rect; tile.contentsScale = scale; tile.actions = ["contents":NSNull(),"position":NSNull(),"bounds":NSNull()]
                let gutter:CGFloat = v.model?.settings.look == .neon ? 32 : 2/scale
                let raster = rect.insetBy(dx:-gutter,dy:-gutter)
                if let image = v.bitmap(size:raster.size,scale:scale,draw: { NSGraphicsContext.current!.cgContext.translateBy(x:-raster.minX,y:-raster.minY); surface.draw(raster) }) {
                    tile.contents = image
                    tile.contentsRect = CGRect(x:gutter*scale/CGFloat(image.width),y:gutter*scale/CGFloat(image.height),width:rect.width*scale/CGFloat(image.width),height:rect.height*scale/CGFloat(image.height))
                }
                moving.addSublayer(tile); tiles[key] = tile
            } }
        }
        for key in Array(tiles.keys) where !keep.contains(key) { tiles.removeValue(forKey:key)?.removeFromSuperlayer() }
    }
}
