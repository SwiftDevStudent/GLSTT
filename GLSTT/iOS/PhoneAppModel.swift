#if os(iOS)
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class PhoneAppModel {
    private static let livePreviewKey = "glstt.ios.livePreview"
    private static let importedVocabularyListsKey = "glstt.ios.importedVocabularyLists"
    private static let transcriptDatabaseName = "phone-transcripts.sqlite"

    private(set) var permissions = AppPermissionsState.current()
    private(set) var finalizedTranscript = ""
    private(set) var volatileTranscript = ""
    private(set) var transcriptHistory: [TranscriptHistoryEntry] = []
    private(set) var importedVocabulary = ImportedVocabularySnapshot()
    private(set) var lastTranscript = ""
    private(set) var audioLevel: Double = 0
    private(set) var audioFileTranscriptionJobs: [AudioFileTranscriptionJob] = []
    private(set) var pendingAudioFileLanguageSelection: PendingAudioFileLanguageSelection?
    private(set) var selectedBuiltInPackIDs = Set<String>()
    private(set) var selectedImportedVocabularyListIDs = Set<UUID>()
    var alertMessage: String?
    var draftText = ""
    var livePreviewEnabled = true {
        didSet {
            defaults.set(livePreviewEnabled, forKey: Self.livePreviewKey)
        }
    }

    let speechController = SpeechTranscriptionController()

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let vocabularyStore: ImportedVocabularyStore
    @ObservationIgnored private let transcriptStore: TranscriptHistoryStore
    @ObservationIgnored private var sessionBaseText = ""
    @ObservationIgnored private var audioFileTranscriptionTask: Task<Void, Never>?

    init() {
        vocabularyStore = ImportedVocabularyStore(storageKey: Self.importedVocabularyListsKey)
        transcriptStore = TranscriptHistoryStore(filename: Self.transcriptDatabaseName)
        livePreviewEnabled = defaults.object(forKey: Self.livePreviewKey) as? Bool ?? true
        importedVocabulary = vocabularyStore.load()
        transcriptHistory = transcriptStore.loadEntries()

        speechController.onTranscriptUpdate = { [weak self] transcript in
            guard let self else { return }
            self.finalizedTranscript = transcript.finalizedText
            self.volatileTranscript = transcript.volatileText
            if self.livePreviewEnabled, self.speechController.isRecording {
                self.applyLivePreview(transcript.combinedText)
            }
        }

        speechController.onAudioLevelUpdate = { [weak self] level in
            self?.audioLevel = level
        }
    }

    var isRecording: Bool {
        speechController.isRecording
    }

    var isAudioFileTranscriptionActive: Bool {
        audioFileTranscriptionJobs.contains { $0.isActive }
    }

    var activeAudioFileTranscriptionJob: AudioFileTranscriptionJob? {
        audioFileTranscriptionJobs.first { $0.isActive }
    }

    var importedVocabularyWordCount: Int {
        importedVocabulary.totalWordCount
    }

    var importedVocabularyLists: [ImportedVocabularyList] {
        importedVocabulary.lists
    }

    var builtInVocabularyPacks: [BuiltInVocabularyPack] {
        BuiltInVocabularyLibrary.packs
    }

    var selectedBuiltInPacks: [BuiltInVocabularyPack] {
        builtInVocabularyPacks.filter { selectedBuiltInPackIDs.contains($0.id) }
    }

    var selectedImportedVocabularyLists: [ImportedVocabularyList] {
        importedVocabularyLists.filter { selectedImportedVocabularyListIDs.contains($0.id) }
    }

    var importedVocabularySummary: String {
        importedVocabulary.summary
    }

    var selectedBiasSummary: String {
        let names = selectedBuiltInPacks.map(\.name) + selectedImportedVocabularyLists.map(\.name)
        guard !names.isEmpty else { return "No active bias packs for this draft." }
        return names.joined(separator: ", ")
    }

    var selectedBiasWordCount: Int {
        selectedBuiltInPacks.reduce(0) { $0 + $1.words.count }
            + selectedImportedVocabularyLists.reduce(0) { $0 + $1.words.count }
    }

    var permissionSummary: String {
        if permissions.speech != .granted {
            return permissions.speechSummary
        }
        if permissions.microphone != .granted {
            return permissions.microphoneSummary
        }
        return "Speech recognition and microphone access are ready."
    }

    func refreshPermissions() {
        permissions = AppPermissionsState.current()
    }

    func requestPermissions() async {
        await speechController.requestSpeechAndMicrophoneAccess()
        refreshPermissions()
    }

    func toggleRecording() {
        Task {
            if speechController.isRecording {
                await stopRecording()
            } else {
                await startRecording()
            }
        }
    }

    func handleIncomingAudioURL(_ url: URL) {
        if let request = AudioFileTranscriptionRequestStore.request(from: url) {
            Task { @MainActor in
                await requestAudioFileLanguageSelection(
                    for: [PendingAudioFileLanguageSelection.File(url: request.fileURL, displayName: request.displayName)]
                )
            }
            return
        }

        guard url.isFileURL else { return }
        enqueueAudioFiles([url])
    }

    func transcribeAudioFile(from url: URL) {
        enqueueAudioFiles([url])
    }

    func enqueueAudioFiles(_ urls: [URL]) {
        Task { @MainActor in
            await requestAudioFileLanguageSelection(for: urls)
        }
    }

    private func requestAudioFileLanguageSelection(for urls: [URL]) async {
        await requestAudioFileLanguageSelection(
            for: urls
                .filter(\.isFileURL)
                .map { PendingAudioFileLanguageSelection.File(url: $0, displayName: $0.lastPathComponent) }
        )
    }

    func confirmPendingAudioFileLanguageSelection(languageID: String) {
        guard let pendingAudioFileLanguageSelection else { return }
        guard let language = pendingAudioFileLanguageSelection.languageOptions.first(where: { $0.id == languageID }) else {
            alertMessage = "Choose a supported Apple speech language for that audio file."
            return
        }

        self.pendingAudioFileLanguageSelection = nil
        for file in pendingAudioFileLanguageSelection.files {
            enqueueAudioFile(at: file.url, displayName: file.displayName, language: language)
        }
    }

    func cancelPendingAudioFileLanguageSelection() {
        pendingAudioFileLanguageSelection = nil
    }

    private func requestAudioFileLanguageSelection(for files: [PendingAudioFileLanguageSelection.File]) async {
        guard !speechController.isRecording else {
            alertMessage = "Stop dictation before queueing audio files."
            return
        }

        guard !files.isEmpty else { return }

        let languageOptions = await AudioTranscriptionLanguageOption.supportedOptions()
        guard let defaultLanguageID = AudioTranscriptionLanguageOption.defaultLanguageID(in: languageOptions) else {
            alertMessage = "Apple did not report any supported file transcription languages on this device."
            return
        }

        let pendingFiles = (pendingAudioFileLanguageSelection?.files ?? []) + files
        pendingAudioFileLanguageSelection = PendingAudioFileLanguageSelection(
            files: pendingFiles,
            languageOptions: languageOptions,
            defaultLanguageID: defaultLanguageID
        )
    }

    private func enqueueAudioFile(
        at url: URL,
        displayName: String,
        language: AudioTranscriptionLanguageOption
    ) {
        audioFileTranscriptionJobs.append(
            AudioFileTranscriptionJob(sourceURL: url, displayName: displayName, language: language)
        )
        startAudioFileQueueIfNeeded()
    }

    func saveCurrentDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendHistory(trimmed)
        lastTranscript = trimmed
    }

    func copyTranscript(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    func clearDraft() {
        draftText = ""
        finalizedTranscript = ""
        volatileTranscript = ""
        lastTranscript = ""
    }

    func importVocabularyList(from url: URL) {
        do {
            let list = try VocabularyImporter.importList(from: url)
            importedVocabulary = vocabularyStore.importing(list, into: importedVocabulary)
            vocabularyStore.save(importedVocabulary)
            selectedImportedVocabularyListIDs.insert(list.id)
            alertMessage = "Imported \(list.words.count) words from \(list.name)."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func removeImportedVocabularyList(_ list: ImportedVocabularyList) {
        importedVocabulary = vocabularyStore.removingList(list, from: importedVocabulary)
        vocabularyStore.save(importedVocabulary)
        selectedImportedVocabularyListIDs.remove(list.id)
    }

    func clearImportedVocabularyLists() {
        importedVocabulary = vocabularyStore.clearing(importedVocabulary)
        vocabularyStore.save(importedVocabulary)
        selectedImportedVocabularyListIDs.removeAll()
    }

    func clearSelectedBiasPacks() {
        selectedBuiltInPackIDs.removeAll()
        selectedImportedVocabularyListIDs.removeAll()
    }

    func toggleBuiltInVocabularyPack(_ pack: BuiltInVocabularyPack) {
        if selectedBuiltInPackIDs.contains(pack.id) {
            selectedBuiltInPackIDs.remove(pack.id)
        } else {
            selectedBuiltInPackIDs.insert(pack.id)
        }
    }

    func toggleImportedVocabularySelection(_ list: ImportedVocabularyList) {
        if selectedImportedVocabularyListIDs.contains(list.id) {
            selectedImportedVocabularyListIDs.remove(list.id)
        } else {
            selectedImportedVocabularyListIDs.insert(list.id)
        }
    }

    func selectOnlyBuiltInVocabularyPack(_ pack: BuiltInVocabularyPack) {
        selectedBuiltInPackIDs = [pack.id]
        selectedImportedVocabularyListIDs.removeAll()
    }

    func selectOnlyImportedVocabularyList(_ list: ImportedVocabularyList) {
        selectedImportedVocabularyListIDs = [list.id]
        selectedBuiltInPackIDs.removeAll()
    }

    private func startRecording() async {
        alertMessage = nil
        refreshPermissions()

        guard !isAudioFileTranscriptionActive else {
            alertMessage = "Finish the current audio file transcription before starting dictation."
            return
        }

        sessionBaseText = draftText
        finalizedTranscript = ""
        volatileTranscript = ""
        audioLevel = 0

        do {
            try await speechController.beginSession(
                contextualStrings: VocabularyImporter.mergedContextualStrings(
                    importedLists: selectedImportedVocabularyLists,
                    runtimeWords: selectedBuiltInPacks.flatMap(\.words)
                )
            )
            refreshPermissions()
        } catch {
            refreshPermissions()
            alertMessage = error.localizedDescription
        }
    }

    private func startAudioFileQueueIfNeeded() {
        guard audioFileTranscriptionTask == nil else { return }

        audioFileTranscriptionTask = Task { [weak self] in
            await self?.processAudioFileQueue()
        }
    }

    private func processAudioFileQueue() async {
        defer {
            audioFileTranscriptionTask = nil
            if audioFileTranscriptionJobs.contains(where: { $0.status == .pending }) {
                startAudioFileQueueIfNeeded()
            }
        }

        while let jobIndex = audioFileTranscriptionJobs.firstIndex(where: { $0.status == .pending }) {
            let job = audioFileTranscriptionJobs[jobIndex]
            await runAudioFileTranscription(job)
        }
    }

    private func runAudioFileTranscription(_ job: AudioFileTranscriptionJob) async {
        alertMessage = nil
        sessionBaseText = draftText
        finalizedTranscript = ""
        volatileTranscript = ""
        audioLevel = 0
        updateAudioFileJob(job.id) { $0.status = .preparing }

        do {
            let result = try await speechController.transcribeAudioFile(
                at: job.sourceURL,
                locale: job.language?.locale,
                contextualStrings: VocabularyImporter.mergedContextualStrings(
                    importedLists: selectedImportedVocabularyLists,
                    runtimeWords: selectedBuiltInPacks.flatMap(\.words)
                )
            ) { [weak self] assembly in
                self?.updateAudioFileJob(job.id) {
                    $0.status = .transcribing
                    $0.preview = assembly.combinedText
                }
            }

            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                updateAudioFileJob(job.id) {
                    $0.status = .failed("No speech was found in that file.")
                }
                alertMessage = "No speech was found in \(job.displayName)."
                return
            }

            let outputURL = try AudioTranscriptOutputStore.saveTranscript(
                trimmed,
                audioFileName: job.displayName
            )

            finalizedTranscript = trimmed
            volatileTranscript = ""
            draftText = mergedText(base: sessionBaseText, transcript: trimmed)
            lastTranscript = trimmed
            appendHistory(trimmed)
            updateAudioFileJob(job.id) {
                $0.status = .finished
                $0.preview = trimmed
                $0.transcript = trimmed
                $0.timedSegments = result.segments
                $0.outputURL = outputURL
            }
        } catch {
            audioLevel = 0
            updateAudioFileJob(job.id) {
                $0.status = .failed(error.localizedDescription)
            }
            alertMessage = error.localizedDescription
        }
    }

    private func updateAudioFileJob(
        _ id: AudioFileTranscriptionJob.ID,
        mutate: (inout AudioFileTranscriptionJob) -> Void
    ) {
        guard let index = audioFileTranscriptionJobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&audioFileTranscriptionJobs[index])
    }

    private func stopRecording() async {
        guard speechController.isRecording else { return }

        do {
            let text = try await speechController.finishSession()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            finalizedTranscript = trimmed
            volatileTranscript = ""
            audioLevel = 0

            guard !trimmed.isEmpty else {
                draftText = sessionBaseText
                alertMessage = "No speech captured."
                return
            }

            draftText = mergedText(base: sessionBaseText, transcript: trimmed)
            lastTranscript = trimmed
            appendHistory(trimmed)
        } catch {
            audioLevel = 0
            alertMessage = error.localizedDescription
        }
    }

    private func appendHistory(_ text: String) {
        let entry = TranscriptHistoryEntry(text: text)
        transcriptHistory.removeAll { $0.text == text }
        transcriptHistory.insert(entry, at: 0)
        transcriptStore.save(entry)
    }

    private func applyLivePreview(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        draftText = mergedText(base: sessionBaseText, transcript: trimmed)
    }

    private func mergedText(base: String, transcript: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return base }
        guard !base.isEmpty else { return trimmedTranscript }

        let needsSpacer = base.last.map(Self.isWordCharacter) == true && trimmedTranscript.first.map(Self.isWordCharacter) == true
        return needsSpacer ? base + " " + trimmedTranscript : base + trimmedTranscript
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}
#endif
