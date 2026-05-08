#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class HomeWindowController: NSWindowController {
    init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "GLSTT"
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.center()
        window.setFrameAutosaveName("GLSTTHomeWindow")
        window.contentView = NSHostingView(rootView: HomeWindowView().environment(model))

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        _ = NSRunningApplication.current.activate(options: [])
    }
}

private struct HomeWindowView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingAudioImporter = false
    @State private var isAudioDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            MacAudioRecorderView(compact: false)
                .environment(appModel)
            if !appModel.audioFileTranscriptionJobs.isEmpty {
                audioFileSection
            }
            transcriptSection
            footer
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
        .fileImporter(
            isPresented: $showingAudioImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                appModel.enqueueAudioFiles(urls)
            }
        }
        .sheet(item: languageSelectionBinding) { selection in
            MacAudioFileLanguageSelectionSheet(
                selection: selection,
                confirm: appModel.confirmPendingAudioFileLanguageSelection(languageID:),
                cancel: appModel.cancelPendingAudioFileLanguageSelection
            )
        }
    }

    private var languageSelectionBinding: Binding<PendingAudioFileLanguageSelection?> {
        Binding(
            get: { appModel.pendingAudioFileLanguageSelection },
            set: { selection in
                if selection == nil {
                    appModel.cancelPendingAudioFileLanguageSelection()
                }
            }
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 12) {
                    Text("GLSTT")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))

                    HomeBadge(title: appModel.isFileRecording ? "Recording" : appModel.isRecordingActive ? "Listening" : "Ready", tint: appModel.isBusyWithAudioWork ? .green : .secondary)
                }

                Text(appModel.triggerSummary)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if appModel.canStopCurrentSession {
                Button {
                    appModel.stopCurrentSession()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }

            AudioImportSquareButton(isTargeted: isAudioDropTargeted) {
                showingAudioImporter = true
            }
            .disabled(appModel.isBusyWithAudioWork)
            .dropDestination(for: URL.self) { urls, _ in
                appModel.enqueueAudioFiles(urls)
                return true
            } isTargeted: { isTargeted in
                isAudioDropTargeted = isTargeted
            }
        }
    }

    private var audioFileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(appModel.isAudioFileTranscriptionActive ? .blue : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("File Transcription")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text(appModel.isAudioFileTranscriptionActive ? "Transcribing queued audio." : "Queue audio from the button above.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            MacAudioFileTranscriptionSections(
                jobs: appModel.audioFileTranscriptionJobs,
                compact: false
            ) { job in
                appModel.openTranscriptOutput(for: job)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Transcripts")
                .font(.system(.title3, design: .rounded, weight: .bold))

            ScrollView {
                MacTranscriptHistoryList(
                    entries: appModel.transcriptHistory,
                    emptyMessage: "Use your shortcut to start dictation and your recent captures will show up here.",
                    copy: appModel.copyTranscript
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            SettingsLink {
                Text("Open Settings")
            }
        }
    }
}

private struct AudioImportSquareButton: View {
    let isTargeted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "waveform.badge.plus")
                    .font(.system(size: 21, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text("Audio")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
            }
            .frame(width: 70, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isTargeted ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.08), lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Import audio file")
    }
}

private struct MacAudioFileLanguageSelectionSheet: View {
    let selection: PendingAudioFileLanguageSelection
    let confirm: (String) -> Void
    let cancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguageID: String

    init(
        selection: PendingAudioFileLanguageSelection,
        confirm: @escaping (String) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.selection = selection
        self.confirm = confirm
        self.cancel = cancel
        _selectedLanguageID = State(initialValue: selection.defaultLanguageID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription Language")
                    .font(.title2.bold())
                Text(selection.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Picker("Language", selection: $selectedLanguageID) {
                ForEach(selection.languageOptions) { language in
                    Text(language.title)
                        .tag(language.id)
                }
            }
            .pickerStyle(.menu)

            if let selectedLanguage {
                Text(selectedLanguage.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    cancel()
                    dismiss()
                }

                Spacer()

                Button("Queue Files") {
                    confirm(selectedLanguageID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private var selectedLanguage: AudioTranscriptionLanguageOption? {
        selection.languageOptions.first { $0.id == selectedLanguageID }
    }
}

private struct HomeBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }
}
#endif
