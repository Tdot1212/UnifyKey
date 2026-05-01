import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case claude = "claude"
    case deepseek = "deepseek"
    case openai = "openai"
    case gemini = "gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI (GPT)"
        case .gemini: return "Gemini (Google)"
        }
    }

    var apiKeyURL: String {
        switch self {
        case .claude: return "https://console.anthropic.com/"
        case .deepseek: return "https://platform.deepseek.com/"
        case .openai: return "https://platform.openai.com/"
        case .gemini: return "https://aistudio.google.com/app/apikey"
        }
    }

    var modelName: String {
        switch self {
        case .claude: return "claude-haiku-4-5-20251001"
        case .deepseek: return "deepseek-chat"
        case .openai: return "gpt-4o-mini"
        case .gemini: return "gemini-2.0-flash"
        }
    }
}
