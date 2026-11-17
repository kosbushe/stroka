import Foundation

// Versioned document shared by both Apple clients and the autonomous TV player.
// Published dates belong to stories, never to the time this document is saved.
struct StationProfile: Codable, Equatable {
    var schema = 2
    var name = "BUSHE NEWS"
    var style = "news"
    var edge = "bottom"
    var height = 64
    var clock = true
    var date = true
    var rounded = true
    var playing = true
    var reducedMotion = false
    var language = "ru"
    var timeZone = TimeZone.current.identifier
    var separator = "▌▌▌"
    var baseSpeed = 45.0
    var rows = [StationRow()]
    var hasContent:Bool {rows.contains{row in row.kind == "content" ? !row.sources.isEmpty : row.kind == "markets" ? !row.instruments.isEmpty : row.messages.contains{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}}}

    func validated() throws -> StationProfile {
        guard schema == 2, (1...4).contains(rows.count), (45...180).contains(height),
              ["news","night","minimal","glass"].contains(style), ["top","bottom"].contains(edge),
              ["ru","en"].contains(language), TimeZone(identifier: timeZone) != nil,
              name.count <= 48, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              separator.count <= 12, (10...120).contains(baseSpeed), baseSpeed.isFinite else { throw ProfileError.invalid }
        guard Set(rows.map(\.id)).count == rows.count else { throw ProfileError.invalid }
        for row in rows {
            guard !row.id.isEmpty, row.id.count <= 64, row.title.count <= 48,
                  ["content","message","markets","offline"].contains(row.kind), row.sources.count <= 24,
                  row.messages.count <= 40, row.messages.allSatisfy({ $0.count <= 600 }),
                  row.instruments.count <= 24, row.instruments.allSatisfy({ $0.range(of: "^[A-Z0-9-]{2,16}$",options:.regularExpression) != nil }) else { throw ProfileError.invalid }
            for source in row.sources { _ = try PublicSource.parse(source.url) }
        }
        return self
    }
    func speed(at index: Int) -> Double { baseSpeed * (1 + Double(index) * 0.15) }
    var effectiveHeight: Int { min(180,max(45,height)) }
}
struct StationRow: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title = "Новости"
    var kind = "content"
    var sources: [StationSource] = []
    var messages: [String] = []
    // v2 first executable slice supports Coinbase product symbols, with an explicit provider label.
    var instruments: [String] = ["BTC-USD", "ETH-USD"]
}
struct StationSource: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var url: String
    var language: String
    var category: String
}
enum ProfileError: Error, LocalizedError {
    case invalid
    var errorDescription:String? {"Проверьте ленту: выберите хотя бы один источник или добавьте свой текст. Допустимы 1-4 строки, высота 45-180 и название до 48 символов."}
}

enum PublicSource {
    static func parse(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") {
            let user = String(value.dropFirst())
            guard user.range(of: "^[A-Za-z][A-Za-z0-9_]{4,31}$",options:.regularExpression) != nil else { throw ProfileError.invalid }
            return "https://t.me/s/\(user)"
        }
        guard let u = URLComponents(string:value), u.scheme == "https", let host = u.host?.lowercased(),
              u.user == nil, u.password == nil, u.fragment == nil,
              u.port == nil || u.port == 443, host.contains("."),
              host.range(of:"^[a-z0-9.-]+$",options:.regularExpression) != nil,
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), !host.hasSuffix(".internal"),
              host != "localhost", !host.allSatisfy({ $0.isNumber || $0 == "." }), value.count <= 2048 else { throw ProfileError.invalid }
        if host == "t.me" || host == "www.t.me" {
            let parts = u.path.split(separator:"/").map(String.init)
            let user = parts.first == "s" ? parts.dropFirst().first : parts.first
            guard let user, parts.count == (parts.first == "s" ? 2 : 1) else { throw ProfileError.invalid }
            return try parse("@"+user)
        }
        return value
    }
}

struct PairTicket: Equatable {
    let host: String
    let port: UInt16
    let fingerprint: String
    let nonce: String
    let deviceID: String
    let service: String
    let expiresAt: Double
    init(_ value: String, now: Date = Date()) throws {
        guard value.count < 2048, let c = URLComponents(string:value), c.scheme == "stroka", c.host == "pair",
              c.path.isEmpty, c.user == nil, c.password == nil, c.fragment == nil else { throw ProfileError.invalid }
        let items = c.queryItems ?? []
        let names = items.map(\.name)
        guard items.count == 8, Set(names).count == names.count, Set(names) == Set(["v","host","port","fp","nonce","id","service","exp"]) else { throw ProfileError.invalid }
        let q = Dictionary(uniqueKeysWithValues:items.compactMap { item -> (String,String)? in guard let value = item.value else{return nil}; return (item.name,value) })
        guard q["v"] == "2", let h = q["host"], Self.privateIPv4(h), let p = q["port"].flatMap(UInt16.init), p >= 1024,
              let fp = q["fp"], fp.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,
              let n = q["nonce"], n.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,
              let id = q["id"], id.range(of:"^[a-f0-9]{16}$",options:.regularExpression) != nil,
              q["service"] == "Stroka-TV-\(id)", let exp = q["exp"].flatMap(Double.init), exp.isFinite,
              exp > now.timeIntervalSince1970, exp <= now.timeIntervalSince1970 + 180 else { throw ProfileError.invalid }
        host=h;port=p;fingerprint=fp;nonce=n;deviceID=id;service=q["service"]!;expiresAt=exp
    }
    static func privateIPv4(_ host: String) -> Bool {
        let raw = host.split(separator:".",omittingEmptySubsequences:false)
        guard raw.count == 4, raw.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && ($0 == "0" || !$0.hasPrefix("0")) }), raw.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) else { return false }
        let x = raw.map { Int($0)! }
        return x[0] == 10 || (x[0] == 172 && (16...31).contains(x[1])) || (x[0] == 192 && x[1] == 168)
    }
}

struct PairedTV: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    let host: String
    let port: UInt16
    let service: String
    let fingerprint: String
    // Access token lives separately in Keychain, never in the profile or defaults.
}
struct TVDocument: Codable {
    var revision: Int
    var profile: StationProfile
    var status: String?
}
