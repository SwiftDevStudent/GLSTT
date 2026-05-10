#if os(iOS)
import ActivityKit
import Foundation

@MainActor
final class PhoneDictationLiveActivityController {
    private var activity: Activity<DictationLiveActivityAttributes>?
    private var startedAt: Date?
    private var lastUpdate = Date.distantPast
    private var lastPreview = ""

    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var availabilitySummary: String {
        isAvailable
            ? "Available on this device."
            : "Live Activities are unavailable or disabled in Settings."
    }

    func startIfNeeded(isEnabled: Bool) async {
        guard isEnabled, isAvailable else { return }

        if activity != nil {
            await update(status: .listening, transcript: "", audioLevel: 0, force: true)
            return
        }

        let startedAt = Date()
        self.startedAt = startedAt
        lastPreview = ""
        let attributes = DictationLiveActivityAttributes(startedAt: startedAt)
        let content = ActivityContent(
            state: contentState(status: .listening, transcript: "", audioLevel: 0, message: nil),
            staleDate: Date().addingTimeInterval(60 * 10),
            relevanceScore: 90
        )

        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            lastUpdate = Date()
        } catch {
            activity = nil
        }
    }

    func update(
        status: DictationLiveActivityAttributes.Status,
        transcript: String,
        audioLevel: Double,
        message: String? = nil,
        force: Bool = false
    ) async {
        guard let activity else { return }

        let preview = Self.previewText(from: transcript)
        let now = Date()
        guard force || preview != lastPreview || now.timeIntervalSince(lastUpdate) >= 0.8 else { return }

        lastPreview = preview
        lastUpdate = now
        await activity.update(
            ActivityContent(
                state: contentState(status: status, transcript: preview, audioLevel: audioLevel, message: message),
                staleDate: Date().addingTimeInterval(60 * 10),
                relevanceScore: status == .failed ? 100 : 90
            )
        )
    }

    func end(
        status: DictationLiveActivityAttributes.Status,
        transcript: String,
        message: String? = nil,
        dismissAfter delay: TimeInterval = 18
    ) async {
        guard let activity else { return }

        let finalContent = ActivityContent(
            state: contentState(status: status, transcript: transcript, audioLevel: 0, message: message),
            staleDate: nil,
            relevanceScore: status == .failed ? 100 : 80
        )
        await activity.end(finalContent, dismissalPolicy: .after(Date().addingTimeInterval(delay)))
        self.activity = nil
        startedAt = nil
        lastPreview = ""
        lastUpdate = .distantPast
    }

    func endImmediately() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        startedAt = nil
        lastPreview = ""
        lastUpdate = .distantPast
    }

    private func contentState(
        status: DictationLiveActivityAttributes.Status,
        transcript: String,
        audioLevel: Double,
        message: String?
    ) -> DictationLiveActivityAttributes.ContentState {
        let elapsedSeconds = max(Date().timeIntervalSince(startedAt ?? Date()), 0)
        return DictationLiveActivityAttributes.ContentState(
            status: status,
            transcriptPreview: Self.previewText(from: transcript),
            audioLevel: min(max(audioLevel, 0), 1),
            elapsedSeconds: elapsedSeconds,
            message: message
        )
    }

    private static func previewText(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return trimmed }
        return String(trimmed.prefix(177)) + "..."
    }
}
#endif
