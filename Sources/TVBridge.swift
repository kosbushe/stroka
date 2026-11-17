import AppKit
import SwiftUI
import Network

struct TVItem:Codable {let id:String;let text:String;let expiresAt:Double?}
struct TVRow:Codable {let title:String;let kind:String;let speed:Double;let items:[TVItem]}
struct TVState:Codable {
    let schema:Int;let serverTime:Double;let brand:String;let style:String;let edge:String;let height:Int
    let clock:Bool;let date:Bool;let language:String;let timeZone:String;let separator:String;let rounded:Bool
    let playing:Bool;let reducedMotion:Bool;let rows:[TVRow]
}
extension AppModel {
    func televisionState(now:Date = Date())->TVState {
        var rows:[TVRow] = []
        for (index,row) in tickerRows.enumerated() {
            var items:[TVItem] = []
            if row.channel == .markets {
                items = quotes.prefix(40).filter{now.timeIntervalSince($0.received)<($0.cadence == .daily ? 86400 : 900)}.map{TVItem(id:$0.id,text:$0.line,expiresAt:$0.received.addingTimeInterval($0.cadence == .daily ? 86400 : 900).timeIntervalSince1970)}
            } else if row.channel == .message {
                items = rowLines(index).prefix(40).enumerated().map{TVItem(id:"own-\(index)-\($0.offset)",text:String($0.element.prefix(600)),expiresAt:nil)}
            } else {
                let offline = ContentPack.find(row.packID).offline
                items = rowStories(index).prefix(40).filter{offline || fresh($0,now:now)}.map{story in
                    let text = !offline && (settings.broadcastSource ?? true) ? story.source+" · "+story.text : story.text
                    return TVItem(id:story.id,text:String(text.prefix(600)),expiresAt:offline ? nil : EditorialPolicy.expires(story,extended:Set(settings.extendedStories ?? []),allowExtended:settings.allowExtended ?? false)?.timeIntervalSince1970)
                }
            }
            rows.append(TVRow(title:row.title,kind:row.channel == .markets ? "markets" : "content",speed:speedForRow(index),items:items))
        }
        if !urgent.isEmpty {rows = [TVRow(title:L("Announcement"),kind:"content",speed:settings.speed,items:[TVItem(id:"announcement",text:String(urgent.prefix(1000)),expiresAt:nil)])]}
        return TVState(schema:1,serverTime:now.timeIntervalSince1970,brand:settings.brand,style:settings.look.simpleLook == .bulletin ? "news" : settings.look.simpleLook == .metro ? "minimal" : settings.look.simpleLook == .glass ? "glass" : "night",edge:settings.desktopEdge == .top ? "top" : "bottom",height:Int(settings.resolvedStripHeight),clock:settings.showClock,date:settings.broadcastDate ?? true,language:interfaceLanguage.rawValue,timeZone:TimeZone.current.identifier,separator:settings.resolvedSeparator,rounded:settings.roundedStrip ?? true,playing:playing,reducedMotion:reduceMotion,rows:rows)
    }
    func setTVSharing(_ enabled:Bool) {
        tvBridge?.stop();tvBridge = nil;tvSharing = enabled;tvAddress = "";tvPairCode = "";tvStatus = ""
        if enabled {let bridge = TVBridgeServer(model:self);tvBridge = bridge;bridge.start()}
    }
}

// A separate, read-only capability. TV tokens cannot call the phone remote's write API.
final class TVBridgeServer {
    weak var model:AppModel?
    let queue = DispatchQueue(label:"ru.bushe.stroka.tv")
    var listener:NWListener?
    private var connections:[UUID:NWConnection] = [:]
    private let token = UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
    private var code = "",expires = Date.distantPast,paired = false
    private var attempts = 0,windowStart = Date()
    private var stopped = false
    #if STROKA_DIAGNOSTICS
    var activeConnectionCount:Int {queue.sync{connections.count}}
    #endif
    init(model:AppModel){self.model = model}
    static func privateIPv4(_ ip:String)->Bool {
        let raw = ip.split(separator:".",omittingEmptySubsequences:false);let parts = raw.compactMap{Int($0)}
        guard raw.count == 4,parts.count == 4,parts.allSatisfy({0...255 ~= $0}) else{return false}
        return parts[0] == 10 || (parts[0] == 172 && 16...31 ~= parts[1]) || (parts[0] == 192 && parts[1] == 168)
    }
    func start() {
        guard let m = model,let ip = RemoteServer(model:m).localIP(),Self.privateIPv4(ip) else{model?.tvStatus = L("Connect your Mac to your home network first.");model?.tvSharing = false;return}
        do {
            let parameters = NWParameters.tcp;parameters.requiredLocalEndpoint = .hostPort(host:NWEndpoint.Host(ip),port:.any)
            let listener = try NWListener(using:parameters);self.listener = listener
            code = String(format:"%06u",arc4random_uniform(1_000_000));expires = Date().addingTimeInterval(600)
            m.tvPairCode = code;m.tvStatus = L("Ready to pair")
            listener.stateUpdateHandler = {[weak self,weak listener] state in
                DispatchQueue.main.async {
                    guard let self,self.model?.tvSharing == true,self.model?.tvBridge === self else{return}
                    if case .ready = state,let port = listener?.port {self.model?.tvAddress = "\(ip):\(port.rawValue)"}
                    else if case .failed = state {self.model?.tvStatus = L("Couldn’t start TV sharing.");self.model?.tvSharing = false}
                }
            }
            listener.newConnectionHandler = {[weak self] connection in
                guard let self,!self.stopped,self.connections.count < 8 else{connection.cancel();return}
                let id = UUID();self.connections[id] = connection;connection.start(queue:self.queue)
                self.read(connection,id:id,buffer:Data());self.queue.asyncAfter(deadline:.now()+6){[weak self,weak connection] in connection?.cancel();self?.connections.removeValue(forKey:id)}
            }
            listener.start(queue:queue)
        } catch {m.tvSharing = false;m.tvStatus = L("Couldn’t start TV sharing.")}
    }
    func stop(){listener?.cancel();listener = nil;queue.async{self.stopped = true;self.paired = false;self.code = "";self.connections.values.forEach{$0.cancel()};self.connections = [:]}}
    func read(_ connection:NWConnection,id:UUID,buffer:Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:8192){[weak self] data,_,done,error in
            guard let self,!self.stopped else{connection.cancel();return};var all = buffer;all.append(data ?? Data())
            guard all.count <= 16384 else{self.respond(connection,id:id,status:"413 Payload Too Large",body:Data());return}
            guard let text = String(data:all,encoding:.utf8),let boundary = text.range(of:"\r\n\r\n") else{if !done && error == nil{self.read(connection,id:id,buffer:all)}else{connection.cancel()};return}
            let head = String(text[..<boundary.lowerBound]),body = String(text[boundary.upperBound...])
            let request = head.components(separatedBy:"\r\n").first?.split(separator:" ") ?? []
            guard request.count == 3 else{self.respond(connection,id:id,status:"400 Bad Request",body:Data());return}
            let headers = head.components(separatedBy:"\r\n").dropFirst()
            let length = headers.first{$0.lowercased().hasPrefix("content-length:")}.flatMap{Int($0.split(separator:":",maxSplits:1,omittingEmptySubsequences:false).last!.trimmingCharacters(in:.whitespaces))} ?? 0
            guard length >= 0,length <= 4096 else{self.respond(connection,id:id,status:"413 Payload Too Large",body:Data());return}
            if body.utf8.count < length && !done {self.read(connection,id:id,buffer:all);return}
            let method = String(request[0]),path = String(request[1])
            if method == "POST",path == "/pair" {
                if Date().timeIntervalSince(self.windowStart)>60{self.attempts = 0;self.windowStart = Date()}
                self.attempts += 1
                guard self.attempts <= 8 else{self.respond(connection,id:id,status:"429 Too Many Requests",body:Data());return}
                guard !self.paired,Date()<self.expires,headers.contains(where:{$0.lowercased().hasPrefix("content-type:") && $0.lowercased().contains("application/json")}),let obj = try? JSONSerialization.jsonObject(with:Data(body.utf8)) as? [String:String],obj["code"] == self.code else{self.respond(connection,id:id,status:"403 Forbidden",body:Data());return}
                self.paired = true
                let result = try! JSONSerialization.data(withJSONObject:["statePath":"/\(self.token)/state"])
                DispatchQueue.main.async{[weak self] in guard let self,self.model?.tvBridge === self,self.model?.tvSharing == true else{return};self.model?.tvPairCode = "";self.model?.tvStatus = L("TV paired")}
                self.respond(connection,id:id,body:result);return
            }
            guard method == "GET",self.paired,path == "/\(self.token)/state" else{self.respond(connection,id:id,status:"404 Not Found",body:Data());return}
            DispatchQueue.main.async{[weak self] in
                guard let self,let model = self.model,model.tvSharing,model.tvBridge === self else{connection.cancel();return}
                guard let data = try? JSONEncoder().encode(model.televisionState()),data.count <= 512_000 else{connection.cancel();return}
                self.queue.async{self.respond(connection,id:id,body:data)}
            }
        }
    }
    func respond(_ c:NWConnection,id:UUID,status:String = "200 OK",body:Data){
        guard !stopped else{c.cancel();connections.removeValue(forKey:id);return}
        var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n".utf8);response.append(body)
        c.send(content:response,completion:.contentProcessed{[weak self] _ in c.cancel();self?.queue.async{self?.connections.removeValue(forKey:id)}})
    }
    deinit{listener?.cancel();connections.values.forEach{$0.cancel()}}
}
struct TVConnectionView:View {
    @ObservedObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    var body:some View {
        VStack(alignment:.leading,spacing:18){HStack{Label(L("Android TV / Google TV"),systemImage:"tv").font(.title2.weight(.semibold));Spacer();Button(L("Done")){dismiss()}}
            Text(L("Install Stroka TV on your television and connect both devices to the same home Wi-Fi.")).font(.callout).foregroundStyle(.secondary)
            Toggle(L("Share my ticker with TV"),isOn:Binding(get:{model.tvSharing},set:{model.setTVSharing($0)})).toggleStyle(.switch)
            if model.tvSharing {
                VStack(alignment:.leading,spacing:10){Text(L("Enter on the TV")).font(.caption).foregroundStyle(.secondary);Text(model.tvAddress.isEmpty ? L("Starting…") : model.tvAddress).font(.system(size:20,weight:.medium,design:.monospaced)).textSelection(.enabled);if !model.tvPairCode.isEmpty{Text(model.tvPairCode).font(.system(size:36,weight:.semibold,design:.monospaced)).textSelection(.enabled)};Text(model.tvStatus).font(.caption).foregroundStyle(.secondary)}.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:14))
                Button(L("New pairing code")){model.setTVSharing(true)}.buttonStyle(.borderless)
            } else if !model.tvStatus.isEmpty {Text(model.tvStatus).foregroundStyle(.secondary)}
            Text(L("On the TV, allow Display over other apps, then press Start. The remote continues to control your TV apps.")).font(.callout)
            Text(L("The pairing code is valid for 10 minutes. Use New pairing code if needed.")).font(.caption).foregroundStyle(.secondary)
            Text(L("Prototype: text, colours, clock and up to four rows. Your Mac must stay on. Some TV apps may hide overlays.")).font(.caption).foregroundStyle(.secondary)
            Text(L("Home network only. This local connection is not encrypted. The TV can read the shared feed, but cannot control your Mac.")).font(.caption).foregroundStyle(.secondary)
        }.padding(26).frame(width:560).environment(\.locale,Localization.locale)
    }
}
