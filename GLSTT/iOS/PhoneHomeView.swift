#if os(iOS)
import SwiftUI

struct PhoneHomeView: View {
    @Environment(PhoneAppModel.self) private var appModel
    @State private var showingSettings = false
    @State private var selectedMode = PhoneHomeMode.dictation

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Mode", selection: $selectedMode) {
                        ForEach(PhoneHomeMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

                switch selectedMode {
                case .dictation:
                    PhoneComposerSection()
                        .environment(appModel)

                    PhoneTranscriptHistorySection()
                        .environment(appModel)

                case .recorder:
                    PhoneAudioRecorderSection()
                        .environment(appModel)
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .safeAreaInset(edge: .bottom) {
                if selectedMode == .recorder {
                    PhoneRecordingDock()
                        .environment(appModel)
                }
            }
            .navigationTitle(selectedMode.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TranscriptHistoryEntry.self) { entry in
                PhoneTranscriptDetailView(entry: entry)
                    .environment(appModel)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    PhoneSettingsView()
                        .environment(appModel)
                }
            }
        }
        .tint(.orange)
        .task {
            appModel.refreshPermissions()
        }
        .alert("GLSTT", isPresented: alertIsPresented) {
            Button("OK", role: .cancel) {
                appModel.alertMessage = nil
            }
        } message: {
            Text(appModel.alertMessage ?? "")
        }
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { appModel.alertMessage != nil },
            set: { newValue in
                if !newValue {
                    appModel.alertMessage = nil
                }
            }
        )
    }
}

private enum PhoneHomeMode: String, CaseIterable, Identifiable {
    case dictation
    case recorder

    var id: Self { self }

    var title: String {
        switch self {
        case .dictation:
            return "Dictation"
        case .recorder:
            return "Recorder"
        }
    }

    var systemImage: String {
        switch self {
        case .dictation:
            return "mic"
        case .recorder:
            return "record.circle"
        }
    }
}

private struct PhoneRecordingDock: View {
    @Environment(PhoneAppModel.self) private var appModel

    private var isDisabled: Bool {
        appModel.isRecording || appModel.isAudioFileTranscriptionActive
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                appModel.toggleFileRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(appModel.isFileRecording ? Color.red : Color.orange)
                        .frame(width: 68, height: 68)
                        .shadow(color: (appModel.isFileRecording ? Color.red : Color.orange).opacity(0.28), radius: 14, y: 8)

                    Image(systemName: appModel.isFileRecording ? "stop.fill" : "record.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.45 : 1)
            .accessibilityLabel(appModel.isFileRecording ? "Stop audio recording" : "Start audio recording")

            VStack(alignment: .leading, spacing: 5) {
                Text(appModel.isFileRecording ? "Recording audio" : "Record audio")
                    .font(.headline)

                if appModel.isFileRecording {
                    HStack(spacing: 8) {
                        PhoneRecordingDockMeter(level: appModel.audioLevel)
                        Text(Self.durationLabel(appModel.fileRecordingElapsedSeconds))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.red)
                    }
                } else {
                    Text(isDisabled ? "Finish the current task first" : "Saved as an audio file. Transcribe when ready.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private static func durationLabel(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct PhoneRecordingDockMeter: View {
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
