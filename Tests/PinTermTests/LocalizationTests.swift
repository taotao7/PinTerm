import Testing
@testable import PinTerm

struct LocalizationTests {
    @Test func systemLanguageResolution() {
        #expect(L10n.resolvedLanguage(preferredLanguages: ["zh-Hans-CN", "en-AU"]) == .chinese)
        #expect(L10n.resolvedLanguage(preferredLanguages: ["en-AU", "zh-Hans"]) == .english)
        #expect(L10n.resolvedLanguage(preferredLanguages: ["fr", "zh-Hant-TW"]) == .chinese)
        #expect(L10n.resolvedLanguage(preferredLanguages: ["de"]) == .english)
        #expect(L10n.resolvedLanguage(preferredLanguages: []) == .english)
    }
}
