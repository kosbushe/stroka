import SwiftUI

struct ContentGroup:Identifiable {
    let id:String;let title:String;let ids:[String]
    var packs:[ContentPack] { ids.map{ContentPack.find($0)} }
}
enum ContentCatalog {
    static let groups:[ContentGroup] = [
        .init(id:"news",title:"News & Knowledge",ids:["world","business","moscow","technology","ai","science","space","environment","sport"]),
        .init(id:"culture",title:"Culture & Entertainment",ids:["cinema","culture","thoughts","jokes","riddles"]),
        .init(id:"events",title:"For Events & Conversations",ids:["conversation","ideas"]),
        .init(id:"yours",title:"Your Channels & Websites",ids:["telegram","custom"])
    ]
    static var packs:[ContentPack] { groups.flatMap(\.packs) }
    static let navigation:[Channel] = [.message,.content,.markets]
    static func matches(_ pack:ContentPack,search:String)->Bool {
        let query = search.trimmingCharacters(in:.whitespacesAndNewlines)
        return query.isEmpty || (L(pack.catalogTitle)+" "+L(pack.catalogDetail)+" "+pack.catalogExamples+" "+L(pack.section)+" "+pack.sources.map(\.name).joined(separator:" ")).localizedCaseInsensitiveContains(query)
    }
}
extension ContentPack {
    var catalogTitle:String { id == "custom" ? "Your Sources" : name }
    var catalogDetail:String {
        switch id {
        case "world":return "World events and the day's main headlines."
        case "business":return "Companies, markets and ideas for your business."
        case "moscow":return "What is happening in the city: transport, places and events."
        case "technology":return "New products, digital culture and the people building technology."
        case "science":return "Discoveries that change how we understand the world."
        case "space":return "Launches, distant planets and space exploration."
        case "environment":return "Nature, climate and the world around us."
        case "sport":return "Matches, results and stories from the world of sport."
        case "cinema":return "New films, premiere announcements and cinema news."
        case "culture":return "Books, music, exhibitions and creative life."
        case "thoughts":return "Short original thoughts to brighten the day."
        case "jokes":return "Light humour for a break, a table or a busy day."
        case "riddles":return "A quick puzzle with its answer in the same message."
        case "conversation":return "Questions that help guests start a conversation."
        case "ideas":return "Small creative challenges for a meeting or workshop."
        case "telegram":return "Updates from your chosen public Telegram channels."
        case "custom":return "Choose publishers or add your own websites and channels."
        default:return detail
        }
    }
    var catalogExamples:String {
        if offline { return BuiltinCollections.stories(pack:self,language:Localization.language == .russian ? .russian : .english).first?.text ?? "" }
        if id == "custom" { return L("Publishers, RSS / Atom, public Telegram channels") }
        return sources.prefix(3).map(\.name).joined(separator:" · ")
    }
}
extension AppModel {
    // Keep old feeds/presets intact; remove the legacy AI navigation route from current use.
    @discardableResult func normalizeContentNavigation()->Bool {
        var changed = false
        if settings.channel == .ai { settings.channel = .content;changed = true }
        if settings.dualUpperChannel == .ai { settings.dualUpperChannel = .content;changed = true }
        return changed
    }
    func activateContentPack(_ id:String) {
        selectPack(id);settings.channel = .content
        if dualBandActive { settings.dualUpperChannel = .content }
        if servicesStarted { refreshContent() }
    }
}
struct ContentTopicCard:View {
    let pack:ContentPack;let selected:Bool;let action:()->Void
    @State private var hovering = false
    var body:some View {
        Button(action:action) {
            VStack(alignment:.leading,spacing:9) {
                HStack { Image(systemName:pack.symbol).font(.system(size:23,weight:.regular)).foregroundStyle(Color.accentColor);Spacer();if selected { Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.accentColor) } else { Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)).foregroundStyle(.tertiary) } }
                Text(L(pack.catalogTitle)).font(.system(size:14,weight:.semibold)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                Text(L(pack.catalogDetail)).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(3).frame(maxWidth:.infinity,alignment:.leading).frame(height:43,alignment:.topLeading)
                Text(pack.catalogExamples).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2).frame(height:26,alignment:.bottomLeading)
                Text(pack.offline ? L("Ready to show · no internet needed") : pack.id == "custom" ? L("Build your own selection") : LF("%ld sources",pack.sources.count)).font(.system(size:10,weight:.medium)).foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }.padding(16).frame(maxWidth:.infinity,alignment:.leading).frame(height:194)
                .background(Color(nsColor:hovering ? .selectedControlColor : .controlBackgroundColor).opacity(hovering ? 0.12 : 1),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(selected ? Color.accentColor.opacity(0.7) : Color(nsColor:.separatorColor).opacity(0.55),lineWidth:selected ? 1.5 : 0.5))
                .contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).onHover{hovering = $0}.accessibilityLabel(L(pack.catalogTitle)).accessibilityValue(selected ? L("Selected Feed") : L(pack.catalogDetail)).help(L("Choose content and sources"))
    }
}
struct ContentGalleryView:View {
    @ObservedObject var model:AppModel
    @Binding var showsInspector:Bool
    let openSources:()->Void
    @State private var search = ""
    @State private var group = "all"
    @State private var showsPreview = false
    var visibleGroups:[ContentGroup] { ContentCatalog.groups.filter{group == "all" || $0.id == group}.filter{$0.packs.contains{ContentCatalog.matches($0,search:search)}} }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            header
            HStack(spacing:10) {
                TextField(L("Search topics, publishers or channels"),text:$search).textFieldStyle(.roundedBorder).accessibilityLabel(L("Search content"))
                Picker(L("Content category"),selection:$group) { Text(L("All Content")).tag("all");ForEach(ContentCatalog.groups){Text(L($0.title)).tag($0.id)} }.labelsHidden().frame(maxWidth:240)
            }
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    selectedFeed
                    if visibleGroups.isEmpty { emptyState(L("No content matches your search"),detail:L("Try a topic such as cinema, science or humour, or a publisher name.")) }
                    ForEach(visibleGroups) { section in
                        VStack(alignment:.leading,spacing:12) {
                            Text(L(section.title)).font(.system(size:17,weight:.semibold))
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:220),spacing:12)],alignment:.leading,spacing:12) {
                                ForEach(section.packs.filter{ContentCatalog.matches($0,search:search)}) { pack in ContentTopicCard(pack:pack,selected:model.selectedPack.id == pack.id) { model.selectPack(pack.id);openSources() } }
                            }
                        }
                    }
                }.padding(2).padding(.bottom,12)
            }
        }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    var header:some View {
        HStack(alignment:.top) {
            VStack(alignment:.leading,spacing:5) { Text(L("Content")).font(.system(size:28,weight:.semibold));Text(L("Choose what belongs on your screen.")).font(.system(size:13)).foregroundStyle(.secondary) }
            Spacer()
            Button { showsInspector.toggle() } label:{Label(L("Display Settings"),systemImage:"slider.horizontal.3")}.help(L("Choose screen, placement and appearance"))
        }
    }
    var selectedFeed:some View {
        VStack(alignment:.leading,spacing:12) {
            ViewThatFits(in:.horizontal) {
                HStack(spacing:16) { selectedDescription.fixedSize(horizontal:true,vertical:false);Spacer();selectedActions.fixedSize(horizontal:true,vertical:false) }
                VStack(alignment:.leading,spacing:12) { selectedDescription;HStack { Spacer();selectedActions } }
            }

            if model.upperChannel == .content && !model.selectedContent.isEmpty { DisclosureGroup(L("Display Preview"),isExpanded:$showsPreview) { BroadcastStripPreview(model:model).frame(height:48).clipShape(RoundedRectangle(cornerRadius:8)).accessibilityLabel(L("Display Preview")) }.font(.system(size:11)).foregroundStyle(.secondary) }
            else { Text(model.refreshingContent ? L("Loading your feed…") : L("Choose sources and review the messages before showing them.")).font(.system(size:12)).foregroundStyle(.secondary) }
        }.padding(16).background(Color.accentColor.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
    }
    var selectedDescription:some View {
        HStack(spacing:12) {
            Image(systemName:model.selectedPack.symbol).font(.system(size:20)).foregroundStyle(Color.accentColor)
            VStack(alignment:.leading,spacing:3) { Text(L("Selected Content")).font(.system(size:10,weight:.medium)).foregroundStyle(.secondary);Text(L(model.selectedPack.catalogTitle)).font(.system(size:15,weight:.semibold));Text(LF("%ld eligible messages",model.selectedContent.count)).font(.system(size:11)).foregroundStyle(.secondary) }
        }
    }
    var selectedActions:some View {
        HStack(spacing:12) {
            if model.refreshingContent { ProgressView().controlSize(.small) }
            Button(model.selectedPack.offline ? L("Messages & Language…") : L("Sources & Filters…")){openSources()}
            Button(model.activeMode == nil ? L("Show on Screen") : L("Update Display")) { model.activateContentPack(model.selectedPack.id);model.outputs.show(model.previewMode) }.buttonStyle(.borderedProminent).disabled(model.selectedContent.isEmpty)
        }
    }

}
