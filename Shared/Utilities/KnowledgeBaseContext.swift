import Foundation

struct KnowledgeBaseContext {
    let glossarySection: String
    let businessSection: String
    let styleSection: String

    static func load() -> KnowledgeBaseContext {
        let settings = SharedSettings.shared

        // Glossary — last N entries (most recently added = end of array)
        let allGlossary = settings.glossary
        let capped = Array(allGlossary.suffix(AppConstants.maxGlossaryInPrompt))
        let glossaryLines = capped.compactMap { entry -> String? in
            guard let term = entry["term"], !term.isEmpty,
                  let meaning = entry["meaning"], !meaning.isEmpty else { return nil }
            return "- \"\(term)\" means: \(meaning)"
        }
        let glossarySection = glossaryLines.joined(separator: "\n")

        // Business info
        let biz = settings.businessInfo
        var bizParts: [String] = []
        if let desc = biz["description"], !desc.isEmpty {
            bizParts.append(desc)
        }
        if let products = biz["products"], !products.isEmpty {
            bizParts.append("Products/Services: \(products)")
        }
        if let terms = biz["terms"], !terms.isEmpty {
            bizParts.append("Standard Terms: \(terms)")
        }
        if let extra = biz["extra"], !extra.isEmpty {
            bizParts.append("Additional Context: \(extra)")
        }
        let businessSection = bizParts.joined(separator: "\n")

        // Writing style — truncate to limit
        var style = settings.writingStyleExamples
        if style.count > AppConstants.maxWritingStyleInPrompt {
            style = String(style.prefix(AppConstants.maxWritingStyleInPrompt))
        }

        return KnowledgeBaseContext(
            glossarySection: glossarySection,
            businessSection: businessSection,
            styleSection: style
        )
    }

    /// Returns only glossary entries whose term appears in the given text.
    static func filterGlossary(for text: String) -> [(term: String, meaning: String)] {
        let settings = SharedSettings.shared
        let allGlossary = settings.glossary
        let lowered = text.lowercased()

        return allGlossary.compactMap { entry -> (term: String, meaning: String)? in
            guard let term = entry["term"], !term.isEmpty,
                  let meaning = entry["meaning"], !meaning.isEmpty else { return nil }
            // Only include if the term appears in the message
            if lowered.contains(term.lowercased()) {
                return (term: term, meaning: meaning)
            }
            return nil
        }
    }
}
