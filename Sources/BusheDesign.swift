import AppKit
import SwiftUI

/// Bushe Design 1.0. Reference: Clock & Timer 3.0, SettingsView and Glass theme.
enum BusheDesign {
    static let page: CGFloat = 21
    static let gap: CGFloat = 8
    static let section: CGFloat = 21
    static let controlRadius: CGFloat = 8
    static let displayRadius: CGFloat = 16
    static let midnight = NSColor(srgbRed: 0.035, green: 0.043, blue: 0.075, alpha: 1)
    static let blue = NSColor(srgbRed: 0.25, green: 0.40, blue: 0.72, alpha: 1)
    static let amber = NSColor(srgbRed: 1, green: 0.62, blue: 0.04, alpha: 1)
    static func glass(in rect: NSRect) {
        NSGradient(colors: [midnight, NSColor(srgbRed:0.075,green:0.105,blue:0.18,alpha:1), NSColor(srgbRed:0.025,green:0.03,blue:0.055,alpha:1)])!.draw(in:rect,angle:-55)
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:rect).addClip()
        for (color, x, y, alpha) in [(blue,0.12,0.18,0.42),(amber,0.94,-0.45,0.26)] {
            let center = NSPoint(x:rect.minX+rect.width*x,y:rect.minY+rect.height*y)
            NSGradient(starting:color.withAlphaComponent(alpha),ending:color.withAlphaComponent(0))!.draw(fromCenter:center,radius:0,toCenter:center,radius:max(rect.width*0.8,rect.height*1.35),options:.drawsAfterEndingLocation)
        }
        NSColor.white.withAlphaComponent(0.07).setFill(); NSRect(x:rect.minX,y:rect.maxY-1,width:rect.width,height:1).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
struct BusheChoiceStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth:.infinity,minHeight:32).contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(configuration.isPressed ? 0.09 : 0.045),in:RoundedRectangle(cornerRadius:BusheDesign.controlRadius))
            .overlay(RoundedRectangle(cornerRadius:BusheDesign.controlRadius).strokeBorder(selected ? Color.accentColor.opacity(0.5) : .clear))
    }
}

extension BusheDesign {
    static func tickerGlass(in rect:NSRect) {
        NSGradient(starting:hex(0x303C4D),ending:hex(0x141B25))!.draw(in:rect,angle:-90)
        NSColor.white.withAlphaComponent(0.13).setFill();CGRect(x:rect.minX,y:rect.maxY-1,width:rect.width,height:1).fill()
    }
}
