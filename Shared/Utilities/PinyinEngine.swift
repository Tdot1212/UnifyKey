import Foundation
import UIKit

final class PinyinEngine {
    static let shared = PinyinEngine()

    private var dictionary: [String: [String]] = [:]
    private var loaded = false
    private var bigramMap: [String: [String]] = [:]
    private let textChecker = UITextChecker()
    private var firstLetterMap: [Character: [String]] = [:]

    private init() {
        // Lazy load on first use to save memory
    }

    private func loadDictionary() {
        if let url = Bundle.main.url(forResource: "PinyinMap", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dict = try? JSONDecoder().decode([String: [String]].self, from: data) {
            dictionary = dict

            var map: [Character: [String]] = [:]
            for (pinyin, candidates) in dict {
                guard let first = pinyin.first, let firstChar = candidates.first else { continue }
                if map[first] == nil { map[first] = [] }
                if !map[first]!.contains(firstChar) {
                    map[first]!.append(firstChar)
                }
            }
            firstLetterMap = map

            loaded = true
        }
    }

    /// Get Chinese character candidates for a pinyin input string.
    /// Input: "nihao" → candidates for "ni", "nihao", etc.
    func candidates(for input: String) -> [String] {
        guard !input.isEmpty else { return [] }
        if !loaded { loadDictionary() }
        let lowered = input.lowercased()
        var results: [String] = []

        // 0. Abbreviated pinyin (first letter of each syllable) — check first
        let abbreviated = abbreviatedCandidates(for: lowered)
        results.append(contentsOf: abbreviated)

        // 1. Our bundled dictionary — exact match
        if let chars = dictionary[lowered] {
            for c in chars where !results.contains(c) {
                results.append(c)
            }
        }

        // 2. Multi-syllable combination
        let syllableCandidates = breakIntoSyllables(lowered)
        if !syllableCandidates.isEmpty && syllableCandidates != [lowered] {
            var combined = ""
            for syllable in syllableCandidates {
                if let chars = dictionary[syllable], let first = chars.first {
                    combined += first
                }
            }
            if !combined.isEmpty && !results.contains(combined) {
                results.insert(combined, at: min(results.count, 1))
            }
        }

        // 3. System dictionary via UITextChecker
        let systemResults = textChecker.completions(
            forPartialWordRange: NSRange(location: 0, length: lowered.utf16.count),
            in: lowered,
            language: "zh_Hans"
        ) ?? []
        for candidate in systemResults where !results.contains(candidate) {
            results.append(candidate)
            if results.count >= 15 { return results }
        }

        // 4. Prefix matches from our dictionary for more candidates
        if results.count < 15 {
            let prefixMatches = dictionary
                .filter { $0.key.hasPrefix(lowered) && $0.key != lowered }
                .sorted { $0.key.count < $1.key.count }

            for match in prefixMatches {
                for char in match.value where !results.contains(char) {
                    results.append(char)
                    if results.count >= 15 { return results }
                }
            }
        }

        return Array(results.prefix(15))
    }

    // MARK: - Abbreviated Pinyin (首字母输入)

    /// Abbreviated pinyin matching — each letter matches the start of a syllable
    /// Input: "nzgm" → tries n=你 z=在 g=干 m=嘛 → "你在干嘛"
    func abbreviatedCandidates(for input: String) -> [String] {
        guard input.count >= 2 else { return [] }
        let letters = Array(input)

        // Build per-position character candidates from dictionary prefix matching
        var charCandidatesPerPosition: [[String]] = []
        for letter in letters {
            let letterStr = String(letter)
            var chars: [String] = []
            // Check single-letter pinyin first (a, e, o)
            if let direct = dictionary[letterStr] {
                for c in direct where !chars.contains(c) {
                    chars.append(c)
                }
            }
            // O(1) lookup from pre-built first-letter map
            if let precomputed = firstLetterMap[letter] {
                for c in precomputed where !chars.contains(c) {
                    chars.append(c)
                }
            }
            charCandidatesPerPosition.append(chars)
        }

        // All positions must have at least one candidate
        guard charCandidatesPerPosition.allSatisfy({ !$0.isEmpty }) else { return [] }

        var results: [String] = []

        // Method 1: Check common fixed abbreviations first
        let commonAbbreviations: [String: [String]] = [
            "nh": ["\u{4F60}\u{597D}"],
            "nhm": ["\u{4F60}\u{597D}\u{5417}"],
            "nzgm": ["\u{4F60}\u{5728}\u{5E72}\u{5417}", "\u{4F60}\u{5728}\u{5E72}\u{561B}"],
            "nzgsm": ["\u{4F60}\u{5728}\u{5E72}\u{4EC0}\u{4E48}"],
            "dsq": ["\u{591A}\u{5C11}\u{94B1}"],
            "hd": ["\u{597D}\u{7684}"],
            "xx": ["\u{8C22}\u{8C22}"],
            "bkq": ["\u{4E0D}\u{5BA2}\u{6C14}"],
            "byq": ["\u{4E0D}\u{7528}\u{6C14}"],
            "zj": ["\u{518D}\u{89C1}"],
            "smsj": ["\u{4EC0}\u{4E48}\u{65F6}\u{95F4}"],
            "smsh": ["\u{4EC0}\u{4E48}\u{65F6}\u{5019}"],
            "wz": ["\u{6211}\u{5728}"],
            "nz": ["\u{4F60}\u{5728}"],
            "hh": ["\u{54C8}\u{54C8}"],
            "mm": ["\u{5988}\u{5988}", "\u{55EF}\u{55EF}"],
            "gg": ["\u{54E5}\u{54E5}"],
            "jj": ["\u{59D0}\u{59D0}"],
            "bb": ["\u{5B9D}\u{5B9D}", "\u{7238}\u{7238}"],
            "dd": ["\u{5F1F}\u{5F1F}"],
            "sjh": ["\u{624B}\u{673A}\u{53F7}"],
            "dz": ["\u{5730}\u{5740}"],
            "dh": ["\u{7535}\u{8BDD}"],
            "gzr": ["\u{5DE5}\u{4F5C}\u{65E5}"],
            "fh": ["\u{53D1}\u{8D27}"],
            "sh": ["\u{6536}\u{8D27}"],
            "ys": ["\u{989C}\u{8272}"],
            "cc": ["\u{5C3A}\u{5BF8}"],
            "sl": ["\u{6570}\u{91CF}"],
            "jg": ["\u{4EF7}\u{683C}"],
            "ht": ["\u{5408}\u{540C}"],
            "fk": ["\u{4ED8}\u{6B3E}"],
            "sk": ["\u{6536}\u{6B3E}"],
            "yh": ["\u{4F18}\u{60E0}"],
            "zk": ["\u{6298}\u{6263}"],
            "bp": ["\u{62A5}\u{4EF7}"],
            "yp": ["\u{6837}\u{54C1}"],
            "zy": ["\u{6CE8}\u{610F}"],
            "qr": ["\u{786E}\u{8BA4}"],
            "ap": ["\u{5B89}\u{6392}"],
            "wt": ["\u{95EE}\u{9898}"],
            "hf": ["\u{56DE}\u{590D}"],
        ]

        if let fixed = commonAbbreviations[input] {
            results.append(contentsOf: fixed)
        }

        // Method 2: Build phrase using bigram chain (most natural)
        var bestPhrase = ""
        var lastChar = ""
        for (i, candidates) in charCandidatesPerPosition.enumerated() {
            if i == 0 {
                bestPhrase = candidates[0]
                lastChar = candidates[0]
            } else {
                let nextPredictions = predictNextCharacter(after: lastChar)
                var found = false
                for pred in nextPredictions {
                    if candidates.contains(pred) {
                        bestPhrase += pred
                        lastChar = pred
                        found = true
                        break
                    }
                }
                if !found {
                    bestPhrase += candidates[0]
                    lastChar = candidates[0]
                }
            }
        }
        if !bestPhrase.isEmpty && !results.contains(bestPhrase) {
            results.append(bestPhrase)
        }

        return results
    }

    /// Try to break a pinyin string into known syllables
    private func breakIntoSyllables(_ input: String) -> [String] {
        guard !input.isEmpty else { return [] }

        var result: [String] = []
        var remaining = input

        while !remaining.isEmpty {
            var matched = false
            // Try longest match first (max pinyin syllable is 6 chars)
            let maxLen = min(remaining.count, 6)
            for len in stride(from: maxLen, through: 1, by: -1) {
                let prefix = String(remaining.prefix(len))
                if dictionary[prefix] != nil {
                    result.append(prefix)
                    remaining = String(remaining.dropFirst(len))
                    matched = true
                    break
                }
            }
            if !matched {
                // No match found, take one character
                result.append(String(remaining.prefix(1)))
                remaining = String(remaining.dropFirst())
            }
        }

        return result
    }

    // MARK: - Next-Character Prediction

    func predictNextCharacter(after lastChar: String) -> [String] {
        if bigramMap.isEmpty { loadBigrams() }
        return bigramMap[lastChar] ?? []
    }

    private func loadBigrams() {
        bigramMap = [
            "\u{4F60}": ["\u{597D}", "\u{4EEC}", "\u{7684}", "\u{662F}", "\u{8BF4}", "\u{8981}", "\u{4F1A}", "\u{80FD}", "\u{5728}", "\u{60F3}", "\u{770B}", "\u{77E5}", "\u{89C9}", "\u{81EA}"],
            "\u{6211}": ["\u{4EEC}", "\u{7684}", "\u{662F}", "\u{8981}", "\u{4F1A}", "\u{80FD}", "\u{5728}", "\u{60F3}", "\u{770B}", "\u{77E5}", "\u{89C9}", "\u{8BF4}", "\u{53BB}", "\u{6765}"],
            "\u{4ED6}": ["\u{4EEC}", "\u{7684}", "\u{662F}", "\u{8BF4}", "\u{5728}", "\u{4F1A}", "\u{8981}", "\u{80FD}", "\u{60F3}", "\u{53BB}"],
            "\u{5979}": ["\u{4EEC}", "\u{7684}", "\u{662F}", "\u{8BF4}", "\u{5728}", "\u{4F1A}", "\u{8981}", "\u{80FD}", "\u{60F3}", "\u{53BB}"],
            "\u{4E0D}": ["\u{662F}", "\u{4F1A}", "\u{80FD}", "\u{8981}", "\u{77E5}", "\u{884C}", "\u{597D}", "\u{5BF9}", "\u{7528}", "\u{4E86}", "\u{60F3}", "\u{5230}", "\u{53EF}"],
            "\u{662F}": ["\u{7684}", "\u{4E0D}", "\u{4EC0}", "\u{4E00}", "\u{5728}", "\u{8FD9}", "\u{6211}", "\u{4ED6}", "\u{56E0}", "\u{5F88}"],
            "\u{4E86}": ["\u{4E00}", "\u{5417}", "\u{89E3}", "\u{4E0D}", "\u{5F88}"],
            "\u{5728}": ["\u{54EA}", "\u{8FD9}", "\u{90A3}", "\u{5BB6}", "\u{505A}", "\u{5417}", "\u{5E72}", "\u{5FD9}", "\u{5403}", "\u{770B}", "\u{4E0A}", "\u{4E0B}"],
            "\u{6709}": ["\u{4EC0}", "\u{6CA1}", "\u{4EBA}", "\u{4E00}", "\u{7684}", "\u{65F6}", "\u{95EE}", "\u{7A7A}", "\u{5174}"],
            "\u{8FD9}": ["\u{4E2A}", "\u{662F}", "\u{91CC}", "\u{4E9B}", "\u{6837}", "\u{4E48}", "\u{79CD}", "\u{6B21}"],
            "\u{90A3}": ["\u{4E2A}", "\u{662F}", "\u{91CC}", "\u{4E9B}", "\u{6837}", "\u{4E48}", "\u{79CD}", "\u{8FB9}"],
            "\u{4EC0}": ["\u{4E48}"],
            "\u{4E48}": ["\u{6837}", "\u{65F6}", "\u{529E}", "\u{4E8B}", "\u{610F}"],
            "\u{600E}": ["\u{4E48}", "\u{6837}"],
            "\u{597D}": ["\u{7684}", "\u{5417}", "\u{4E86}", "\u{770B}", "\u{5403}", "\u{4E45}", "\u{50CF}", "\u{591A}", "\u{5927}", "\u{4EBA}", "\u{5904}"],
            "\u{5F88}": ["\u{597D}", "\u{591A}", "\u{5927}", "\u{9AD8}", "\u{5FEB}", "\u{4E45}", "\u{5F00}", "\u{6F02}", "\u{91CD}"],
            "\u{53EF}": ["\u{4EE5}", "\u{80FD}", "\u{662F}", "\u{601C}", "\u{7231}", "\u{6015}", "\u{60DC}"],
            "\u{4EE5}": ["\u{540E}", "\u{524D}", "\u{4E3A}", "\u{4E0A}", "\u{4E0B}", "\u{6765}"],
            "\u{6CA1}": ["\u{6709}", "\u{4EC0}", "\u{5173}", "\u{95EE}", "\u{60F3}", "\u{4E8B}"],
            "\u{4F1A}": ["\u{4E0D}", "\u{8BAE}", "\u{7684}", "\u{5458}", "\u{957F}", "\u{8BA1}"],
            "\u{60F3}": ["\u{8981}", "\u{5230}", "\u{8D77}", "\u{5FF5}", "\u{6CD5}", "\u{8C61}", "\u{8BF4}", "\u{53BB}", "\u{5403}", "\u{770B}", "\u{4E70}"],
            "\u{8981}": ["\u{662F}", "\u{4E0D}", "\u{6C42}", "\u{4E48}", "\u{7D27}"],
            "\u{53BB}": ["\u{54EA}", "\u{5427}", "\u{4E86}", "\u{8FC7}", "\u{5403}", "\u{770B}", "\u{4E70}", "\u{627E}"],
            "\u{6765}": ["\u{4E86}", "\u{5427}", "\u{7684}", "\u{5230}", "\u{8BF4}", "\u{770B}", "\u{81EA}"],
            "\u{5230}": ["\u{4E86}", "\u{5E95}", "\u{65F6}", "\u{8FBE}", "\u{5904}"],
            "\u{8BF4}": ["\u{7684}", "\u{4E86}", "\u{8BDD}", "\u{660E}", "\u{662F}", "\u{4EC0}", "\u{4E0D}"],
            "\u{770B}": ["\u{770B}", "\u{5230}", "\u{4E86}", "\u{89C1}", "\u{8D77}", "\u{4E00}", "\u{5427}"],
            "\u{5403}": ["\u{996D}", "\u{4E86}", "\u{4EC0}", "\u{7684}", "\u{4E1C}", "\u{8FC7}", "\u{5427}"],
            "\u{505A}": ["\u{4EC0}", "\u{7684}", "\u{4E86}", "\u{996D}", "\u{4E8B}", "\u{5230}", "\u{597D}"],
            "\u{4ECA}": ["\u{5929}", "\u{5E74}", "\u{540E}", "\u{665A}", "\u{65E9}", "\u{65E5}"],
            "\u{660E}": ["\u{5929}", "\u{767D}", "\u{5E74}"],
            "\u{6628}": ["\u{5929}", "\u{665A}"],
            "\u{4E0B}": ["\u{5348}", "\u{6B21}", "\u{73ED}", "\u{6765}", "\u{9762}", "\u{4E2A}", "\u{8F7D}", "\u{5468}"],
            "\u{4E0A}": ["\u{5348}", "\u{73ED}", "\u{6765}", "\u{9762}", "\u{4E2A}", "\u{6B21}", "\u{6D77}", "\u{5468}"],
            "\u{5927}": ["\u{5BB6}", "\u{7684}", "\u{5B66}", "\u{6982}", "\u{7EA6}", "\u{5C0F}", "\u{4EBA}", "\u{591A}"],
            "\u{5C0F}": ["\u{65F6}", "\u{5FC3}", "\u{7684}", "\u{59D0}", "\u{54E5}"],
            "\u{65F6}": ["\u{95F4}", "\u{5019}", "\u{5019}", "\u{523B}"],
            "\u{591A}": ["\u{5C11}", "\u{5927}", "\u{957F}", "\u{4E45}", "\u{8C22}", "\u{4E48}"],
            "\u{5C11}": ["\u{94B1}"],
            "\u{8C22}": ["\u{8C22}", "\u{4E86}"],
            "\u{5BF9}": ["\u{4E0D}", "\u{7684}", "\u{4E86}", "\u{65B9}", "\u{5417}", "\u{554A}"],
            "\u{8BF7}": ["\u{95EE}", "\u{4F60}", "\u{5E2E}", "\u{8FDB}", "\u{5750}", "\u{7B49}", "\u{7ED9}", "\u{53D1}"],
            "\u{7ED9}": ["\u{4F60}", "\u{6211}", "\u{4ED6}", "\u{5979}", "\u{4EEC}"],
            "\u{6253}": ["\u{7535}", "\u{7B97}", "\u{5F00}", "\u{6270}", "\u{6298}", "\u{5305}"],
            "\u{7535}": ["\u{8BDD}", "\u{8111}", "\u{5F71}", "\u{89C6}", "\u{5B50}"],
            "\u{53D1}": ["\u{73B0}", "\u{9001}", "\u{8D27}", "\u{7ED9}", "\u{5C55}", "\u{7968}", "\u{751F}"],
            "\u{9001}": ["\u{8D27}", "\u{5230}", "\u{7ED9}", "\u{4F60}", "\u{6765}"],
            "\u{8D27}": ["\u{7269}", "\u{5230}", "\u{54C1}"],
            "\u{4EF7}": ["\u{683C}", "\u{94B1}", "\u{4F4D}"],
            "\u{4ED8}": ["\u{6B3E}", "\u{94B1}", "\u{8D39}"],
            "\u{8BA2}": ["\u{5355}", "\u{8D2D}", "\u{91D1}"],
            "\u{786E}": ["\u{8BA4}", "\u{5B9A}", "\u{5B9E}"],
            "\u{5B89}": ["\u{6392}", "\u{5168}", "\u{88C5}"],
            "\u{6837}": ["\u{54C1}", "\u{5B50}", "\u{7684}"],
            "\u{7167}": ["\u{7247}", "\u{987E}", "\u{6837}"],
            "\u{5FEB}": ["\u{9012}", "\u{4E50}", "\u{70B9}", "\u{901F}"],
            "\u{7B49}": ["\u{4E00}", "\u{4E0B}", "\u{7B49}", "\u{4F1A}", "\u{5230}"],
            "\u{5148}": ["\u{751F}", "\u{4ED8}"],
            "\u{8001}": ["\u{677F}", "\u{5E08}", "\u{5A46}", "\u{516C}"],
            "\u{5DE5}": ["\u{5382}", "\u{4F5C}", "\u{4EBA}", "\u{8D44}"],
            "\u{516C}": ["\u{53F8}", "\u{91CC}"],
            "\u{7ECF}": ["\u{7406}", "\u{9A8C}", "\u{5E38}", "\u{8FC7}", "\u{6D4E}"],
            "\u{5BA2}": ["\u{6237}", "\u{4EBA}", "\u{670D}", "\u{6C14}"],
        ]
    }
}
