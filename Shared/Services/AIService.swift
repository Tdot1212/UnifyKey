import Foundation

protocol AIService {
    func translate(text: String, from: String, to: String, context: String, tone: String?, generateReply: Bool) async throws -> TranslationResult
    func sendRawPrompt(_ prompt: String) async throws -> String
    func testConnection() async throws -> Bool
}

enum AIServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case noAPIKey
    case decodingError
    case timeout
    case budgetExceeded

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid response from API"
        case .apiError(let message): return "API Error: \(message)"
        case .noAPIKey: return "Set up API key in UnifyKey app"
        case .decodingError: return "Failed to parse API response"
        case .timeout: return "Translation timed out — tap to retry"
        case .budgetExceeded: return "Daily limit reached — translations paused until tomorrow"
        }
    }
}

struct AIResponseJSON: Codable {
    let translation: String
    let suggestedReply: String?
    let contextNote: String?
}

final class AIServiceFactory {
    static func createService(provider: AIProvider, apiKey: String) -> AIService {
        switch provider {
        case .claude: return ClaudeService(apiKey: apiKey)
        case .deepseek: return DeepSeekService(apiKey: apiKey)
        case .openai: return OpenAIService(apiKey: apiKey)
        case .gemini: return GeminiService(apiKey: apiKey)
        }
    }

    static func createCurrentService() -> AIService? {
        let settings = SharedSettings.shared
        guard let apiKey = KeychainHelper.shared.loadAPIKey(),
              !apiKey.isEmpty else {
            return nil
        }
        return createService(provider: settings.selectedProvider, apiKey: apiKey)
    }
}

extension AIService {
    func makeTimedRequest(url: URL, request: URLRequest) async throws -> (Data, URLResponse) {
        // Check budget before making request
        if UsageTracker.shared.isBudgetExceeded() {
            throw AIServiceError.budgetExceeded
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config)
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw AIServiceError.timeout
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw AIServiceError.apiError("Network error — check connection")
        }
    }

    // MARK: - Translation-Only Prompt (lean, natural human translation)

    func buildTranslateOnlyPrompt(text: String, from: String, to: String, tone: String? = nil, relevantGlossary: [(term: String, meaning: String)] = []) -> String {
        var prompt = """
        You are a native bilingual speaker, not a translator. You speak both \(from) and \(to) fluently as a native speaker.

        Someone said this in \(from): "\(text)"

        Say the same thing in \(to) the way a real person would naturally say it. Rules:

        1. Sound like a real human talking, not a translation. If a friend sent you this message, how would you say the same thing in \(to)? Say it that way.
        2. NEVER translate word by word. Translate the MEANING and the FEELING.
        3. Keep the same energy — if it's casual, keep it casual. If it's polite, keep it polite. If it's urgent, keep it urgent.
        4. Always be respectful. Even if the original is blunt, make sure the translation maintains respect and professionalism.
        5. If there are idioms, slang, or expressions, convert them to natural equivalents in \(to). Do NOT translate literally.
        6. Keep it concise. Don't add words that weren't in the original meaning.
        7. For business communication: be clear, direct, and professional. The other person should understand exactly what you mean with zero confusion.
        """

        // Language-pair specific instructions
        if from == "English" && to == "Chinese" {
            prompt += "\n\nUse simplified Chinese (\u{7B80}\u{4F53}\u{4E2D}\u{6587}). Use natural conversational Chinese, not formal written Chinese unless the tone is set to Formal."
        } else if from == "Chinese" && to == "English" {
            prompt += "\n\nUse natural conversational English. Don't make it sound overly polished or formal unless the tone is set to Formal."
        }

        if !relevantGlossary.isEmpty {
            prompt += "\n\nUse these specific term meanings:"
            for entry in relevantGlossary {
                prompt += "\n- \"\(entry.term)\" \u{2192} \(entry.meaning)"
            }
        }

        let kb = KnowledgeBaseContext.load()
        if !kb.businessSection.isEmpty {
            prompt += "\n\nContext: The speaker works in business. \(kb.businessSection)"
        }

        if let tone = tone, !tone.isEmpty {
            prompt += "\n\n\(tone)"
        }

        prompt += "\n\nRespond with ONLY the translation. No quotes, no explanation, no \"Here's the translation:\" \u{2014} just the translated text exactly as a person would type it in a message."

        return prompt
    }

    // MARK: - Full Prompt with Reply (rich, ~800-1200 tokens)

    func buildFullPrompt(text: String, from: String, to: String, context: String, tone: String? = nil) -> String {
        let kb = KnowledgeBaseContext.load()
        var sections: [String] = []

        var intro = """
        You are a native bilingual speaker and business communication assistant. You speak both \(from) and \(to) fluently as a native speaker. Your job is to convey MEANING and FEELING, not just words.

        The user's native language is \(to). They work in the \(context) industry.

        Translation rules:
        1. Sound like a real human, not a translation.
        2. NEVER translate word by word. Translate the MEANING.
        3. Keep the same energy and tone as the original.
        4. Always maintain respect and professionalism.
        5. Convert idioms and expressions to natural equivalents.
        """

        if from == "English" && to == "Chinese" {
            intro += "\n\nUse simplified Chinese (\u{7B80}\u{4F53}\u{4E2D}\u{6587}). Use natural conversational Chinese, not formal written Chinese unless the tone is Formal."
        } else if from == "Chinese" && to == "English" {
            intro += "\n\nUse natural conversational English. Don't make it sound overly polished or formal unless the tone is Formal."
        }

        sections.append(intro)

        if !kb.glossarySection.isEmpty {
            sections.append("""
            IMPORTANT — The user has defined these specific terms. ALWAYS use these exact meanings:
            \(kb.glossarySection)
            """)
        }

        if !kb.businessSection.isEmpty {
            sections.append("""
            ABOUT THE USER'S BUSINESS:
            \(kb.businessSection)
            Use this information to give accurate, contextual translations and replies.
            """)
        }

        if !kb.styleSection.isEmpty {
            sections.append("""
            THE USER'S COMMUNICATION STYLE — Match this tone and style when suggesting replies:
            \(kb.styleSection)
            """)
        }

        let convoContext = ConversationBuffer.shared.buildPromptSection()
        if !convoContext.isEmpty {
            sections.append(convoContext)
        }

        if let tone = tone, !tone.isEmpty {
            sections.append("TONE INSTRUCTION: \(tone)")
        }

        sections.append("""
        The user received this message: "\(text)"

        Do two things:
        1. Translate the message to \(to). It must sound like a native speaker wrote it.
        2. Suggest a brief reply in the SENDER's language. Keep it 1-3 sentences.

        If anything is ambiguous, add a brief context note.

        Respond in this exact JSON format only:
        {"translation": "...", "suggestedReply": "...", "contextNote": "..." or null}
        """)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Unified prompt builder (routes to the right one)

    func buildTranslationPrompt(text: String, from: String, to: String, context: String, tone: String? = nil, generateReply: Bool = true) -> String {
        if generateReply {
            return buildFullPrompt(text: text, from: from, to: to, context: context, tone: tone)
        } else {
            let relevantGlossary = KnowledgeBaseContext.filterGlossary(for: text)
            return buildTranslateOnlyPrompt(text: text, from: from, to: to, tone: tone, relevantGlossary: relevantGlossary)
        }
    }

    // MARK: - Response Parsing

    func parseTranslationResponse(_ responseText: String, translationOnly: Bool = false) throws -> TranslationResult {
        let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines)

        if translationOnly {
            // Plain text response — strip surrounding quotes if present
            var result = cleaned
            if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 2 {
                result = String(result.dropFirst().dropLast())
            }
            return TranslationResult(translation: result, suggestedReply: nil, contextNote: nil)
        }

        // JSON response (full translation + reply)
        var jsonString = cleaned

        if let jsonStart = cleaned.range(of: "{"),
           let jsonEnd = cleaned.range(of: "}", options: .backwards) {
            jsonString = String(cleaned[jsonStart.lowerBound...jsonEnd.upperBound])
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw AIServiceError.decodingError
        }

        do {
            let decoded = try JSONDecoder().decode(AIResponseJSON.self, from: data)
            return TranslationResult(
                translation: decoded.translation,
                suggestedReply: decoded.suggestedReply,
                contextNote: decoded.contextNote
            )
        } catch {
            return TranslationResult(translation: cleaned, suggestedReply: nil, contextNote: nil)
        }
    }

    // Keep backward-compatible version
    func parseTranslationResponse(_ responseText: String) throws -> TranslationResult {
        return try parseTranslationResponse(responseText, translationOnly: false)
    }
}
