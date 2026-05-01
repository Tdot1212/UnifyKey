import Foundation

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case arabic = "ar"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case portuguese = "pt"
    case russian = "ru"
    case italian = "it"
    case thai = "th"
    case vietnamese = "vi"
    case indonesian = "id"
    case hindi = "hi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "\u{4E2D}\u{6587} (Chinese)"
        case .japanese: return "\u{65E5}\u{672C}\u{8A9E} (Japanese)"
        case .korean: return "\u{D55C}\u{AD6D}\u{C5B4} (Korean)"
        case .arabic: return "\u{0627}\u{0644}\u{0639}\u{0631}\u{0628}\u{064A}\u{0629} (Arabic)"
        case .spanish: return "Espa\u{00F1}ol"
        case .french: return "Fran\u{00E7}ais"
        case .german: return "Deutsch"
        case .portuguese: return "Portugu\u{00EA}s"
        case .russian: return "\u{0420}\u{0443}\u{0441}\u{0441}\u{043A}\u{0438}\u{0439} (Russian)"
        case .italian: return "Italiano"
        case .thai: return "\u{0E20}\u{0E32}\u{0E29}\u{0E32}\u{0E44}\u{0E17}\u{0E22} (Thai)"
        case .vietnamese: return "Ti\u{1EBF}ng Vi\u{1EC7}t (Vietnamese)"
        case .indonesian: return "Bahasa Indonesia"
        case .hindi: return "\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940} (Hindi)"
        }
    }

    var shortLabel: String {
        switch self {
        case .english: return "EN"
        case .chinese: return "中文"
        case .japanese: return "JP"
        case .korean: return "KR"
        case .arabic: return "AR"
        case .spanish: return "ES"
        case .french: return "FR"
        case .german: return "DE"
        case .portuguese: return "PT"
        case .russian: return "RU"
        case .italian: return "IT"
        case .thai: return "TH"
        case .vietnamese: return "VI"
        case .indonesian: return "ID"
        case .hindi: return "HI"
        }
    }

    var fullLanguageName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .arabic: return "Arabic"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .italian: return "Italian"
        case .thai: return "Thai"
        case .vietnamese: return "Vietnamese"
        case .indonesian: return "Indonesian"
        case .hindi: return "Hindi"
        }
    }

}
