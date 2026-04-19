import Foundation

struct ImportedVocabularyList: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var words: [String]
    var importedAt: Date

    init(id: UUID = UUID(), name: String, words: [String], importedAt: Date = .now) {
        self.id = id
        self.name = name
        self.words = words
        self.importedAt = importedAt
    }
}

enum VocabularyImportError: LocalizedError {
    case unreadableFile
    case unsupportedJSONShape
    case noWordsFound

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Unable to read that vocabulary file."
        case .unsupportedJSONShape:
            return "Use either a JSON array of strings or a JSON object with a `words` array."
        case .noWordsFound:
            return "No usable words were found in that file."
        }
    }
}

enum VocabularyImporter {
    static func importList(from url: URL) throws -> ImportedVocabularyList {
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw VocabularyImportError.unreadableFile
        }

        let name = url.deletingPathExtension().lastPathComponent

        if url.pathExtension.lowercased() == "json" {
            return try importJSONList(named: name, data: data)
        }

        let text = String(decoding: data, as: UTF8.self)
        let words = sanitize(words: splitPlainText(text))
        guard !words.isEmpty else {
            throw VocabularyImportError.noWordsFound
        }

        return ImportedVocabularyList(name: name, words: words)
    }

    static func mergedContextualStrings(
        importedLists: [ImportedVocabularyList],
        runtimeWords: [String],
        limit: Int = 100
    ) -> [String] {
        sanitize(words: importedLists.flatMap(\.words) + runtimeWords)
            .prefix(limit)
            .map { $0 }
    }

    private static func importJSONList(named name: String, data: Data) throws -> ImportedVocabularyList {
        let object = try JSONSerialization.jsonObject(with: data)

        if let words = object as? [String] {
            let sanitized = sanitize(words: words)
            guard !sanitized.isEmpty else {
                throw VocabularyImportError.noWordsFound
            }
            return ImportedVocabularyList(name: name, words: sanitized)
        }

        if let dictionary = object as? [String: Any] {
            let rawWords = dictionary["words"] as? [String]
            let displayName = (dictionary["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sanitized = sanitize(words: rawWords ?? [])
            guard !sanitized.isEmpty else {
                throw VocabularyImportError.noWordsFound
            }
            return ImportedVocabularyList(name: displayName?.isEmpty == false ? displayName! : name, words: sanitized)
        }

        throw VocabularyImportError.unsupportedJSONShape
    }

    private static func splitPlainText(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
            .filter { !$0.isEmpty }
    }

    private static func sanitize(words: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for rawWord in words {
            let trimmed = rawWord.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`[](){}<>").union(.whitespacesAndNewlines))
            guard !trimmed.isEmpty else { continue }
            let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !seen.contains(folded) else { continue }
            seen.insert(folded)
            result.append(trimmed)
        }

        return result
    }
}
