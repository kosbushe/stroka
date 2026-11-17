import Foundation
@main struct LinkChecks {
    static func main()async throws {
        let args=CommandLine.arguments
        guard args.count==4,let port=UInt16(args[2])else{fatalError("host port fingerprint required")}
        let d=PairedTV(id:String(repeating:"1",count:16),name:"Fixture",host:args[1],port:port,service:"",fingerprint:args[3])
        let client=PinnedTransport(d),token=String(repeating:"a",count:64)
        let bytes=try await client.request("GET","/profile",token:token)
        guard let result=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],result["ok"] as? Bool == true else{fatalError("Valid response")}
        var checks=1
        do{_ = try await client.request("GET","/profile",token:String(repeating:"b",count:64));fatalError("Token must fail")}catch LinkFailure.rejected(401){checks+=1}
        do{_ = try await client.request("PUT","/profile",token:token,body:Data("{}".utf8));fatalError("Conflict must fail")}catch LinkFailure.conflict{checks+=1}
        do{_ = try await client.request("GET","/malformed",token:token);fatalError("Framing must fail")}catch LinkFailure.invalidResponse{checks+=1}
        do{_ = try await client.request("GET","/profile\r\nInjected",token:token);fatalError("Path injection must fail")}catch LinkFailure.invalidResponse{checks+=1}
        do{_ = try await client.request("GET","/profile",token:token+"\r\nInjected");fatalError("Token injection must fail")}catch LinkFailure.invalidResponse{checks+=1}
        let wrong=PairedTV(id:d.id,name:d.name,host:d.host,port:d.port,service:"",fingerprint:String(repeating:"0",count:64))
        do{_ = try await PinnedTransport(wrong).request("GET","/profile",token:token);fatalError("Wrong identity accepted")}catch{checks+=1}
        print("PASS \(checks) real local TLS/pinning, auth, revision and framing checks")
    }
}
