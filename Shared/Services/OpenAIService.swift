import Foundation

final class OpenAIService: AIService {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o-mini"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func translate(text: String, from: String, to: String, context: String, tone: String? = nil, generateReply: Bool = true) async throws -> TranslationResult {
        let prompt = buildTranslationPrompt(text: text, from: from, to: to, context: context, tone: tone, generateReply: generateReply)
        let maxTokens = generateReply ? 1024 : 512
        let responseText = try await sendChatRequest(prompt: prompt, maxTokens: maxTokens)

        UsageTracker.shared.recordCall(
            provider: "openai",
            inputText: prompt,
            outputText: responseText
        )

        return try parseTranslationResponse(responseText, translationOnly: !generateReply)
    }

    func sendRawPrompt(_ prompt: String) async throws -> String {
        return try await sendChatRequest(prompt: prompt, maxTokens: 256)
    }

    func testConnection() async throws -> Bool {
        _ = try await sendChatRequest(prompt: "Reply with: OK", maxTokens: 32)
        return true
    }

    private func sendChatRequest(prompt: String, maxTokens: Int) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await makeTimedRequest(url: url, request: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 {
                throw AIServiceError.apiError("Invalid API key")
            } else if httpResponse.statusCode == 429 {
                throw AIServiceError.apiError("Rate limited — try again shortly")
            }
            throw AIServiceError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.decodingError
        }

        return content
    }
}
