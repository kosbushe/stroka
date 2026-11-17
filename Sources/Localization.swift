import Foundation

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case english = "en", russian = "ru"
    var id: String { rawValue }
    var title: String { self == .english ? "English" : "Русский" }
}
enum Localization {
    static var language = InterfaceLanguage(rawValue: UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "en") ?? .english
    static var locale: Locale { Locale(identifier: language == .english ? "en_US" : "ru_RU") }
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: ["en", "ru"].compactMap { code in Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)).map { (code, $0) } })
    static var bundle: Bundle { bundles[language.rawValue] ?? .main }
}
func L(_ key: String) -> String { Localization.bundle.localizedString(forKey: key, value: key, table: "Localizable") }
func LF(_ key: String, _ arguments: CVarArg...) -> String { String(format: L(key), locale: Localization.locale, arguments: arguments) }
func localTime(_ date: Date) -> String { date.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(Localization.locale)) }
extension Channel { var title: String { switch self { case .message: return L("My Text"); case .ai: return L("AI News"); case .content: return L("Content"); case .markets: return L("Markets"); case .mix: return L("Mix") } } }
extension Look { var title: String { switch self { case .glass: return L("Glass"); case .white: return L("White"); case .black: return L("Black"); case .metro: return L("Mono Compact"); case .pulse: return L("Bulletin Duo"); case .editorial: return L("Editorial"); case .nightline: return L("Nightline"); case .signal: return L("Signal Blue"); case .minimal: return L("Clean Line"); case .bulletin: return L("Classic Red"); case .wire: return L("International"); case .desk: return L("Market Desk"); case .studio: return L("Studio"); case .led: return L("LED"); case .neon: return L("Neon"); case .paper: return L("Paper"); case .ribbon: return L("Ribbon"); case .champagne: return L("Champagne"); case .graphite: return L("Graphite"); case .electric: return L("Electric") } } }
extension Motion { var title: String { switch self { case .horizontal: return L("Scrolling Text"); case .vertical: return L("Credits"); case .phrases: return L("Phrases"); case .words: return L("Word by Word") } } }
extension OutputMode { var title: String { switch self { case .full: return L("Full Screen"); case .strip: return L("Strip"); case .frame: return L("Screen Frame") } } }
extension StripPlacement { var title: String { switch self { case .bottom: return L("Bottom"); case .top: return L("Top"); case .left: return L("Left"); case .right: return L("Right"); case .center: return L("Center"); case .floating: return L("Floating") } } }
extension Composition { var title: String { switch self { case .ticker: return L("Ticker"); case .poster: return L("Poster"); case .split: return L("Split") } } }
extension NewsLanguage { var title: String { switch self { case .russian: return L("Russian"); case .english: return L("English"); case .all: return L("All Languages") } } }
