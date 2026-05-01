import Foundation

final class ClaudeService: AIService {
    private let apiKey: String
    private let endpoint = "https://api.anthropic.com/v1/messages"
    private let model = "claude-haiku-4-5-20251001"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func translate(text: String, from: String, to: String, context: String, tone: String? = nil, generateReply: Bool = true) async throws -> TranslationResult {
        let prompt = buildTranslationPrompt(text: text, from: from, to: to, context: context, tone: tone, generateReply: generateReply)

        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
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
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let responseText = firstContent["text"] as? String else {
            throw AIServiceError.decodingError
        }

        // Track usage
        UsageTracker.shared.recordCall(
            provider: "claude",
            inputText: prompt,
            outputText: responseText
        )

        return try parseTranslationResponse(responseText, translationOnly: !generateReply)
    }

    func sendRawPrompt(_ prompt: String) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await makeTimedRequest(url: url, request: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIServiceError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let responseText = firstContent["text"] as? String else {
            throw AIServiceError.decodingError
        }

        return responseText
    }

    func testConnection() async throws -> Bool {
        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 32,
            "messages": [
                ["role": "user", "content": "Reply with: OK"]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await makeTimedRequest(url: url, request: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            return true
        } else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }
}
