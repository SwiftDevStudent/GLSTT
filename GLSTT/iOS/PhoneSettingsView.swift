#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct PhoneSettingsView: View {
    @Environment(PhoneAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingVocabularyImporter = false

    var body: some View {
        @Bindable var appModel = appModel

        Form {
            Section("Dictation") {
                Toggle("Show live transcript in the note", isOn: $appModel.livePreviewEnabled)

                Button(appModel.isRecording ? "Stop Dictation" : "Start Dictation") {
                    appModel.toggleRecording()
                }
            }

            Section("Vocabulary Bias") {
                Text("Active for this draft")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(appModel.builtInVocabularyPacks) { pack in
                    DraftBiasPackRow(
                        title: pack.name,
                        detail: pack.detail,
                        wordCount: pack.words.count,
                        isSelected: appModel.selectedBuiltInPackIDs.contains(pack.id)
                    ) {
                        appModel.toggleBuiltInVocabularyPack(pack)
                    }
                }

                if !appModel.importedVocabularyLists.isEmpty {
                    ForEach(appModel.importedVocabularyLists) { list in
                        DraftBiasPackRow(
                            title: list.name,
                            detail: "Imported list",
                            wordCount: list.words.count,
                            isSelected: appModel.selectedImportedVocabularyListIDs.contains(list.id)
                        ) {
                            appModel.toggleImportedVocabularySelection(list)
                        }
                    }
                }

                if appModel.selectedBiasWordCount > 0 {
                    Button("Clear Active Bias Packs", role: .destructive) {
                        appModel.clearSelectedBiasPacks()
                    }
                }

                Button("Import Word List") {
                    showingVocabularyImporter = true
                }

                Text(appModel.importedVocabularySummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if appModel.importedVocabularyLists.isEmpty {
                    Text("No imported lists yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appModel.importedVocabularyLists) { list in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.name)
                                Text("\(list.words.count) words")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                appModel.removeImportedVocabularyList(list)
                            }
                        }
                    }

                    Button("Clear All", role: .destructive) {
                        appModel.clearImportedVocabularyLists()
                    }
                }

                Text("Bias selection is off by default and only applies to the current draft. Apple’s contextual bias API is most effective with short terms, and the app sends at most 100 phrases per dictation session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Speech Recognition",
                    state: appModel.permissions.speech,
                    detail: appModel.permissions.speechSummary
                )
                PermissionRow(
                    title: "Microphone",
                    state: appModel.permissions.microphone,
                    detail: appModel.permissions.microphoneSummary
                )

                Button("Request Access") {
                    Task {
                        await appModel.requestPermissions()
                    }
                }

                Button("Refresh Status") {
                    appModel.refreshPermissions()
                }
            }

            Section("Draft") {
                Button("Save Current Note to History") {
                    appModel.saveCurrentDraft()
                }
                .disabled(appModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
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
}

private struct DraftBiasPackRow: View {
    let title: String
    let detail: String
    let wordCount: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("\(wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(isSelected ? "Using" : "Use") {
                action()
            }
            .controlSize(.small)
            .modifier(DraftBiasSelectionButtonStyleModifier(isSelected: isSelected))
        }
        .padding(.vertical, 4)
    }
}

private struct DraftBiasSelectionButtonStyleModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let state: AccessState
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.headline)
            }

            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch state {
        case .granted:
            return .green
        case .notDetermined:
            return .orange
        case .denied, .restricted:
            return .red
        }
    }
}
#endif
