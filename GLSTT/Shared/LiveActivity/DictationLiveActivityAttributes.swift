#if os(iOS)
import ActivityKit
import Foundation

struct DictationLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: Status
        var transcriptPreview: String
        var audioLevel: Double
        var elapsedSeconds: TimeInterval
        var message: String?
    }

    enum Status: String, Codable, Hashable {
        case listening
        case finalizing
        case finished
        case failed

        var title: String {
            switch self {
            case .listening:
                return "Listening"
            case .finalizing:
                return "Finalizing"
            case .finished:
                return "Captured"
            case .failed:
                return "Needs attention"
            }
        }
    }

    var startedAt: Date
}
#endif
