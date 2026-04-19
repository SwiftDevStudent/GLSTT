import Foundation

struct TranscriptHistoryEntry: Identifiable, Equatable, Hashable {
    let id: UUID
    let text: String
    let timestamp: Date

    init(id: UUID = UUID(), text: String, timestamp: Date = .now) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }

    var title: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled Transcript" }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        let headline = words.prefix(6).joined(separator: " ")
        return headline.isEmpty ? "Untitled Transcript" : headline
    }

    var preview: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
