import AppKit

@main enum MessageSeparatorsTests {
    static func main() {
        var count = 0
        func check(_ ok:Bool,_ message:String){guard ok else{fatalError(message)};count += 1;print("PASS: \(message)")}
        check(MessageSeparators.options == ["│││","││","─","•••","***","●"],"six requested neutral options")
        check(MessageSeparators.resolve(nil) == "│││" && MessageSeparators.resolve(" \n ") == "│││","default and empty settings stay visible")
        for legacy in ["▌▌▌","///","🇫🇷","🇷🇺"] {check(MessageSeparators.resolve(legacy) == "│││","legacy flag/slashes normalize to neutral bars")}
        check(MessageSeparators.resolve("◆") == "●","legacy diamond becomes the circle option")
        check(MessageSeparators.resolve("123456789012345").count == 12,"custom separators remain bounded")
        check(MessageSeparators.resolve("  a\nb  ") == "a b","newlines cannot break the ticker row")
        let font = NSFont.systemFont(ofSize:22)
        for token in MessageSeparators.options {
            let marker = MessageSeparators.marker(token,font:font,accent:.orange)
            check(marker.string == "   \(token)   ","exact token and boundary spacing: \(token)")
            var monochrome = true
            marker.enumerateAttributes(in:NSRange(location:0,length:marker.length)){attributes,_,_ in
                monochrome = monochrome && (attributes[.foregroundColor] as? NSColor == .orange) && attributes[.strokeColor] == nil
            }
            check(monochrome,"no flag coloring: \(token)")
            check(marker.size().width.isFinite && marker.size().width>font.pointSize,"marker has finite visible width: \(token)")
        }
        check(MessageSeparators.marker("▌▌▌",font:font,accent:.orange).string.contains("│││"),"legacy rendering cannot reintroduce a flag")
        if CommandLine.arguments.count>1 {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1000,pixelsHigh:700,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
            for (column,dark) in [false,true].enumerated() {
                (dark ? NSColor.black:NSColor.white).setFill();NSRect(x:column*500,y:0,width:500,height:700).fill()
                for (i,token) in MessageSeparators.options.enumerated() {
                    let ink:NSColor = dark ? .white:.black
                    let text = NSMutableAttributedString(string:"Новость",attributes:[.font:font,.foregroundColor:ink]);text.append(MessageSeparators.marker(token,font:font,accent:dark ? .white:.systemRed));text.append(NSAttributedString(string:"Следующая новость",attributes:[.font:font,.foregroundColor:ink]))
                    text.draw(at:NSPoint(x:column*500+20,y:610-i*105))
                }
            }
            NSGraphicsContext.restoreGraphicsState();try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
        }
        print("\(count) separator checks passed")
    }
}
