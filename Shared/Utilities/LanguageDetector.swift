import Foundation
import NaturalLanguage

final class LanguageDetector {
    static let shared = LanguageDetector()

    private init() {}

    func detectLanguage(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)

        guard let dominant = recognizer.dominantLanguage else { return nil }
        return dominant.rawValue
    }

    func isForeignLanguage(_ text: String, userLanguage: String) -> Bool {
        guard let detected = detectLanguage(text) else { return false }
        // Handle language code variants (e.g., "zh-Hans" vs "zh")
        let detectedPrefix = detected.components(separatedBy: "-").first ?? detected
        let userPrefix = userLanguage.components(separatedBy: "-").first ?? userLanguage
        return detectedPrefix != userPrefix
    }

    func languageNameForCode(_ code: String) -> String {
        let prefix = code.components(separatedBy: "-").first ?? code
        if let supported = SupportedLanguage(rawValue: prefix) {
            return supported.fullLanguageName
        }
        let locale = Locale(identifier: "en")
        return locale.localizedString(forLanguageCode: code) ?? code
    }
}
