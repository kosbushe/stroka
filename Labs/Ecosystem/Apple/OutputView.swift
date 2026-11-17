import SwiftUI
#if os(macOS)
import AppKit
import CoreImage
#endif

struct OutputView:View {
    @EnvironmentObject var model:ControllerModel
    @Environment(\.dismiss) var dismiss
    @State var scanner=false
    @State var link=""
    @State var importError=""
    var body:some View {NavigationStack{ScrollView{VStack(alignment:.leading,spacing:24){
        Image(systemName:"tv").font(.system(size:42,weight:.light)).foregroundStyle(.secondary)
        Text(model.device == nil ? "Продолжить на телевизоре":"Ваш телевизор").font(.largeTitle.bold())
        Text("Откройте Stroka TV Lab на телевизоре. Оба устройства должны быть в одной домашней сети Wi-Fi.").foregroundStyle(.secondary)
        if !model.challenge.isEmpty {
            VStack(alignment:.leading,spacing:12){Text("Сверьте число на экране ТВ");Text(model.challenge).font(.system(size:44,weight:.medium,design:.monospaced));Text("На телевизоре нажмите «Разрешить и запустить».").foregroundStyle(.secondary)}.padding(22).frame(maxWidth:.infinity,alignment:.leading).background(Color.accentColor.opacity(0.08),in:RoundedRectangle(cornerRadius:20))
            Button("Отменить подключение"){model.cancelPairing()}
        } else if let device=model.device {
            VStack(alignment:.leading,spacing:12){Label(device.name,systemImage:"checkmark.shield").font(.headline);Text(model.status).foregroundStyle(.secondary)
                Button("Загрузить текущую ленту ТВ"){Task{await model.reload()}}.disabled(model.busy)
                Button("Отключить это устройство",role:.destructive){Task{await model.disconnect()}}.disabled(model.busy)
            }.padding(20).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:20))
        }
        #if os(iOS)
        Button {scanner=true} label:{Label(model.device == nil ? "Сканировать QR":"Подключить другой телевизор",systemImage:"qrcode.viewfinder").frame(maxWidth:.infinity).padding(.vertical,10)}.buttonStyle(.borderedProminent).disabled(model.busy)
        #else
        Button {importQR()} label:{Label("Открыть изображение QR",systemImage:"qrcode.viewfinder").frame(maxWidth:.infinity).padding(.vertical,10)}.buttonStyle(.borderedProminent).disabled(model.busy)
        Text("На Mac можно открыть фотографию QR с телевизора. Подключение камеры iPhone проверяется отдельно.").font(.caption).foregroundStyle(.secondary)
        #endif
        DisclosureGroup("Ввести ссылку вручную") {VStack(alignment:.leading,spacing:10){TextField("stroka://pair?…",text:$link).textFieldStyle(.roundedBorder).autocorrectionDisabled();Button("Подключить"){model.connect(link);link=""}.disabled(model.busy)}}
        if model.busy {ProgressView(model.status)}
        if !importError.isEmpty{Text(importError).foregroundStyle(.red)}
        Text("Разрешения камеры, локальной сети и показа поверх приложений запрашиваются системой при первом подключении. После него устройства запоминают друг друга.").font(.caption).foregroundStyle(.secondary)
    }.padding(28).frame(maxWidth:560)}.navigationTitle("Подключение").toolbar{ToolbarItem(placement:.confirmationAction){Button("Готово"){if model.busy{model.cancelPairing()};dismiss()}}}}
    #if os(iOS)
    .sheet(isPresented:$scanner){QRScanner{value in scanner=false;model.connect(value)}}
    #else
    .frame(width:540,height:720)
    #endif
    .alert("Подключение",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})){Button("Понятно"){model.error=nil}}message:{Text(model.error ?? "")}
    }
    #if os(macOS)
    func importQR(){
        let panel=NSOpenPanel();panel.allowedContentTypes=[.image];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
        guard let image=CIImage(contentsOf:url),let detector=CIDetector(ofType:CIDetectorTypeQRCode,context:nil,options:[CIDetectorAccuracy:CIDetectorAccuracyHigh]),let feature=detector.features(in:image).compactMap({$0 as? CIQRCodeFeature}).first,let value=feature.messageString else{importError="QR не найден. Сфотографируйте весь код без бликов.";return}
        model.connect(value)
    }
    #endif
}
