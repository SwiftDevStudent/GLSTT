import AppIntents
import Foundation
import UniformTypeIdentifiers

enum TranscriptionJobStatus: String, AppEnum, Codable, Sendable {
    case queued
    case processing
    case completed
    case failed
    case cancelled

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Transcription Status")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .queued: "Queued",
        .processing: "Processing",
        .completed: "Completed",
        .failed: "Failed",
        .cancelled: "Cancelled",
    ]
}

struct TranscriptionSegment: Codable, Hashable, Sendable {
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var confidence: Double?
}

struct AudioTranscriptionResultEntity: TransientAppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Audio Transcription Result")

    var id = UUID().uuidString

    @Property(identifier: "requestID", title: "Request ID")
    var requestID: String

    @Property(identifier: "status", title: "Status")
    var status: String

    @Property(identifier: "transcript", title: "Transcript")
    var transcript: String?

    @Property(identifier: "languageIdentifier", title: "Language")
    var languageIdentifier: String?

    @Property(identifier: "durationSeconds", title: "Duration")
    var durationSeconds: Double?

    @Property(identifier: "segmentsJSON", title: "Segments JSON")
    var segmentsJSON: String

    @Property(identifier: "transcriptFilePath", title: "Transcript File Path")
    var transcriptFilePath: String?

    @Property(identifier: "transcriptFile", title: "Transcript File")
    var transcriptFile: IntentFile?

    @Property(identifier: "errorMessage", title: "Error Message")
    var errorMessage: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(requestID)", subtitle: "\(status)")
    }

    init() {
        requestID = ""
        status = TranscriptionJobStatus.queued.rawValue
        transcript = nil
        languageIdentifier = nil
        durationSeconds = nil
        segmentsJSON = "[]"
        transcriptFilePath = nil
        transcriptFile = nil
        errorMessage = nil
    }

    init(record: AudioTranscriptionIntentRecord) {
        id = record.requestID
        requestID = record.requestID
        status = record.status.rawValue
        transcript = record.transcript
        languageIdentifier = record.languageIdentifier
        durationSeconds = record.durationSeconds
        segmentsJSON = Self.encodeSegments(record.segments)
        transcriptFilePath = record.transcriptFileURL?.path
        transcriptFile = nil
        if let transcriptFileURL = record.transcriptFileURL {
            transcriptFile = IntentFile(
                fileURL: transcriptFileURL,
                filename: transcriptFileURL.lastPathComponent,
                type: .plainText
            )
        }
        errorMessage = record.errorMessage
    }

    private static func encodeSegments(_ segments: [TranscriptionSegment]) -> String {
        guard !segments.isEmpty else {
            return "[]"
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(segments),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}

struct AudioTranscriptionIntentRecord: Codable, Sendable {
    var requestID: String
    var status: TranscriptionJobStatus
    var sourceAppBundleID: String?
    var sourceAudioURL: URL
    var originalFileName: String
    var originalFileSize: Int64?
    var originalCreationDate: Date?
    var originalModificationDate: Date?
    var languageIdentifier: String?
    var durationSeconds: Double?
    var returnTimestamps: Bool
    var preferredEngine: String?
    var transcript: String?
    var segments: [TranscriptionSegment]
    var transcriptFileURL: URL?
    var metadataFileURL: URL?
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date
}
