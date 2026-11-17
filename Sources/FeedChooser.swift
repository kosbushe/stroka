import SwiftUI

struct EditorialStoryRow:View {
    @ObservedObject var model:AppModel;let story:Story;var review = false
    var marked:Bool { model.settings.extendedStories?.contains(story.id) == true }
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            HStack(spacing:8) {
                Text(story.source)
                if let date = story.date { Text(date,style:.relative) }
                if story.isExcerpt == true { Text(L("Excerpt")) }
                if story.isTranslated == true { Text(L("Translated")) }
                if model.settings.shortHeadlines == true { Text(LF("%ld words",story.wordCount)) }
                Spacer()
                if story.date != nil { Button { model.highlight(story,enabled:!marked) } label:{Image(systemName:marked ? "star.fill" : "star")}.buttonStyle(.plain).foregroundStyle(marked ? Color.orange : Color.secondary).help(L("Allow this highlight for up to 48 hours from publication")) }
                if !story.link.isEmpty { Button { openLink(story.link) } label:{Image(systemName:"arrow.up.right")}.buttonStyle(.plain).accessibilityLabel(L("Open original article")) }
            }.font(.system(size:11)).foregroundStyle(.secondary)
            Text(story.text).font(.system(size:14,weight:.medium)).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
            if review && !model.selectedContent.contains(where:{$0.id == story.id}) {Text(L("Not currently in the ticker")).font(.caption).foregroundStyle(.secondary)}
            if marked { Text(L("Selected highlight · maximum 48 hours")).font(.caption).foregroundStyle(.orange) }
        }.padding(.vertical,9)
    }
}
struct FeedChooserView:View {
    @ObservedObject var model:AppModel;@Environment(\.dismiss) var dismiss
    @State private var storySearch = "";@State private var tab = "sources";@State private var search = "";@State private var name = "";@State private var address = "";@State private var error = ""
    var sourceRows:[FeedSource] {
        let rows = model.selectedPack.id == "custom" ? NewsCatalog.all.map(\.feed)+(model.settings.customFeeds ?? [])+ContentPack.find("telegram").sources : model.contentSources
        var seen = Set<String>();return rows.filter { feed in
            seen.insert(feed.url).inserted && (model.newsLanguage == .all || feed.language == nil || feed.language == (model.newsLanguage == .english ? "en" : "ru")) && (search.isEmpty || (feed.name+" "+feed.url).localizedCaseInsensitiveContains(search))
        }.sorted { (selected($0) ? 0 : 1,$0.name) < (selected($1) ? 0 : 1,$1.name) }
    }
    func selected(_ feed:FeedSource)->Bool { model.selectedPack.id == "custom" ? model.settings.customFeeds?.contains{$0.url == feed.url} == true : model.enabledContentSources.contains{$0.url == feed.url} }
    func select(_ feed:FeedSource,_ enabled:Bool) {
        if model.selectedPack.id == "custom" {
            if enabled,!selected(feed) { model.settings.customFeeds = (model.settings.customFeeds ?? [])+[feed] }
            else if !enabled { model.settings.customFeeds?.removeAll{$0.url == feed.url} }
        } else { model.setContentSource(feed,enabled:enabled) }
    }
    var body:some View {
        VStack(spacing:0) {
            HStack { VStack(alignment:.leading,spacing:4) { Text(model.selectedPack.offline ? L("Content Setup") : L("Content Sources")).font(.system(size:25,weight:.semibold));Text(model.selectedPack.offline ? L("Choose a language and review your ready-made messages.") : L("Choose sources, define your session topic, then review what will run.")).font(.callout).foregroundStyle(.secondary) };Spacer();Button(L("All Content")){dismiss()}.keyboardShortcut(.cancelAction) }.padding(24)
            Divider()
            HStack(spacing:0) {
                List(selection:Binding<String?>(get:{model.selectedPack.id},set:{if let id = $0 { model.selectPack(id);if model.servicesStarted { model.refreshContent() };tab = model.selectedPack.offline ? "preview" : "sources" }})) {
                    ForEach(ContentCatalog.groups) { section in Section(L(section.title)) { ForEach(section.packs) { pack in Label(L(pack.catalogTitle),systemImage:pack.symbol).font(.system(size:12)).padding(.vertical,3).tag(pack.id) } } }
                }.listStyle(.sidebar).frame(width:220)
                Divider()
                VStack(alignment:.leading,spacing:14) {
                    HStack { Text(L(model.selectedPack.catalogTitle)).font(.title3.weight(.semibold));Spacer();Text(model.selectedPack.offline ? L("Offline Collection") : L("News · 24 hours")).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    Text(L(model.selectedPack.catalogDetail)).font(.caption).foregroundStyle(.secondary)
                    if model.selectedPack.offline {
                        Picker(L("Content Language"),selection:Binding(get:{model.settings.offlineLanguage.flatMap(NewsLanguage.init(rawValue:)) ?? (model.settings.translateRussian == true ? .russian : model.newsLanguage)},set:{model.settings.offlineLanguage = $0.rawValue})) { ForEach(NewsLanguage.allCases){Text($0.title).tag($0)} }
                    } else {
                        HStack { Picker(L("Source Language"),selection:$model.newsLanguage){ForEach(NewsLanguage.allCases){Text($0.title).tag($0)}};Toggle(L("Translate to Russian"),isOn:Binding(get:{model.settings.translateRussian ?? false},set:{model.settings.translateRussian = $0;if $0 { model.newsLanguage = .all }})).toggleStyle(.checkbox) }
                        if model.settings.translateRussian == true { HStack { Text(model.translationStatus.isEmpty ? L("Fresh English headlines are translated on this Mac") : model.translationStatus).font(.caption).foregroundStyle(.secondary);Spacer();Button(model.translationNeedsDownload ? L("Prepare Translation…") : L("Translate Headlines")){NotificationCenter.default.post(name:Notification.Name("StrokaPrepareTranslation"),object:nil)} } }
                    }
                    HStack { TextField(L("Session or event name"),text:Binding(get:{model.settings.sessionTitle ?? ""},set:{model.settings.sessionTitle = $0}));TextField(L("Keywords, separated by commas"),text:Binding(get:{model.settings.sessionKeywords ?? ""},set:{model.settings.sessionKeywords = $0})) }.textFieldStyle(.roundedBorder)
                    DisclosureGroup(L("More filters")) {
                        VStack(alignment:.leading,spacing:8) { TextField(L("Exclude keywords, separated by commas"),text:Binding(get:{model.settings.excludedKeywords ?? ""},set:{model.settings.excludedKeywords = $0})).textFieldStyle(.roundedBorder);if !model.selectedPack.offline { Toggle(L("Short headlines · up to 11 words"),isOn:Binding(get:{model.settings.shortHeadlines ?? false},set:{model.settings.shortHeadlines = $0})).toggleStyle(.checkbox) };Text(model.selectedPack.offline ? L("Filter the ready-made messages by your keywords.") : L("Keywords match visible headlines and excerpts. Unknown publication dates are excluded.")).font(.caption).foregroundStyle(.secondary) }
                    }
                    if model.selectedPack.offline { storyList(model.selectedContent) }
                    else {
                        Picker(L("Feed details"),selection:$tab){Text(L("Sources")).tag("sources");Text(L("In the Ticker")).tag("preview");Text(L("Highlights · up to 48h")).tag("highlights")}.pickerStyle(.segmented).labelsHidden()
                        if tab == "sources" { sourcePanel }
                        else if tab == "highlights" {
                            Toggle(L("Allow only selected highlights up to 48 hours"),isOn:Binding(get:{model.settings.allowExtended ?? false},set:{model.settings.allowExtended = $0})).toggleStyle(.checkbox).font(.callout)
                            storyList(model.editorialReviewStories.map{model.displayStory($0,applyRules:false) ?? $0})
                        } else { storyList(model.selectedContent) }
                    }

                }.padding(22).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            }
            Divider()
            HStack { Text(model.selectedPack.offline ? L("Ready to show · no internet needed") : L("News expires after 24 hours. Starred highlights never exceed 48 hours.")).font(.caption).foregroundStyle(.secondary);Spacer();Button(L("Use This Content")){model.activateContentPack(model.selectedPack.id);dismiss()}.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }.padding(18)
        }.onAppear { if model.servicesStarted { model.refreshContent() } }.background(Color(nsColor:.windowBackgroundColor)).environment(\.locale,Localization.locale).frame(width:1060,height:760)
    }
    @ViewBuilder var sourcePanel:some View {
        if model.selectedPack.offline { storyList(model.selectedContent) }
        else {
            TextField(L("Search sources"),text:$search).textFieldStyle(.roundedBorder)
            ScrollView { LazyVStack(spacing:0) { ForEach(sourceRows) { feed in
                Toggle(isOn:Binding(get:{selected(feed)},set:{select(feed,$0)})) { HStack { VStack(alignment:.leading,spacing:4) { Text(feed.name).font(.system(size:13,weight:.semibold));Text((feed.language ?? "").uppercased()+" · "+(URL(string:feed.url)?.host ?? "")).font(.caption).foregroundStyle(.secondary);if selected(feed) { Text(model.sourceSummary(feed)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) } };Spacer();Button{openLink(feed.url)}label:{Image(systemName:"arrow.up.right")}.buttonStyle(.plain).accessibilityLabel(L("Open source feed")) } }.toggleStyle(.checkbox).padding(.vertical,10);Divider()
            } } }
            HStack { Button{model.refreshContent()}label:{Label(L("Refresh feeds"),systemImage:"arrow.clockwise")}.disabled(model.refreshingContent);Spacer();Text(LF("%ld sources",model.enabledContentSources.count)).font(.caption).foregroundStyle(.secondary) }
            TelegramChannelField{feed in
                guard !(model.settings.customFeeds ?? []).contains(where:{$0.url == feed.url}) else{return false}
                model.settings.customFeeds = (model.settings.customFeeds ?? [])+[feed];model.selectPack("custom");model.newsLanguage = .all;return true
            }
            DisclosureGroup(L("Add RSS feed…")) { VStack(alignment:.leading,spacing:8) { HStack { TextField(L("Name (optional)"),text:$name);TextField("https://…",text:$address);Button(L("Add")){addSource()} }.textFieldStyle(.roundedBorder);if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) } } }
        }
    }
    @ViewBuilder func storyList(_ stories:[Story])->some View {
        if stories.isEmpty { VStack(alignment:.leading,spacing:8) { Text(model.refreshingContent ? L("Loading your feed…") : L("No eligible messages yet")).font(.headline);Text(L("Check sources, topic filters, publication dates and translation readiness.")).font(.callout).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.center) }
        else {
            TextField(L("Search visible headlines"),text:$storySearch).textFieldStyle(.roundedBorder)
            let visible = stories.filter{storySearch.isEmpty || ($0.text+" "+$0.source).localizedCaseInsensitiveContains(storySearch)}
            if visible.isEmpty { Text(L("No search results")).foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity) }
            else { ScrollView { LazyVStack(alignment:.leading,spacing:0) { ForEach(visible){story in EditorialStoryRow(model:model,story:story);Divider()} } } }
        }
    }
    func addSource() {
        let raw = address.trimmingCharacters(in:.whitespacesAndNewlines)
        let channel = raw.hasPrefix("@") || ["t.me","telegram.me"].contains(URL(string:raw)?.host ?? "")
        let url = channel ? TelegramPublicReader.username(raw).map{"https://t.me/s/"+$0} ?? raw : raw
        guard let parsed = URL(string:url),parsed.scheme == "https",parsed.host != nil else {error = L("Enter a name and the full HTTPS feed URL.");return}
        guard !(model.settings.customFeeds ?? []).contains(where:{$0.url == url}) else {error = L("This source has already been added.");return}
        model.settings.customFeeds = (model.settings.customFeeds ?? [])+[FeedSource(name:name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? parsed.host! : name,url:url)];model.selectPack("custom");name = "";address = "";error = ""
    }
}
