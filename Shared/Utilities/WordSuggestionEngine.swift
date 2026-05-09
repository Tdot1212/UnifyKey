import UIKit
import NaturalLanguage

final class WordSuggestionEngine {
    static let shared = WordSuggestionEngine()

    private let textChecker = UITextChecker()
    private let languageRecognizer = NLLanguageRecognizer()
    private var suggestionCache: [String: [WordSuggestion]] = [:]
    private var cacheKeys: [String] = []
    private let maxCacheSize = 50

    private init() {
        NotificationCenter.default.addObserver(
            forName: .userWordFrequencyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suggestionCache.removeAll()
            self?.cacheKeys.removeAll()
        }
    }

    // MARK: - Detect typing language

    func detectTypingLanguage(_ text: String) -> String {
        languageRecognizer.reset()
        languageRecognizer.processString(text)
        guard let lang = languageRecognizer.dominantLanguage else { return "en" }
        return lang.rawValue
    }

    /// Map NL language codes to UITextChecker language codes
    func textCheckerLanguage(for nlCode: String) -> String {
        let prefix = nlCode.components(separatedBy: "-").first ?? nlCode
        let available = UITextChecker.availableLanguages
        // Try exact match first
        if available.contains(nlCode) { return nlCode }
        // Try prefix match
        if let match = available.first(where: { $0.hasPrefix(prefix) }) {
            return match
        }
        return "en_US"
    }

    // MARK: - Word Completions

    func completions(for partialWord: String, language: String) -> [String] {
        guard partialWord.count >= 2 else { return [] }
        let lang = textCheckerLanguage(for: language)
        let range = NSRange(location: 0, length: (partialWord as NSString).length)
        let results = textChecker.completions(forPartialWordRange: range, in: partialWord, language: lang) ?? []
        return Array(results.prefix(8))
    }

    // MARK: - Spell Check

    func correction(for word: String, language: String) -> String? {
        guard word.count >= 2 else { return nil }
        let lang = textCheckerLanguage(for: language)
        let nsWord = word as NSString
        let range = NSRange(location: 0, length: nsWord.length)
        let misspelled = textChecker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false, language: lang
        )
        guard misspelled.location != NSNotFound else { return nil }
        let guesses = textChecker.guesses(forWordRange: misspelled, in: word, language: lang) ?? []
        return guesses.first
    }

    func isMisspelled(_ word: String, language: String) -> Bool {
        guard word.count >= 2 else { return false }
        let lang = textCheckerLanguage(for: language)
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = textChecker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false, language: lang
        )
        return misspelled.location != NSNotFound
    }

    // MARK: - Autocorrect on space

    func autocorrect(text: String, language: String) -> (corrected: String, didCorrect: Bool) {
        let words = text.components(separatedBy: " ")
        guard let lastWord = words.last, !lastWord.isEmpty else {
            return (text, false)
        }

        if let corrected = correction(for: lastWord, language: language) {
            var newWords = words
            newWords[newWords.count - 1] = corrected
            return (newWords.joined(separator: " "), true)
        }
        return (text, false)
    }

    // MARK: - Pre-translation spell correction

    func correctAllWords(in text: String, language: String) -> String {
        let words = text.components(separatedBy: " ")
        let corrected = words.map { word -> String in
            if let fix = correction(for: word, language: language) {
                return fix
            }
            return word
        }
        return corrected.joined(separator: " ")
    }

    // MARK: - Suggestions for bar (3 items)

    func suggestions(beforeCursor: String, language: String) -> [WordSuggestion] {
        guard !beforeCursor.isEmpty else { return [] }

        let components = beforeCursor.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        guard let partial = components.last, !partial.isEmpty else { return [] }

        let cacheKey = "\(partial.lowercased())|\(language)"
        if let cached = suggestionCache[cacheKey] {
            return cached
        }

        var results: [WordSuggestion] = []

        let userMatches = UserWordFrequency.shared.suggestions(forPrefix: partial, limit: 3)
        let comps = completions(for: partial, language: language)
        let correctionCandidate = correction(for: partial, language: language)

        var usedWords = Set<String>()
        usedWords.insert(partial.lowercased())

        // Slot 1: top user-frequent match (personal vocabulary wins)
        for userWord in userMatches {
            if !usedWords.contains(userWord) {
                results.append(WordSuggestion(word: userWord, isAutocorrect: false))
                usedWords.insert(userWord)
                break
            }
        }

        // Slot 2: autocorrect, else next user match, else system completion
        if let correction = correctionCandidate, !usedWords.contains(correction.lowercased()) {
            results.append(WordSuggestion(word: correction, isAutocorrect: true))
            usedWords.insert(correction.lowercased())
        } else {
            var slot2Filled = false
            for userWord in userMatches.dropFirst() {
                if !usedWords.contains(userWord) {
                    results.append(WordSuggestion(word: userWord, isAutocorrect: false))
                    usedWords.insert(userWord)
                    slot2Filled = true
                    break
                }
            }
            if !slot2Filled {
                for c in comps {
                    let lower = c.lowercased()
                    if !usedWords.contains(lower) {
                        results.append(WordSuggestion(word: c, isAutocorrect: false))
                        usedWords.insert(lower)
                        break
                    }
                }
            }
        }

        // Slot 3: best system completion not yet used
        for c in comps {
            let lower = c.lowercased()
            if !usedWords.contains(lower) {
                results.append(WordSuggestion(word: c, isAutocorrect: false))
                usedWords.insert(lower)
                break
            }
        }

        // Fill remaining slots with leftover user matches
        for userWord in userMatches {
            if results.count >= 3 { break }
            if !usedWords.contains(userWord) {
                results.append(WordSuggestion(word: userWord, isAutocorrect: false))
                usedWords.insert(userWord)
            }
        }

        suggestionCache[cacheKey] = results
        cacheKeys.append(cacheKey)
        if cacheKeys.count > maxCacheSize {
            let oldKey = cacheKeys.removeFirst()
            suggestionCache.removeValue(forKey: oldKey)
        }

        return results
    }
}

struct WordSuggestion: Equatable {
    let word: String
    let isAutocorrect: Bool
}
