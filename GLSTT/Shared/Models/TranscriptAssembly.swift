import Foundation

struct TranscriptUpdate: Equatable {
    var text: String
    var isFinal: Bool
}

struct TranscriptAssembly: Equatable {
    private(set) var finalizedText = ""
    private(set) var volatileText = ""

    var combinedText: String {
        Self.join(finalizedText, volatileText)
    }

    mutating func apply(_ update: TranscriptUpdate) {
        if update.isFinal {
            finalizedText = Self.join(finalizedText, update.text)
            volatileText = ""
        } else {
            volatileText = update.text
        }
    }

    mutating func reset() {
        finalizedText = ""
        volatileText = ""
    }

    static func join(_ lhs: String, _ rhs: String) -> String {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }

        if let first = right.first, ".,!?;:)]}".contains(first) {
            return left + right
        }

        return left + " " + right
    }
}
