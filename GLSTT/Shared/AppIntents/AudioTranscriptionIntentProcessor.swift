import Foundation

@MainActor
final class AudioTranscriptionIntentProcessor {
    static let shared = AudioTranscriptionIntentProcessor()

    private static let inlineTranscriptionLimitSeconds = 90.0

    private let store = AudioTranscriptionIntentJobStore.shared
    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {}

    func submit(
        requestID: String,
        sourceURL: URL,
        sourceAppBundleID: String?,
        languageIdentifier: String?,
        returnTimestamps: Bool,
        preferredEngine: String?
    ) async -> AudioTranscriptionResultEntity {
        do {
            let record = try store.createRecord(
                requestID: requestID,
                sourceURL: sourceURL,
                sourceAppBundleID: sourceAppBundleID,
                languageIdentifier: languageIdentifier,
                returnTimestamps: returnTimestamps,
                preferredEngine: preferredEngine
            )

            if let duration = record.durationSeconds,
               duration <= Self.inlineTranscriptionLimitSeconds {
                await process(requestID: requestID)
                return status(requestID: requestID)
            }

            startProcessingIfNeeded(requestID: requestID)
            return status(requestID: requestID)
        } catch {
            let failed = AudioTranscriptionIntentRecord(
                requestID: requestID,
                status: .failed,
                sourceAppBundleID: sourceAppBundleID,
                sourceAudioURL: sourceURL,
                originalFileName: sourceURL.lastPathComponent,
                originalFileSize: nil,
                originalCreationDate: nil,
                originalModificationDate: nil,
                languageIdentifier: languageIdentifier,
                durationSeconds: nil,
                returnTimestamps: returnTimestamps,
                preferredEngine: preferredEngine,
                transcript: nil,
                segments: [],
                transcriptFileURL: nil,
                metadataFileURL: nil,
                errorMessage: error.localizedDescription,
                createdAt: .now,
                updatedAt: .now
            )
            return AudioTranscriptionResultEntity(record: failed)
        }
    }

    func status(requestID: String) -> AudioTranscriptionResultEntity {
        guard let record = store.load(requestID: requestID) else {
            return missingRecordResult(requestID: requestID)
        }

        if record.status == .queued || record.status == .processing {
            startProcessingIfNeeded(requestID: requestID)
        }

        return AudioTranscriptionResultEntity(record: store.load(requestID: requestID) ?? record)
    }

    func cancel(requestID: String) -> AudioTranscriptionResultEntity {
        tasks[requestID]?.cancel()
        tasks[requestID] = nil

        do {
            if let record = try store.markCancelled(requestID) {
                return AudioTranscriptionResultEntity(record: record)
            }
        } catch {
            return failedResult(requestID: requestID, message: error.localizedDescription)
        }

        return missingRecordResult(requestID: requestID)
    }

    private func startProcessingIfNeeded(requestID: String) {
        guard tasks[requestID] == nil else { return }
        guard let record = store.load(requestID: requestID),
              record.status == .queued || record.status == .processing
        else {
            return
        }

        tasks[requestID] = Task { [weak self] in
            await self?.process(requestID: requestID)
        }
    }

    private func process(requestID: String) async {
        defer {
            tasks[requestID] = nil
        }

        do {
            guard let record = try store.markProcessing(requestID) else { return }
            guard !Task.isCancelled else {
                _ = try? store.markCancelled(requestID)
                return
            }

            let controller = SpeechTranscriptionController()
            let locale = record.languageIdentifier.map(Locale.init(identifier:))
            let result = try await controller.transcribeAudioFile(
                at: record.sourceAudioURL,
                locale: locale,
                contextualStrings: []
            )

            guard !Task.isCancelled else {
                _ = try? store.markCancelled(requestID)
                return
            }

            let segments = result.segments.map { segment in
                TranscriptionSegment(
                    startTime: segment.startTime ?? 0,
                    endTime: segment.endTime ?? segment.startTime ?? 0,
                    text: segment.speaker.map { "\($0): \(segment.text)" } ?? segment.text,
                    confidence: nil
                )
            }
            _ = try store.complete(requestID, transcript: result.text, segments: segments)
            saveToHistory(result.text)
        } catch {
            _ = try? store.markFailed(requestID, message: error.localizedDescription)
        }
    }

    private func saveToHistory(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        #if os(iOS)
        let historyStore = TranscriptHistoryStore(filename: "phone-transcripts.sqlite")
        #elseif os(macOS)
        let historyStore = TranscriptHistoryStore(filename: "mac-transcripts.sqlite")
        #else
        let historyStore = TranscriptHistoryStore(filename: "intent-transcripts.sqlite")
        #endif
        historyStore.save(TranscriptHistoryEntry(text: trimmed))
    }

    private func missingRecordResult(requestID: String) -> AudioTranscriptionResultEntity {
        failedResult(requestID: requestID, message: "No transcription job exists for request ID \(requestID).")
    }

    private func failedResult(requestID: String, message: String) -> AudioTranscriptionResultEntity {
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
}
