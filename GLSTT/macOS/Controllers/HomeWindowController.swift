#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class HomeWindowController: NSWindowController {
    init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            audioFileSection
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
        .dropDestination(for: URL.self) { urls, _ in
            appModel.enqueueAudioFiles(urls)
            return true
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
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("GLSTT")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))

                Text(appModel.triggerSummary)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    HomeBadge(title: appModel.statusSummary, tint: appModel.isRecordingActive ? .green : .secondary)
                    HomeBadge(title: appModel.hudDisplayMode.title, tint: .blue)
                    HomeBadge(title: appModel.launchAtLoginBadgeTitle, tint: appModel.launchAtLoginEnabled ? .green : .secondary)
                }
            }

            Spacer()

            Button {
                showingAudioImporter = true
            } label: {
                Label("Audio", systemImage: "waveform.badge.plus")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .controlSize(.small)
            .disabled(appModel.isRecordingActive)
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
                    Text("Audio Files")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text("Drop recordings here for local transcription.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if appModel.audioFileTranscriptionJobs.isEmpty {
                Text("No audio files queued.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
            } else {
                MacAudioFileTranscriptionSections(
                    jobs: appModel.audioFileTranscriptionJobs,
                    compact: false
                ) { job in
                    appModel.openTranscriptOutput(for: job)
                }
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
            Button("Copy Latest") {
                appModel.copyLastTranscript()
            }
            .disabled(appModel.lastTranscript.isEmpty)

            Spacer()

            SettingsLink {
                Text("Open Settings")
            }
        }
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
