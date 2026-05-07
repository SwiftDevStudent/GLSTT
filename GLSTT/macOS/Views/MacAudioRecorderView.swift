#if os(macOS)
import SwiftUI

struct MacAudioRecorderView: View {
    @Environment(AppModel.self) private var appModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "record.circle")
                    .foregroundStyle(.orange)

                Text("Audio Recorder")
                    .font(.system(compact ? .headline : .title3, design: .rounded, weight: .bold))

                Spacer()

                if !appModel.savedAudioRecordings.isEmpty {
                    Button("Folder", systemImage: "folder") {
                        appModel.openSavedRecordingsFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            recorderControl

            if appModel.savedAudioRecordings.isEmpty {
                Text("Recordings save to Documents/GLSTT Recordings.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved Recordings")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(Array(appModel.savedAudioRecordings.prefix(compact ? 3 : 8))) { recording in
                        MacSavedRecordingRow(recording: recording, compact: compact)
                            .environment(appModel)
                    }
                }
            }
        }
        .padding(compact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var recorderControl: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                appModel.toggleFileRecording()
            } label: {
                Label(
                    appModel.isFileRecording ? "Stop Recording" : "Start Recording",
                    systemImage: appModel.isFileRecording ? "stop.circle.fill" : "record.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(compact ? .regular : .large)
            .tint(appModel.isFileRecording ? .red : .orange)
            .disabled(appModel.isRecordingActive || appModel.isAudioFileTranscriptionActive)

            if appModel.isFileRecording {
                HStack(spacing: 8) {
                    MacRecordingLevelMeter(level: appModel.audioLevel)
                    Text(Self.durationLabel(appModel.fileRecordingElapsedSeconds))
                        .font(.system(compact ? .subheadline : .headline, design: .rounded).monospacedDigit().weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private static func durationLabel(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct MacSavedRecordingRow: View {
    @Environment(AppModel.self) private var appModel
    let recording: SavedAudioRecording
    let compact: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .foregroundStyle(.orange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.displayName)
                    .font(.system(compact ? .caption : .subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Text("\(recording.durationLabel) - \(recording.detailLabel)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Transcribe") {
                appModel.transcribeSavedRecording(recording)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                appModel.revealSavedRecording(recording)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reveal recording in Finder")

            Button(role: .destructive) {
                appModel.deleteSavedRecording(recording)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete recording")
        }
        .padding(compact ? 8 : 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

private struct MacRecordingLevelMeter: View {
    let level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(level > 0.02 ? 0.95 : 0.35))
                    .frame(width: 4, height: height(for: index))
            }
        }
    }

    private func height(for index: Int) -> Double {
        let base = [8.0, 14.0, 20.0, 14.0, 8.0][index]
        guard level > 0.02 else { return base }
        return base + (level * [6.0, 10.0, 14.0, 10.0, 6.0][index])
    }
}
#endif
