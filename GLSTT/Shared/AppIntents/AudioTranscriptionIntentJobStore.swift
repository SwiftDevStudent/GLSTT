import AVFAudio
import Foundation

@MainActor
final class AudioTranscriptionIntentJobStore {
    static let shared = AudioTranscriptionIntentJobStore()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func createRecord(
        requestID: String,
        sourceURL: URL,
        sourceAppBundleID: String?,
        languageIdentifier: String?,
        returnTimestamps: Bool,
        preferredEngine: String?
    ) throws -> AudioTranscriptionIntentRecord {
        if let existingRecord = load(requestID: requestID) {
            return existingRecord
        }

        let directory = try jobDirectory(for: requestID)
        let sourceDirectory = directory.appendingPathComponent("Source", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let copiedAudioURL = uniqueFileURL(
            in: sourceDirectory,
            preferredName: sourceURL.lastPathComponent.isEmpty ? "audio" : sourceURL.lastPathComponent
        )
        try copySourceFile(from: sourceURL, to: copiedAudioURL)

        let metadata = sourceMetadata(for: sourceURL)
        let now = Date()
        let record = AudioTranscriptionIntentRecord(
            requestID: requestID,
            status: .queued,
            sourceAppBundleID: sourceAppBundleID,
            sourceAudioURL: copiedAudioURL,
            originalFileName: sourceURL.lastPathComponent,
            originalFileSize: metadata.fileSize,
            originalCreationDate: metadata.creationDate,
            originalModificationDate: metadata.modificationDate,
            languageIdentifier: normalizedLanguageIdentifier(languageIdentifier),
            durationSeconds: durationSeconds(for: copiedAudioURL),
            returnTimestamps: returnTimestamps,
            preferredEngine: preferredEngine,
            transcript: nil,
            segments: [],
            transcriptFileURL: nil,
            metadataFileURL: nil,
            errorMessage: nil,
            createdAt: now,
            updatedAt: now
        )
        try save(record)
        return record
    }

    func load(requestID: String) -> AudioTranscriptionIntentRecord? {
        let url = recordURL(for: requestID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(AudioTranscriptionIntentRecord.self, from: data)
    }

    func save(_ record: AudioTranscriptionIntentRecord) throws {
        var mutableRecord = record
        mutableRecord.updatedAt = Date()
        let directory = try jobDirectory(for: record.requestID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(mutableRecord)
        try data.write(to: recordURL(for: record.requestID), options: .atomic)
    }

    func markProcessing(_ requestID: String) throws -> AudioTranscriptionIntentRecord? {
        guard var record = load(requestID: requestID) else { return nil }
        guard record.status == .queued || record.status == .processing else { return record }
        record.status = .processing
        record.errorMessage = nil
        try save(record)
        return record
    }

    func markCancelled(_ requestID: String) throws -> AudioTranscriptionIntentRecord? {
        guard var record = load(requestID: requestID) else { return nil }
        guard record.status != .completed else { return record }
        record.status = .cancelled
        record.errorMessage = nil
        try save(record)
        return record
    }

    func markFailed(_ requestID: String, message: String) throws -> AudioTranscriptionIntentRecord? {
        guard var record = load(requestID: requestID) else { return nil }
        record.status = .failed
        record.transcript = nil
        record.errorMessage = message
        try save(record)
        return record
    }

    func complete(
        _ requestID: String,
        transcript: String,
        segments: [TranscriptionSegment]
    ) throws -> AudioTranscriptionIntentRecord? {
        guard var record = load(requestID: requestID) else { return nil }
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return try markFailed(requestID, message: "Empty recognition result.")
        }

        let directory = try jobDirectory(for: requestID)
        let transcriptURL = directory.appendingPathComponent("transcript.txt")
        try trimmedTranscript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        record.status = .completed
        record.transcript = trimmedTranscript
        record.segments = record.returnTimestamps ? segments : []
        record.transcriptFileURL = transcriptURL
        record.errorMessage = nil

        let metadataURL = directory.appendingPathComponent("transcript.json")
        record.metadataFileURL = metadataURL
        let data = try encoder.encode(record)
        try data.write(to: metadataURL, options: .atomic)
        try save(record)
        return record
    }

    private func copySourceFile(from sourceURL: URL, to destinationURL: URL) throws {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let metadata = sourceMetadata(for: sourceURL)
        var attributes: [FileAttributeKey: Any] = [:]
        if let creationDate = metadata.creationDate {
            attributes[.creationDate] = creationDate
        }
        if let modificationDate = metadata.modificationDate {
            attributes[.modificationDate] = modificationDate
        }
        if !attributes.isEmpty {
            try? fileManager.setAttributes(attributes, ofItemAtPath: destinationURL.path)
        }
    }

    private func durationSeconds(for url: URL) -> Double? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        return Double(audioFile.length) / sampleRate
    }

    private func sourceMetadata(for url: URL) -> (
        fileSize: Int64?,
        creationDate: Date?,
        modificationDate: Date?
    ) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        return (
            values?.fileSize.map(Int64.init),
            values?.creationDate,
            values?.contentModificationDate
        )
    }

    private func uniqueFileURL(in directory: URL, preferredName: String) -> URL {
        let baseName = sanitizedBaseName(preferredName)
        let pathExtension = (preferredName as NSString).pathExtension
        let stem = (baseName as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(baseName)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let fileName = pathExtension.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(pathExtension)"
            candidate = directory.appendingPathComponent(fileName)
            suffix += 1
        }

        return candidate
    }

    private func jobDirectory(for requestID: String) throws -> URL {
        let directory = baseDirectory()
            .appendingPathComponent(sanitizedRequestID(requestID), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func recordURL(for requestID: String) -> URL {
        baseDirectory()
            .appendingPathComponent(sanitizedRequestID(requestID), isDirectory: true)
            .appendingPathComponent("job.json")
    }

    private func baseDirectory() -> URL {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return supportDirectory
            .appendingPathComponent("GLSTT", isDirectory: true)
            .appendingPathComponent("Intent Transcriptions", isDirectory: true)
    }

    private func sanitizedRequestID(_ requestID: String) -> String {
        sanitizedBaseName(requestID).isEmpty ? UUID().uuidString : sanitizedBaseName(requestID)
    }

    private func sanitizedBaseName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
            .union(.newlines)
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: invalid)
            .joined(separator: "-")
    }

    private func normalizedLanguageIdentifier(_ languageIdentifier: String?) -> String? {
        let trimmed = languageIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
