import Foundation

struct SavedAudioRecording: Codable, Identifiable, Equatable {
    var id: UUID
    var fileName: String
    var createdAt: Date
    var durationSeconds: Double?
    var fileSize: Int64?

    var displayName: String {
        let base = (fileName as NSString).deletingPathExtension
        return base.isEmpty ? "Recording" : base
    }

    var durationLabel: String {
        guard let durationSeconds else {
            return "Saved recording"
        }

        let totalSeconds = max(Int(durationSeconds.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    var detailLabel: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}
