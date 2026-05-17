import Foundation

struct TimedTranscriptSegment: Identifiable, Equatable, Hashable {
    let id = UUID()
    let speaker: String?
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let text: String

    var timeRangeLabel: String {
        let start = Self.formattedTime(startTime)
        let end = Self.formattedTime(endTime)
        return "\(start)-\(end)"
    }

    private static func formattedTime(_ time: TimeInterval?) -> String {
        guard let time else { return "--:--" }
        let totalSeconds = max(Int(time.rounded(.down)), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct AudioFileTranscriptionResult: Equatable {
    var text: String
    var segments: [TimedTranscriptSegment]
}

enum AudioFileOutputMode: String, CaseIterable, Identifiable {
    case transcript
    case timestamps

    var id: Self { self }

    var title: String {
        switch self {
        case .transcript:
            return "Transcript"
        case .timestamps:
            return "Timestamps"
        }
    }
}

struct AudioFileTranscriptionJob: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case preparing
        case transcribing
        case finished
        case failed(String)
    }

    let id: UUID
    let sourceURL: URL
    let displayName: String
    var status: Status
    var preview: String
    var transcript: String
    var timedSegments: [TimedTranscriptSegment]
    var language: AudioTranscriptionLanguageOption?
    var outputURL: URL?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        displayName: String,
        status: Status = .pending,
        preview: String = "",
        transcript: String = "",
        timedSegments: [TimedTranscriptSegment] = [],
        language: AudioTranscriptionLanguageOption? = nil,
        outputURL: URL? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.displayName = displayName
        self.status = status
        self.preview = preview
        self.transcript = transcript
        self.timedSegments = timedSegments
        self.language = language
        self.outputURL = outputURL
    }

    var isActive: Bool {
        switch status {
        case .preparing, .transcribing:
            return true
        case .pending, .finished, .failed:
            return false
        }
    }

    var isComplete: Bool {
        switch status {
        case .finished, .failed:
            return true
        case .pending, .preparing, .transcribing:
            return false
        }
    }

    var statusTitle: String {
        switch status {
        case .pending:
            return "Queued"
        case .preparing:
            return "Preparing"
        case .transcribing:
            return "Transcribing"
        case .finished:
            return "Finished"
        case .failed:
            return "Failed"
        }
    }

    var statusMessage: String {
        switch status {
        case .pending:
            return "Waiting for the current transcription to finish."
        case .preparing:
            return "Loading the audio file and preparing Apple's speech model."
        case .transcribing:
            let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedPreview.isEmpty ? "Reading the file. Long recordings can keep running for a while." : trimmedPreview
        case .finished:
            return transcript
        case .failed(let message):
            return message
        }
    }

    var iconName: String {
        switch status {
        case .pending:
            return "clock"
        case .preparing:
            return "hourglass"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        case .finished:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}
