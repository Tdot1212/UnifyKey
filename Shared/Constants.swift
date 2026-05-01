import Foundation

enum AppConstants {
    // Knowledge Base limits
    static let maxGlossaryEntries = 100
    static let maxGlossaryInPrompt = 50
    static let maxWritingStyleCharacters = 2000
    static let maxWritingStyleInPrompt = 1500

    // Saved Phrases
    static let maxSavedPhrases = 50

    // Smart Translation
    static let typingDebounceDuration: TimeInterval = 1.5
    static let minClipboardLength = 3
    static let minTypingLength = 5

    // Provider pricing (per million tokens)
    enum Pricing {
        struct Rate {
            let inputPerMillion: Double
            let outputPerMillion: Double
        }
        static let claude = Rate(inputPerMillion: 0.80, outputPerMillion: 4.00)
        static let deepseek = Rate(inputPerMillion: 0.14, outputPerMillion: 0.28)
        static let openai = Rate(inputPerMillion: 0.15, outputPerMillion: 0.60)
        static let gemini = Rate(inputPerMillion: 0.075, outputPerMillion: 0.30)

        static func rate(for provider: String) -> Rate {
            switch provider {
            case "claude": return claude
            case "deepseek": return deepseek
            case "openai": return openai
            case "gemini": return gemini
            default: return openai
            }
        }
    }
}
