import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

@MainActor final class ControllerModel: ObservableObject {
    @Published var profile:StationProfile { didSet { saveDraft() } }
    @Published var device:PairedTV?
    @Published var revision:Int?
    @Published var busy=false
    @Published var status="Выберите ленту и подключите телевизор"
    @Published var challenge=""
    @Published var error:String?
    let catalog:[StationSource]
    private let defaults=UserDefaults.standard
    private var pairTask:Task<Void,Never>?
    init() {
        if let data=defaults.data(forKey:"draft-v2"),let saved=try? JSONDecoder().decode(StationProfile.self,from:data),let valid=try? saved.validated(){profile=valid}else{profile=StationProfile()}
        if let data=defaults.data(forKey:"device-v2"){device=try? JSONDecoder().decode(PairedTV.self,from:data)}
        if let url=Bundle.main.url(forResource:"NewsCatalog",withExtension:"json"),let data=try? Data(contentsOf:url){catalog=(try? JSONDecoder().decode([StationSource].self,from:data)) ?? []}else{catalog=[]}
    }
    private func saveDraft(){if let data=try? JSONEncoder().encode(profile){defaults.set(data,forKey:"draft-v2")}}
    func connect(_ text:String) {
        guard !busy else{return}
        do {
            let ticket=try PairTicket(text)
            let pending=PairedTV(id:ticket.deviceID,name:"Stroka TV",host:ticket.host,port:ticket.port,service:ticket.service,fingerprint:ticket.fingerprint)
            busy=true;error=nil;status="Подключаемся к телевизору…"
            pairTask=Task {
                defer{busy=false;challenge="";pairTask=nil}
                do {
                    #if os(iOS)
                    let name=String(UIDevice.current.name.prefix(48))
                    #else
                    let name=String((Host.current().localizedName ?? "Mac").prefix(48))
                    #endif
                    let client=PinnedTransport(pending)
                    let start=try await client.request("POST","/pair/request",body:JSONSerialization.data(withJSONObject:["nonce":ticket.nonce,"name":name]))
                    try Task.checkCancellation()
                    guard let response=try JSONSerialization.jsonObject(with:start) as? [String:Any],let request=response["request"] as? String,request.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,let code=response["challenge"] as? String else{throw LinkFailure.invalidResponse}
                    challenge=code;status="Подтвердите это число на телевизоре"
                    for _ in 0..<60 {
                        try Task.checkCancellation();try await Task.sleep(for:.seconds(2))
                        let result=try await client.request("POST","/pair/result",body:JSONSerialization.data(withJSONObject:["request":request]))
                        try Task.checkCancellation()
                        guard let r=try JSONSerialization.jsonObject(with:result) as? [String:Any],let state=r["state"] as? String else{throw LinkFailure.invalidResponse}
                        if state == "denied"{throw LinkFailure.refused}
                        if state == "approved" {
                            guard let token=r["token"] as? String,token.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,r["id"] as? String == pending.id else{throw LinkFailure.invalidResponse}
                            try DeviceSecrets.save(token,pending.id);device=pending;defaults.set(try JSONEncoder().encode(pending),forKey:"device-v2")
                            let data=try await client.request("GET","/profile",token:token)
                            let document=try JSONDecoder().decode(TVDocument.self,from:data);_ = try document.profile.validated();revision=document.revision
                            if document.revision>0 {profile=document.profile;status="Подключено. Загружена текущая лента телевизора."}
                            else if profile.hasContent {try await putProfile();status="Подключено. Ваша лента передана телевизору."}
                            else {status="Подключено. Теперь выберите источники или добавьте свой текст."}
                            return
                        }
                    }
                    throw LinkFailure.timeout
                } catch is CancellationError {status="Подключение отменено"}
                catch {self.error=error.localizedDescription;status=device?.id == pending.id ? "Доступ сохранён. Загрузите настройки телевизора повторно.":"Новое подключение не завершено"}
            }
        } catch {self.error="QR недействителен или устарел. Покажите новый QR в Stroka TV."}
    }
    func cancelPairing(){pairTask?.cancel()}
    func reload() async {
        guard let device,!busy else{return};busy=true;defer{busy=false}
        do {
            let data=try await PinnedTransport(device).request("GET","/profile",token:DeviceSecrets.token(device.id))
            let d=try JSONDecoder().decode(TVDocument.self,from:data);profile=try d.profile.validated();revision=d.revision;status=d.status ?? "Подключено"
        } catch {self.error=error.localizedDescription}
    }
    private func putProfile() async throws {
        guard let device,let revision else{throw LinkFailure.noToken}
        guard profile.hasContent else{throw ProfileError.invalid}
        let value=TVDocument(revision:revision,profile:try profile.validated())
        let data=try await PinnedTransport(device).request("PUT","/profile",token:DeviceSecrets.token(device.id),body:JSONEncoder().encode(value))
        let d=try JSONDecoder().decode(TVDocument.self,from:data);_ = try d.profile.validated();self.revision=d.revision;status="Лента обновлена на телевизоре"
    }
    func publish() async {
        guard !busy else{return};busy=true;defer{busy=false}
        do{try await putProfile()}catch{self.error=error.localizedDescription}
    }
    func disconnect() async {
        guard let device,!busy else{return};busy=true;defer{busy=false}
        do{
            _ = try await PinnedTransport(device).request("POST","/device/revoke",token:DeviceSecrets.token(device.id),body:Data("{}".utf8))
            DeviceSecrets.delete(device.id);self.device=nil;revision=nil;defaults.removeObject(forKey:"device-v2");status="Доступ этого устройства отключён"
        }catch{self.error="Не удалось отозвать доступ на ТВ. Откройте Stroka TV и отключите устройства там."}
    }
}
