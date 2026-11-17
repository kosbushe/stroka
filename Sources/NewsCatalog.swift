import SwiftUI
import AppKit

struct CatalogFeed: Decodable, Identifiable {
    let id:String; let name:String; let url:String; let language:String; let category:String; let availability:String
    var feed:FeedSource { FeedSource(id:UUID(uuidString:"00000000-0000-4000-8000-"+String(format:"%012d",Int(id) ?? 0))!,name:name,url:url,language:language) }
}
enum NewsCatalog {
    static let topics = ["world","business","moscow","technology","ai","science","space","culture","cinema","sport","environment"]
    static func title(_ id:String)->String { L(["world":"World Headlines","business":"Business & Economy","moscow":"Moscow","technology":"Technology","ai":"AI & Research","science":"Science","space":"Space","culture":"Arts & Culture","cinema":"Cinema & Premieres","sport":"Sport","environment":"Environment"][id] ?? "All Topics") }
    static let all:[CatalogFeed] = {
        guard let url = Bundle.main.url(forResource:"NewsCatalog",withExtension:"json"),let data = try? Data(contentsOf:url) else { return [] }
        return (try? JSONDecoder().decode([CatalogFeed].self,from:data)) ?? []
    }()
    static let byURL:[String:CatalogFeed] = Dictionary(all.map{($0.url,$0)},uniquingKeysWith:{first,_ in first})
    static func sources(_ topic:String)->[FeedSource] { all.filter{$0.category == topic}.map(\.feed) }
}
struct NewsCatalogView:View {
    @ObservedObject var model:AppModel; @Environment(\.dismiss) var dismiss
    @State private var search = ""; @State private var language = "all"; @State private var topic = "all"
    var filtered:[CatalogFeed] { NewsCatalog.all.filter { (language == "all" || $0.language == language) && (topic == "all" || $0.category == topic) && (search.isEmpty || ($0.name+" "+$0.url+" "+NewsCatalog.title($0.category)).localizedCaseInsensitiveContains(search)) }.sorted { ($0.availability == "checked" ? 0 : 1,$0.name)<($1.availability == "checked" ? 0 : 1,$1.name) } }
    func contains(_ feed:CatalogFeed)->Bool { model.settings.customFeeds?.contains(where:{$0.url == feed.url}) == true }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { VStack(alignment:.leading,spacing:5) { Text(L("News Sources")).font(.title.weight(.semibold)); Text(L("Build your own newsroom from public RSS and Atom feeds.")).foregroundStyle(.secondary) }; Spacer(); Button(L("Done")) { dismiss() }.keyboardShortcut(.cancelAction) }
            HStack { TextField(L("Search sources"),text:$search).textFieldStyle(.roundedBorder); Picker(L("Language"),selection:$language) { Text(L("All Languages")).tag("all"); Text(L("English")).tag("en"); Text(L("Russian")).tag("ru") }.frame(width:230) }
            HStack { Picker(L("Topic"),selection:$topic) { Text(L("All Topics")).tag("all"); ForEach(NewsCatalog.topics,id:\.self) { Text(NewsCatalog.title($0)).tag($0) } }; Spacer(); Text(LF("%ld sources",filtered.count)).font(.caption).foregroundStyle(.secondary) }
            ScrollView { LazyVStack(spacing:0) { ForEach(filtered) { row in
                HStack(spacing:14) {
                    Text(row.language.uppercased()).font(.system(size:11,weight:.semibold,design:.monospaced)).foregroundStyle(.secondary).frame(width:34,height:32).background(.quaternary,in:RoundedRectangle(cornerRadius:7))
                    VStack(alignment:.leading,spacing:4) { Text(row.name).font(.system(size:14,weight:.semibold)); Text(NewsCatalog.title(row.category)+" · "+(URL(string:row.url)?.host ?? "RSS")).font(.caption).foregroundStyle(.secondary);if row.availability == "timeout" { Text(L("Connection not verified in the latest check")).font(.caption).foregroundStyle(.orange) } }
                    Spacer()
                    Button { openLink(row.url) } label: { Image(systemName:"arrow.up.right") }.buttonStyle(.plain).accessibilityLabel(L("Open source feed"))
                    Button { if contains(row) { model.settings.customFeeds?.removeAll{$0.url == row.url} } else { model.settings.customFeeds = (model.settings.customFeeds ?? [])+[row.feed] } } label: { Label(contains(row) ? L("Added") : L("Add"),systemImage:contains(row) ? "checkmark" : "plus").fixedSize(horizontal:true,vertical:false).frame(minWidth:104) }
                }.padding(.vertical,12); Divider()
            } } }
            HStack { Text(L("Choose sources, then open Your RSS Feeds to show them together.")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(L("Show My Feeds")) { model.settings.channel = .content; if model.dualBandActive { model.settings.dualUpperChannel = .content }; model.selectPack("custom"); model.refreshContent(); dismiss() }.buttonStyle(.borderedProminent).disabled((model.settings.customFeeds ?? []).isEmpty) }
        }.padding(28).frame(width:780,height:650)
    }
}
