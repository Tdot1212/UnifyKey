import Foundation

extension Notification.Name {
    static let userWordFrequencyChanged = Notification.Name("userWordFrequencyChanged")
}

/// Tracks how often the user types each word. Persists across keyboard sessions.
/// Used to boost personal vocabulary in suggestions.
final class UserWordFrequency {
    static let shared = UserWordFrequency()

    private let appGroupID = "group.com.unifykey.app"
    private let frequencyKey = "userWordFrequency_v1"
    private let maxWords = 500
    private let minWordLength = 2

    private var frequencies: [String: Int] = [:]
    private var dirty = false
    private var saveTimer: Timer?

    private init() {
        loadFrequencies()
    }

    // MARK: - Recording

    /// Record that the user typed this word. Should be called when a word is "completed"
    /// (space pressed, return pressed, etc.)
    func recordWord(_ word: String) {
        let normalized = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= minWordLength else { return }

        if normalized.allSatisfy({ $0.isNumber }) { return }
        if normalized.contains("http") || normalized.contains("www.") { return }

        let oldFreq = frequencies[normalized] ?? 0
        frequencies[normalized] = oldFreq + 1

        // Promote on first sighting or every 5th occurrence — invalidate suggestion caches
        if oldFreq == 0 || (oldFreq + 1) % 5 == 0 {
            NotificationCenter.default.post(name: .userWordFrequencyChanged, object: nil)
        }

        dirty = true
        scheduleSave()
    }

    /// Record multiple words at once (e.g., when user hits space — record the word before space)
    func recordWords(_ words: [String]) {
        for word in words { recordWord(word) }
    }

    // MARK: - Lookup

    /// Get user's typing frequency for a word. 0 means never typed.
    func frequency(for word: String) -> Int {
        return frequencies[word.lowercased()] ?? 0
    }

    /// Get top user words matching a prefix, ordered by frequency (most used first)
    func suggestions(forPrefix prefix: String, limit: Int = 5) -> [String] {
        let lower = prefix.lowercased()
        guard !lower.isEmpty else { return [] }

        let matches = frequencies.filter { $0.key.hasPrefix(lower) && $0.key != lower }
        let sorted = matches.sorted { $0.value > $1.value }
        return sorted.prefix(limit).map { $0.key }
    }

    /// Get user's most-frequent words overall (for next-word predictions when context is empty)
    func topWords(limit: Int = 10) -> [String] {
        let sorted = frequencies.sorted { $0.value > $1.value }
        return sorted.prefix(limit).map { $0.key }
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.saveFrequencies()
        }
    }

    private func saveFrequencies() {
        guard dirty else { return }

        if frequencies.count > maxWords {
            let sorted = frequencies.sorted { $0.value > $1.value }
            frequencies = Dictionary(uniqueKeysWithValues: sorted.prefix(maxWords).map { ($0.key, $0.value) })
        }

        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        if let data = try? JSONEncoder().encode(frequencies) {
            defaults.set(data, forKey: frequencyKey)
            dirty = false
        }
    }

    private func loadFrequencies() {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        guard let data = defaults.data(forKey: frequencyKey),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return
        }
        frequencies = dict
    }

    /// Force immediate save (e.g., when keyboard is dismissed)
    func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        saveFrequencies()
    }

    /// Clear all learned data (for settings page)
    func reset() {
        frequencies.removeAll()
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        defaults.removeObject(forKey: frequencyKey)
        dirty = false
    }

    /// For UI display
    func totalWordsLearned() -> Int {
        return frequencies.count
    }
}
