#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct GLSTTLiveActivityExtensionBundle: WidgetBundle {
    var body: some Widget {
        GLSTTDictationLiveActivityWidget()
    }
}

struct GLSTTDictationLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationLiveActivityAttributes.self) { context in
            DictationLiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.86))
                .activitySystemActionForegroundColor(.green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityWaveform(level: context.state.audioLevel, barCount: 5)
                        .frame(width: 38, height: 28)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.status.title)
                            .font(.caption.weight(.semibold))
                        Text(context.state.message ?? context.state.transcriptPreview.ifEmpty("Speak now"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(Self.durationLabel(context.state.elapsedSeconds))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.green)
                }
            } compactLeading: {
                LiveActivityWaveform(level: context.state.audioLevel, barCount: 3)
                    .frame(width: 22, height: 16)
            } compactTrailing: {
                Text(Self.durationLabel(context.state.elapsedSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.green)
            } minimal: {
                Image(systemName: context.state.status == .failed ? "exclamationmark" : "waveform")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(context.state.status == .failed ? .orange : .green)
            }
        }
    }

    static func durationLabel(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct DictationLiveActivityLockScreenView: View {
    let state: DictationLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            LiveActivityWaveform(level: state.audioLevel, barCount: 5)
                .frame(width: 44, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(state.status.title)
                        .font(.headline)
                    Spacer()
                    Text(GLSTTDictationLiveActivityWidget.durationLabel(state.elapsedSeconds))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.green)
                }

                Text(state.message ?? state.transcriptPreview.ifEmpty("Speak now"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LiveActivityWaveform: View {
    let level: Double
    let barCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: barCount == 3 ? 2 : 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Color.green.opacity(opacity(for: index)))
                    .frame(width: barCount == 3 ? 3 : 4, height: height(for: index))
            }
        }
    }

    private func height(for index: Int) -> Double {
        let profiles = barCount == 3 ? [0.45, 1.0, 0.45] : [0.32, 0.68, 1.0, 0.68, 0.32]
        let profile = profiles[index]
        return 5 + (profile * 14) + (min(max(level, 0), 1) * profile * 10)
    }

    private func opacity(for index: Int) -> Double {
        let center = Double(barCount - 1) / 2
        let distance = abs(Double(index) - center) / max(center, 1)
        return 1 - (distance * 0.36)
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}
#endif
