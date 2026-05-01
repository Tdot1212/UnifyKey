import Foundation

struct ConversationEntry {
    let original: String
    let translated: String
    let direction: Direction
    let timestamp: Date

    enum Direction: String {
        case incoming = "Incoming"
        case outgoing = "Outgoing"
    }
}

final class ConversationBuffer {
    static let shared = ConversationBuffer()

    private var entries: [ConversationEntry] = []
    private let maxEntries = 6
    private let timeoutInterval: TimeInterval = 30 * 60 // 30 minutes

    private init() {}

    func addEntry(original: String, translated: String, direction: ConversationEntry.Direction) {
        pruneIfStale()
        let entry = ConversationEntry(
            original: original,
            translated: translated,
            direction: direction,
            timestamp: Date()
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func buildPromptSection() -> String {
        pruneIfStale()
        guard !entries.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("RECENT CONVERSATION CONTEXT (use this to give contextually relevant translations and replies):")
        for entry in entries {
            lines.append("[\(entry.direction.rawValue)] \(entry.original) → \(entry.translated)")
        }
        return lines.joined(separator: "\n")
    }

    func clear() {
        entries.removeAll()
    }

    private func pruneIfStale() {
        guard let lastEntry = entries.last else { return }
        if Date().timeIntervalSince(lastEntry.timestamp) > timeoutInterval {
            entries.removeAll()
        }
    }
}
