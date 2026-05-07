#if os(iOS)
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showingAudioImporter = false
    @State private var previewedTranscriptURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow

            PhoneAudioFileTranscriptionQueueView(
                jobs: appModel.audioFileTranscriptionJobs,
                openOutput: { previewedTranscriptURL = $0 }
            )

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
            PhoneAudioFileLanguageSelectionSheet(
                selection: selection,
                confirm: appModel.confirmPendingAudioFileLanguageSelection(languageID:),
                cancel: appModel.cancelPendingAudioFileLanguageSelection
            )
        }
        .quickLookPreview($previewedTranscriptURL)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isEditorFocused = false
                }
            }
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

            Button {
                showingAudioImporter = true
            } label: {
                Label("Audio", systemImage: "waveform")
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)
            .disabled(appModel.isRecording)

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

private struct PhoneAudioFileTranscriptionQueueView: View {
    let jobs: [AudioFileTranscriptionJob]
    let openOutput: (URL) -> Void

    private var activeJobs: [AudioFileTranscriptionJob] {
        jobs.filter { !$0.isComplete }
    }

    private var completedJobs: [AudioFileTranscriptionJob] {
        jobs.filter(\.isComplete)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if jobs.isEmpty {
                Text("Drop an audio file here or tap Audio to queue a recording.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
            } else {
                if !activeJobs.isEmpty {
                    PhoneAudioFileTranscriptionJobSection(title: "Active Queue") {
                        ForEach(activeJobs) { job in
                            PhoneAudioFileTranscriptionJobRow(job: job, openOutput: openOutput)
                        }
                    }
                }

                if !completedJobs.isEmpty {
                    PhoneAudioFileTranscriptionJobSection(title: "Completed Outputs") {
                        ForEach(completedJobs) { job in
                            PhoneAudioFileTranscriptionJobRow(job: job, openOutput: openOutput)
                        }
                    }
                }
            }
        }
    }
}

private struct PhoneAudioFileTranscriptionJobSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }
}

private struct PhoneAudioFileTranscriptionJobRow: View {
    let job: AudioFileTranscriptionJob
    let openOutput: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: job.iconName)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(job.language.map { "\(job.statusTitle) - \($0.title)" } ?? job.statusTitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(iconColor)
                }

                Spacer()

                if let outputURL = job.outputURL {
                    Button("Open Output") {
                        openOutput(outputURL)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            PhoneStreamingTranscriptText(text: job.statusMessage)

            if !job.timedSegments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Timestamps")
                        .font(.footnote.weight(.semibold))
                    ForEach(job.timedSegments.prefix(10)) { segment in
                        HStack(alignment: .top, spacing: 8) {
                            Text(segment.timeRangeLabel)
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 82, alignment: .leading)
                            Text(segment.speaker.map { "\($0): \(segment.text)" } ?? segment.text)
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
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

private struct PhoneAudioFileLanguageSelectionSheet: View {
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
        NavigationStack {
            Form {
                Section {
                    Picker("Language", selection: $selectedLanguageID) {
                        ForEach(selection.languageOptions) { language in
                            Text(language.title)
                                .tag(language.id)
                        }
                    }
                    .pickerStyle(.menu)

                    if let selectedLanguage {
                        Text(selectedLanguage.detail)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(selection.title)
                }
            }
            .navigationTitle("Transcription Language")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Queue") {
                        confirm(selectedLanguageID)
                        dismiss()
                    }
                }
            }
        }
    }

    private var selectedLanguage: AudioTranscriptionLanguageOption? {
        selection.languageOptions.first { $0.id == selectedLanguageID }
    }
}

private struct PhoneStreamingTranscriptText: View {
    let text: String
    private let bottomID = "phone-streaming-transcript-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
            }
            .frame(maxHeight: 140)
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
