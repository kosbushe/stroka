import Foundation
@main struct ProfileChecks {
    static var count=0
    static func check(_ ok:Bool,_ name:String){precondition(ok,name);count+=1}
    static func rejects(_ value:String,_ now:Date){check((try? PairTicket(value,now:now)) == nil,"Ticket must be rejected")}
    static func main()throws {
        let now=Date(timeIntervalSince1970:1_800_000_000),fp=String(repeating:"a",count:64),nonce=String(repeating:"b",count:64),id=String(repeating:"c",count:16)
        let valid="stroka://pair?v=2&host=192.168.50.20&port=43185&fp=\(fp)&nonce=\(nonce)&id=\(id)&service=Stroka-TV-\(id)&exp=1800000120"
        check(try PairTicket(valid,now:now).host == "192.168.50.20","Valid private QR")
        for h in ["8.8.8.8","127.0.0.1","169.254.1.1","192.168.0.999","192.168.00.1","192.168.0.1.evil.com","::1","172.15.0.1","172.32.0.1"] {rejects(valid.replacingOccurrences(of:"192.168.50.20",with:h),now)}
        for h in ["10.0.0.1","172.16.0.1","172.31.255.254","192.168.1.2"]{check(PairTicket.privateIPv4(h),"Private subnet")}
        for change in [valid+"&host=10.0.0.1",valid+"#bad",valid.replacingOccurrences(of:"v=2",with:"v=1"),valid.replacingOccurrences(of:"43185",with:"443"),valid.replacingOccurrences(of:"1800000120",with:"1800000000"),valid.replacingOccurrences(of:"1800000120",with:"1800001000"),valid.replacingOccurrences(of:fp,with:"abc"),valid.replacingOccurrences(of:"service=Stroka-TV-",with:"service=Other-"),valid.replacingOccurrences(of:"stroka://",with:"https://")]{rejects(change,now)}
        check(try PublicSource.parse("@aiffring")=="https://t.me/s/aiffring","Telegram handle")
        check(try PublicSource.parse("https://t.me/exploitex")=="https://t.me/s/exploitex","Telegram URL")
        for s in ["http://example.com/rss","https://127.0.0.1/","https://192.168.0.1/","https://localhost.local/rss","https://user:pass@example.com/feed","@abc","@with space","https://t.me/+private","https://t.me/s/username/12","https://example.com:444/feed"]{check((try? PublicSource.parse(s)) == nil,"Bad source")}
        var p=StationProfile();p.rows[0].sources=[StationSource(id:"test",name:"RSS",url:"https://example.com/rss",language:"ru",category:"world")]
        check(try p.validated()==p,"Profile accepted")
        for n in 1...4 {p.rows=(0..<n).map{_ in StationRow()};check(try p.validated().rows.count == n,"Row bounds");if n>1{check(p.speed(at:n-1)>p.speed(at:n-2),"Speed ladder");check(p.effectiveHeight==64,"Requested height is preserved for every row count")}}
        p.rows.append(StationRow());check((try? p.validated())==nil,"Fifth row rejected")
        p=StationProfile();p.rows.append(p.rows[0]);check((try? p.validated())==nil,"Duplicate row rejected")
        p=StationProfile();p.baseSpeed = .infinity;check((try? p.validated())==nil,"Nonfinite speed rejected")
        p=StationProfile();p.height=181;check((try? p.validated())==nil,"Height maximum")
        p=StationProfile();let data=try JSONEncoder().encode(p);check(try JSONDecoder().decode(StationProfile.self,from:data)==p,"Roundtrip")
        print("PASS \(count) profile, QR, source and speed checks")
    }
}
