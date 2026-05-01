import Foundation

/// All shared settings between the main app and keyboard extension.
/// Backed entirely by SharedKeychain — no App Group / UserDefaults dependency.
final class SharedSettings {
    static let shared = SharedSettings()

    private let keychain = SharedKeychain.shared

    private init() {}

    // MARK: - Language & Provider

    var userLanguage: String {
        get { keychain.load(key: "userLanguage") ?? "en" }
        set { keychain.save(key: "userLanguage", value: newValue) }
    }

    var aiProvider: String {
        get { keychain.load(key: "aiProvider") ?? AIProvider.claude.rawValue }
        set { keychain.save(key: "aiProvider", value: newValue) }
    }

    var industryContext: String {
        get { keychain.load(key: "industryContext") ?? "General" }
        set { keychain.save(key: "industryContext", value: newValue) }
    }

    var hasCompletedOnboarding: Bool {
        get { keychain.loadBool(key: "hasCompletedOnboarding") }
        set { keychain.saveBool(key: "hasCompletedOnboarding", value: newValue) }
    }

    var selectedProvider: AIProvider {
        get { AIProvider(rawValue: aiProvider) ?? .claude }
        set { aiProvider = newValue.rawValue }
    }

    var selectedLanguage: SupportedLanguage {
        get { SupportedLanguage(rawValue: userLanguage) ?? .english }
        set { userLanguage = newValue.rawValue }
    }

    // MARK: - Knowledge Base

    var glossary: [[String: String]] {
        get { keychain.loadJSON(key: "glossary") ?? [] }
        set { keychain.saveJSON(key: "glossary", value: newValue) }
    }

    var writingStyleExamples: String {
        get { keychain.load(key: "writingStyleExamples") ?? "" }
        set { keychain.save(key: "writingStyleExamples", value: newValue) }
    }

    var businessInfo: [String: String] {
        get { keychain.loadJSON(key: "businessInfo") ?? [:] }
        set { keychain.saveJSON(key: "businessInfo", value: newValue) }
    }

    // MARK: - Saved Phrases

    var savedPhrases: [[String: String]] {
        get { keychain.loadJSON(key: "savedPhrases") ?? [] }
        set { keychain.saveJSON(key: "savedPhrases", value: newValue) }
    }

    func addSavedPhrase(original: String, translation: String) {
        var phrases = savedPhrases
        let entry: [String: String] = ["original": original, "translation": translation]
        if phrases.contains(where: { $0["original"] == original && $0["translation"] == translation }) { return }
        phrases.insert(entry, at: 0)
        if phrases.count > AppConstants.maxSavedPhrases {
            phrases = Array(phrases.prefix(AppConstants.maxSavedPhrases))
        }
        savedPhrases = phrases
    }

    func removeSavedPhrase(at index: Int) {
        var phrases = savedPhrases
        guard index < phrases.count else { return }
        phrases.remove(at: index)
        savedPhrases = phrases
    }

    func clearKnowledgeBase() {
        glossary = []
        writingStyleExamples = ""
        businessInfo = [:]
    }

    // MARK: - Cost Tracking Settings

    var showCostPerTranslation: Bool {
        get { keychain.loadBool(key: "showCostPerTranslation") }
        set { keychain.saveBool(key: "showCostPerTranslation", value: newValue) }
    }

    // MARK: - Budget (shared so keyboard can check limit set in main app)

    var dailyBudget: Double? {
        get {
            let val = keychain.loadDouble(key: "dailyBudget") ?? 0
            return val > 0 ? val : nil
        }
        set { keychain.saveDouble(key: "dailyBudget", value: newValue ?? 0) }
    }

    // MARK: - Haptic Feedback

    /// Whether keyboard key presses should trigger haptic feedback.
    /// Defaults to true (ON) when no value has been written yet.
    var hapticFeedbackEnabled: Bool {
        get {
            guard let raw = keychain.load(key: "hapticFeedbackEnabled") else { return true }
            return raw == "1"
        }
        set { keychain.saveBool(key: "hapticFeedbackEnabled", value: newValue) }
    }

    /// Recorded by the keyboard extension on launch so the main app's settings
    /// view can warn the user if Full Access is required for haptics to work.
    var hasKeyboardFullAccess: Bool {
        get { keychain.loadBool(key: "hasKeyboardFullAccess") }
        set { keychain.saveBool(key: "hasKeyboardFullAccess", value: newValue) }
    }
}
