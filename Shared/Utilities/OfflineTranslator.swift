import Foundation

final class OfflineTranslator {
    static let shared = OfflineTranslator()

    private var phrases: [String: [String: String]] = [:]
    private var loaded = false

    private init() {
        loadPhrases()
    }

    private func loadPhrases() {
        // Try keyboard extension bundle first, then main app bundle
        let bundles = [Bundle.main]
        for bundle in bundles {
            if let url = bundle.url(forResource: "CommonPhrases", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let dict = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
                phrases = dict
                loaded = true
                return
            }
        }
    }

    /// Returns an offline translation if available, nil otherwise.
    func translate(text: String, from: String, to: String) -> String? {
        guard loaded else { return nil }

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        // Try exact pair key
        let pairKey = "\(from)-\(to)"
        let reversePairKey = "\(to)-\(from)"

        if let pair = phrases[pairKey] {
            // Direct match
            for (source, target) in pair {
                if source.lowercased() == normalized {
                    return target
                }
            }
            // Match without trailing punctuation
            let stripped = normalized.trimmingCharacters(in: CharacterSet(charactersIn: ".!?。！？"))
            for (source, target) in pair {
                if source.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!?。！？")) == stripped {
                    return target
                }
            }
        }

        // Try reverse pair (translate target→source means looking up the value to get the key)
        if let pair = phrases[reversePairKey] {
            for (target, source) in pair {
                if source.lowercased() == normalized {
                    return target
                }
            }
        }

        return nil
    }
}
