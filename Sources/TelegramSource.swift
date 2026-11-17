import Foundation
import SwiftUI
import NaturalLanguage

// One public preview request, bounded and cancellable. No Telegram login or bot token.
final class TelegramAddState:ObservableObject {
    @Published var handle = ""
    @Published var busy = false
    @Published var error = ""
    @Published var added = ""
    private let transport:FeedTransport
    private let scope = UUID().uuidString
    private var generation = 0
    init(configuration:URLSessionConfiguration? = nil) {
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15;config.timeoutIntervalForResource = 20
        config.httpShouldSetCookies = false
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
        config.httpAdditionalHeaders = ["User-Agent":"Stroka/\(version) public Telegram preview"]
        transport = FeedTransport(configuration:config,limit:3_000_000,concurrency:1)
    }
    static func metadata(_ data:Data,username:String)->FeedSource? {
        var feed = FeedSource(name:"@"+username,url:"https://t.me/s/"+username)
        let stories = TelegramPublicReader.read(data,source:feed)
        guard !stories.isEmpty,let html = String(data:data,encoding:.utf8) else{return nil}
        let re = try! NSRegularExpression(pattern:"<meta\\b[^>]*property=\"og:title\"[^>]*content=\"([^\"]+)\"",options:.caseInsensitive)
        if let match = re.firstMatch(in:html,range:NSRange(location:0,length:(html as NSString).length)) {
            let title = ShortText.plainHTML((html as NSString).substring(with:match.range(at:1)))
            if !title.isEmpty {feed.name = String(title.prefix(100))+" · @"+username}
        }
        let language = NLLanguageRecognizer.dominantLanguage(for:stories.prefix(5).map(\.text).joined(separator:" "))
        feed.language = language == .russian ? "ru" : language == .english ? "en" : nil
        return feed
    }
    func add(_ receive:@escaping (FeedSource)->Bool) {
        guard !busy else{return};error = "";added = ""
        guard let username = TelegramPublicReader.username(handle) else{error = L("Enter a public Telegram username, for example @channel.");return}
        busy = true;generation += 1;let ticket = generation
        transport.load(URL(string:"https://t.me/s/"+username)!,scope:scope){[weak self] data,response,failure in
            let status = response?.url?.host?.lowercased() == "t.me" ? (response as? HTTPURLResponse)?.statusCode ?? 0 : 0
            let feed = status == 200 ? data.flatMap{Self.metadata($0,username:username)} : nil
            DispatchQueue.main.async {
                guard let self,self.generation == ticket else{return};self.busy = false
                guard failure == nil,status == 200 else{self.error = L("Couldn’t reach Telegram. Check your connection and try again.");return}
                guard let feed else{self.error = L("No public text posts found. Check the username; private channels need a public preview.");return}
                guard receive(feed) else{self.error = L("This source has already been added.");return}
                self.added = feed.name;self.handle = ""
            }
        }
    }
    func cancel(){generation += 1;busy = false;transport.cancel(scope:scope)}
    deinit{transport.invalidate()}
}
struct TelegramChannelField:View {
    @StateObject private var state = TelegramAddState()
    let add:(FeedSource)->Bool
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(spacing:10) {
                Image(systemName:"paperplane").foregroundStyle(Color.accentColor)
                TextField(L("Telegram: @channel"),text:$state.handle).textFieldStyle(.roundedBorder).onSubmit{state.add(add)}.disabled(state.busy).accessibilityLabel(L("Telegram username"))
                if state.busy {ProgressView().controlSize(.small).frame(width:18)}
                Button(L("Add channel")){state.add(add)}.disabled(state.busy || state.handle.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            if !state.error.isEmpty {Text(state.error).font(.caption).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
            else if !state.added.isEmpty {Label(state.added,systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(.green).lineLimit(2)}
            else {Text(L("Just enter @username. We’ll find the name and public posts automatically.")).font(.caption).foregroundStyle(.secondary)}
        }.onDisappear{state.cancel()}
    }
}
