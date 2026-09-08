import Foundation

enum AppLanguage: String, CaseIterable {
    case system, chinese, english
}

enum L10n {
    static var language: AppLanguage {
        get {
            UserDefaults.standard.string(forKey: "interfaceLanguage")
                .flatMap(AppLanguage.init(rawValue:)) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "interfaceLanguage")
        }
    }

    static func resolvedLanguage(preferredLanguages: [String]) -> AppLanguage {
        for language in preferredLanguages {
            let language = language.lowercased()
            if language.hasPrefix("zh") { return .chinese }
            if language.hasPrefix("en") { return .english }
        }
        return .english
    }

    static func text(_ chinese: String, _ english: String) -> String {
        let selected = language
        let resolved = selected == .system
            ? resolvedLanguage(preferredLanguages: Locale.preferredLanguages)
            : selected
        return resolved == .chinese ? chinese : english
    }
}
