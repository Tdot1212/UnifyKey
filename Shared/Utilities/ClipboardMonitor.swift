import UIKit

final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private(set) var lastProcessedString: String?
    private(set) var lastTranslation: String?
    private(set) var lastSuggestedReply: String?
    private(set) var lastContextNote: String?
    private(set) var lastDetectedLanguage: String?

    private init() {}

    func checkClipboard(userLanguage: String) -> String? {
        guard let clipboardText = UIPasteboard.general.string,
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // Skip if we already processed this exact string
        if clipboardText == lastProcessedString {
            return nil
        }

        // Check if it's a foreign language
        let detector = LanguageDetector.shared
        guard detector.isForeignLanguage(clipboardText, userLanguage: userLanguage) else {
            return nil
        }

        lastDetectedLanguage = detector.detectLanguage(clipboardText)
        return clipboardText
    }

    func cacheResult(original: String, translation: String, suggestedReply: String?, contextNote: String? = nil) {
        lastProcessedString = original
        lastTranslation = translation
        lastSuggestedReply = suggestedReply
        lastContextNote = contextNote
    }

    func clearCache() {
        lastProcessedString = nil
        lastTranslation = nil
        lastSuggestedReply = nil
        lastContextNote = nil
        lastDetectedLanguage = nil
    }
}
