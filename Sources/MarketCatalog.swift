import Foundation
import SwiftUI

struct MarketInstrument:Codable,Identifiable {
    let id:String; let symbol:String; let name:String; let kind:String; let currency:String
}
enum MarketCatalog {
    static let defaults = ["index:IMOEX","index:RTSI","share:SBER","share:GAZP","share:LKOH","share:YDEX","currency:USD","currency:EUR","currency:CNY","ecb:USD","ecb:GBP"]
    static let all:[MarketInstrument] = {
        guard let url = Bundle.main.url(forResource:"MarketCatalog",withExtension:"json"),let data = try? Data(contentsOf:url) else { return [] };return (try? JSONDecoder().decode([MarketInstrument].self,from:data)) ?? []
    }()
    static func name(_ kind:String)->String { L(["index":"Indices","share":"Shares","currency":"Currency Rates","euro":"Euro Reference Rates"][kind] ?? kind) }
}
enum QuoteCadence:String { case stream, delayed, index, daily, close }
extension Quote {
    var displayValue:String { formatted+(currency.map { " "+$0 } ?? "") }
    var dataNote:String { switch cadence { case .daily:return L("Official daily rate");case .close:return L("Previous close");case .delayed:return L("Delayed · 15 min");case .index:return L("Exchange index");case .stream:return L("Trade stream");case nil:return source == "Coinbase" ? L("Trade stream") : source == "MOEX" ? L("Exchange index") : source } }
    var timeLabel:String {
        var day = Date.FormatStyle(date:.abbreviated,time:.omitted).locale(Localization.locale)
        if cadence == .daily || cadence == .close { day.timeZone = TimeZone(identifier:"Europe/Moscow")!;return time.formatted(day) }
        let c = Calendar.current.dateComponents([.hour,.minute],from:time)
        let clock = String(format:"%02d:%02d",c.hour ?? 0,c.minute ?? 0)
        return Calendar.current.isDateInToday(time) ? clock : time.formatted(day)+" "+clock
    }
}
extension AppModel {
    var selectedMarketIDs:[String] { settings.marketInstruments ?? MarketCatalog.defaults }
    var selectedInstruments:[MarketInstrument] { let ids = Set(selectedMarketIDs);return marketUniverse.filter{ids.contains($0.id)} }
    func selectInstrument(_ id:String,enabled:Bool) {
        var ids = Set(selectedMarketIDs);if enabled { ids.insert(id) } else { ids.remove(id) };settings.marketInstruments = ids.sorted()
    }
}
struct MarketPickerView:View {
    @ObservedObject var model:AppModel; @Environment(\.dismiss) var dismiss
    @State private var search = ""; @State private var kind = "all"
    var cryptoPairs:[String] {Array(Set(["BTC-USD","ETH-USD","SOL-USD"]+model.settings.cryptoPairs.uppercased().components(separatedBy:CharacterSet(charactersIn:", \n")).filter{!$0.isEmpty})).sorted().filter{search.isEmpty || $0.localizedCaseInsensitiveContains(search)}}
    var filtered:[MarketInstrument] { model.marketUniverse.filter { (kind == "all" || $0.kind == kind) && (search.isEmpty || ($0.symbol+" "+$0.name).localizedCaseInsensitiveContains(search)) } }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text(L("Market Instruments")).font(.title.weight(.semibold)); Spacer(); Button(L("Done")) { dismiss() }.keyboardShortcut(.cancelAction) }
            Text(L("Choose shares, indices and official currency rates for your ticker.")).foregroundStyle(.secondary)
            HStack { TextField(L("Search instruments"),text:$search).textFieldStyle(.roundedBorder);Picker(L("Type"),selection:$kind) { Text(L("All Types")).tag("all");Text(L("Cryptocurrency")).tag("crypto");ForEach(["index","share","currency","euro"],id:\.self) { Text(MarketCatalog.name($0)).tag($0) } }.frame(width:240) }
            HStack { Button(L("Update Instrument Catalog")) { model.market.refreshCatalog() };Text(model.marketCatalogStatus).font(.caption).foregroundStyle(.secondary) }
            ScrollView { LazyVStack(spacing:0) {
                if kind == "all" || kind == "crypto" {ForEach(cryptoPairs,id:\.self){pair in Toggle(isOn:Binding(get:{model.hasCrypto(pair)},set:{model.setSimpleCrypto(pair,enabled:$0)})){HStack{Text(pair).font(.system(size:13,weight:.semibold,design:.monospaced)).frame(width:100,alignment:.leading);Text("Coinbase · "+L("Trade stream")).font(.system(size:12)).foregroundStyle(.secondary);Spacer()}}.toggleStyle(.checkbox).padding(.vertical,10);Divider()}}
                ForEach(filtered) { item in
                Toggle(isOn:Binding(get:{model.selectedMarketIDs.contains(item.id)},set:{model.selectInstrument(item.id,enabled:$0)})) {
                    HStack { Text(item.symbol).font(.system(size:13,weight:.semibold,design:.monospaced)).frame(width:100,alignment:.leading); VStack(alignment:.leading,spacing:4) { Text(item.name).font(.system(size:13));Text(MarketCatalog.name(item.kind)+" · "+item.currency+" · "+((item.kind == "currency" || item.kind == "euro") ? L("Official daily rate") : item.kind == "share" ? L("Delayed · 15 min") : "MOEX ISS")).font(.caption).foregroundStyle(.secondary) };Spacer() }
                }.toggleStyle(.checkbox).padding(.vertical,10);Divider()
            } } }
            HStack { Button(L("Market Mix")) { model.settings.marketInstruments = MarketCatalog.defaults };Button(L("Clear Selection")) { model.settings.marketInstruments = [];model.settings.cryptoPairs = "" }; Spacer();Text(LF("%ld selected",model.selectedMarketIDs.count)).font(.caption).foregroundStyle(.secondary) }
            Text(L("MOEX shares may be delayed by 15 minutes. Central-bank rates are daily reference values, not tradable prices.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(28).frame(width:730,height:650)
    }
}
