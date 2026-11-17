import AppKit
import Foundation
import Network
import NaturalLanguage

final class RSSReader: NSObject, XMLParserDelegate {
    let source: String; var stories: [Story] = []; var inside = false; var field = ""; var title = ""; var link = ""; var date = ""; var stack: [String] = []; var buffer = ""
    private var limited = false;private var oversizedItem = false
    let language: String?
    init(source: String, language: String? = nil) { self.source = source; self.language = language }
    func read(_ data: Data) -> [Story] { stories = [];limited = false;inside = false;field = "";title = "";link = "";date = "";stack = [];buffer = "";let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = self;let parsed = parser.parse();return parsed || limited ? stories : [] }
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let parent = stack.last; stack.append(element)
        if element == "item" || element == "entry" { inside = true;oversizedItem = false; title = ""; link = ""; date = "" }
        guard inside else { return }
        if parent == "item" || parent == "entry" {
            if ["title", "link", "pubDate", "published", "date", "dc:date"].contains(element) { field = element; buffer = "" }
            if element == "link", let href = attributes["href"], attributes["rel"] == nil || attributes["rel"] == "alternate" { link = href }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inside else { return }
        if !field.isEmpty { if buffer.utf16.count+string.utf16.count > 8192 {oversizedItem = true;buffer = "";field = ""} else {buffer += string} }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if let text = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: text) } }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == field {
            switch field { case "title": title = buffer; case "link": if link.isEmpty { link = buffer }; case "pubDate", "published", "date", "dc:date": date = buffer; default: break }
            field = ""; buffer = ""
        }
        if element == "item" || element == "entry" {
            let clean = title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !oversizedItem { stories.append(Story(id: url.isEmpty ? "\(source):\(clean)" : url, text: clean, source: source, date: parseDate(date.trimmingCharacters(in: .whitespacesAndNewlines)), link: url, language: language ?? NLLanguageRecognizer.dominantLanguage(for: clean)?.rawValue)) }
            inside = false
            if stories.count >= 40 {limited = true;parser.abortParsing()}
        }
        _ = stack.popLast()
    }
}

final class MarketService {
    weak var model: AppModel?; var socket: URLSessionWebSocketTask?; var retry: DispatchWorkItem?; var moexTimer: Timer?; var pingTimer: Timer?
    var catalogGeneration = 0; var catalogFetching = false
    var referenceGeneration = 0; var referenceTasks:[URLSessionDataTask] = []; var fetching = false; var lastCBR = Date.distantPast;var lastECB = Date.distantPast
    var generation = 0; var pairs = ["BTC-USD", "ETH-USD"]; var updateCounts: [String: Int] = [:]; var lastPublish: [String: Date] = [:]
    init(model: AppModel) { self.model = model }
    private(set) var isRunning = false
    func start() {
        guard !isRunning else { return }; isRunning = true
        connect(pairs: model?.settings.cryptoPairs ?? "BTC-USD, ETH-USD"); fetchMOEX()
        moexTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.fetchMOEX() }
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.socket?.sendPing { _ in } }
    }
    func stop() {
        guard isRunning else { return }; isRunning = false; generation += 1; referenceGeneration += 1; referenceTasks.forEach{$0.cancel()};referenceTasks = [];fetching = false
        retry?.cancel(); retry = nil; moexTimer?.invalidate(); moexTimer = nil; pingTimer?.invalidate(); pingTimer = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
    }
    func connect(pairs input: String) {
        generation += 1; let gen = generation; retry?.cancel(); socket?.cancel(with: .goingAway, reason: nil)
        pairs = Array(Set(input.uppercased().components(separatedBy: CharacterSet(charactersIn: ", \n")).filter { $0.range(of: "^[A-Z0-9]{2,12}-[A-Z0-9]{2,6}$", options: .regularExpression) != nil })).sorted()
        model?.quotes.removeAll { $0.source == "Coinbase" && !pairs.contains($0.id) }
        guard !pairs.isEmpty else { model?.cryptoStatus = L("Enter pairs, such as BTC-USD"); return }
        model?.cryptoStatus = L("Connecting to Coinbase…")
        let task = URLSession.shared.webSocketTask(with: URL(string: "wss://ws-feed.exchange.coinbase.com")!); socket = task; task.resume()
        let subscription: [String: Any] = ["type": "subscribe", "product_ids": pairs, "channels": ["ticker", "heartbeat"]]
        let data = try! JSONSerialization.data(withJSONObject: subscription)
        task.send(.string(String(data: data, encoding: .utf8)!)) { [weak self] error in if let error { self?.failed(error, gen: gen) } }
        receive(task, gen: gen)
    }
    func receive(_ task: URLSessionWebSocketTask, gen: Int) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): self.failed(error, gen: gen)
            case .success(let message):
                let data: Data
                switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: return }
                if let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, gen == self.generation else { return }
                        if row["type"] as? String == "error" { self.model?.cryptoStatus = "Coinbase: \(row["message"] as? String ?? L("subscription error"))" }
                        if row["type"] as? String == "ticker", let id = row["product_id"] as? String, let p = row["price"] as? String, let price = Double(p), let time = parseDate(row["time"] as? String ?? "") {
                            self.updateCounts[id, default: 0] += 1
                            if Date().timeIntervalSince(self.lastPublish[id] ?? .distantPast) < 0.4 { return }
                            self.lastPublish[id] = Date()
                            let open = (row["open_24h"] as? String).flatMap(Double.init)
                            self.update(Quote(id: id, value: price, change: open.flatMap { $0 > 0 ? (price / $0 - 1) * 100 : nil }, time: time, received: Date(), source: "Coinbase"))
                            self.model?.cryptoStatus = LF("Coinbase stream · received %@", localTime(Date()))
                        }
                    }
                }
                DispatchQueue.main.async { if gen == self.generation { self.receive(task, gen: gen) } }
            }
        }
    }
    func failed(_ error: Error, gen: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, gen == self.generation else { return }
            self.model?.cryptoStatus = L("Coinbase disconnected · retrying in 10 s")
            self.retry?.cancel(); let work = DispatchWorkItem { [weak self] in guard let self, gen == self.generation else { return }; self.connect(pairs: self.pairs.joined(separator: ",")) }; self.retry = work; DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
        }
    }
    func update(_ quote: Quote) { guard let model else { return }; if let i = model.quotes.firstIndex(where: { $0.id == quote.id }) { model.quotes[i] = quote } else { model.quotes.append(quote) }; model.quotes.sort { $0.id < $1.id } }

}

final class RemoteServer {
    weak var model: AppModel?; var listener: NWListener?; let key = UUID().uuidString.replacingOccurrences(of: "-", with: ""); let queue = DispatchQueue(label: "ru.bushe.stroka.remote")
    private var connections:[ObjectIdentifier:NWConnection] = [:]
    #if STROKA_DIAGNOSTICS
    var activeConnectionCount:Int {queue.sync{connections.count}}
    #endif
    static func privateIPv4(_ ip:String)->Bool {
        let raw = ip.split(separator:".",omittingEmptySubsequences:false),parts = ip.split(separator:".").compactMap{Int($0)}
        guard raw.count == 4,parts.count == 4,parts.allSatisfy({0...255 ~= $0}) else{return false}
        return parts[0] == 10 || (parts[0] == 172 && 16...31 ~= parts[1]) || (parts[0] == 192 && parts[1] == 168)
    }
    init(model: AppModel) { self.model = model }
    func start() {
        guard let ip = localIP(),Self.privateIPv4(ip) else{model?.remoteInfo = L("Connect your Mac to your home network first.");model?.remoteEnabled = false;return}
        do {
            let parameters = NWParameters.tcp;parameters.requiredLocalEndpoint = .hostPort(host:NWEndpoint.Host(ip),port:.any)
            let listener = try NWListener(using:parameters); self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self else { return }
                DispatchQueue.main.async {
                    guard self.model?.remote === self else{return}
                    if case .ready = state, let port = listener?.port {
                        guard self.model?.remote === self,self.model?.remoteEnabled == true else{return}
                        self.model?.remoteInfo = "http://\(ip):\(port.rawValue)/\(self.key)"
                    } else if case .failed = state { self.model?.remoteInfo = L("Couldn’t start the remote"); self.model?.remoteEnabled = false }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self,self.connections.count<8 else{connection.cancel();return}
                self.connections[ObjectIdentifier(connection)] = connection
                connection.start(queue:self.queue);self.read(connection,buffer:Data())
                self.queue.asyncAfter(deadline:.now()+8){[weak self,weak connection] in
                    guard let connection else{return};connection.cancel();self?.connections.removeValue(forKey:ObjectIdentifier(connection))
                }
            }
            listener.start(queue: queue)
        } catch { model?.remoteInfo = L("Couldn’t start the remote. Try enabling it again."); model?.remoteEnabled = false }
    }
    func stop() {
        listener?.cancel();listener = nil
        queue.async{self.connections.values.forEach{$0.cancel()};self.connections = [:]}
    }
    deinit{listener?.cancel();connections.values.forEach{$0.cancel()}}
    func localIP() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?; guard getifaddrs(&list) == 0, let first = list else { return nil }; defer { freeifaddrs(list) }
        var item: UnsafeMutablePointer<ifaddrs>? = first
        while let current = item {
            defer { item = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), String(cString: current.pointee.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST)); if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { let ip = String(cString:host);if Self.privateIPv4(ip){return ip} }
        }; return nil
    }
    func read(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            guard let self else { c.cancel(); return }; var all = buffer; all.append(data ?? Data())
            guard all.count <= 16384 else { c.cancel(); return }
            guard let text = String(data: all, encoding: .utf8), let range = text.range(of: "\r\n\r\n") else { if !done && error == nil { self.read(c, buffer: all) } else { c.cancel() }; return }
            let head = String(text[..<range.lowerBound]); let body = String(text[range.upperBound...]); let first = head.components(separatedBy: "\r\n").first?.split(separator: " ") ?? []
            guard first.count >= 2 else { c.cancel(); return }
            let length = head.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }.flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "0") } ?? 0
            guard length>=0,length<=4096,body.utf8.count<=4096 else{self.respond(c,status:"413 Payload Too Large",body:"Request too large");return}
            if body.utf8.count < length && !done { self.read(c, buffer: all); return }
            let path = String(first[1]); guard path == "/\(self.key)" || path == "/\(self.key)/action" else { self.respond(c, status: "404 Not Found", body: "Not found"); return }
            if first[0] == "GET", path == "/\(self.key)" { self.respond(c, body: self.html); return }
            guard first[0] == "POST", path.hasSuffix("/action"), let obj = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: String] else { self.respond(c, status: "400 Bad Request", body: "Invalid request"); return }
            guard let action = obj["action"], ["pause", "next", "previous", "urgent", "clear", "stop"].contains(action) else { self.respond(c, status: "400 Bad Request", body: "Unknown action"); return }
            let contentType = head.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-type:") }?.lowercased() ?? ""
            guard contentType.contains("application/json") else { self.respond(c, status: "415 Unsupported Media Type", body: "JSON required"); return }
            DispatchQueue.main.async {
                guard let m = self.model,m.remoteEnabled,m.remote === self else { return }
                switch action {
                case "pause": m.playing.toggle()
                case "next": m.step(1)
                case "previous": m.step(-1)
                case "urgent": m.urgent = String((obj["text"] ?? "").prefix(1000))
                case "clear": m.urgent = ""
                case "stop": m.outputs.stop()
                default: break
                }
            }; self.respond(c, contentType: "application/json", body: "{\"ok\":true}")
        }
    }
    func respond(_ c: NWConnection, status: String = "200 OK", contentType: String = "text/html; charset=utf-8", body: String) {
        let data = Data(body.utf8); var response = Data("HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nX-Frame-Options: DENY\r\nConnection: close\r\n\r\n".utf8); response.append(data)
        c.send(content: response, completion: .contentProcessed { [weak self] _ in c.cancel();self?.queue.async{self?.connections.removeValue(forKey:ObjectIdentifier(c))} })
    }
    var html: String {
        guard let url = Localization.bundle.url(forResource: "Remote", withExtension: "html"), let page = try? String(contentsOf: url, encoding: .utf8) else { return "Remote unavailable" }
        return page
    }
}
