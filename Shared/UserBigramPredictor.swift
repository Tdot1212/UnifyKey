import Foundation

/// Learns user's sentence patterns (bigrams + trigrams) from typing.
/// Predicts the next word based on the previous 1-2 words the user typed.
/// This is sentence-level prediction, NOT just word completion.
final class UserBigramPredictor {
    static let shared = UserBigramPredictor()

    private let storeKey = "userBigrams_v1"
    private let maxEntries = 2000
    private let minWordLength = 2

    // bigram: previous word -> [next word: count]
    // trigram: "previous1 previous2" -> [next word: count]
    private var bigrams: [String: [String: Int]] = [:]
    private var trigrams: [String: [String: Int]] = [:]
    private var dirty = false
    private var saveTimer: Timer?

    private init() {
        load()
    }

    // MARK: - Recording

    /// Record a complete typed sentence. Call this when user finishes a thought
    /// (period, question mark, return, send button).
    func recordSentence(_ text: String) {
        let cleaned = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split into sentences
        let sentences = cleaned.components(separatedBy: CharacterSet(charactersIn: ".?!\n"))

        for sentence in sentences {
            let words = sentence
                .components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count >= minWordLength && !$0.isEmpty }

            guard words.count >= 2 else { continue }

            // Record bigrams (word -> next word)
            for i in 0..<(words.count - 1) {
                let prev = words[i]
                let next = words[i + 1]
                if bigrams[prev] == nil { bigrams[prev] = [:] }
                bigrams[prev]![next, default: 0] += 1
            }

            // Record trigrams ("word1 word2" -> next word) — more contextual
            for i in 0..<(words.count - 2) {
                let prev = "\(words[i]) \(words[i + 1])"
                let next = words[i + 2]
                if trigrams[prev] == nil { trigrams[prev] = [:] }
                trigrams[prev]![next, default: 0] += 1
            }
        }

        dirty = true
        scheduleSave()
    }

    // MARK: - Prediction

    /// Predict the next word based on the last 1-2 words typed.
    /// Returns up to 3 predictions, ordered by user's frequency.
    func predict(after text: String) -> [String] {
        let words = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return [] }

        var combinedScores: [String: Int] = [:]

        // Try trigram first (most specific)
        if words.count >= 2 {
            let key = "\(words[words.count - 2]) \(words.last!)"
            if let trigramMatches = trigrams[key] {
                for (next, count) in trigramMatches {
                    combinedScores[next, default: 0] += count * 3  // weight trigrams higher
                }
            }
        }

        // Fall back to / supplement with bigram
        if let lastWord = words.last, let bigramMatches = bigrams[lastWord] {
            for (next, count) in bigramMatches {
                combinedScores[next, default: 0] += count
            }
        }

        let sorted = combinedScores.sorted { $0.value > $1.value }
        return sorted.prefix(3).map { $0.key }
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.save()
        }
    }

    private struct Storage: Codable {
        let bigrams: [String: [String: Int]]
        let trigrams: [String: [String: Int]]
    }

    private func save() {
        guard dirty else { return }

        // Trim if too large — keep entries that have at least one strong signal (count > 1)
        if bigrams.count > maxEntries {
            bigrams = bigrams.filter { _, value in (value.values.max() ?? 0) > 1 }
        }
        if trigrams.count > maxEntries {
            trigrams = trigrams.filter { _, value in (value.values.max() ?? 0) > 1 }
        }

        let storage = Storage(bigrams: bigrams, trigrams: trigrams)
        if let data = try? JSONEncoder().encode(storage) {
            UserDefaults.standard.set(data, forKey: storeKey)
            dirty = false
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let storage = try? JSONDecoder().decode(Storage.self, from: data) else {
            return
        }
        bigrams = storage.bigrams
        trigrams = storage.trigrams
    }

    func flush() {
        saveTimer?.invalidate()
        save()
    }

    func reset() {
        bigrams.removeAll()
        trigrams.removeAll()
        UserDefaults.standard.removeObject(forKey: storeKey)
        dirty = false
    }

    /// For UI display — how much has been learned
    func totalPatternsLearned() -> Int {
        return bigrams.count + trigrams.count
    }
}
