import Foundation
import Speech

struct AudioTranscriptionLanguageOption: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String

    var locale: Locale {
        Locale(identifier: id)
    }

    init(locale: Locale) {
        let identifier = locale.identifier
        self.id = identifier
        self.title = Locale.current.localizedString(forIdentifier: identifier)
            ?? locale.localizedString(forIdentifier: identifier)
            ?? identifier
        self.detail = identifier.replacingOccurrences(of: "_", with: "-")
    }

    @MainActor
    static func supportedOptions() async -> [AudioTranscriptionLanguageOption] {
        let supportedLocales = await DictationTranscriber.supportedLocales
        let optionsByIdentifier = Dictionary(
            grouping: supportedLocales.map { AudioTranscriptionLanguageOption(locale: $0) },
            by: \.id
        )
        return optionsByIdentifier.values
            .compactMap(\.first)
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    @MainActor
    static func defaultLanguageID(in options: [AudioTranscriptionLanguageOption]) -> String? {
        let currentIdentifier = Locale.current.identifier
        if let exactMatch = options.first(where: { $0.id == currentIdentifier }) {
            return exactMatch.id
        }

        guard let currentLanguageCode = Locale.current.language.languageCode?.identifier else {
            return options.first?.id
        }

        return options.first {
            Locale(identifier: $0.id).language.languageCode?.identifier == currentLanguageCode
        }?.id ?? options.first?.id
    }
}

struct PendingAudioFileLanguageSelection: Identifiable, Equatable {
    struct File: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let displayName: String
    }

    let id = UUID()
    let files: [File]
    let languageOptions: [AudioTranscriptionLanguageOption]
    let defaultLanguageID: String

    var title: String {
        files.count == 1 ? files[0].displayName : "\(files.count) audio files"
    }
}
