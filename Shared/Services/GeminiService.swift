import Foundation

final class GeminiService: AIService {
    private let apiKey: String
    private let model = "gemini-2.0-flash"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    private var endpoint: String {
        "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
    }

    func translate(text: String, from: String, to: String, context: String, tone: String? = nil, generateReply: Bool = true) async throws -> TranslationResult {
        let prompt = buildTranslationPrompt(text: text, from: from, to: to, context: context, tone: tone, generateReply: generateReply)
        let responseText = try await sendRequest(prompt: prompt)

        UsageTracker.shared.recordCall(
            provider: "gemini",
            inputText: prompt,
            outputText: responseText
        )

        return try parseTranslationResponse(responseText, translationOnly: !generateReply)
    }

    func sendRawPrompt(_ prompt: String) async throws -> String {
        return try await sendRequest(prompt: prompt)
    }

    func testConnection() async throws -> Bool {
        _ = try await sendRequest(prompt: "Reply with: OK")
        return true
    }

    private func sendRequest(prompt: String) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await makeTimedRequest(url: url, request: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AIServiceError.apiError("Invalid API key")
            } else if httpResponse.statusCode == 429 {
                throw AIServiceError.apiError("Rate limited — try again shortly")
            }
            throw AIServiceError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIServiceError.decodingError
        }

        return text
    }
}
