import AppIntents
import Foundation
import UniformTypeIdentifiers

struct TranscribeAudioFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Transcribe Audio File"
    static var description = IntentDescription("Transcribes an audio file with GLSTT and returns a structured transcription result.")
    static var openAppWhenRun = false

    @Parameter(title: "Request ID")
    var requestID: String

    @Parameter(title: "Audio File", supportedContentTypes: [.audio])
    var audioFile: IntentFile?

    @Parameter(title: "Audio File URL")
    var audioFileURL: URL?

    @Parameter(title: "Audio File Bookmark Base64")
    var audioFileURLBookmarkBase64: String?

    @Parameter(title: "Source App Bundle ID")
    var sourceAppBundleID: String?

    @Parameter(title: "Language")
    var languageIdentifier: String?

    @Parameter(title: "Return Timestamps", default: true)
    var returnTimestamps: Bool

    @Parameter(title: "Preferred Engine")
    var preferredEngine: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Transcribe \(\.$audioFile) with request ID \(\.$requestID)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<AudioTranscriptionResultEntity> {
        let normalizedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestID.isEmpty else {
            return .result(value: failedResult(requestID: requestID, message: "A non-empty request ID is required."))
        }

        if let audioFile {
            let result = try await audioFile.withFile(contentType: .audio, allowOpenInPlace: true) { url, _ in
                await AudioTranscriptionIntentProcessor.shared.submit(
                    requestID: normalizedRequestID,
                    sourceURL: url,
                    sourceAppBundleID: sourceAppBundleID,
                    languageIdentifier: languageIdentifier,
                    returnTimestamps: returnTimestamps,
                    preferredEngine: preferredEngine
                )
            }
            return .result(value: result)
        }

        if let audioFileURL {
            let result = await AudioTranscriptionIntentProcessor.shared.submit(
                requestID: normalizedRequestID,
                sourceURL: audioFileURL,
                sourceAppBundleID: sourceAppBundleID,
                languageIdentifier: languageIdentifier,
                returnTimestamps: returnTimestamps,
                preferredEngine: preferredEngine
            )
            return .result(value: result)
        }

        if let bookmarkURL = resolveBookmarkURL(audioFileURLBookmarkBase64) {
            let result = await AudioTranscriptionIntentProcessor.shared.submit(
                requestID: normalizedRequestID,
                sourceURL: bookmarkURL,
                sourceAppBundleID: sourceAppBundleID,
                languageIdentifier: languageIdentifier,
                returnTimestamps: returnTimestamps,
                preferredEngine: preferredEngine
            )
            return .result(value: result)
        }

        return .result(value: failedResult(requestID: normalizedRequestID, message: "No audio file was provided."))
    }
}

struct GetTranscriptionStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Transcription Status"
    static var description = IntentDescription("Checks the status of a GLSTT audio transcription request.")
    static var openAppWhenRun = false

    @Parameter(title: "Request ID")
    var requestID: String

    static var parameterSummary: some ParameterSummary {
        Summary("Get transcription status for \(\.$requestID)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<AudioTranscriptionResultEntity> {
        let normalizedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await AudioTranscriptionIntentProcessor.shared.status(requestID: normalizedRequestID)
        return .result(value: result)
    }
}

struct CancelTranscriptionIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel Transcription"
    static var description = IntentDescription("Cancels a queued or running GLSTT audio transcription request.")
    static var openAppWhenRun = false

    @Parameter(title: "Request ID")
    var requestID: String

    static var parameterSummary: some ParameterSummary {
        Summary("Cancel transcription \(\.$requestID)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<AudioTranscriptionResultEntity> {
        let normalizedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await AudioTranscriptionIntentProcessor.shared.cancel(requestID: normalizedRequestID)
        return .result(value: result)
    }
}

struct GLSTTAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranscribeAudioFileIntent(),
            phrases: [
                "Transcribe audio with \(.applicationName)",
                "Start a GLSTT transcription with \(.applicationName)",
            ],
            shortTitle: "Transcribe Audio",
            systemImageName: "waveform.badge.plus"
        )

        AppShortcut(
            intent: GetTranscriptionStatusIntent(),
            phrases: [
                "Check GLSTT transcription with \(.applicationName)",
            ],
            shortTitle: "Check Transcription",
            systemImageName: "clock.badge.checkmark"
        )
    }
}

nonisolated private func resolveBookmarkURL(_ base64: String?) -> URL? {
    guard let base64,
          let bookmarkData = Data(base64Encoded: base64)
    else {
        return nil
    }

    var stale = false
    #if os(macOS)
    let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    let options: URL.BookmarkResolutionOptions = []
    #endif

    return try? URL(
        resolvingBookmarkData: bookmarkData,
        options: options,
        relativeTo: nil,
        bookmarkDataIsStale: &stale
    )
}

nonisolated private func failedResult(requestID: String, message: String) -> AudioTranscriptionResultEntity {
    AudioTranscriptionResultEntity(
        record: AudioTranscriptionIntentRecord(
            requestID: requestID,
            status: .failed,
            sourceAppBundleID: nil,
            sourceAudioURL: URL(fileURLWithPath: "/"),
            originalFileName: "",
            originalFileSize: nil,
            originalCreationDate: nil,
            originalModificationDate: nil,
            languageIdentifier: nil,
            durationSeconds: nil,
            returnTimestamps: false,
            preferredEngine: nil,
            transcript: nil,
            segments: [],
            transcriptFileURL: nil,
            metadataFileURL: nil,
            errorMessage: message,
            createdAt: .now,
            updatedAt: .now
        )
    )
}
