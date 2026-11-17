import Foundation
import Network
import Security
import CryptoKit

enum LinkFailure: Error, LocalizedError {
    case timeout, invalidResponse, rejected(Int), changedIdentity, noToken, refused, conflict
    var errorDescription: String? {
        switch self {
        case .timeout: return "Телевизор не отвечает. Откройте Stroka TV и подключите устройства к одной сети Wi-Fi."
        case .changedIdentity: return "Изменился ключ телевизора. Подключитесь заново через QR на самом телевизоре."
        case .rejected(401), .noToken: return "Доступ отозван. Подключитесь заново через QR."
        case .conflict: return "Настройки изменены с другого устройства. Загрузите текущую ленту перед сохранением."
        case .refused: return "Подключение отклонено на телевизоре."
        default: return "Не удалось обменяться данными. Проверьте соединение и повторите."
        }
    }
}

// Network.framework allows narrowly pinned local TLS without disabling ATS for RSS or the app.
final class PinnedTransport {
    let device: PairedTV
    init(_ device: PairedTV) { self.device=device }
    func request(_ method:String, _ path:String, token:String? = nil, body:Data? = nil) async throws -> Data {
        guard ["GET","POST","PUT"].contains(method), path.range(of:"^/[a-z/]+$",options:.regularExpression) != nil,
              (body?.count ?? 0) <= 262_144, PairTicket.privateIPv4(device.host), device.port >= 1024,
              device.fingerprint.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,
              token == nil || token!.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else { throw LinkFailure.invalidResponse }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let fingerprint = device.fingerprint
        let queue = DispatchQueue(label:"stroka.link.request")
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first else { complete(false);return }
            let digest = SHA256.hash(data:SecCertificateCopyData(leaf) as Data).map { String(format:"%02x",$0) }.joined()
            complete(digest == fingerprint)
        },queue)
        let parameters = NWParameters(tls:tls,tcp:NWProtocolTCP.Options())
        // One direct attempt; Bonjour fallback resolves changed LAN addresses while keeping the exact cert pin.
        let direct = NWEndpoint.hostPort(host:NWEndpoint.Host(device.host),port:NWEndpoint.Port(rawValue:device.port)!)
        do { return try await send(direct,parameters,method,path,token,body,seconds:5) }
        catch {
            if let failure=error as? LinkFailure, case .timeout = failure {} else if error is LinkFailure {throw error}
            guard device.service == "Stroka-TV-\(device.id)" else { throw error }
            return try await send(.service(name:device.service,type:"_stroka._tcp",domain:"local.",interface:nil),parameters,method,path,token,body,seconds:7)
        }
    }
    private func send(_ endpoint:NWEndpoint,_ parameters:NWParameters,_ method:String,_ path:String,_ token:String?,_ body:Data?,seconds:Double) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let operation = HTTPExchange(endpoint,parameters,continuation,seconds)
            var headers = "\(method) \(path) HTTP/1.1\r\nHost: stroka.local\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: \(body?.count ?? 0)\r\n"
            if let token { headers += "Authorization: Bearer \(token)\r\n" }
            var request = Data((headers+"\r\n").utf8); if let body { request.append(body) }
            operation.start(request)
        }
    }
}

private final class HTTPExchange: @unchecked Sendable {
    let connection:NWConnection
    let queue=DispatchQueue(label:"stroka.link.http")
    var continuation:CheckedContinuation<Data,Error>?
    var received=Data()
    var timeout:DispatchWorkItem?
    let seconds:Double
    init(_ endpoint:NWEndpoint,_ parameters:NWParameters,_ continuation:CheckedContinuation<Data,Error>,_ seconds:Double) {
        connection=NWConnection(to:endpoint,using:parameters);self.continuation=continuation;self.seconds=seconds
    }
    func start(_ request:Data) {
        // Callbacks retain the exchange until finish; finish clears them on every exit.
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: self.connection.send(content:request,completion:.contentProcessed { error in
                if let error { self.finish(.failure(error)) } else { self.receive() }
            })
            case .failed(let error):self.finish(.failure(error))
            case .cancelled:self.finish(.failure(LinkFailure.timeout))
            default:break
            }
        }
        let work=DispatchWorkItem { self.finish(.failure(LinkFailure.timeout)) };timeout=work
        queue.asyncAfter(deadline:.now()+seconds,execute:work);connection.start(queue:queue)
    }
    func receive() {
        connection.receive(minimumIncompleteLength:1,maximumLength:32768) { data,_,done,error in
            guard self.continuation != nil else {return}
            if let data { self.received.append(data) }
            guard self.received.count <= 524_288 else { self.finish(.failure(LinkFailure.invalidResponse));return }
            if let error { self.finish(.failure(error));return }
            if done { self.parse();return };self.receive()
        }
    }
    func parse() {
        guard let end=received.range(of:Data("\r\n\r\n".utf8)), end.lowerBound <= 8192,
              let headers=String(data:received[..<end.lowerBound],encoding:.utf8) else {finish(.failure(LinkFailure.invalidResponse));return}
        let lines=headers.components(separatedBy:"\r\n")
        guard let status=lines.first?.split(separator:" ").dropFirst().first.flatMap({Int($0)}),
              let lengthLine=lines.first(where:{$0.lowercased().hasPrefix("content-length:")}),
              let length=Int(lengthLine.split(separator:":",maxSplits:1)[1].trimmingCharacters(in:.whitespaces)),
              length >= 0, length == received.count-end.upperBound else {finish(.failure(LinkFailure.invalidResponse));return}
        if status == 409 {finish(.failure(LinkFailure.conflict));return}
        guard (200...299).contains(status) else {finish(.failure(LinkFailure.rejected(status)));return}
        finish(.success(received.subdata(in:end.upperBound..<received.count)))
    }
    func finish(_ result:Result<Data,Error>) {
        guard let continuation else{return};self.continuation=nil;timeout?.cancel();timeout=nil
        connection.stateUpdateHandler=nil;connection.cancel();continuation.resume(with:result)
    }
}

enum DeviceSecrets {
    private static let service="ru.bushe.stroka.ecosystem.lab.tv"
    static func token(_ id:String) throws -> String {
        let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:id,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result:CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess,let data=result as? Data,let value=String(data:data,encoding:.utf8) else{throw LinkFailure.noToken};return value
    }
    static func save(_ token:String,_ id:String)throws {
        let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:id]
        let changes:[String:Any]=[kSecValueData as String:Data(token.utf8),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status=SecItemUpdate(q as CFDictionary,changes as CFDictionary)
        if status==errSecItemNotFound {var add=q;changes.forEach{add[$0.key]=$0.value};guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else{throw LinkFailure.noToken}}
        else if status != errSecSuccess {throw LinkFailure.noToken}
    }
    static func delete(_ id:String) {
        SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:id] as CFDictionary)
    }
}
