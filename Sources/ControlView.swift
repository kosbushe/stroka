import SwiftUI
import AppKit

struct ControlView: View {
    @ObservedObject var model: AppModel
    @State private var sourceSheet = false
    @State private var contentInspector = false
    var isContentWorkspace:Bool { [.content,.ai,.mix].contains(model.settings.channel) }
    @State private var urgentSheet = false
    @State private var remoteSheet = false
    @State private var urgentText = ""
    @State private var privacySheet = false
    @State private var helpSheet = false
    @State var inspectorTab = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 176)
                Divider()
                if isContentWorkspace {
                    ContentGalleryView(model:model,showsInspector:$contentInspector) { sourceSheet = true }
                } else {
                GeometryReader { viewport in
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(L("Preview")).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if let mode = model.activeMode { Label(mode.title, systemImage: "display").font(.system(size: 11)).foregroundStyle(teal) }
                        else { Text(L("Display Off")).font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                    PreviewDisplay(model: model).aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxHeight: max(180, min(300, viewport.size.height * 0.38))).clipShape(RoundedRectangle(cornerRadius: BusheDesign.displayRadius)).overlay(RoundedRectangle(cornerRadius: BusheDesign.displayRadius).strokeBorder(Color(nsColor: .separatorColor).opacity(0.45))).frame(maxWidth: .infinity, alignment: .center)
                    if model.settings.look.isBroadcast { BroadcastStripPreview(model:model).frame(height:model.settings.stripHeight <= 72 ? max(28,model.settings.stripHeight*0.7) : (model.dualBandActive ? 112 : 76)).clipShape(RoundedRectangle(cornerRadius:8)) }
                    playback
                    Divider()
                    HStack {
                        Text(model.settings.channel.title).font(.system(size: 19, weight: .semibold))
                        Spacer()
                        if model.settings.channel == .ai || model.settings.channel == .mix {
                            Button { sourceSheet = true } label: { Label(L("Sources"), systemImage: "slider.horizontal.3") }
                            Button { model.refreshNews() } label: { Image(systemName: "arrow.clockwise") }.disabled(model.refreshing).help(L("Refresh feeds"))
                        }
                    }
                    channelContent.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }.padding(BusheDesign.page)
                }.frame(minWidth: 490, maxWidth: .infinity)
                }
                if !isContentWorkspace || contentInspector {
                    Divider()
                    VStack(spacing:0) {
                        if isContentWorkspace { HStack { Text(L("Display Settings")).font(.caption.weight(.semibold));Spacer();Button { contentInspector = false } label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel(L("Close display settings")) }.padding(.horizontal,21).padding(.top,14) }
                        inspector
                    }.frame(width:310)
                }
            }.id(model.interfaceLanguage)
            Divider()
            ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Circle().fill(model.needsNews ? (model.refreshing ? Color.orange : (model.availableStories.isEmpty ? Color.gray : teal)) : (model.activeMode == nil ? Color.gray : teal)).frame(width: 6, height: 6)
                Text(model.needsNews ? (model.refreshing ? L("Refreshing headlines…") : LF("%ld headlines · refreshed every %ld min", model.availableStories.count, Int(model.settings.rssMinutes))) : model.settings.channel.title + " · " + LF("%ld messages", model.lines.count))
                Spacer()
                Text(L("On display: Space to pause · ← → to browse · Esc to close")).foregroundStyle(.secondary)
            }
            Text(L("On display: Space to pause · ← → to browse · Esc to close")).foregroundStyle(.secondary)
            }.font(.system(size: 11)).padding(.horizontal, 20).padding(.vertical, 9)
        }
        .environment(\.locale, Localization.locale)
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1010, minHeight: 580)
        .sheet(isPresented:$sourceSheet) { FeedChooserView(model:model) }
        .sheet(isPresented: $urgentSheet) { urgentEditor }
        .sheet(isPresented: $remoteSheet) { RemoteView(model: model) }
        .sheet(isPresented: $privacySheet) { SettingsView(model: model) }
        .sheet(isPresented: $helpSheet) { HelpView() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StrokaHelp"))) { _ in helpSheet = true }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StrokaPrivacy"))) { _ in privacySheet = true }
        .background { RussianTranslationHost(model:model) }
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaChooseFeed"))) { _ in model.normalizeContentNavigation();model.settings.channel = .content }
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaContentSources"))) { _ in sourceSheet = true }
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaDisplaySettings"))) { note in
            guard let sender = note.object as? AppModel,sender === model else {return}
            sourceSheet = false;urgentSheet = false;remoteSheet = false;privacySheet = false;helpSheet = false
            inspectorTab = 0;contentInspector = true
        }
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaAppearance"))) { _ in inspectorTab = 1;contentInspector = true }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StrokaRemote"))) { _ in remoteSheet = true }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StrokaUrgent"))) { _ in urgentSheet = true }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StrokaSavePreset"))) { _ in saveScene() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StrokaReset"))) { _ in resetData() }
    }
    var sidebar: some View {
        List(selection: Binding(get:{isContentWorkspace ? Channel.content : model.settings.channel},set:{model.settings.channel = $0})) {
            Section(L("Sources")) {
                ForEach(ContentCatalog.navigation) { channel in Label(channel.title, systemImage: channel.icon).font(.system(size: 13)).padding(.vertical, 3).tag(channel) }
            }
        }.listStyle(.sidebar)
    }
    var playback: some View {
        HStack(spacing: 10) {
            Button { model.step(-1) } label: { Image(systemName: "backward.end.fill").frame(width: 18) }.help(L("Previous message"))
            Button { model.playing.toggle() } label: { Label(model.playing ? L("Pause") : L("Resume"), systemImage: model.playing ? "pause.fill" : "play.fill") }.frame(minWidth: 95)
            Button { model.step(1) } label: { Image(systemName: "forward.end.fill").frame(width: 18) }.help(L("Next message"))
            Spacer()
            if !model.urgent.isEmpty { Button(L("Resume Feed")) { model.urgent = "" }.tint(.orange) }
            Text(LF("%ld messages", model.lines.count)).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder var channelContent: some View {
        switch model.settings.channel {
        case .message:
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Each new line becomes a separate message.")).font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: $model.settings.messages).font(.system(size: 16)).padding(8).scrollContentBackground(.hidden).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.18))).accessibilityLabel(L("Message queue"))
            }
        case .ai,.content,.mix: ContentLibraryView(model:model)
        case .markets: MarketsView(model:model)
        }
    }

    func storyList(_ stories: [Story]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(stories) { story in
                    Button { openLink(story.link) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(story.source); Spacer(); if let date = story.date { Text(date, style: .relative) } }.font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(story.text).font(.system(size: 14, weight: .medium)).multilineTextAlignment(.leading).lineLimit(3)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    Divider()
                }
            }.padding(.trailing, 6)
        }
    }
    var inspector: some View {
        VStack(spacing:0) {
            Picker(L("Inspector"),selection:$inspectorTab) { Text(L("Controls")).tag(0); Text(L("Appearance")).tag(1) }.pickerStyle(.segmented).labelsHidden().padding(.horizontal,BusheDesign.page).padding(.top,12).padding(.bottom,8).accessibilityLabel(L("Inspector"))
            if inspectorTab == 0 { ScrollView { VStack(alignment:.leading,spacing:BusheDesign.section) {
                sectionLabel(L("Output"))
                Picker(L("Screen"), selection: $model.selectedScreen) {
                    ForEach(Array(model.screens.enumerated()), id: \.offset) { i, screen in Text(screen.localizedName).tag(i) }
                }.labelsHidden().frame(maxWidth: .infinity).accessibilityLabel(L("Output screen"))
                Picker(L("Mode"), selection: $model.previewMode) { ForEach(OutputMode.allCases) { Text($0.title).tag($0) } }
                if model.previewMode == .strip {
                    Picker(L("Placement"), selection: Binding(get: { model.settings.resolvedPlacement }, set: { model.settings.stripPlacement = $0 })) { ForEach(StripPlacement.allCases) { Text($0.title).tag($0) } }
                    if model.settings.look.isBroadcast {
                        Picker(L("Strip Size"),selection:Binding(get:{model.settings.resolvedStripDensity},set:{model.settings.applyDensity($0)})) { ForEach(StripDensity.allCases) { Text($0.title).tag($0) } }
                    }
                    labeledSlider(L("Strip Thickness"), value:Binding(get:{model.settings.resolvedStripHeight},set:{model.settings.stripDensity = .custom;model.settings.stripHeight = min(180,max(45,$0))}), range:45...180, suffix:" pt")
                }
                if model.settings.look.isBroadcast {
                    Toggle(L("Two Rows: News + Markets"),isOn:Binding(get:{model.settings.dualTicker ?? false},set:{ enabled in
                        let density = model.settings.resolvedStripDensity
                        model.settings.dualTicker = enabled
                        if enabled { model.settings.dualUpperChannel = [Channel.message,.ai,.content].contains(model.settings.channel) ? model.settings.channel : .content; model.settings.motion = .horizontal }
                        model.settings.applyDensity(density)
                        if model.settings.stripHeight < 45 { model.settings.stripHeight = 45 }
                    })).toggleStyle(.checkbox)
                    if model.dualBandActive {
                        Picker(L("Upper Row"),selection:Binding(get:{model.upperChannel},set:{model.settings.dualUpperChannel = $0})) { Text(L("Content")).tag(Channel.content); Text(L("My Text")).tag(Channel.message) }
                        if model.upperChannel == .content { Picker(L("Content Feed"),selection:Binding(get:{model.selectedPack.id},set:{model.selectPack($0)})) { ForEach(ContentCatalog.packs) { Text(L($0.catalogTitle)).tag($0.id) } } }
                        labeledSlider(L("Markets Speed"),value:Binding(get:{model.settings.marketSpeed ?? 85},set:{model.settings.marketSpeed = $0}),range:20...260,suffix:"")
                        Text(L("The lower row shows your configured market instruments. Both rows pause together.")).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                }
                Divider()
                sectionLabel(L("Motion"))
                Picker(L("Style"), selection: $model.settings.motion) { ForEach(Motion.allCases) { Text($0.title).tag($0) } }.disabled(model.dualBandActive)
                labeledSlider(L("Speed"), value: $model.settings.speed, range: 20...260, suffix: "")
                if model.settings.motion == .horizontal || model.dualBandActive || model.settings.resolvedPlacement.vertical {
                    VStack(alignment:.leading,spacing:8) {
                        Picker(L("Message Separator"),selection:Binding(get:{ MessageSeparators.options.contains(model.settings.resolvedSeparator) ? model.settings.resolvedSeparator : "custom" },set:{ model.settings.separator = $0 == "custom" ? "●" : $0 })) {
                            ForEach(MessageSeparators.options,id:\.self){Text($0+"  "+L(MessageSeparators.labelKey($0))).tag($0)};Text(L("Custom")).tag("custom")
                        }
                        TextField(L("Your separator"),text:Binding(get:{model.settings.resolvedSeparator},set:{model.settings.separator = String($0.components(separatedBy:.newlines).joined(separator:" ").prefix(12))})).textFieldStyle(.roundedBorder).font(.system(size:13,design:.monospaced))
                        Text(L("Messages follow one another without a blank pause. Both rows use this separator.")).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                }
                labeledSlider(L("Text Size"), value: $model.settings.fontSize, range:(model.settings.look.isBroadcast && model.settings.stripHeight <= 72 ? 12.0 : 28.0)...180, suffix:" pt")
                if model.settings.motion == .phrases && !model.dualBandActive { labeledSlider(L("Phrase Duration"), value: $model.settings.holdSeconds, range: 2...30, suffix: L(" s")) }
                DisclosureGroup(L("Advanced")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(L("Reverse Direction"), isOn: $model.settings.reverse).disabled(model.settings.motion == .phrases || model.settings.motion == .words)
                        Toggle(L("Mirror Text"), isOn: $model.settings.mirror)
                        Toggle(L("Reduce Motion"), isOn: $model.reduceMotion)
                        if model.settings.resolvedComposition != .poster { TextField(L("Display label"), text: $model.settings.brand).textFieldStyle(.roundedBorder) }
                    }.toggleStyle(.checkbox).padding(.top, 10)
                }
                Divider()
                DisclosureGroup(L("Idle Display")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(L("Show When Idle"), isOn: $model.settings.idleEnabled)
                        if model.settings.idleEnabled {
                            Picker(L("After"), selection: $model.settings.idleMinutes) { Text(L("1 minute")).tag(1.0); Text(L("5 minutes")).tag(5.0); Text(L("10 minutes")).tag(10.0); Text(L("15 minutes")).tag(15.0) }
                            Text(L("Works while Stroka is open. Your Mac’s lock screen is managed separately.")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 10)
                }
            }.font(.system(size:12)).padding(BusheDesign.page) } }
            else { ScrollView { VStack(alignment:.leading,spacing:18) {
                Picker(L("Visual Style"),selection:Binding(get:{model.settings.look},set:{model.applyLook($0)})) { Section(L("Television Models")) { ForEach(Look.broadcastLooks) { Text($0.title).tag($0) } } }
                if model.settings.look.isBroadcast { BroadcastBrandControls(model:model) }
                DisclosureGroup(L("Browse Styles")) { BroadcastModelPicker(model:model) }
                if !model.settings.look.isBroadcast {
                Picker(L("Layout"), selection: Binding(get: { model.settings.resolvedComposition }, set: { model.settings.composition = $0 })) { ForEach(Composition.allCases) { Text($0.title).tag($0) } }
                if model.settings.resolvedComposition == .poster {
                    TextField(L("Poster title"), text: $model.settings.brand).textFieldStyle(.roundedBorder)
                    TextField(L("Subtitle"), text: Binding(get: { model.settings.caption ?? "" }, set: { model.settings.caption = $0 })).textFieldStyle(.roundedBorder)
                }
                } else { Text(L("Your style applies to both ticker rows.")).font(.system(size:11)).foregroundStyle(.secondary) }
            }.font(.system(size:12)).padding(BusheDesign.page) } }
        }
        .safeAreaInset(edge:.bottom,spacing:0) { outputButtons }
    }
    var outputButtons: some View {
        VStack(spacing: 12) {
            Divider()
            Button { model.outputs.show(model.previewMode) } label: { Label(model.activeMode == nil ? L("Start Display") : L("Update Display"), systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(.borderedProminent).controlSize(.large)
            if model.activeMode != nil { Button(L("Stop Display")) { model.outputs.stop() }.buttonStyle(.borderless).foregroundStyle(.secondary) }
        }.padding(.horizontal, 20).padding(.bottom, 18).background(Color(nsColor: .windowBackgroundColor))
    }
    func sectionLabel(_ text: String) -> some View { Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
    func labeledSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(spacing: 4) { HStack { Text(label); Spacer(); Text("\(Int(value.wrappedValue))\(suffix)").monospacedDigit().foregroundStyle(.secondary) }.font(.system(size: 12)); Slider(value: value, in: range).tint(teal).accessibilityLabel(label).accessibilityValue("\(Int(value.wrappedValue))\(suffix)") }
    }
    var urgentEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L("Show an Announcement"), systemImage: "megaphone").font(.title2.weight(.semibold))
            Text(L("The announcement stays on screen until you resume the feed.")).font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $urgentText).accessibilityLabel(L("Announcement text")).font(.title3).frame(height: 120).padding(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
            HStack { Button(L("Cancel")) { urgentSheet = false }; Spacer(); Button(L("Resume Feed")) { model.urgent = ""; urgentSheet = false }; Button(L("Show")) { model.urgent = urgentText; urgentSheet = false }.buttonStyle(.borderedProminent).tint(teal).disabled(urgentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(28).frame(width: 520)
    }
    func saveScene() {
        let alert = NSAlert(); alert.messageText = L("Save Preset"); alert.informativeText = L("Save your text, sources, and appearance.")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24)); input.placeholderString = L("For example: Meeting · Welcome"); alert.accessoryView = input; alert.addButton(withTitle: L("Save")); alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); if !name.isEmpty { model.savePreset(name) } }
    }
    func resetData() {
        let alert = NSAlert(); alert.messageText = L("Delete Stroka’s local data?"); alert.informativeText = L("Your messages, presets, and cached headlines will be deleted. This can’t be undone."); alert.alertStyle = .warning; alert.addButton(withTitle: L("Cancel")); alert.addButton(withTitle: L("Delete"))
        if alert.runModal() == .alertSecondButtonReturn {
            model.invalidatePendingContent(); model.outputs.stop(); model.enableRemote(false);model.setTVSharing(false)
            model.settings = Settings(); model.presets = []; model.persistPresets(); model.stories = []; model.contentStories = []; model.defaults.removeObject(forKey: "contentCache");model.defaults.removeObject(forKey:"translationCache");model.translationCache = [:]; model.defaults.removeObject(forKey: "newsCache"); model.newsLanguage = .english; model.feedStatus = [:]; model.feedUpdated = [:]; model.sequence += 1
        }
    }
}

func emptyState(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(detail).font(.callout).foregroundStyle(.secondary) }.padding(.vertical, 18)
}
func openLink(_ string: String) { if let url = URL(string: string), ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) } }

struct FeedSettingsView: View {
    @ObservedObject var model: AppModel; @Environment(\.dismiss) var dismiss
    @State private var name = ""; @State private var address = ""; @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("AI News Sources")).font(.title2.weight(.semibold))
            Text(L("RSS and Atom headlines link to the original article. Articles remain in their original language.")).font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 14) {
                    ForEach($model.settings.feeds) { $feed in
                        HStack(alignment: .top) {
                            Toggle("", isOn: $feed.enabled).labelsHidden().accessibilityLabel(LF("Enable %@", feed.name))
                            VStack(alignment: .leading, spacing: 4) { Text(feed.name).font(.headline); Text(feed.url).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1); Text(model.feedStatus[feed.id] ?? L("Not refreshed yet")).font(.system(size: 11)).foregroundStyle(.secondary); if let date = model.feedUpdated[feed.id] { Text(LF("Received %@", localTime(date))).font(.system(size: 11)).foregroundStyle(.secondary) } }
                            Spacer()
                            Button { let id = feed.id; model.settings.feeds.removeAll { $0.id == id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help(L("Remove source"))
                        }; Divider()
                    }
                }
            }.frame(height: 220)
            HStack { TextField(L("Name"), text: $name).frame(width: 150); TextField("https://… / RSS", text: $address); Button(L("Add")) { add() } }.textFieldStyle(.roundedBorder)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            Picker(L("Refresh"), selection: $model.settings.rssMinutes) { Text(L("Every minute")).tag(1.0); Text(L("Every 3 minutes")).tag(3.0); Text(L("Every 5 minutes")).tag(5.0); Text(L("Every 15 minutes")).tag(15.0) }
            HStack { Button(L("Restore Defaults")) { model.settings.feeds = FeedSource.defaults }; Spacer(); Button(L("Refresh")) { model.refreshNews() }.disabled(model.refreshing); Button(L("Done")) { dismiss() }.buttonStyle(.borderedProminent).tint(teal) }
        }.padding(28).frame(width: 620)
    }
    func add() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines); let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let url = URL(string: a), url.scheme == "https", url.host != nil else { error = L("Enter a name and the full HTTPS feed URL."); return }
        guard !model.settings.feeds.contains(where: { $0.name == n || $0.url == a }) else { error = L("This source has already been added."); return }
        model.settings.feeds.append(FeedSource(name: n, url: a)); name = ""; address = ""; error = ""; model.refreshNews()
    }
}

struct MarketsView: View {
    @ObservedObject var model:AppModel
    @State private var pairs = "";@State private var picker = false
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text(L("Your Watchlist")).font(.headline);Spacer();Button(L("Instruments…")) { picker = true };Button { model.market.refreshWatchlist() } label:{Image(systemName:"arrow.clockwise")}.help(L("Refresh market data")) }
            Text(model.moexStatus).font(.caption).foregroundStyle(.secondary)
            Text(model.cryptoStatus).font(.caption).foregroundStyle(.secondary)
            ScrollView { LazyVStack(spacing:0) { ForEach(model.quotes) { quote in
                HStack(spacing:12) {
                    VStack(alignment:.leading,spacing:4) { Text(quote.id).font(.system(size:14,weight:.semibold)); if let label = quote.label { Text(label).font(.caption).lineLimit(1) };Text(quote.source+" · "+quote.dataNote+" · "+quote.timeLabel).font(.caption).foregroundStyle(.secondary) }
                    Spacer();VStack(alignment:.trailing,spacing:4) { Text(quote.displayValue).font(.system(size:17,weight:.medium,design:.monospaced));if let change = quote.change { Text(String(format:"%+.2f%%",change)).font(.caption.monospacedDigit()).foregroundStyle(change >= 0 ? teal : .red) } }
                }.padding(.vertical,10);Divider()
            } } }
            if model.quotes.isEmpty { Text(L("No market data yet. Stroka will reconnect when the connection is restored.")).font(.callout).foregroundStyle(.secondary) }
            DisclosureGroup(L("Crypto Pairs")) { HStack { TextField("BTC-USD, ETH-USD",text:$pairs).textFieldStyle(.roundedBorder);Button(L("Apply")) { model.settings.cryptoPairs = pairs } }.padding(.top,8) }
            Text(L("MOEX shares may be delayed by 15 minutes. Central-bank rates are daily reference values, not tradable prices.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.onAppear { pairs = model.settings.cryptoPairs }.sheet(isPresented:$picker) { MarketPickerView(model:model) }
    }
}

struct RemoteView: View {
    @ObservedObject var model: AppModel; @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L("Phone Remote"), systemImage: "iphone").font(.title2.weight(.semibold))
            Text(L("Connect your Mac and phone to the same trusted Wi-Fi network. Anyone with the link can control the display.")).font(.callout).foregroundStyle(.secondary)
            Toggle(L("Enable Local Remote"), isOn: Binding(get: { model.remoteEnabled }, set: { model.enableRemote($0) }))
            if model.remoteEnabled {
                Text(model.remoteInfo.isEmpty ? L("Starting…") : model.remoteInfo).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                if let image = qrImage(model.remoteInfo) { Image(nsImage: image).interpolation(.none).resizable().frame(width: 160, height: 160).frame(maxWidth: .infinity) }
                Button(L("Copy Link")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.remoteInfo, forType: .string) }.disabled(!model.remoteInfo.hasPrefix("http"))
            }
            HStack { Spacer(); Button(L("Done")) { dismiss() }.buttonStyle(.borderedProminent).tint(teal) }
        }.padding(28).frame(width: 500)
    }
    func qrImage(_ text: String) -> NSImage? {
        guard text.hasPrefix("http"), let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }; f.setValue(Data(text.utf8), forKey: "inputMessage"); f.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = f.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }; return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var television = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L("Settings")).font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    VStack(alignment:.leading,spacing:8) {
                        Picker(L("Interface Language"), selection:$model.interfaceLanguage) {
                            ForEach(InterfaceLanguage.allCases){Text($0.title).tag($0)}
                        }.pickerStyle(.segmented)
                        Text(L("English is the default interface language. News language is selected separately.")).font(.callout).foregroundStyle(.secondary)
                    }
                    Divider()
                    SavedSettingsSection(model:model)
                    Divider()
                    WindowFitControls(model:model)
                    Divider()
                    VStack(alignment:.leading,spacing:10) {
                        Text(L("Television")).font(.headline)
                        Text(L("Use your ticker on Android TV or Google TV. Test setup.")).font(.callout).foregroundStyle(.secondary)
                        Button {television = true} label:{Label(L("Connect a TV…"),systemImage:"tv")}
                    }
                    Divider()
                    DisclosureGroup(L("Privacy")) {
                        Text(content).font(.body).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(.top,8)
                    }
                }.padding(.trailing,6)
            }.frame(maxHeight:480)
            HStack { Spacer(); Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 620).environment(\.locale, Localization.locale).sheet(isPresented:$television){TVConnectionView(model:model)}
    }
    var content: String { Localization.bundle.url(forResource: "Privacy", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? L("Messages and settings stay on your Mac. Feeds connect directly to the selected publishers. Offline collections are bundled with the app. No analytics or ads.") }
}

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L("Quick Start")).font(.title2.weight(.semibold))
            ScrollView { Text(content).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 380)
            HStack { Spacer(); Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 620)
    }
    var content: String { Localization.bundle.url(forResource: "Help", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "" }
}
