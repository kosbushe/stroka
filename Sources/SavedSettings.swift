import SwiftUI
import AppKit

extension AppModel {
    func savedSettingsNameAvailable(_ name:String)->Bool {
        let trimmed = name.trimmingCharacters(in:.whitespacesAndNewlines)
        return !trimmed.isEmpty && !presets.contains{$0.name.trimmingCharacters(in:.whitespacesAndNewlines).localizedCaseInsensitiveCompare(trimmed) == .orderedSame}
    }
    @discardableResult func saveNamedSettings(_ name:String)->Bool {
        guard savedSettingsNameAvailable(name) else{return false}
        saveSettingsNow()
        savePreset(name.trimmingCharacters(in:.whitespacesAndNewlines))
        return true
    }
    @discardableResult func loadSavedSettings(_ id:UUID)->Bool {
        guard let saved = presets.first(where:{$0.id == id}) else{return false}
        settings = saved.settings
        if let language = saved.newsLanguage {newsLanguage = language}
        normalizeContentNavigation();normalizeBroadcastStyle()
        prepareSimpleSetup(force:true);prepareDesktopTicker(force:true)
        sequence += 1;saveSettingsNow()
        return true
    }
    func deleteSavedSettings(_ id:UUID) {
        presets.removeAll{$0.id == id};persistPresets()
    }
}

struct SavedSettingsSection:View {
    @ObservedObject var model:AppModel
    @State private var saving = false
    @State private var deletion:ScenePreset?
    @State private var statusName = ""
    @State private var loaded = false
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L("Saved settings")).font(.headline)
            Text(L("Keep your sources, rows and appearance to use them again.")).font(.callout).foregroundStyle(.secondary)
            Button(L("Save current settings…")){saving = true}.accessibilityIdentifier("settings-save-current")
            if model.presets.isEmpty {
                Text(L("No saved settings yet. Save your current ticker to get started.")).font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing:0) {
                        ForEach(Array(model.presets.enumerated()),id:\.element.id) {index,saved in
                            if index > 0 {Divider()}
                            HStack(spacing:10) {
                                Text(saved.name).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                                Button(L("Load")) {
                                    if model.loadSavedSettings(saved.id){statusName = saved.name;loaded = true}
                                }.accessibilityLabel(LF("Load %@",saved.name))
                                Button {deletion = saved} label:{Image(systemName:"trash")}
                                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                                    .help(L("Delete saved settings"))
                                    .accessibilityLabel(LF("Delete %@",saved.name))
                            }.padding(.horizontal,12).padding(.vertical,10)
                        }
                    }
                }.frame(height:min(180,CGFloat(model.presets.count)*48))
                    .background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:8))
                    .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Color(nsColor:.separatorColor).opacity(0.5),lineWidth:0.5))
            }
            if !statusName.isEmpty {Text(LF(loaded ? "Loaded: %@" : "Saved: %@",statusName)).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("saved-settings-status")}
        }
        .sheet(isPresented:$saving) {
            SaveSettingsEditor(model:model){name in statusName = name;loaded = false}
        }
        .alert(L("Delete saved settings?"),isPresented:Binding(get:{deletion != nil},set:{if !$0{deletion = nil}}),presenting:deletion) {saved in
            Button(L("Cancel"),role:.cancel){deletion = nil}
            Button(L("Delete"),role:.destructive){model.deleteSavedSettings(saved.id);statusName = "";deletion = nil}
        } message:{saved in Text(LF("Delete “%@”? Your current ticker will stay unchanged.",saved.name))}
    }
}

struct SaveSettingsEditor:View {
    @ObservedObject var model:AppModel
    let onSave:(String)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var nameFocused:Bool
    var trimmedName:String {name.trimmingCharacters(in:.whitespacesAndNewlines)}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(L("Save current settings")).font(.title2.weight(.semibold))
            Text(L("Give this setup a name so you can load it later.")).font(.callout).foregroundStyle(.secondary)
            TextField(L("For example: Work or Event"),text:$name).textFieldStyle(.roundedBorder)
                .accessibilityLabel(L("Settings name")).accessibilityIdentifier("saved-settings-name")
                .focused($nameFocused).onSubmit(save)
            if !trimmedName.isEmpty && !model.savedSettingsNameAvailable(trimmedName) {
                Text(L("This name is already used. Choose another name.")).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button(L("Cancel")){dismiss()}.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Save"),action:save).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(!model.savedSettingsNameAvailable(trimmedName))
            }
        }.padding(24).frame(width:420).environment(\.locale,Localization.locale)
            .onAppear{nameFocused = true}
    }
    private func save() {
        guard model.saveNamedSettings(trimmedName) else{return}
        onSave(trimmedName);dismiss()
    }
}
