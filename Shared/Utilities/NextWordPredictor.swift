import Foundation

final class NextWordPredictor {
    static let shared = NextWordPredictor()

    private let nextWords: [String: [String]] = [
        "how": ["are", "is", "do", "much", "many", "about", "can"],
        "how are": ["you", "things", "we"],
        "what": ["is", "are", "do", "about", "time", "happened"],
        "what is": ["the", "your", "this", "that", "going"],
        "i": ["am", "have", "will", "don't", "think", "want", "need", "can"],
        "i am": ["going", "sorry", "happy", "here", "not", "doing", "fine"],
        "i'm": ["sorry", "good", "fine", "not", "here", "going", "doing"],
        "i have": ["a", "to", "been", "no", "some"],
        "i want": ["to", "a", "the", "some", "this"],
        "i need": ["to", "a", "the", "your", "some", "help"],
        "i think": ["so", "that", "we", "it", "the"],
        "i don't": ["know", "think", "want", "have", "understand", "need"],
        "we": ["can", "should", "will", "need", "have", "are"],
        "we can": ["do", "meet", "talk", "go", "try", "start"],
        "we should": ["meet", "talk", "do", "go", "try", "discuss"],
        "can": ["you", "we", "I", "do", "be"],
        "can you": ["send", "help", "please", "tell", "check", "do", "come"],
        "do": ["you", "we", "not", "it", "this"],
        "do you": ["have", "want", "need", "know", "think", "like"],
        "are": ["you", "we", "they", "there"],
        "are you": ["okay", "free", "busy", "sure", "available", "coming", "there"],
        "the": ["price", "order", "sample", "delivery", "payment", "quality", "product"],
        "please": ["send", "confirm", "check", "let", "help", "provide"],
        "please send": ["me", "the", "your", "a", "photos", "samples"],
        "thank": ["you"],
        "thank you": ["for", "so", "very"],
        "thanks": ["for", "a", "so"],
        "let": ["me", "us", "them"],
        "let me": ["know", "check", "see", "think", "ask"],
        "would": ["you", "like", "be"],
        "would you": ["like", "be", "mind", "prefer"],
        "could": ["you", "we", "be"],
        "could you": ["please", "send", "help", "tell", "check"],
        "when": ["can", "will", "do", "is", "are", "should"],
        "when can": ["you", "we", "I", "they"],
        "where": ["is", "are", "can", "do", "should"],
        "hello": ["how", "there", "everyone"],
        "hi": ["there", "how", "everyone"],
        "good": ["morning", "afternoon", "evening", "news", "to"],
        "good morning": ["how", "hope", "I"],
        "sorry": ["for", "about", "I", "to"],
        "sorry for": ["the", "any", "my"],
        "nice": ["to", "meeting", "work"],
        "nice to": ["meet", "hear", "see", "talk"],
        "looking": ["forward", "for", "at", "into", "good"],
        "looking forward": ["to"],
        "see": ["you", "the", "if", "what"],
        "see you": ["soon", "later", "there", "tomorrow"],
        "talk": ["to", "about", "later", "soon"],
        "talk to": ["you", "them", "me"],
        "it": ["is", "was", "will", "looks", "seems"],
        "it is": ["a", "the", "not", "very", "ready"],
        "this": ["is", "was", "will", "looks"],
        "this is": ["a", "the", "not", "very", "great"],
        "that": ["is", "was", "would", "looks", "sounds"],
        "that is": ["great", "fine", "good", "perfect", "not"],
        "not": ["sure", "yet", "a", "the", "available"],
        "yes": ["I", "we", "please", "of", "that"],
        "no": ["problem", "worries", "I", "we", "thanks"],
        "is": ["there", "it", "this", "that", "the"],
        "will": ["be", "do", "send", "let", "get", "check"],
        "have": ["a", "you", "been", "to", "the", "any"],
        "for": ["the", "you", "your", "a", "this", "any"],
        "to": ["the", "you", "your", "a", "do", "be", "meet", "send"],
        "in": ["the", "a", "this", "my", "your", "our"],
        "on": ["the", "my", "your", "this", "Monday", "time"],
        "with": ["the", "a", "you", "your", "this", "my"],
        // Business specific
        "minimum": ["order", "quantity"],
        "order": ["quantity", "confirmed", "placed", "ready", "shipped"],
        "payment": ["received", "pending", "terms", "confirmed"],
        "delivery": ["date", "time", "confirmed", "delayed"],
        "sample": ["ready", "sent", "received", "approved"],
        "price": ["is", "for", "per", "list"],
        "shipping": ["cost", "date", "time", "address"],
        "send": ["me", "the", "you", "a", "your", "it"],
        "meet": ["you", "at", "on", "tomorrow", "next"],
    ]

    private init() {}

    func predict(after text: String) -> [String] {
        let words = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return [] }

        // Try matching last 2 words first
        if words.count >= 2 {
            let twoWord = "\(words[words.count - 2]) \(words.last!)"
            if let predictions = nextWords[twoWord] {
                return Array(predictions.prefix(3))
            }
        }

        // Then try last word
        if let lastWord = words.last, let predictions = nextWords[lastWord] {
            return Array(predictions.prefix(3))
        }

        return []
    }
}
