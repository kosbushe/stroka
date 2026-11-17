import Foundation

// Column names, nominal values and provider dates are part of the data contract.
// Missing prices are never converted to zero or stamped with the receipt time.
enum OpenMarketData {
    static func table(_ value:Any?)->[[String:Any]] {
        guard let table = value as? [String:Any],let columns = table["columns"] as? [String],let rows = table["data"] as? [[Any]] else { return [] }
        return rows.map { row in Dictionary(zip(columns,row),uniquingKeysWith:{_,last in last}) }
    }
    static func number(_ value:Any?)->Double? { if let n = value as? NSNumber { return n.doubleValue };return (value as? String).flatMap(Double.init) }
    static func date(_ text:String,format:String = "yyyy-MM-dd HH:mm:ss")->Date? {
        let f = DateFormatter();f.locale = Locale(identifier:"en_US_POSIX");f.timeZone = TimeZone(identifier:"Europe/Moscow");f.dateFormat = format;return f.date(from:text)
    }
    static func moex(_ data:Data,kind:String,selected:[MarketInstrument],received:Date = Date())->[Quote] {
        guard let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [] }
        let securities = Dictionary(table(json["securities"]).compactMap { row -> (String,[String:Any])? in guard let id = row["SECID"] as? String else { return nil };return (id,row) },uniquingKeysWith:{$1})
        let lookup = Dictionary(uniqueKeysWithValues:selected.map{($0.symbol,$0)})
        return table(json["marketdata"]).compactMap { row in
            guard let id = row["SECID"] as? String,let item = lookup[id] else { return nil }
            let sec = securities[id] ?? [:]
            let price = number(row[kind == "index" ? "CURRENTVALUE" : "LAST"])
            let day = row["TRADEDATE"] as? String ?? (row["SYSTIME"] as? String).map{String($0.prefix(10))}
            let stamp = (row["SYSTIME"] as? String).flatMap{date($0)} ?? day.flatMap { d in (row["UPDATETIME"] as? String).flatMap { date(d+" "+$0) } }
            if let price,price.isFinite,price > 0,let stamp {
                return Quote(id:id,value:price,change:number(row[kind == "index" ? "LASTCHANGEPRC" : "LASTTOPREVPRICE"]),time:stamp,received:received,source:"MOEX",currency:item.currency,label:item.name,cadence:kind == "index" ? .index : .delayed,instrumentID:item.id)
            }
            let previous = number(sec["PREVPRICE"]) ?? number(row["LASTVALUE"])
            let previousDay = sec["PREVDATE"] as? String ?? row["TRADEDATE"] as? String
            guard let previous,previous.isFinite,previous > 0,let day = previousDay,let date = date(day,format:"yyyy-MM-dd") else { return nil }
            return Quote(id:id,value:previous,change:nil,time:date,received:received,source:"MOEX",currency:item.currency,label:item.name,cadence:.close,instrumentID:item.id)
        }
    }
}
final class CBRRateReader:NSObject,XMLParserDelegate {
    var date:Date?;var rows:[String:(Double,String)] = [:];var field = "";var buffer = "";var code = "";var nominal = 1.0;var value:Double?;var name = ""
    func read(_ data:Data)->[Quote] {
        let p = XMLParser(data:data);p.shouldResolveExternalEntities = false;p.delegate = self;guard p.parse(),let date else { return [] }
        return rows.map { Quote(id:$0.key+"/RUB",value:$0.value.0,change:nil,time:date,received:Date(),source:"CBR",currency:"RUB",label:$0.value.1,cadence:.daily,instrumentID:"currency:"+$0.key) }
    }
    func parser(_ parser:XMLParser,didStartElement element:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        if element == "ValCurs" { date = attributes["Date"].flatMap{OpenMarketData.date($0,format:"dd.MM.yyyy")} }
        if element == "Valute" { code = "";nominal = 1;value = nil;name = "" }
        field = element;buffer = ""
    }
    func parser(_ parser:XMLParser,foundCharacters text:String) { buffer += text }
    func parser(_ parser:XMLParser,didEndElement element:String,namespaceURI:String?,qualifiedName:String?) {
        let text = buffer.trimmingCharacters(in:.whitespacesAndNewlines)
        if element == field { switch element { case "CharCode":code = text;case "Nominal":nominal = Double(text) ?? 0;case "Value":value = Double(text.replacingOccurrences(of:",",with:"."));case "Name":name = text;default:break } }
        if element == "Valute",!code.isEmpty,nominal > 0,let value,value.isFinite,value > 0 { rows[code] = (value/nominal,name) }
        buffer = "";field = ""
    }
}
extension MarketService {
    func refreshWatchlist() {
        referenceGeneration += 1;referenceTasks.forEach{$0.cancel()};referenceTasks = [];fetching = false
        guard let model else { return };let selected = Set(model.selectedMarketIDs)
        model.quotes.removeAll { quote in if let id = quote.instrumentID { return !selected.contains(id) };return quote.source == "MOEX" && !selected.contains("index:"+quote.id) && !selected.contains("share:"+quote.id) }
        lastCBR = .distantPast;lastECB = .distantPast;fetchMOEX()
    }
    func fetchMOEX() {
        guard let model,isRunning,!fetching else { return };fetching = true
        let gen = referenceGeneration;let items = model.selectedInstruments;let group = DispatchGroup();var notes:[String] = []
        func request(_ url:URL,kind:String,selection:[MarketInstrument]) {
            group.enter()
            let task = model.session.dataTask(with:url) { [weak self] data,response,error in
                let valid = (response as? HTTPURLResponse)?.statusCode == 200
                let parsed:[Quote] = valid ? data.map { kind == "currency" || kind == "euro" ? (kind == "currency" ? CBRRateReader().read($0) : ECBRateReader().read($0)).filter{q in selection.contains{$0.id == q.instrumentID}} : OpenMarketData.moex($0,kind:kind,selected:selection) } ?? [] : []
                DispatchQueue.main.async {
                    defer { group.leave() };guard let self,self.isRunning,self.referenceGeneration == gen else { return }
                    for quote in parsed { self.update(quote) }
                    if kind == "currency",!parsed.isEmpty { self.lastCBR = Date() };if kind == "euro",!parsed.isEmpty { self.lastECB = Date() }
                    notes.append(MarketCatalog.name(kind)+": "+(parsed.isEmpty ? L("Unavailable · will retry") : LF("%ld instruments",parsed.count)))
                }
            };referenceTasks.append(task);task.resume()
        }
        for kind in ["index","share"] {
            let selection = items.filter{$0.kind == kind};guard !selection.isEmpty else { continue }
            let route = kind == "share" ? "shares/boards/TQBR" : "index"
            var components = URLComponents(string:"https://iss.moex.com/iss/engines/stock/markets/\(route)/securities.json")!
            components.queryItems = [URLQueryItem(name:"iss.meta",value:"off"),URLQueryItem(name:"iss.only",value:"securities,marketdata"),URLQueryItem(name:"securities",value:selection.map(\.symbol).joined(separator:","))]
            request(components.url!,kind:kind,selection:selection)
        }
        let rates = items.filter{$0.kind == "currency"}
        if !rates.isEmpty,Date().timeIntervalSince(lastCBR)>3600 { request(URL(string:"https://www.cbr.ru/scripts/XML_daily.asp")!,kind:"currency",selection:rates) }
        let euro = items.filter{$0.kind == "euro"}
        if !euro.isEmpty,Date().timeIntervalSince(lastECB)>3600 { request(URL(string:"https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!,kind:"euro",selection:euro) }
        group.notify(queue:.main) { [weak self] in guard let self,self.referenceGeneration == gen else { return };self.fetching = false;self.referenceTasks = [];if !notes.isEmpty { self.model?.moexStatus = notes.joined(separator:" · ") } }
    }
}

extension MarketService {
    func refreshCatalog() {
        guard let model,!catalogFetching else { return };catalogFetching = true;catalogGeneration += 1
        let gen = catalogGeneration;let group = DispatchGroup();var received:[MarketInstrument] = [];var successful = Set<String>()
        model.marketCatalogStatus = L("Updating catalog…")
        for kind in ["share","index","currency"] {
            let address = kind == "currency" ? "https://www.cbr.ru/scripts/XML_daily.asp" : "https://iss.moex.com/iss/engines/stock/markets/\(kind == "share" ? "shares/boards/TQBR" : "index")/securities.json?iss.meta=off&iss.only=securities"
            group.enter();model.session.dataTask(with:URL(string:address)!) { [weak self] data,response,_ in
                var rows:[MarketInstrument] = []
                if (response as? HTTPURLResponse)?.statusCode == 200,let data {
                    if kind == "currency" { rows = CBRRateReader().read(data).compactMap { quote in guard let id = quote.instrumentID else { return nil };return MarketInstrument(id:id,symbol:String(quote.id.prefix(3)),name:quote.label ?? quote.id,kind:kind,currency:"RUB") } }
                    else if let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any] {
                        rows = OpenMarketData.table(json["securities"]).compactMap { row in
                            guard let id = row["SECID"] as? String else { return nil }
                            return MarketInstrument(id:kind+":"+id,symbol:id,name:row["SECNAME"] as? String ?? row["NAME"] as? String ?? row["SHORTNAME"] as? String ?? id,kind:kind,currency:kind == "index" ? "pts" : (["SUR","RUR"].contains(row["CURRENCYID"] as? String ?? "SUR") ? "RUB" : row["CURRENCYID"] as? String ?? "RUB"))
                        }
                    }
                }
                let parsed = rows
                DispatchQueue.main.async { defer { group.leave() };guard let self,self.catalogGeneration == gen else { return };if !parsed.isEmpty { received += parsed;successful.insert(kind) } }
            }.resume()
        }
        group.notify(queue:.main) { [weak self] in
            guard let self,let model = self.model,self.catalogGeneration == gen else { return };self.catalogFetching = false
            guard !received.isEmpty else { model.marketCatalogStatus = L("Catalog unavailable · saved list kept");return }
            let merged = model.marketUniverse.filter{!successful.contains($0.kind)}+received
            model.marketUniverse = Dictionary(merged.map{($0.id,$0)},uniquingKeysWith:{$1}).values.sorted { ($0.kind,$0.symbol)<($1.kind,$1.symbol) }
            if let data = try? JSONEncoder().encode(model.marketUniverse) { model.defaults.set(data,forKey:"marketCatalog") }
            model.marketCatalogStatus = LF("%ld instruments",model.marketUniverse.count)
            if self.isRunning { self.refreshWatchlist() }
        }
    }
}

final class ECBRateReader:NSObject,XMLParserDelegate {
    var date:Date?;var values:[String:Double] = [:]
    func read(_ data:Data)->[Quote] {
        let p = XMLParser(data:data);p.shouldResolveExternalEntities = false;p.delegate = self;guard p.parse(),let date else { return [] }
        return values.map { Quote(id:"EUR/"+$0.key,value:$0.value,change:nil,time:date,received:Date(),source:"ECB",currency:$0.key,label:"Euro / "+$0.key,cadence:.daily,instrumentID:"ecb:"+$0.key) }
    }
    func parser(_ parser:XMLParser,didStartElement element:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        if let text = attributes["time"] { date = OpenMarketData.date(text,format:"yyyy-MM-dd") }
        if let currency = attributes["currency"],let raw = attributes["rate"],let value = Double(raw),value.isFinite,value > 0 { values[currency] = value }
    }
}
