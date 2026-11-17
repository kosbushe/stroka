import Foundation

// Age always refers to the publisher's original timestamp, never fetch or translation time.
enum EditorialPolicy {
    static func expires(_ story:Story,extended:Set<String>,allowExtended:Bool)->Date? {
        story.date?.addingTimeInterval(allowExtended && extended.contains(story.id) ? 48*3600 : 24*3600)
    }
    static func accepts(_ story:Story,now:Date,extended:Set<String>,allowExtended:Bool)->Bool {
        guard let date = story.date,date <= now,let end = expires(story,extended:extended,allowExtended:allowExtended) else { return false }
        return now < end
    }
    static func terms(_ input:String)->[String] { input.components(separatedBy:CharacterSet(charactersIn:",;\n")).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter{!$0.isEmpty} }
    static func matches(_ text:String,include:String,exclude:String)->Bool {
        let yes = terms(include),no = terms(exclude)
        return (yes.isEmpty || yes.contains{text.localizedCaseInsensitiveContains($0)}) && !no.contains{text.localizedCaseInsensitiveContains($0)}
    }
}
extension AppModel {
    var currentRawStories:[Story] {
        let pack = selectedPack
        if pack.offline { return BuiltinCollections.stories(pack:pack,language:settings.offlineLanguage.flatMap(NewsLanguage.init(rawValue:)) ?? (settings.translateRussian == true ? .russian : newsLanguage)) }
        let names = Set(enabledContentSources.map(\.name))
        var seen = Set<String>()
        return contentStories.filter{(($0.sourceURL.map{url in enabledContentSources.contains{$0.url == url}}) ?? ($0.packID == pack.id && names.contains($0.source))) && sourceLanguageMatches($0) && seen.insert($0.id).inserted}
    }
    func originalLanguage(_ story:Story)->String {
        story.language ?? settings.feeds.first(where:{$0.name == story.source})?.language ?? contentSources.first(where:{$0.name == story.source})?.language ?? (story.text.range(of:"[А-Яа-яЁё]",options:.regularExpression) != nil ? "ru" : "en")
    }
    func sourceLanguageMatches(_ story:Story)->Bool { newsLanguage == .all || originalLanguage(story) == (newsLanguage == .russian ? "ru" : "en") }
    func fresh(_ story:Story,now:Date = Date())->Bool { EditorialPolicy.accepts(story,now:now,extended:Set(settings.extendedStories ?? []),allowExtended:settings.allowExtended ?? false) }
    func displayStory(_ story:Story,offline:Bool = false,applyRules:Bool = true)->Story? {
        let reviewEligible = story.date.map{$0 <= Date() && Date().timeIntervalSince($0)<48*3600} ?? false
        guard offline || (applyRules ? fresh(story) : reviewEligible) else { return nil }
        var result = story
        if settings.translateRussian == true && !offline && originalLanguage(story) != "ru" {
            guard let translated = translationCache[story.translationKey],!translated.isEmpty else { return nil }
            result.originalText = story.text;result.text = translated;result.isTranslated = true
        }
        if applyRules {
            guard offline || settings.shortHeadlines != true || ShortText.fits(result.text),EditorialPolicy.matches(result.text,include:settings.sessionKeywords ?? "",exclude:settings.excludedKeywords ?? "") else { return nil }
        }
        return result
    }
    var editorialReviewStories:[Story] { currentRawStories.filter { story in guard let date = story.date else { return false };return date <= Date() && Date().timeIntervalSince(date) < 48*3600 } }
    func highlight(_ story:Story,enabled:Bool) {
        var ids = Set(settings.extendedStories ?? []);if enabled { ids.insert(story.id);settings.allowExtended = true } else { ids.remove(story.id) };settings.extendedStories = Array(ids).sorted()
    }
    func scheduleEditorialExpiry() {
        editorialWake?.invalidate();editorialWake = nil
        let now = Date(),extended = Set(settings.extendedStories ?? [])
        let dates = (stories+contentStories).compactMap { story -> Date? in
            guard let date = story.date else { return nil }
            if date > now { return date }
            return EditorialPolicy.expires(story,extended:extended,allowExtended:settings.allowExtended ?? false)
        }.filter{$0 > now}
        guard let next = dates.min() else { return }
        let timer = Timer(timeInterval:max(0.001,next.timeIntervalSince(now)),repeats:false) { [weak self] _ in
            guard let self else { return };self.invalidateTextCache();self.objectWillChange.send();self.scheduleEditorialExpiry()
        };timer.tolerance = 0;editorialWake = timer;RunLoop.main.add(timer,forMode:.common)
    }
}

extension AppModel {
    func sourceSummary(_ feed:FeedSource)->String {
        guard let state = sourceLoadState[feed.url] else { return L("Not checked yet") }
        switch state {
        case .loading:return L("Refreshing…")
        case .failed(let reason):return LF("Couldn’t refresh: %@",reason)
        case .loaded:
            let rows = contentStories.filter{$0.sourceURL == feed.url || ($0.sourceURL == nil && $0.packID == selectedPack.id && $0.source == feed.name)}
            let freshRows = rows.filter{fresh($0)}
            let eligible = freshRows.compactMap{displayStory($0)}.count
            if eligible > 0 {return LF("%ld eligible headlines",eligible)}
            if freshRows.isEmpty {return L("No recent news with a publication date")}
            if settings.translateRussian == true && freshRows.contains(where:{originalLanguage($0) != "ru" && translationCache[$0.translationKey] == nil}) {return L("Waiting for Russian translation")}
            return L("No headlines match your topic or length filters")
        }
    }
}
