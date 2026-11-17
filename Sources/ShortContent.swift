import Foundation
import NaturalLanguage

enum ShortText {
    static let limit = 11
    static func count(_ text:String)->Int { text.split(whereSeparator:{$0.isWhitespace}).filter{$0.unicodeScalars.contains{CharacterSet.alphanumerics.contains($0)}}.count }
    static func fits(_ text:String)->Bool { let n = count(text);return n>0 && n<=limit }
    static func preview(_ text:String)->(String,Bool) {
        let clean = text.trimmingCharacters(in:.whitespacesAndNewlines)
        let lines = clean.components(separatedBy:.newlines).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter{count($0)>0}
        guard let line = lines.first else { return ("",false) }
        let words = line.split(whereSeparator:{$0.isWhitespace})
        if fits(line) { return (line,count(clean)>count(line)) }
        var output:[String] = [];var length = 0
        for word in words { if count(String(word))>0 { if length == limit { break };length += 1 };output.append(String(word)) }
        return (output.joined(separator:" ").trimmingCharacters(in:CharacterSet(charactersIn:" -–—,:;"))+"…",true)
    }
    static func plainHTML(_ html:String)->String {
        var text = html.replacingOccurrences(of:"<(script|style)\\b[^>]*>[\\s\\S]*?</\\1>",with:"",options:.regularExpression)
        text = text.replacingOccurrences(of:"<br\\s*/?>|</p>",with:"\n",options:[.regularExpression,.caseInsensitive]).replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)
        let named = ["nbsp":" ","quot":"\"","apos":"'","lt":"<","gt":">","amp":"&","ndash":"–","mdash":"—","hellip":"…","laquo":"«","raquo":"»"]
        let pattern = try! NSRegularExpression(pattern:"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
        let value = text as NSString;let result = NSMutableString(string:text)
        for match in pattern.matches(in:text,range:NSRange(location:0,length:value.length)).reversed() {
            let token = value.substring(with:match.range(at:1));let number:UInt32? = token.hasPrefix("#x") ? UInt32(token.dropFirst(2),radix:16) : token.hasPrefix("#") ? UInt32(token.dropFirst()) : nil
            let replacement = number.flatMap(UnicodeScalar.init).map(String.init) ?? named[token]
            if let replacement { result.replaceCharacters(in:match.range,with:replacement) }
        }
        return (result as String).replacingOccurrences(of:"[ \\t]+",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
    }
}
enum TelegramPublicReader {
    static func username(_ input:String)->String? {
        var value = input.trimmingCharacters(in:.whitespacesAndNewlines)
        if value.lowercased().hasPrefix("t.me/") || value.lowercased().hasPrefix("telegram.me/") {value = "https://"+value}
        if value.hasPrefix("@") {value.removeFirst()}
        else if let url = URL(string:value),url.scheme == "https",["t.me","telegram.me"].contains(url.host?.lowercased() ?? ""),url.user == nil,url.password == nil {
            let pieces = url.pathComponents.filter{$0 != "/"};guard let name = pieces.first == "s" ? pieces.dropFirst().first : pieces.first else{return nil};value = name
        } else {return nil}
        return value.range(of:"^[A-Za-z][A-Za-z0-9_]{2,31}$",options:.regularExpression) != nil ? value.lowercased() : nil
    }
    static func read(_ data:Data,source:FeedSource)->[Story] {
        guard data.count<=3_000_000,let html = String(data:data,encoding:.utf8),let name = username(source.url) else { return [] }
        let expression = try! NSRegularExpression(pattern:"data-post=\"("+NSRegularExpression.escapedPattern(for:name)+"/[0-9]+)\"",options:.caseInsensitive)
        let ns = html as NSString;let matches = expression.matches(in:html,range:NSRange(location:0,length:ns.length));var seen = Set<String>();var rows:[Story] = []
        func capture(_ pattern:String,in text:String)->String? { guard let re = try? NSRegularExpression(pattern:pattern,options:[.dotMatchesLineSeparators,.caseInsensitive]),let m = re.firstMatch(in:text,range:NSRange(location:0,length:(text as NSString).length)) else { return nil };return (text as NSString).substring(with:m.range(at:1)) }
        for (index,match) in matches.enumerated() {
            let id = ns.substring(with:match.range(at:1));guard seen.insert(id).inserted else { continue }
            let start = NSMaxRange(match.range),end = index+1<matches.count ? matches[index+1].range.location : ns.length
            let block = ns.substring(with:NSRange(location:start,length:end-start))
            guard let body = capture("<div\\b[^>]*class=\"[^\"]*tgme_widget_message_text[^\"]*\"[^>]*>(.*?)</div>",in:block) else { continue }
            let (text,excerpt) = ShortText.preview(ShortText.plainHTML(body));guard ShortText.fits(text) else { continue }
            let ownDate = "<a\\b[^>]*href=\"https://t\\.me/"+NSRegularExpression.escapedPattern(for:id)+"\"[^>]*>\\s*<time\\b[^>]*datetime=\"([^\"]+)\""
            let stamp = (capture(ownDate,in:block) ?? capture("<time\\b[^>]*datetime=\"([^\"]+)\"",in:block)).flatMap(parseDate)
            rows.append(Story(id:"https://t.me/"+id,text:text,source:source.name,date:stamp,link:"https://t.me/"+id,language:source.language ?? NLLanguageRecognizer.dominantLanguage(for:text)?.rawValue,isExcerpt:excerpt))
        }
        return Array(rows.suffix(40))
    }
}
extension FeedSource {
    var isTelegram:Bool { guard let url = URL(string:url) else { return false };return url.scheme == "https" && url.host?.lowercased() == "t.me" && url.path.hasPrefix("/s/") && TelegramPublicReader.username(self.url) != nil }
}
