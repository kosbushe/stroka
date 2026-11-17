import SwiftUI
#if os(macOS)
import AppKit
import CoreImage
#endif

@main struct StrokaEcosystemApp:App {
    @StateObject var model=ControllerModel()
    var body:some Scene {WindowGroup {StationHome().environmentObject(model).onOpenURL{model.connect($0.absoluteString)}
        #if os(macOS)
        .frame(minWidth:460,idealWidth:540,minHeight:700)
        #endif
    }}
}
private enum StudioColor {
    static let red=Color(red:0.79,green:0.08,blue:0.16)
    static let ink=Color(red:0.08,green:0.11,blue:0.15)
    static let paper=Color(red:0.96,green:0.97,blue:0.98)
}
struct StationHome:View {
    @EnvironmentObject var model:ControllerModel
    @State var output=false
    @State var settings=false
    @State var editingRow:StationRow?
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:26){
                    HStack {Text("Ваша лента").font(.largeTitle.bold());Spacer();Text("LAB").font(.caption.monospaced().bold()).foregroundStyle(.secondary)}
                    VStack(alignment:.leading,spacing:12){
                        StationPreview(profile:model.profile).accessibilityLabel("Предпросмотр оформления: \(model.profile.name), \(model.profile.rows.count) строки")
                        Text("Предпросмотр оформления").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment:.leading,spacing:12){
                        Text("Как вас назвать?").font(.headline)
                        TextField("Название в левой части строки",text:$model.profile.name,axis:.vertical).lineLimit(2).textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment:.leading,spacing:12){
                        HStack{Text("Что читать").font(.headline);Spacer();Text("\(model.profile.rows.count) из 4 строк").font(.caption).foregroundStyle(.secondary)}
                        ForEach(Array(model.profile.rows.enumerated()),id:\.element.id){index,row in
                            Button {editingRow=row} label:{
                                HStack(spacing:12){Image(systemName:row.kind == "markets" ? "chart.line.uptrend.xyaxis" : row.kind == "message" ? "text.alignleft":"dot.radiowaves.left.and.right").frame(width:25)
                                    VStack(alignment:.leading,spacing:4){Text(row.title).foregroundStyle(.primary);Text(row.kind == "content" ? "\(row.sources.count) источников" : row.kind == "markets" ? "Coinbase · тестовый провайдер":"\(row.messages.count) сообщений").font(.caption).foregroundStyle(.secondary)};Spacer();Text("\(Int(model.profile.speed(at:index)))").font(.caption.monospacedDigit()).foregroundStyle(.secondary);Image(systemName:"chevron.right").font(.caption)}.padding(15).background(StudioColor.paper,in:RoundedRectangle(cornerRadius:16))
                            }.buttonStyle(.plain)
                        }
                        if model.profile.rows.count<4 {Button("Добавить строку",systemImage:"plus"){var row=StationRow();row.title="Строка \(model.profile.rows.count+1)";model.profile.rows.append(row);editingRow=row}}
                    }
                    VStack(alignment:.leading,spacing:12){Text("Оформление").font(.headline)
                        HStack(spacing:10){ForEach([("news","Новости"),("night","Ночной"),("minimal","Минимал"),("glass","Glass")],id:\.0){style,title in
                            Button {model.profile.style=style} label:{VStack(spacing:8){RoundedRectangle(cornerRadius:9).fill(style == "news" ? StudioColor.red:style == "minimal" ? Color.gray.opacity(0.2):style == "glass" ? Color.blue.opacity(0.35):StudioColor.ink).frame(height:34).overlay(alignment:.leading){Text("///").font(.caption.bold()).foregroundStyle(style == "minimal" ? .black:.white).padding(7)};Text(title).font(.caption).foregroundStyle(.primary)}.padding(6).background(model.profile.style == style ? Color.accentColor.opacity(0.12):Color.clear,in:RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain)
                        }}
                    }
                    Button {settings=true} label:{Label("Скорость, положение и часы",systemImage:"slider.horizontal.3")}
                    VStack(alignment:.leading,spacing:12){
                        HStack{Image(systemName:"tv");Text(model.device?.name ?? "Телевизор").font(.headline);Spacer();Button(model.device == nil ? "Подключить":"Устройства"){output=true}}
                        Text(model.status).font(.callout).foregroundStyle(.secondary)
                        Button {if model.device == nil {output=true}else{Task{await model.publish()}}} label:{Text(model.device == nil ? "Подключить телевизор":"Показать на телевизоре").frame(maxWidth:.infinity).padding(.vertical,6)}.buttonStyle(.borderedProminent).disabled(model.busy || model.device != nil && model.revision == nil)
                        if model.device != nil && model.revision == nil {Button("Загрузить настройки телевизора"){Task{await model.reload()}}.disabled(model.busy)}
                    }.padding(18).background(StudioColor.paper,in:RoundedRectangle(cornerRadius:20))
                    Text("iPhone и Mac задают ленту. Телевизор читает её самостоятельно.").font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth:600)
            }
            .navigationTitle("Stroka").toolbarTitleDisplayMode(.inline)
            .sheet(isPresented:$output){OutputView().environmentObject(model)}
            .sheet(isPresented:$settings){AppearanceView().environmentObject(model)}
            .sheet(item:$editingRow){row in RowEditor(initial:row){updated in if let index=model.profile.rows.firstIndex(where:{$0.id==updated.id}){model.profile.rows[index]=updated}}.environmentObject(model)}
            .alert("Нужна проверка",isPresented:Binding(get:{!output && model.error != nil},set:{if !$0 && !output{model.error=nil}})){Button("Понятно"){model.error=nil}}message:{Text(model.error ?? "")}
        }
    }
}
struct StationPreview:View {
    let profile:StationProfile
    var body:some View {
        let dark=profile.style == "night" || profile.style == "glass"
        HStack(spacing:0){
            Text(profile.name.isEmpty ? "STROKA":profile.name).font(.system(size:11,weight:.bold)).multilineTextAlignment(.center).lineLimit(2).frame(width:72).frame(maxHeight:.infinity).foregroundStyle(profile.style == "minimal" ? Color.primary:Color.white).background(profile.style == "news" ? StudioColor.red:dark ? StudioColor.ink:StudioColor.paper)
            VStack(alignment:.leading,spacing:0){ForEach(Array(profile.rows.enumerated()),id:\.element.id){_,row in
                Text(row.kind == "message" ? row.messages.first ?? "Ваш текст":row.kind == "markets" ? "BTC-USD · ETH-USD":row.sources.first?.name ?? "Выберите ваши источники").font(.system(size:12,weight:.semibold)).lineLimit(1).padding(.horizontal,8).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading).foregroundStyle(dark ? .white:StudioColor.ink)
            }}.background(dark ? StudioColor.ink.opacity(0.94):StudioColor.paper)
            if profile.clock {VStack(spacing:3){Text("12:45").font(.system(size:17,weight:.medium,design:.rounded));if profile.date{Text("СБ, 14 НОЯ").font(.system(size:6,weight:.semibold))}}.foregroundStyle(.white).frame(width:65).frame(maxHeight:.infinity).background(StudioColor.ink)}
        }.frame(height:CGFloat(max(72,profile.rows.count*27))).clipShape(RoundedRectangle(cornerRadius:profile.rounded ? 14:0))
    }
}
struct AppearanceView:View {
    @EnvironmentObject var model:ControllerModel
    @Environment(\.dismiss) var dismiss
    var body:some View {NavigationStack{Form{
        Section("Движение"){Toggle("Двигать строку",isOn:$model.profile.playing);HStack{Text("Скорость верхней строки");Spacer();Text("\(Int(model.profile.baseSpeed))").monospacedDigit()};Slider(value:$model.profile.baseSpeed,in:10...120,step:1);Text("Каждая следующая строка движется на 15% быстрее.").font(.caption).foregroundStyle(.secondary);Toggle("Уменьшить движение",isOn:$model.profile.reducedMotion)}
        Section("Полоса"){Picker("Положение",selection:$model.profile.edge){Text("Снизу").tag("bottom");Text("Сверху").tag("top")};HStack{Text("Высота");Spacer();Text("\(model.profile.effectiveHeight)")};Slider(value:Binding(get:{Double(model.profile.height)},set:{model.profile.height=Int($0)}),in:45...180,step:1);Toggle("Скруглённые углы",isOn:$model.profile.rounded);Toggle("Время",isOn:$model.profile.clock);Toggle("Дата и день недели",isOn:$model.profile.date)}
        Section("Между сообщениями"){Picker("Разделитель",selection:$model.profile.separator){Text("Три цвета").tag("▌▌▌");Text("Три точки").tag("•••");Text("Ромб").tag("◆")}}
    }.formStyle(.grouped).navigationTitle("Оформление").toolbar{ToolbarItem(placement:.confirmationAction){Button("Готово"){dismiss()}}}}
    #if os(macOS)
    .frame(width:500,height:620)
    #endif
    }
}
struct RowEditor:View {
    @EnvironmentObject var model:ControllerModel
    @Environment(\.dismiss) var dismiss
    @State var row:StationRow
    @State var query=""
    @State var category="world"
    @State var custom=""
    @State var customError=""
    let save:(StationRow)->Void
    init(initial:StationRow,save:@escaping(StationRow)->Void){_row=State(initialValue:initial);self.save=save}
    let categories=[("world","Новости"),("technology","Технологии"),("ai","AI"),("business","Бизнес"),("science","Наука"),("cinema","Кино"),("sport","Спорт"),("culture","Культура"),("moscow","Москва"),("space","Космос"),("environment","Экология")]
    var matching:[StationSource]{model.catalog.filter{query.isEmpty ? $0.category == category : $0.name.localizedCaseInsensitiveContains(query)}.sorted{if ($0.language == "ru") != ($1.language == "ru"){return $0.language == "ru"};return $0.name<$1.name}}
    var body:some View {NavigationStack{Form{
        Section {TextField("Название строки",text:$row.title);Picker("Показывать",selection:$row.kind){Text("Источники").tag("content");Text("Свой текст").tag("message");Text("Короткие мысли").tag("offline");Text("Криптовалюты · тест").tag("markets")}}
        if row.kind == "content" {
            Section("Выбрано: \(row.sources.count) из 24"){
                ForEach(row.sources){source in HStack{Text(source.name);Spacer();Button{row.sources.removeAll{$0.id == source.id}}label:{Image(systemName:"minus.circle")}.buttonStyle(.borderless)}}
            }
            Section("Telegram или своя RSS-лента"){
                TextField("@канал или https://…",text:$custom).autocorrectionDisabled()
                Button("Добавить"){do{let url=try PublicSource.parse(custom);guard row.sources.count<24 else{customError="В одной строке максимум 24 источника";return};if !row.sources.contains(where:{$0.url==url}){row.sources.append(StationSource(id:UUID().uuidString,name:custom,url:url,language:"ru",category:"custom"))};custom="";customError=""}catch{customError="Введите @имя публичного канала или HTTPS-адрес RSS"}}
                if !customError.isEmpty{Text(customError).font(.caption).foregroundStyle(.red)}
            }
            Section("Каталог"){
                Picker("Тема",selection:$category){ForEach(categories,id:\.0){key,title in Text(title).tag(key)}}
                TextField("Поиск источника",text:$query)
                ForEach(matching){source in Button{
                    if row.sources.contains(where:{$0.id==source.id}){row.sources.removeAll{$0.id==source.id}}
                    else if row.sources.count<24{row.sources.append(source)}
                }label:{HStack{VStack(alignment:.leading){Text(source.name).foregroundStyle(.primary);Text(source.language == "ru" ? "Русский":"Английский · оригинал").font(.caption).foregroundStyle(.secondary)};Spacer();if row.sources.contains(where:{$0.id==source.id}){Image(systemName:"checkmark.circle.fill")}}}.buttonStyle(.plain)}
                Text("В лабораторной версии автономный ТВ показывает оригинал. Перевод и все рыночные провайдеры ещё не перенесены.").font(.caption).foregroundStyle(.secondary)
            }
        } else if row.kind == "message" || row.kind == "offline" {
            Section("Одно сообщение на строку"){
                TextEditor(text:Binding(get:{row.messages.joined(separator:"\n")},set:{row.messages=$0.components(separatedBy:"\n")})).frame(minHeight:180)
                if row.kind == "offline" {Button("Добавить мысли дня"){row.messages=["Сначала главное. Остальное подождёт.","Хороший вопрос меняет направление разговора.","Один небольшой шаг сегодня лучше большого плана на потом."]}}
            }
        } else {Section("Символы Coinbase, через запятую"){TextField("BTC-USD, ETH-USD",text:Binding(get:{row.instruments.joined(separator:", ")},set:{row.instruments=$0.uppercased().split(separator:",").map{$0.trimmingCharacters(in:.whitespaces)}}));Text("Цена по запросу. Источник и время запроса видны в строке.").font(.caption)}}
        if model.profile.rows.count>1 {Section{Button("Удалить эту строку",role:.destructive){model.profile.rows.removeAll{$0.id==row.id};dismiss()}}}
    }.formStyle(.grouped).navigationTitle("Содержимое строки").toolbar{ToolbarItem(placement:.cancellationAction){Button("Отмена"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Готово"){save(row);dismiss()}}}}
    #if os(macOS)
    .frame(width:560,height:700)
    #endif
    }
}
