import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct BroadcastGeometry {
    var band: CGRect; var content: CGRect; var badge: CGRect; var clock: CGRect; var header: CGRect
    static func make(canvas: CGRect, scale: CGFloat, showClock: Bool, look: Look = .bulletin,compact:Bool = false) -> Self {
        let h = canvas.height > 320*scale ? min(96*scale,canvas.height*0.15) : canvas.height
        let bw = min(canvas.width*0.20,(compact ? 80 : 120)*scale)
        let cw = showClock ? min(canvas.width*0.22,(compact ? 88 : 136)*scale) : 0
        let badge = CGRect(x:0,y:0,width:bw,height:h)
        let clock = CGRect(x:canvas.width-cw,y:0,width:cw,height:h)
        let content = CGRect(x:badge.maxX,y:0,width:max(1,clock.minX-badge.maxX),height:h)
        return Self(band:CGRect(x:0,y:0,width:canvas.width,height:h),content:content,badge:badge,clock:clock,header:.zero)
    }
}

enum BroadcastLogo {
    static func normalized(_ data: Data) -> Data? {
        guard data.count <= 10_000_000, let source = CGImageSourceCreateWithData(data as CFData,nil),
              let type = CGImageSourceGetType(source) as String?, [UTType.png.identifier,UTType.jpeg.identifier].contains(type),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1024,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage:image)
        guard let png = rep.representation(using:.png,properties:[:]), png.count <= 1_500_000 else { return nil }
        return png
    }
    static func fitted(image: NSSize, in rect: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let ratio = min(rect.width/image.width,rect.height/image.height)
        let size = CGSize(width:image.width*ratio,height:image.height*ratio)
        return CGRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height)
    }
}
extension AppModel {
    var displayLogo: NSImage? {
        guard let data = settings.logoData else { return nil }
        if cachedLogo == nil { cachedLogo = NSImage(data:data) }
        return cachedLogo
    }
}

extension TickerView {
    var rawLine: String {
        guard let m = model else { return "" }; let rows = messageRows
        let empty = m.settings.tickerRows == nil ? (isMarketLane ? L("Waiting for market data…") : m.emptyMessage) : channelToken == .markets ? L("Waiting for market data…") : channelToken == .message ? L("Enter a message in the control window") : m.refreshingContent ? L("Loading your feed…") : L("No eligible messages yet")
        return rows.isEmpty ? empty : rows[((localIndex % rows.count)+rows.count)%rows.count]
    }
    var broadcastRecord: BroadcastRecord { (model?.settings.tickerRows != nil ? model?.rowRecord(rawLine,index:rowIndex) : model?.record(for:rawLine)) ?? BroadcastRecord(text:"",source:"Stroka",date:nil,section:L("HEADLINES")) }
    func broadcastLabel(_ text: String, in rect: CGRect, ink: NSColor, size: CGFloat, weight: NSFont.Weight = .medium, align: NSTextAlignment = .left) {
        guard rect.width > 0, rect.height > 0 else { return }
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize:size,weight:weight)
        let h = font.ascender-font.descender+font.leading
        (text as NSString).draw(in:CGRect(x:rect.minX,y:rect.midY-h/2,width:rect.width,height:h+2),withAttributes:[.font:font,.foregroundColor:ink,.paragraphStyle:p])
    }
    func drawMarketRail(in canvas: CGRect,scale:CGFloat) {
        let g = BroadcastGeometry.make(canvas:canvas,scale:scale,showClock:model?.settings.showClock ?? true,compact:compactBand)
        hex(0xFFC53D).withAlphaComponent(0.45).setFill();CGRect(x:g.content.minX,y:canvas.maxY-max(1,scale),width:g.content.width,height:max(1,scale)).fill()
    }
    func drawStation(in canvas:CGRect,scale:CGFloat) {
        guard let m = model else { return };let s = m.settings,look = s.look
        let geometry = BroadcastGeometry.make(canvas:canvas,scale:scale,showClock:s.showClock,look:look,compact:compactBand)
        let badge = CGRect(x:geometry.badge.minX,y:0,width:geometry.badge.width,height:canvas.height)
        let clock = CGRect(x:geometry.clock.minX,y:0,width:geometry.clock.width,height:canvas.height)
        let light = look == .wire || look == .desk || look == .editorial || look == .minimal
        let badgeColor = look == .glass ? hex(0x2C3644) : look == .editorial || look == .minimal ? look.bg : look == .nightline ? hex(0x222A36) : look.accent
        let ink = light ? look.ink : NSColor.white
        let brandInk = look == .signal ? hex(0x143E8E) : look == .wire || look == .desk ? hex(0x101820) : ink
        badgeColor.setFill();badge.fill()
        let caption = canvas.height >= 60*scale ? (s.caption ?? "").trimmingCharacters(in:.whitespacesAndNewlines) : ""
        let captionH:CGFloat = caption.isEmpty ? 0 : min(24*scale,canvas.height*0.24)
        let dx:CGFloat = compactBand ? 6*scale : 10*scale,dy:CGFloat = compactBand ? 4*scale : 8*scale
        let brandRect = CGRect(x:badge.minX+dx,y:dy+captionH,width:max(1,badge.width-2*dx),height:max(1,badge.height-2*dy-captionH))
        if let logo = m.displayLogo {
            if s.logoPlate ?? true { NSColor.white.setFill();NSBezierPath(roundedRect:badge.insetBy(dx:compactBand ? 4*scale : 8*scale,dy:compactBand ? 4*scale : 8*scale),xRadius:10*scale,yRadius:10*scale).fill() }
            logo.draw(in:BroadcastLogo.fitted(image:logo.size,in:brandRect),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
        } else {
            let text = s.brand.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "STROKA" : s.brand
            let p = NSMutableParagraphStyle();p.alignment = .center;p.lineBreakMode = .byWordWrapping
            var size = min((compactBand ? 18 : 24)*scale,brandRect.height*0.52)
            var attr = NSAttributedString();var measured = CGRect.zero
            repeat {
                attr = NSAttributedString(string:String(text.prefix(100)),attributes:[.font:NSFont.systemFont(ofSize:size,weight:.semibold),.foregroundColor:brandInk,.paragraphStyle:p])
                measured = attr.boundingRect(with:CGSize(width:brandRect.width,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading])
                let font = NSFont.systemFont(ofSize:size,weight:.semibold)
                let widestWord = text.split(whereSeparator:{$0.isWhitespace}).map { (String($0) as NSString).size(withAttributes:[.font:font]).width }.max() ?? 0
                if measured.height <= brandRect.height && widestWord <= brandRect.width { break };size -= scale
            } while size > 10*scale
            attr.draw(with:CGRect(x:brandRect.minX,y:brandRect.midY-measured.height/2,width:brandRect.width,height:measured.height+2),options:[.usesLineFragmentOrigin,.usesFontLeading])
        }
        if !caption.isEmpty { broadcastLabel(caption,in:CGRect(x:badge.minX+12*scale,y:9*scale,width:badge.width-24*scale,height:captionH),ink:m.displayLogo != nil && (s.logoPlate ?? true) ? hex(0x333942) : brandInk.withAlphaComponent(0.82),size:max(5,10*scale),weight:.medium,align:.center) }
        if !m.playing {
            let color = m.displayLogo != nil && (s.logoPlate ?? true) ? hex(0x333942) : brandInk
            color.withAlphaComponent(0.8).setFill()
            for offset in [0.0,4.0] { CGRect(x:badge.maxX-(12-offset)*scale,y:badge.maxY-12*scale,width:2*scale,height:6*scale).fill() }
        }
        if s.showClock {
            let plain = look == .minimal || look == .editorial
            let bg = plain ? look.bg : look == .wire || look == .signal ? hex(0x132C45) : hex(0x20252D)
            let clockInk = plain ? look.ink : NSColor.white
            bg.setFill();clock.fill()
            let dateOn = (s.broadcastDate ?? true) && canvas.height >= 44*scale
            let f = DateFormatter();f.locale = Locale(identifier:"en_US_POSIX");f.dateFormat = "HH:mm";let now = Date();let time = f.string(from:now)
            let clockPadding:CGFloat = (compactBand ? 5 : 8)*scale
            var fontSize = min(64*scale,clock.height*(dateOn ? 0.52 : 0.65))
            while (time as NSString).size(withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:fontSize,weight:.medium)]).width > clock.width-2*clockPadding && fontSize > 10*scale { fontSize -= scale }
            let font = NSFont.monospacedDigitSystemFont(ofSize:fontSize,weight:.medium)
            let p = NSMutableParagraphStyle();p.alignment = .center
            let attr = NSAttributedString(string:time,attributes:[.font:font,.foregroundColor:clockInk,.paragraphStyle:p]);let height = attr.size().height
            let center = clock.midY+(dateOn ? min(10*scale,clock.height*0.10) : 0)
            attr.draw(in:CGRect(x:clock.minX+clockPadding,y:center-height/2,width:clock.width-2*clockPadding,height:height+2))
            if dateOn { f.locale = Localization.locale;f.dateFormat = compactBand ? "EEE, d MMM" : "EEE, d MMM yyyy";broadcastLabel(f.string(from:now),in:CGRect(x:clock.minX+clockPadding,y:clock.height*0.10,width:clock.width-2*clockPadding,height:clock.height*0.21),ink:clockInk.withAlphaComponent(0.70),size:compactBand ? 9*scale : max(5,min(12*scale,clock.height*0.15)),weight:.medium,align:.center) }
        }
    }
    func drawBroadcast(in canvas: CGRect, scale: CGFloat, record: BroadcastRecord) {
        guard let m = model else { return }; let s = m.settings, look = s.look
        let g = BroadcastGeometry.make(canvas:canvas,scale:scale,showClock:s.showClock,look:look,compact:compactBand)
        // A single baseline keeps scrolling headlines vertically centred.
        // In two-row mode the side blocks are drawn once over both rows.
        if !m.dualBandActive { drawStation(in:CGRect(x:0,y:0,width:canvas.width,height:g.band.height),scale:scale) }
        if canvas.height > g.band.height+80*scale {
            let margin = canvas.width*0.08
            let headline = record.isQuote ? L("Markets at a Glance") : record.text
            let hero = CGRect(x:margin,y:g.band.maxY+(canvas.height-g.band.height)*0.20,width:canvas.width-2*margin,height:(canvas.height-g.band.height)*0.52)
            drawCentered(headline,in:hero,look:look,preferred:min(132*scale,hero.height*0.30))
            broadcastLabel(record.section,in:CGRect(x:margin,y:canvas.height-88*scale,width:canvas.width-2*margin,height:32*scale),ink:look.accent,size:21*scale,weight:.semibold)
        }
    }
}

struct BroadcastStripPreview: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> TickerView { let v = TickerView(model:model,preview:true); return v }
    func updateNSView(_ view: TickerView,context:Context) { view.previewScale = 0.7; view.requestRefresh() }
}
struct BroadcastModelPicker: View {
    @ObservedObject var model: AppModel
    var body: some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:2),spacing:10) {
            ForEach(Look.broadcastLooks) { look in
                Button { model.applyLook(look) } label: {
                    VStack(alignment:.leading,spacing:6) {
                        HStack(spacing:0) {
                            Rectangle().fill(Color(nsColor:look.accent)).frame(width:22)
                            VStack(alignment:.leading,spacing:4) { Rectangle().fill(Color(nsColor:look.ink).opacity(0.4)).frame(height:2); Rectangle().fill(Color(nsColor:look.ink)).frame(height:3) }.padding(6)
                            Text("12:45").font(.system(size:9,weight:.medium,design:.monospaced)).foregroundStyle(.white).frame(width:38,height:34).background(Color(nsColor:hex(0x20252D)))
                        }.frame(height:34).background(Color(nsColor:look.bg)).clipShape(RoundedRectangle(cornerRadius:6))
                        Text(look.title).font(.system(size:11,weight:.semibold)).lineLimit(2).frame(maxWidth:.infinity,minHeight:28,alignment:.topLeading)
                        Text(L(look.broadcastDetail)).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth:.infinity,minHeight:26,alignment:.topLeading)
                    }.padding(7)
                }.buttonStyle(BusheChoiceStyle(selected:model.settings.look == look)).accessibilityLabel(L("Appearance: ")+look.title).accessibilityAddTraits(model.settings.look == look ? .isSelected : [])
            }
        }
    }
}
struct BroadcastBrandControls: View {
    @ObservedObject var model: AppModel
    @State private var error = ""
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Toggle(L("Rounded Corners"),isOn:Binding(get:{model.settings.roundedStrip ?? true},set:{model.settings.roundedStrip = $0}))
            Toggle(L("Show Time"),isOn:$model.settings.showClock)
            if model.settings.showClock { Toggle(L("Show Date"),isOn:Binding(get:{model.settings.broadcastDate ?? true},set:{model.settings.broadcastDate = $0})) }
            Toggle(L("Show Source"),isOn:Binding(get:{model.settings.broadcastSource ?? true},set:{model.settings.broadcastSource = $0}))
            Divider(); Text(L("Your Station")).font(.system(size:12,weight:.semibold)).foregroundStyle(.secondary)
            TextField(L("Station name"),text:$model.settings.brand).textFieldStyle(.roundedBorder)
            TextField(L("Station subtitle"),text:Binding(get:{model.settings.caption ?? ""},set:{model.settings.caption = String($0.prefix(60))})).textFieldStyle(.roundedBorder)
            if let image = model.displayLogo { Image(nsImage:image).resizable().scaledToFit().frame(maxWidth:.infinity).frame(height:50).padding(8).background(.white,in:RoundedRectangle(cornerRadius:8)).accessibilityLabel(L("Station logo")) }
            HStack { Button(model.settings.logoData == nil ? L("Upload Logo…") : L("Replace Logo…")) { chooseLogo() }; if model.settings.logoData != nil { Button(L("Remove")) { model.settings.logoData = nil; model.settings.logoName = nil } } }
            Text(model.settings.logoName ?? L("PNG or JPEG · kept on this Mac")).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2)
            if !error.isEmpty { Text(error).font(.system(size:11)).foregroundStyle(.red) }
            if model.settings.logoData != nil { Toggle(L("White Logo Plate"),isOn:Binding(get:{model.settings.logoPlate ?? true},set:{model.settings.logoPlate = $0})) }
            Text(L("The clock uses your Mac’s time zone. Article dates remain in the feed list.")).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.toggleStyle(.checkbox)
    }
    func chooseLogo() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize, size <= 10_000_000,
              let data = try? Data(contentsOf:url), let png = BroadcastLogo.normalized(data) else { error = L("Choose a valid PNG or JPEG under 10 MB."); return }
        model.settings.logoData = png; model.settings.logoName = url.lastPathComponent; error = ""
    }
}
