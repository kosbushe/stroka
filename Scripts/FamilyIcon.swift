import AppKit

let build = CommandLine.arguments[1]
let output = CommandLine.arguments[2]
let iconset = build + "/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func shadow(_ opacity: CGFloat, blur: CGFloat, y: CGFloat, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(opacity)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: y)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon(detail: Bool) {
    let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205)
    shadow(0.16, blur: 22, y: -9) { color(0xD9E4F4).setFill(); tile.fill() }
    NSGradient(starting: color(0xD4E0F2), ending: color(0xFCFDFF))!.draw(in: tile, angle: 90)
    color(0xFFFFFF, alpha: 0.92).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    let bezel = NSBezierPath(roundedRect:NSRect(x:150,y:238,width:724,height:548),xRadius:84,yRadius:84)
    shadow(0.25,blur:30,y:-14) { color(0x7186A7).setFill(); bezel.fill() }
    NSGradient(starting:color(0xB7C8E0),ending:color(0xFFFFFF))!.draw(in:bezel,angle:90)
    let screen = NSBezierPath(roundedRect:NSRect(x:178,y:266,width:668,height:492),xRadius:60,yRadius:60)
    NSGradient(starting:color(0x081426),ending:color(0x263E60))!.draw(in:screen,angle:115)
    color(0xDDEAFD,alpha:0.9).setFill()
    for (y,width) in [(CGFloat(625),CGFloat(300)),(520,450),(415,260)] {
        NSBezierPath(roundedRect:NSRect(x:244,y:y,width:width,height:36),xRadius:18,yRadius:18).fill()
    }
    let arrow = NSBezierPath()
    arrow.move(to:NSPoint(x:650,y:443)); arrow.line(to:NSPoint(x:750,y:369)); arrow.line(to:NSPoint(x:650,y:295))
    arrow.lineWidth = 32; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    color(0x52EFDB).setStroke(); arrow.stroke()
    if detail {
        color(0xFF796B).setFill(); NSBezierPath(ovalIn:NSRect(x:756,y:678,width:22,height:22)).fill()
    }
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current!.imageInterpolation = .high
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        drawIcon(detail: pixels >= 128)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(size)x\(size)\(suffix).png"))
    }
}

func number(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
var chunks = Data()
for (type, name) in [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png"),
    ("ic11", "icon_16x16@2x.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic13", "icon_128x128@2x.png"), ("ic14", "icon_256x256@2x.png")
] {
    let png = try Data(contentsOf: URL(fileURLWithPath: iconset + "/" + name))
    chunks.append(Data(type.utf8))
    chunks.append(number(png.count + 8))
    chunks.append(png)
}
var container = Data("icns".utf8)
container.append(number(chunks.count + 8))
container.append(chunks)
try container.write(to: URL(fileURLWithPath: output))
