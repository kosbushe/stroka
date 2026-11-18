import AppKit

enum MessageSeparators {
    static let standard = "│││"
    static let options = ["│││","││","─","•••","***","●"]
    static func labelKey(_ token:String)->String {
        ["│││":"Three vertical bars","││":"Two vertical bars","─":"Horizontal bar","•••":"Three dots","***":"Three stars","●":"Large circle"][token] ?? "Custom"
    }
    static func resolve(_ raw:String?)->String {
        let value = String((raw ?? standard).components(separatedBy:.newlines).joined(separator:" ").trimmingCharacters(in:.whitespacesAndNewlines).prefix(12))
        switch value {
        case "","▌▌▌","///","🇫🇷","🇷🇺":return standard
        case "◆","◇":return "●"
        default:return value
        }
    }
    static func marker(_ raw:String,font:NSFont,accent:NSColor)->NSAttributedString {
        let separator = resolve(raw)
        let result = NSMutableAttributedString(string:"   \(separator)   ",attributes:[.font:NSFont.systemFont(ofSize:font.pointSize,weight:.semibold),.foregroundColor:accent])
        if separator == "●" {result.addAttribute(.font,value:NSFont.systemFont(ofSize:font.pointSize*1.1,weight:.semibold),range:NSRange(location:3,length:1))}
        return result
    }
}
