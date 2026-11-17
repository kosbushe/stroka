import Foundation
import SwiftUI
import Translation

extension AppModel {
    var translationCandidates:[Story] {
        guard settings.translateRussian == true else { return [] }
        let enabled = Set(settings.feeds.filter(\.enabled).map(\.name))
        let rows = (needsNews ? stories.filter{enabled.contains($0.source) && sourceLanguageMatches($0)} : []) + (settings.tickerRows != nil ? tickerRows.filter{$0.channel == .content && !ContentPack.find($0.packID).offline}.flatMap{rawStories(for:$0)} : (selectedPack.offline ? [] : currentRawStories))
        var seen = Set<String>()
        let candidates = rows.filter{originalLanguage($0) == "en" && ($0.date.map{$0 <= Date() && Date().timeIntervalSince($0)<48*3600} ?? false) && translationCache[$0.translationKey] == nil && !translationFailures.contains($0.translationKey) && seen.insert($0.translationKey).inserted}
        let grouped = Dictionary(grouping:candidates,by:{$0.source}),names = grouped.keys.sorted()
        var balanced:[Story] = []
        for i in 0..<(grouped.values.map(\.count).max() ?? 0) { for name in names { if let items = grouped[name],i<items.count { balanced.append(items[i]) } } }
        return balanced
    }
    func storeTranslations(_ values:[String:String]) {
        translationCache.merge(values,uniquingKeysWith:{$1})
        if translationCache.count>900 {
            let keep = Set((stories+contentStories).map(\.translationKey))
            translationCache = translationCache.filter{keep.contains($0.key)}
        }
        if let data = try? JSONEncoder().encode(translationCache) { defaults.set(data,forKey:"translationCache") }
        invalidateTextCache();objectWillChange.send()
    }
}
struct RussianTranslationHost:View {
    @ObservedObject var model:AppModel
    var body:some View {
        if #available(macOS 15,*) { TranslationWorker(model:model) }
        else { Color.clear.onAppear{if model.settings.translateRussian == true { model.translationStatus = L("Russian translation requires macOS 15 or later") }} }
    }
}
@available(macOS 15,*)
private struct TranslationWorker:View {
    @ObservedObject var model:AppModel
    @State private var configuration:TranslationSession.Configuration?
    @State private var busy = false
    var body:some View {
        Color.clear.frame(width:1,height:1)
            .task { await checkAvailability() }
            .onChange(of:model.translationSignal) { _,_ in Task { await checkAvailability() } }
            .onReceive(NotificationCenter.default.publisher(for:Notification.Name("StrokaPrepareTranslation"))) { _ in
                guard model.settings.translateRussian == true else { return }
                model.translationFailures = [];configuration = TranslationSession.Configuration(source:Locale.Language(identifier:"en"),target:Locale.Language(identifier:"ru"));configuration?.invalidate()
            }
            .translationTask(configuration) { @MainActor session in
                guard !busy,model.settings.translateRussian == true else { return };busy = true
                defer { busy = false }
                do {
                    try await session.prepareTranslation();model.translationNeedsDownload = false
                    var translated = 0
                    for _ in 0..<10 {
                        if Task.isCancelled || model.settings.translateRussian != true { break }
                        let batch = Array(model.translationCandidates.prefix(8));if batch.isEmpty { break }
                        model.translationStatus = L("Translating fresh headlines…")
                        var values:[String:String] = [:]
                        for story in batch {
                            if Task.isCancelled || model.settings.translateRussian != true { break }
                            do { let result = try await session.translate(story.text);if !result.targetText.isEmpty { values[story.translationKey] = result.targetText;translated += 1 } else { model.translationFailures.insert(story.translationKey) } }
                            catch { model.translationFailures.insert(story.translationKey) }
                        }
                        model.storeTranslations(values)
                    }
                    model.translationStatus = LF("%ld headlines translated",translated)
                } catch { model.translationStatus = L("Translation is not ready. Prepare the languages and try again.");model.translationNeedsDownload = true }
            }
    }
    @MainActor private func checkAvailability() async {
        guard model.settings.translateRussian == true,!busy else { return }
        let status = await LanguageAvailability().status(from:Locale.Language(identifier:"en"),to:Locale.Language(identifier:"ru"))
        switch status {
        case .installed:
            model.translationNeedsDownload = false
            if !model.translationCandidates.isEmpty { if configuration == nil { configuration = TranslationSession.Configuration(source:Locale.Language(identifier:"en"),target:Locale.Language(identifier:"ru")) } else { configuration?.invalidate() } }
        case .supported:model.translationNeedsDownload = true;model.translationStatus = L("Download English and Russian for on-device translation")
        case .unsupported:model.translationNeedsDownload = false;model.translationStatus = L("English-to-Russian translation is unavailable on this Mac")
        @unknown default:model.translationStatus = L("Translation is not ready. Prepare the languages and try again.")
        }
    }
}
