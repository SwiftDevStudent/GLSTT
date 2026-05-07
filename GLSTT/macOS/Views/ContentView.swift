#if os(macOS)
//
//  ContentView.swift
//  GLSTT
//
//  Created by Naftali Antebi on 4/19/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppUpdater.self) private var updater
    @State private var showingTranscriptHistory = false
    @State private var showingAudioImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            permissionSection
            MacAudioRecorderView(compact: true)
                .environment(appModel)
            audioFileSection
            transcriptSection
            softwareUpdateSection
            actionSection
        }
        .padding(16)
        .frame(width: 320)
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
        .task {
            appModel.refreshPermissions()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GLSTT")
                .font(.system(.title2, design: .rounded, weight: .semibold))
            Text(appModel.triggerSummary)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var audioFileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Audio Files")
                    .font(.system(.headline, design: .rounded))

                Spacer()

                Button {
                    showingAudioImporter = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .disabled(appModel.isBusyWithAudioWork)
            }

            if appModel.audioFileTranscriptionJobs.isEmpty {
                Text("Drop recordings here or choose files to transcribe them into Recent Transcripts.")
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
                    compact: true
                ) { job in
                    appModel.openTranscriptOutput(for: job)
                }
            }
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PermissionRow(title: "Accessibility", detail: appModel.permissions.accessibilitySummary, isGranted: appModel.permissions.accessibilityTrusted)
            PermissionRow(title: "Speech", detail: appModel.permissions.speechSummary, isGranted: appModel.permissions.speech == .granted)
            PermissionRow(title: "Microphone", detail: appModel.permissions.microphoneSummary, isGranted: appModel.permissions.microphone == .granted)
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Recent Transcripts")
                    .font(.system(.headline, design: .rounded))

                Spacer()

                Button(action: {
                    showingTranscriptHistory.toggle()
                }) {
                    Label(showingTranscriptHistory ? "Hide" : "Show", systemImage: showingTranscriptHistory ? "chevron.up" : "chevron.down")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }

            if let latestEntry = appModel.transcriptHistory.first {
                Text(latestEntry.title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            } else {
                Text("Nothing captured yet.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }

            if showingTranscriptHistory {
                ScrollView {
                    MacTranscriptHistoryList(
                        entries: appModel.transcriptHistory,
                        emptyMessage: "Use your shortcut to start dictation and your recent captures will show up here.",
                        compact: true,
                        copy: appModel.copyTranscript
                    )
                }
                .frame(maxHeight: 220)
                .clipped()
            }
        }
    }

    private var softwareUpdateSection: some View {
        SoftwareUpdateSectionView(compact: true)
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Refresh Permissions") {
                appModel.refreshPermissions()
            }

            Button("Request Accessibility Access") {
                appModel.requestAccessibilityAccess()
            }

            Button("Request Speech & Microphone Access") {
                Task {
                    await appModel.requestSpeechAndMicrophoneAccess()
                }
            }

            Button("Show Permissions Window") {
                appModel.showPermissionsWindow()
            }

            Button("Open Window") {
                appModel.showHomeWindow()
            }

            Button("Open Accessibility Settings") {
                appModel.openAccessibilitySettings()
            }

            Button("Open Speech Settings") {
                appModel.openSpeechSettings()
            }

            Button("Open Microphone Settings") {
                appModel.openMicrophoneSettings()
            }

            if !appModel.lastTranscript.isEmpty {
                Button("Copy Last Transcript") {
                    appModel.copyLastTranscript()
                }

                Button("Open Main Window") {
                    appModel.showTranscriptWindow()
                }
            }

            Divider()

            SettingsLink {
                Text("Open Settings")
            }

            Button("Quit GLSTT") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.plain)
    }
}

struct MacAudioFileTranscriptionSections: View {
    let jobs: [AudioFileTranscriptionJob]
    let compact: Bool
    let openOutput: (AudioFileTranscriptionJob) -> Void

    private var activeJobs: [AudioFileTranscriptionJob] {
        jobs.filter { !$0.isComplete }
    }

    private var completedJobs: [AudioFileTranscriptionJob] {
        jobs.filter(\.isComplete)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if !activeJobs.isEmpty {
                MacAudioFileTranscriptionJobSection(title: "Active Queue") {
                    ForEach(activeJobs) { job in
                        MacAudioFileTranscriptionJobRow(job: job, compact: compact) {
                            openOutput(job)
                        }
                    }
                }
            }

            if !completedJobs.isEmpty {
                MacAudioFileTranscriptionJobSection(title: "Completed Outputs") {
                    ForEach(completedJobs) { job in
                        MacAudioFileTranscriptionJobRow(job: job, compact: compact) {
                            openOutput(job)
                        }
                    }
                }
            }
        }
    }
}

private struct MacAudioFileTranscriptionJobSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
    }
}

struct MacAudioFileTranscriptionJobRow: View {
    let job: AudioFileTranscriptionJob
    let compact: Bool
    let openOutput: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: job.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(job.displayName)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    Text(job.language.map { "\(job.statusTitle) - \($0.title)" } ?? job.statusTitle)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                Spacer(minLength: 8)

                if job.outputURL != nil {
                    Button("Open Output", action: openOutput)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .buttonStyle(.borderless)
                }
            }

            MacStreamingTranscriptText(text: job.statusMessage, maxHeight: compact ? 92 : 160)

            if !job.timedSegments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Timestamps")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                    ForEach(job.timedSegments.prefix(compact ? 4 : 12)) { segment in
                        HStack(alignment: .top, spacing: 8) {
                            Text(segment.timeRangeLabel)
                                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 82, alignment: .leading)
                            Text(segment.speaker.map { "\($0): \(segment.text)" } ?? segment.text)
                                .font(.system(.caption2, design: .rounded))
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var iconColor: Color {
        switch job.status {
        case .finished:
            return .green
        case .failed:
            return .orange
        case .preparing, .transcribing:
            return .blue
        case .pending:
            return .secondary
        }
    }
}

private struct MacStreamingTranscriptText: View {
    let text: String
    let maxHeight: CGFloat
    private let bottomID = "mac-streaming-transcript-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
            }
            .frame(maxHeight: maxHeight)
            .onAppear {
                scrollToBottom(proxy)
            }
            .onChange(of: text) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.16)) {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel(previewMode: true))
        .environment(AppUpdater())
}
#endif
