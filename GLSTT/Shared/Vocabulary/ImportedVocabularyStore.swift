import Foundation

struct ImportedVocabularySnapshot: Equatable {
    var lists: [ImportedVocabularyList] = []

    var totalWordCount: Int {
        lists.reduce(0) { $0 + $1.words.count }
    }

    var summary: String {
        guard !lists.isEmpty else { return "No imported word lists." }

        let listCount = lists.count
        let wordCount = totalWordCount
        let listLabel = listCount == 1 ? "list" : "lists"
        let wordLabel = wordCount == 1 ? "word" : "words"
        return "\(listCount) \(listLabel), \(wordCount) \(wordLabel)"
    }
}

struct ImportedVocabularyStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> ImportedVocabularySnapshot {
        guard let data = defaults.data(forKey: storageKey) else {
            return ImportedVocabularySnapshot()
        }

        let lists = (try? JSONDecoder().decode([ImportedVocabularyList].self, from: data)) ?? []
        return ImportedVocabularySnapshot(lists: lists)
    }

    func save(_ snapshot: ImportedVocabularySnapshot) {
        let data = try? JSONEncoder().encode(snapshot.lists)
        defaults.set(data, forKey: storageKey)
    }

    func importingList(from url: URL, into snapshot: ImportedVocabularySnapshot) throws -> ImportedVocabularySnapshot {
        let list = try VocabularyImporter.importList(from: url)
        return importing(list, into: snapshot)
    }

    func importing(_ list: ImportedVocabularyList, into snapshot: ImportedVocabularySnapshot) -> ImportedVocabularySnapshot {
        var lists = snapshot.lists
        lists.removeAll {
            $0.id == list.id || $0.name.caseInsensitiveCompare(list.name) == .orderedSame
        }
        lists.insert(list, at: 0)
        return ImportedVocabularySnapshot(lists: lists)
    }

    func removingList(_ list: ImportedVocabularyList, from snapshot: ImportedVocabularySnapshot) -> ImportedVocabularySnapshot {
        ImportedVocabularySnapshot(lists: snapshot.lists.filter { $0.id != list.id })
    }

    func clearing(_ snapshot: ImportedVocabularySnapshot) -> ImportedVocabularySnapshot {
        ImportedVocabularySnapshot(lists: [])
    }
}
