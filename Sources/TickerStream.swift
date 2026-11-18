import AppKit
import CoreText

struct TickerStreamWindow {
    let text: NSAttributedString
    let size: CGSize
    let advance: CGFloat
    let currentWidth: CGFloat
    static func width(_ text: NSAttributedString) -> CGFloat { max(1,CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text),nil,nil,nil))) }
    static func marker(_ separator:String,font:NSFont,accent:NSColor)->NSAttributedString {
        MessageSeparators.marker(separator,font:font,accent:accent)
    }
    static func make(messages:[String],index:Int,separator:String,font:NSFont,ink:NSColor,accent:NSColor,viewport:CGFloat,reverse:Bool,glow:Bool = false,displayText:(String)->String = {$0}) -> Self? {
        guard !messages.isEmpty else { return nil }
        let marker = marker(separator,font:font,accent:accent)
        var pieces:[NSAttributedString] = []; var total:CGFloat = 0; var advance:CGFloat = 0
        var firstWidth:CGFloat = 0
        // Only prepare enough adjacent items to cover the viewport and one outgoing item.
        // Long messages remain tile-backed; this does not allocate a full-width bitmap.
        for offset in 0..<256 {
            let item = displayText(messages[((index+offset)%messages.count+messages.count)%messages.count])
            let part = NSMutableAttributedString(string:String(item.prefix(6000)),attributes:[.font:font,.foregroundColor:ink]); part.append(marker)
            let w = width(part)
            if offset == 0 { advance = w; firstWidth = w-width(marker) }
            pieces.append(part); total += w
            if total >= viewport+advance+64 { break }
        }
        let text = NSMutableAttributedString(string:"")
        for piece in reverse ? Array(pieces.reversed()) : pieces { text.append(piece) }
        if glow { let shadow = NSShadow(); shadow.shadowColor = ink.withAlphaComponent(0.8); shadow.shadowBlurRadius = 16; shadow.shadowOffset = .zero; text.addAttribute(.shadow,value:shadow,range:NSRange(location:0,length:text.length)) }
        return Self(text:text,size:CGSize(width:width(text),height:ceil(max(text.size().height,font.ascender-font.descender+font.leading))),advance:max(1,advance),currentWidth:firstWidth)
    }
}
struct TickerStreamKey: Equatable {
    var rows:[String]; var revision:Int; var index:Int; var separator:String; var size:CGFloat; var look:Look; var viewport:CGFloat; var reverse:Bool; var source:Bool; var brand:String
}
extension TickerView {
    var messageRows:[String] { guard let model else { return [] }; if preview && isMarketLane && model.quotes.isEmpty {return [L("Market prices")]}; return model.settings.tickerRows != nil ? model.rowLines(rowIndex) : isMarketLane ? model.quotes.map(\.line) : model.lines }
    func streamWindow(fontSize:CGFloat,look:Look,viewport:CGFloat,reverse:Bool) -> TickerStreamWindow? {
        guard let model else { return nil }; let rows = messageRows
        let key = TickerStreamKey(rows:rows,revision:model.textRevision,index:localIndex,separator:model.settings.resolvedSeparator,size:fontSize,look:look,viewport:viewport,reverse:reverse,source:model.settings.broadcastSource ?? true,brand:model.settings.brand)
        if key == streamKey { return cachedStream }
        // Format only the adjacent items required by make(), not the complete feed.
        let window = TickerStreamWindow.make(messages:rows,index:localIndex,separator:model.settings.resolvedSeparator,font:displayFont(size:fontSize,look:look),ink:look.ink,accent:look.accent,viewport:viewport,reverse:reverse,glow:look == .neon) { raw in
            guard !isMarketLane, look.isBroadcast else { return raw }
            let record = model.settings.tickerRows != nil ? model.rowRecord(raw,index:rowIndex) : model.record(for:raw)
            if !record.isOffline && channelToken != .message && (model.settings.broadcastSource ?? true) && !record.source.isEmpty { return record.source + (record.isTranslated ? " · "+L("Translated") : "") + " · " + record.text }
            return record.text
        }
        streamKey = key; cachedStream = window; return window
    }
}
