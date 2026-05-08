#if os(macOS)
//
//  ContentView.swift
//  GLSTT
//
//  Created by Naftali Antebi on 4/19/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Open Window") {
                appModel.showHomeWindow()
            }

            if appModel.canStopCurrentSession {
                Button("Stop Current Session") {
                    appModel.stopCurrentSession()
                }
            }

            if !appModel.lastTranscript.isEmpty {
                Button("Copy Last Transcript") {
                    appModel.copyLastTranscript()
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
        .padding(12)
        .frame(width: 180)
        .task {
            appModel.refreshMenuBarState()
        }
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
