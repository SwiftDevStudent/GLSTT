#if os(iOS)
import SwiftUI

struct PhoneComposerSection: View {
    @Environment(PhoneAppModel.self) private var appModel

    var body: some View {
        Section {
            PhoneComposerCard()
                .environment(appModel)
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
        }
    }
}

private struct PhoneComposerCard: View {
    @Environment(PhoneAppModel.self) private var appModel
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow

            if hasActiveBiasPacks {
                Text("Biasing: \(appModel.selectedBiasSummary)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            TextEditor(text: draftBinding)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .padding(14)
                .focused($isEditorFocused)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                )

            if hasDraftText {
                draftActions
            }

            PhoneDictationControls()
                .environment(appModel)
                .environment(\.phoneEditorFocusBinding, $isEditorFocused)
        }
        .padding(.vertical, 8)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isEditorFocused = false
                }
            }
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { appModel.draftText },
            set: { appModel.draftText = $0 }
        )
    }

    private var hasDraftText: Bool {
        !appModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasActiveBiasPacks: Bool {
        appModel.selectedBiasWordCount > 0
    }

    @ViewBuilder
    private var draftActions: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 12) {
                actionRow
            }
        } else {
            actionRow
        }
    }

    private var actionRow: some View {
        HStack {
            Spacer()
            clearButton
            copyButton
        }
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            appModel.clearDraft()
        } label: {
            Label("Clear", systemImage: "xmark.circle")
        }
        .controlSize(.regular)
        .modifier(SecondaryActionButtonStyleModifier())
    }

    private var copyButton: some View {
        Button {
            appModel.copyTranscript(appModel.draftText)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
                .foregroundStyle(.white)
                .symbolRenderingMode(.monochrome)
        }
        .controlSize(.regular)
        .modifier(PrimaryActionButtonStyleModifier())
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Quick Dictation")
                .font(.title2.weight(.bold))

            Spacer()

            Menu {
                Button("No Pack") {
                    appModel.clearSelectedBiasPacks()
                }

                if !appModel.builtInVocabularyPacks.isEmpty {
                    Section("Built-in") {
                        ForEach(appModel.builtInVocabularyPacks) { pack in
                            Button(pack.name) {
                                appModel.selectOnlyBuiltInVocabularyPack(pack)
                            }
                        }
                    }
                }

                if !appModel.importedVocabularyLists.isEmpty {
                    Section("Imported") {
                        ForEach(appModel.importedVocabularyLists) { list in
                            Button(list.name) {
                                appModel.selectOnlyImportedVocabularyList(list)
                            }
                        }
                    }
                }
            } label: {
                Label("Packs", systemImage: "square.stack.3d.up")
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)
        }
    }
}

private struct PhoneDictationControls: View {
    @Environment(PhoneAppModel.self) private var appModel
    @Environment(\.phoneEditorFocusBinding) private var editorFocusBinding

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Button {
                appModel.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(appModel.isRecording ? Color.orange : Color.green)
                        .frame(width: 96, height: 96)
                        .shadow(color: (appModel.isRecording ? Color.orange : Color.green).opacity(0.28), radius: 18, y: 10)

                    VStack(spacing: 6) {
                        Image(systemName: appModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        PhoneLevelMeter(level: appModel.audioLevel)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appModel.isRecording ? "Stop dictation" : "Start dictation")

            VStack(alignment: .leading, spacing: 6) {
                Text(appModel.isRecording ? "Listening" : "Tap to start recording")
                    .font(.headline)
                Text(appModel.isRecording ? "Tap to stop" : appModel.permissionSummary)
                    .font(.footnote)
                    .foregroundStyle(appModel.isRecording ? .orange : .secondary)
                if appModel.importedVocabularyWordCount > 0 {
                    Text("Bias library: \(appModel.importedVocabularyWordCount) imported words.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if appModel.selectedBiasWordCount > 100 {
                    Text("Using the first 100 phrases for Apple biasing.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                if editorFocusBinding?.wrappedValue == true {
                    Button("Hide Keyboard") {
                        editorFocusBinding?.wrappedValue = false
                    }
                    .buttonStyle(.borderless)
                    .font(.footnote.weight(.semibold))
                }
            }
        }
    }
}

private struct PhoneLevelMeter: View {
    let level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            meterBar(index: 0)
            meterBar(index: 1)
            meterBar(index: 2)
        }
    }

    private func meterBar(index: Int) -> some View {
        Capsule(style: .continuous)
            .fill(fillColor)
            .frame(width: 4, height: heights[index])
    }

    private var heights: [Double] {
        guard level > 0.02 else {
            return [10, 10, 10]
        }

        return [
            9 + (level * 9),
            12 + (level * 16),
            9 + (level * 11),
        ]
    }

    private var fillColor: Color {
        level > 0.02 ? Color.white : Color.secondary.opacity(0.55)
    }
}

private struct PrimaryActionButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

private struct SecondaryActionButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct PhoneEditorFocusBindingKey: EnvironmentKey {
    static let defaultValue: FocusState<Bool>.Binding? = nil
}

private extension EnvironmentValues {
    var phoneEditorFocusBinding: FocusState<Bool>.Binding? {
        get { self[PhoneEditorFocusBindingKey.self] }
        set { self[PhoneEditorFocusBindingKey.self] = newValue }
    }
}
#endif
