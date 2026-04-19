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
    @Environment(AppUpdater.self) private var updater
    @State private var showingTranscriptHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            permissionSection
            transcriptSection
            softwareUpdateSection
            actionSection
        }
        .padding(16)
        .frame(width: 320)
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
                        compact: true
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

                Button("Show Transcript Window") {
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

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
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
