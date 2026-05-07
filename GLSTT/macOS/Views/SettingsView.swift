#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var captureTarget: ShortcutCaptureTarget?
    @State private var showingVocabularyImporter = false

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                SettingsCard("General") {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsToggleRow(
                            title: "Launch at login",
                            subtitle: appModel.loginItemSummary,
                            isOn: $appModel.launchAtLoginEnabled
                        )
                    }
                }

                SettingsCard("Triggers") {
                    VStack(alignment: .leading, spacing: 14) {
                        TriggerSummaryView(
                            holdSummary: appModel.holdTriggerSummary,
                            toggleSummary: appModel.toggleTriggerSummary
                        )

                        TriggerCaptureRow(
                            title: "Hold",
                            keyTitle: appModel.holdTriggerKey.title,
                            actionTitle: "Change Key"
                        ) {
                            captureTarget = .hold
                        }

                        TriggerCaptureRow(
                            title: "Toggle",
                            keyTitle: appModel.toggleTriggerKey.title,
                            actionTitle: "Change Key"
                        ) {
                            captureTarget = .toggle
                        }

                        Toggle("Require a double-press for the toggle key", isOn: $appModel.toggleTriggerRequiresDoublePress)
                            .toggleStyle(.switch)

                        if appModel.isBusyWithAudioWork {
                            Text("Stop dictation before changing hotkeys.")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(appModel.isBusyWithAudioWork)
                }

                SettingsCard("Insertion") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Insert live transcript while listening", isOn: $appModel.liveInsertionEnabled)
                        Toggle("Insert final transcript when dictation stops", isOn: $appModel.finalInsertionEnabled)
                        Toggle("Bias recognition with focused-field terms", isOn: $appModel.contextualVocabularyEnabled)
                        Toggle("Copy to clipboard if insertion is uncertain", isOn: $appModel.copyFailedInsertionsToClipboard)
                        Toggle("Open main window on failed insertion", isOn: $appModel.showTranscriptWindowOnFailure)
                    }
                }

                SettingsCard("Vocabulary Bias") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Imported Lists")
                                    .font(.system(.headline, design: .rounded, weight: .semibold))
                                Text(appModel.importedVocabularySummary)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Import Words") {
                                showingVocabularyImporter = true
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Clear") {
                                appModel.clearImportedVocabularyLists()
                            }
                            .buttonStyle(.bordered)
                            .disabled(appModel.importedVocabularyLists.isEmpty)
                        }

                        Text("Use a plain-text, CSV, or JSON file containing custom words. Apple recommends short entries and a combined limit of 100 contextual phrases.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)

                        if appModel.importedVocabularyLists.isEmpty {
                            Text("No imported lists yet.")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(appModel.importedVocabularyLists) { list in
                                    ImportedVocabularyRow(list: list) {
                                        appModel.removeImportedVocabularyList(list)
                                    }
                                }
                            }
                        }
                    }
                }

                SettingsCard("Permissions") {
                    VStack(alignment: .leading, spacing: 12) {
                        PermissionSettingsRow(
                            title: "Accessibility",
                            detail: appModel.permissions.accessibilitySummary,
                            status: permissionStatus(
                                isGranted: appModel.isAccessibilityGranted,
                                missingLabel: "Needed"
                            ),
                            requestAction: appModel.requestAccessibilityAccess,
                            openAction: appModel.openAccessibilitySettings
                        )

                        PermissionSettingsRow(
                            title: "Speech Recognition",
                            detail: appModel.permissions.speechSummary,
                            status: permissionStatus(
                                isGranted: appModel.isSpeechGranted,
                                missingLabel: "Needed"
                            ),
                            requestAction: {
                                Task {
                                    await appModel.requestSpeechAccess()
                                }
                            },
                            openAction: appModel.openSpeechSettings
                        )

                        PermissionSettingsRow(
                            title: "Microphone",
                            detail: appModel.permissions.microphoneSummary,
                            status: permissionStatus(
                                isGranted: appModel.isMicrophoneGranted,
                                missingLabel: "Needed"
                            ),
                            requestAction: {
                                Task {
                                    await appModel.requestMicrophoneAccess()
                                }
                            },
                            openAction: appModel.openMicrophoneSettings
                        )
                    }
                }

                SettingsCard("Utilities") {
                    HStack(spacing: 10) {
                        Button("Refresh") {
                            appModel.refreshPermissions()
                        }

                        Button("Permissions Window") {
                            appModel.showPermissionsWindow()
                        }

                        Button("Main Window") {
                            appModel.showTranscriptWindow()
                        }
                        .disabled(appModel.lastTranscript.isEmpty)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                SettingsCard("Software Update") {
                    SoftwareUpdateSectionView()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: 700, height: 620)
        .sheet(item: $captureTarget) { target in
            ShortcutCaptureSheet(
                target: target,
                onCapture: { key in
                    switch target {
                    case .hold:
                        appModel.holdTriggerKey = key
                    case .toggle:
                        appModel.toggleTriggerKey = key
                    }
                    captureTarget = nil
                },
                onCancel: {
                    captureTarget = nil
                }
            )
        }
        .fileImporter(
            isPresented: $showingVocabularyImporter,
            allowedContentTypes: [.plainText, .commaSeparatedText, .json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                appModel.importVocabularyList(from: url)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("GLSTT Settings")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))

                Text(appModel.triggerSummary)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    StatusBadge(title: appModel.statusSummary, tint: appModel.isBusyWithAudioWork ? .green : .secondary)
                    StatusBadge(title: appModel.hudDisplayMode.title, tint: .blue)
                    StatusBadge(title: appModel.launchAtLoginBadgeTitle, tint: appModel.launchAtLoginEnabled ? .green : .secondary)
                }
            }
        }
    }

    private func permissionStatus(isGranted: Bool, missingLabel: String) -> PermissionVisualStatus {
        if isGranted {
            return PermissionVisualStatus(title: "Ready", tint: .green, symbolName: "checkmark.circle.fill")
        }

        return PermissionVisualStatus(title: missingLabel, tint: .orange, symbolName: "exclamationmark.circle.fill")
    }
}

private struct ImportedVocabularyRow: View {
    let list: ImportedVocabularyList
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Text("\(list.words.count) words")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(list.words.prefix(8).joined(separator: ", "))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Remove", action: remove)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }
}

private struct TriggerCaptureRow: View {
    let title: String
    let keyTitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(width: 58, alignment: .leading)

            Text(keyTitle)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

            Spacer()

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        )
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct TriggerSummaryView: View {
    let holdSummary: String
    let toggleSummary: String

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(title: holdSummary, tint: .green)
            StatusBadge(title: toggleSummary, tint: .orange)
        }
    }
}

private struct StatusBadge: View {
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

private struct PermissionVisualStatus {
    let title: String
    let tint: Color
    let symbolName: String
}

private struct PermissionSettingsRow: View {
    let title: String
    let detail: String
    let status: PermissionVisualStatus
    let requestAction: () -> Void
    let openAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: status.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(status.tint)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    StatusBadge(title: status.title, tint: status.tint)
                }

                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Request", action: requestAction)
                Button("Open Settings", action: openAction)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SettingsView()
        .environment(AppModel(previewMode: true))
}
#endif
