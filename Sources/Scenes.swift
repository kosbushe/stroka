import SwiftUI

struct EventScene: Identifiable {
    let id: String; let name: String; let detail: String; let symbol: String
    let look: Look; let motion: Motion; let composition: Composition
    let brand: String; let caption: String; let text: String
    var channel: Channel = .message; var position: StripPlacement = .bottom; var output: OutputMode = .full; var contentPack: String? = nil
    var fontSize: Double = 76; var speed: Double = 80; var hold: Double = 7
    static let all: [EventScene] = [
        EventScene(id: "wedding", name: "Wedding", detail: "Warm typography, names, and messages for guests", symbol: "heart", look: .champagne, motion: .phrases, composition: .poster, brand: "Anastasia & Michael", caption: "Together. Today and always.", text: "So happy to share this day with you\nThe ceremony will begin soon\nLeave a wish for the newlyweds\nEveryone on the dance floor!", fontSize: 60, hold: 9),
        EventScene(id: "conference", name: "Conference", detail: "Announcements and information for the audience", symbol: "person.3", look: .graphite, motion: .phrases, composition: .split, brand: "CONFERENCE", caption: "Ideas that shape tomorrow", text: "Welcome! Please take your seats\nThe next talk starts in 5 minutes\nQuestions are welcome after the talk\nTaking a break. See you soon", fontSize: 96),
        EventScene(id: "party", name: "Party", detail: "Big words with a bold rhythm", symbol: "music.note", look: .electric, motion: .words, composition: .poster, brand: "THIS IS OUR NIGHT", caption: "Meet. Connect. Dance.", text: "MORE MUSIC MORE MOVEMENT\nMAKE TONIGHT YOURS\nTHE BEST MOMENTS ARE HERE", fontSize: 110, speed: 45),
        EventScene(id: "exhibition", name: "Exhibition", detail: "Welcome messages and announcements on a big screen", symbol: "rectangle.3.group", look: .paper, motion: .phrases, composition: .poster, brand: "ROOM FOR SOMETHING NEW", caption: "Ideas. People. Experiences.", text: "Welcome to the exhibition\nMeet the exhibitors and discover something new\nExplore the programme of talks", fontSize: 70, hold: 10),
        EventScene(id: "shop", name: "Shop", detail: "Offers and announcements along the bottom edge", symbol: "bag", look: .paper, motion: .horizontal, composition: .ticker, brand: "YOUR SHOP", caption: "Something to take home", text: "Lovely to see you!\nAsk us about what’s new\nThank you for choosing us", output: .strip, fontSize: 64, speed: 75),
        EventScene(id: "cafe", name: "Café", detail: "Relaxed typography and messages for guests", symbol: "cup.and.saucer", look: .champagne, motion: .phrases, composition: .poster, brand: "GOOD TO BE HERE", caption: "Coffee. Conversation. Your time.", text: "A good day to get together\nAsk your barista about today’s special\nStay a little longer", fontSize: 62, hold: 12),
        EventScene(id: "birthday", name: "Birthday", detail: "Names, wishes, and celebrations", symbol: "gift", look: .neon, motion: .phrases, composition: .poster, brand: "HAPPY BIRTHDAY!", caption: "Make it a night to remember", text: "All the wishes are for you today\nMake your biggest wish\nTime for a group photo!", fontSize: 76, hold: 8),
        EventScene(id: "ai", name: "AI Live", detail: "AI headlines in your chosen language", symbol: "sparkles", look: .studio, motion: .horizontal, composition: .split, brand: "AI / NOW", caption: "Stories worth following", text: "", channel: .ai, fontSize: 80, speed: 100),
        EventScene(id: "lobby", name: "Lobby & Check-in", detail: "Welcome messages, directions, and announcements", symbol: "signpost.right", look: .graphite, motion: .phrases, composition: .poster, brand: "WELCOME", caption: "You’re in the right place", text: "Please check in at the reception desk\nHave your ticket ready\nOur team is here to help", fontSize: 72, hold: 9),
        EventScene(id: "edge", name: "At the Edge", detail: "A vertical strip along the side of the screen", symbol: "rectangle.lefthalf.inset.filled", look: .ribbon, motion: .horizontal, composition: .ticker, brand: "ON THE SIDE", caption: "A place for important words", text: "Ideas are close. Keep what matters in sight.\nYour message could be here", position: .right, output: .strip, fontSize: 60, speed: 65),
        EventScene(id:"newsroom",name:"Newsroom",detail:"A classic red-and-white television news strip.",symbol:"newspaper",look:.bulletin,motion:.horizontal,composition:.ticker,brand:"STROKA NEWS",caption:"Headlines from your sources",text:"",channel:.content,output:.strip,contentPack:"world",fontSize:48,speed:100),
        EventScene(id:"techwire",name:"Technology Wire",detail:"A dark news strip for AI and technology headlines.",symbol:"antenna.radiowaves.left.and.right",look:.wire,motion:.horizontal,composition:.ticker,brand:"STROKA TECH",caption:"",text:"",channel:.ai,output:.strip,fontSize:48,speed:100),
        EventScene(id:"marketdesk",name:"Markets & Indices",detail:"Market data in a compact yellow-and-navy strip.",symbol:"chart.line.uptrend.xyaxis",look:.desk,motion:.horizontal,composition:.ticker,brand:"STROKA MARKETS",caption:"",text:"",channel:.markets,output:.strip,fontSize:44,speed:90),
        EventScene(id:"coffeebreak",name:"Coffee Break",detail:"A light collection of jokes for a break between sessions.",symbol:"face.smiling",look:.paper,motion:.phrases,composition:.poster,brand:"TAKE A BREATH",caption:"A little humour goes a long way",text:"",channel:.content,contentPack:"jokes",fontSize:58,hold:10)
    ]
}

struct SceneLibraryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    var scenes: [EventScene] { EventScene.all.filter { query.isEmpty || (L($0.name) + " " + L($0.detail)).localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text(L("For Every Occasion")).font(.system(size: 27, weight: .semibold)); Text(L("Choose a scene, then make the words your own.")).foregroundStyle(.secondary) }
                Spacer(); Button(L("Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField(L("Search scenes"), text: $query).textFieldStyle(.roundedBorder).frame(width: 280)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 22) {
                    ForEach(scenes) { scene in
                        Button { model.apply(scene); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: scene.look.bg))
                                    VStack(spacing: 11) {
                                        Image(systemName: scene.symbol).font(.system(size: 17)).foregroundStyle(Color(nsColor: scene.look.accent))
                                        Text(L(scene.brand)).font(.system(size: scene.id == "wedding" ? 24 : 21, weight: scene.id == "wedding" ? .regular : .semibold, design: scene.id == "wedding" || scene.id == "cafe" ? .serif : .default)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
                                        Text(L(scene.caption)).font(.system(size: 11)).multilineTextAlignment(.center).opacity(0.8)
                                    }.foregroundStyle(Color(nsColor: scene.look.ink)).padding(20)
                                }.frame(height: 164)
                                HStack { Text(L(scene.name)).font(.system(size: 14, weight: .semibold)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.secondary) }
                                Text(L(scene.detail)).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(height: 30, alignment: .topLeading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).help(LF("Apply “%@” scene", L(scene.name)))
                    }
                }.padding(.trailing, 6)
            }
            Text(L("Scenes update the appearance, sample text, and placement. Your connections and sources are preserved.")).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 900, height: 690)
    }
}
