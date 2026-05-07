#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    private static let onboardingDismissedKey = "glstt.permissions.onboarding.dismissed"
    private static let launchAtLoginPromptedKey = "glstt.settings.launchAtLogin.prompted"
    private static let hudDisplayModeKey = "glstt.settings.hudDisplayMode"
    private static let holdTriggerKeyKey = "glstt.settings.holdTriggerKey"
    private static let toggleTriggerKeyKey = "glstt.settings.toggleTriggerKey"
    private static let toggleDoublePressKey = "glstt.settings.toggleDoublePress"
    private static let liveInsertionKey = "glstt.settings.liveInsertion"
    private static let finalInsertionKey = "glstt.settings.finalInsertion"
    private static let contextualVocabularyKey = "glstt.settings.contextualVocabulary"
    private static let importedVocabularyListsKey = "glstt.settings.importedVocabularyLists"
    private static let copyFailedInsertionsKey = "glstt.settings.copyFailedInsertions"
    private static let showTranscriptWindowOnFailureKey = "glstt.settings.showTranscriptWindowOnFailure"

    enum HUDMode: Equatable {
        case hidden
        case recording
        case finalizing
        case message(String, isError: Bool)
    }

    enum HUDDisplayMode: String, CaseIterable, Identifiable {
        case off
        case compact
        case transcript

        var id: Self { self }

        var title: String {
            switch self {
            case .off:
                return "Off"
            case .compact:
                return "Compact"
            case .transcript:
                return "Transcript"
            }
        }
    }

    private(set) var permissions = AppPermissionsState.current()
    private(set) var finalizedTranscript = ""
    private(set) var volatileTranscript = ""
    private(set) var hudMode: HUDMode = .hidden
    private(set) var lastTranscript = ""
    private(set) var transcriptHistory: [TranscriptHistoryEntry] = []
    private(set) var importedVocabulary = ImportedVocabularySnapshot()
    private(set) var audioLevel: Double = 0
    private(set) var audioFileTranscriptionJobs: [AudioFileTranscriptionJob] = []
    private(set) var pendingAudioFileLanguageSelection: PendingAudioFileLanguageSelection?
    var launchAtLoginEnabled = false {
        didSet {
            guard !previewMode, !isSyncingLaunchAtLogin, launchAtLoginEnabled != oldValue else { return }
            isSyncingLaunchAtLogin = true
            defer { isSyncingLaunchAtLogin = false }

            do {
                try loginItemController.setEnabled(launchAtLoginEnabled)
                if loginItemController.state == .requiresApproval {
                    showMessage("Approve GLSTT in Login Items to finish enabling launch at login.", isError: false)
                }
            } catch {
                launchAtLoginEnabled = oldValue
                showMessage("Unable to change launch-at-login right now.", isError: true, autoHide: false)
            }
        }
    }
    var hudDisplayMode: HUDDisplayMode = .transcript {
        didSet {
            guard !previewMode else { return }
            defaults.set(hudDisplayMode.rawValue, forKey: Self.hudDisplayModeKey)
            syncHUDVisibility()
        }
    }
    var holdTriggerKey: TriggerKey = .rightOption {
        didSet {
            guard !previewMode, holdTriggerKey != oldValue else { return }
            syncHotkeyPreferences(preferred: .hold)
        }
    }
    var toggleTriggerKey: TriggerKey = .rightOption {
        didSet {
            guard !previewMode, toggleTriggerKey != oldValue else { return }
            syncHotkeyPreferences(preferred: .toggle)
        }
    }
    var toggleTriggerRequiresDoublePress = true {
        didSet {
            guard !previewMode, toggleTriggerRequiresDoublePress != oldValue else { return }
            syncHotkeyPreferences(preferred: .toggleMode)
        }
    }
    var liveInsertionEnabled = true {
        didSet {
            guard !previewMode else { return }
            defaults.set(liveInsertionEnabled, forKey: Self.liveInsertionKey)
        }
    }
    var finalInsertionEnabled = true {
        didSet {
            guard !previewMode else { return }
            defaults.set(finalInsertionEnabled, forKey: Self.finalInsertionKey)
        }
    }
    var contextualVocabularyEnabled = true {
        didSet {
            guard !previewMode else { return }
            defaults.set(contextualVocabularyEnabled, forKey: Self.contextualVocabularyKey)
        }
    }
    var copyFailedInsertionsToClipboard = true {
        didSet {
            guard !previewMode else { return }
            defaults.set(copyFailedInsertionsToClipboard, forKey: Self.copyFailedInsertionsKey)
        }
    }
    var showTranscriptWindowOnFailure = true {
        didSet {
            guard !previewMode else { return }
            defaults.set(showTranscriptWindowOnFailure, forKey: Self.showTranscriptWindowOnFailureKey)
        }
    }

    let speechController = SpeechTranscriptionController()

    @ObservationIgnored private let loginItemController = LoginItemController()
    @ObservationIgnored
    private let hotkeyMonitor = HotkeyMonitor()
    @ObservationIgnored
    private let inserter = AccessibilityInserter()
    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let vocabularyStore: ImportedVocabularyStore
    @ObservationIgnored
    private var hudPanelController: HUDPanelController?
    @ObservationIgnored
    private var onboardingWindowController: OnboardingWindowController?
    @ObservationIgnored
    private var transcriptWindowController: TranscriptWindowController?
    @ObservationIgnored
    private var homeWindowController: HomeWindowController?
    @ObservationIgnored
    private var hudDismissTask: Task<Void, Never>?
    @ObservationIgnored
    private var insertionTarget: AccessibilityInsertionTarget?
    @ObservationIgnored
    private var liveInsertionSession: LiveInsertionSession?
    @ObservationIgnored
    private var audioFileTranscriptionTask: Task<Void, Never>?
    private let previewMode: Bool
    @ObservationIgnored
    private var isSyncingLaunchAtLogin = false
    @ObservationIgnored
    private var isSyncingHotkeyPreferences = false

    private enum HotkeyPreferenceChange {
        case hold
        case toggle
        case toggleMode
    }

    init(previewMode: Bool = false) {
        self.previewMode = previewMode
        self.defaults = .standard
        self.vocabularyStore = ImportedVocabularyStore(storageKey: Self.importedVocabularyListsKey)
        self.hudPanelController = nil
        self.onboardingWindowController = nil
        self.transcriptWindowController = nil
        self.homeWindowController = nil
        let loginItemState = loginItemController.state
        self.launchAtLoginEnabled = previewMode
            ? false
            : (loginItemState == .enabled || loginItemState == .requiresApproval)
        self.hudDisplayMode = previewMode
            ? .compact
            : HUDDisplayMode(rawValue: defaults.string(forKey: Self.hudDisplayModeKey) ?? "") ?? .compact
        self.holdTriggerKey = previewMode
            ? .rightOption
            : {
                let storedValue = defaults.integer(forKey: Self.holdTriggerKeyKey)
                return storedValue == 0 ? .rightOption : TriggerKey(keyCode: UInt16(storedValue))
            }()
        self.toggleTriggerKey = previewMode
            ? .rightOption
            : {
                let storedValue = defaults.integer(forKey: Self.toggleTriggerKeyKey)
                return storedValue == 0 ? .rightOption : TriggerKey(keyCode: UInt16(storedValue))
            }()
        self.toggleTriggerRequiresDoublePress = previewMode
            ? true
            : defaults.object(forKey: Self.toggleDoublePressKey) as? Bool ?? true
        self.liveInsertionEnabled = previewMode ? true : defaults.object(forKey: Self.liveInsertionKey) as? Bool ?? true
        self.finalInsertionEnabled = previewMode ? true : defaults.object(forKey: Self.finalInsertionKey) as? Bool ?? true
        self.contextualVocabularyEnabled = previewMode ? true : defaults.object(forKey: Self.contextualVocabularyKey) as? Bool ?? true
        self.importedVocabulary = previewMode ? ImportedVocabularySnapshot() : vocabularyStore.load()
        self.copyFailedInsertionsToClipboard = previewMode ? true : defaults.object(forKey: Self.copyFailedInsertionsKey) as? Bool ?? true
        self.showTranscriptWindowOnFailure = previewMode ? true : defaults.object(forKey: Self.showTranscriptWindowOnFailureKey) as? Bool ?? true

        speechController.onTranscriptUpdate = { [weak self] transcript in
            guard let self else { return }
            self.finalizedTranscript = transcript.finalizedText
            self.volatileTranscript = transcript.volatileText
            if self.liveInsertionEnabled, self.speechController.isRecording {
                Task { @MainActor in
                    await self.applyLiveInsertionUpdate(transcript)
                }
            }
            self.syncHUDVisibility()
        }
        speechController.onAudioLevelUpdate = { [weak self] level in
            self?.audioLevel = level
        }

        hotkeyMonitor.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .beginRecording:
                Task { @MainActor in
                    await self.beginRecording()
                }
            case .endRecording:
                Task { @MainActor in
                    await self.finishRecording()
                }
            }
        }

        if !previewMode {
            hudPanelController = HUDPanelController(model: self)
            syncHotkeyPreferences(preferred: .toggle)
            hotkeyMonitor.start()
            if shouldPresentOnboarding {
                onboardingWindowController = OnboardingWindowController(model: self) { [weak self] in
                    self?.markOnboardingDismissed()
                }
                onboardingWindowController?.show()
            }
        }

        refreshPermissions()

        if !holdTriggerKey.isSupportedGlobalShortcut {
            holdTriggerKey = .rightOption
        }
        if !toggleTriggerKey.isSupportedGlobalShortcut {
            toggleTriggerKey = toggleTriggerRequiresDoublePress ? holdTriggerKey : .rightCommand
        }
    }

    isolated deinit {
        hotkeyMonitor.stop()
    }

    var menuBarIconName: String {
        if case .recording = hudMode {
            return "mic.fill"
        }

        if case .finalizing = hudMode {
            return "waveform"
        }

        return permissions.accessibilityTrusted ? "waveform.badge.mic" : "exclamationmark.magnifyingglass"
    }

    var statusSummary: String {
        switch hudMode {
        case .hidden:
            if speechController.isRecording {
                return "Listening"
            }
            return "Ready"
        case .recording:
            return "Listening"
        case .finalizing:
            return "Finalizing"
        case .message(let message, let isError):
            return isError ? "Error: \(message)" : message
        }
    }

    var loginItemSummary: String {
        switch loginItemController.state {
        case .enabled:
            return "Launches with macOS."
        case .disabled:
            return "Launches only when you open it."
        case .requiresApproval:
            return "Waiting for approval in Login Items."
        case .unavailable:
            return "Not available in this build."
        }
    }

    var launchAtLoginBadgeTitle: String {
        launchAtLoginEnabled ? "Launch at Login" : "Manual Launch"
    }

    var holdTriggerSummary: String {
        "Hold \(holdTriggerKey.title)"
    }

    var toggleTriggerSummary: String {
        if toggleTriggerRequiresDoublePress {
            return "Double-press \(toggleTriggerKey.title)"
        }

        return "Tap \(toggleTriggerKey.title)"
    }

    var triggerSummary: String {
        "\(holdTriggerSummary). \(toggleTriggerSummary) to latch."
    }

    var isRecordingActive: Bool {
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

    var importedVocabularySummary: String {
        importedVocabulary.summary
    }

    var hudTitle: String {
        switch hudMode {
        case .recording:
            return hudDisplayMode == .compact ? "" : "Listening"
        case .finalizing:
            return hudDisplayMode == .compact ? "" : "Finalizing Transcript"
        case .message(_, let isError):
            return isError ? "Attention Needed" : "GLSTT"
        case .hidden:
            return "Not Listening"
        }
    }

    var hudAppName: String {
        "GLSTT"
    }

    var hudMessage: String {
        switch hudMode {
        case .recording:
            return "Speak now. Release \(holdTriggerKey.shortTitle) to stop, or \(toggleTriggerSummary.lowercased()) to latch."
        case .finalizing:
            return "Wrapping up the final Apple transcript."
        case .message(let message, _):
            return message
        case .hidden:
            return "Hold \(holdTriggerKey.shortTitle) to start dictation."
        }
    }

    var hudAccentColor: Color {
        switch hudMode {
        case .recording:
            return .green
        case .finalizing:
            return .orange
        case .message(_, let isError):
            return isError ? .orange : .green
        case .hidden:
            return .secondary
        }
    }

    var hudBorderColor: Color {
        hudAccentColor.opacity(0.35)
    }

    var isHUDSpinning: Bool {
        if case .finalizing = hudMode { return true }
        return false
    }

    var canDismissHUD: Bool {
        if case .message = hudMode {
            return true
        }

        return false
    }

    var hudPanelSize: CGSize {
        switch hudDisplayMode {
        case .off:
            return .zero
        case .compact:
            switch hudMode {
            case .hidden:
                return CGSize(width: 92, height: 92)
            case .message:
                return CGSize(width: 260, height: 86)
            case .recording, .finalizing:
                return CGSize(width: 92, height: 92)
            }
        case .transcript:
            break
        }

        switch hudMode {
        case .hidden:
            return CGSize(width: 420, height: 112)
        case .message:
            return CGSize(width: 420, height: 126)
        case .recording, .finalizing:
            return CGSize(width: 620, height: 220)
        }
    }

    var hudStatusPanelSize: CGSize {
        switch hudDisplayMode {
        case .off:
            return .zero
        case .compact:
            return CGSize(width: 92, height: 92)
        case .transcript:
            return CGSize(width: 620, height: 220)
        }
    }

    var shouldPresentOnboarding: Bool {
        !defaults.bool(forKey: Self.onboardingDismissedKey)
    }

    var showsTranscriptHUD: Bool {
        hudDisplayMode == .transcript
    }

    var isAccessibilityGranted: Bool {
        permissions.accessibilityTrusted
    }

    var isSpeechGranted: Bool {
        permissions.speech == .granted
    }

    var isMicrophoneGranted: Bool {
        permissions.microphone == .granted
    }

    func refreshPermissions() {
        permissions = AppPermissionsState.current()
    }

    func showPermissionsWindow() {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController(model: self) { [weak self] in
                self?.markOnboardingDismissed()
            }
        }

        onboardingWindowController?.show()
    }

    func dismissOnboarding() {
        markOnboardingDismissed()
        onboardingWindowController?.close()
        onboardingWindowController = nil
        maybePromptForLaunchAtLogin()
    }

    func requestAccessibilityAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissions()
        showMessage("Accessibility permission is needed for the global hotkey and cross-app insertion.", isError: !permissions.accessibilityTrusted, autoHide: false)
    }

    func openAccessibilitySettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openSpeechSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    }

    func openMicrophoneSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func requestSpeechAccess() async {
        _ = await speechController.requestSpeechAccess()
        refreshPermissions()
    }

    func requestMicrophoneAccess() async {
        _ = await speechController.requestMicrophoneAccess()
        refreshPermissions()
    }

    func requestSpeechAndMicrophoneAccess() async {
        await speechController.requestSpeechAndMicrophoneAccess()
        refreshPermissions()
        showMessage("Speech and microphone permissions were refreshed.", isError: false)
    }

    func copyLastTranscript() {
        copyTranscript(lastTranscript)
    }

    func copyTranscript(_ entry: TranscriptHistoryEntry) {
        copyTranscript(entry.text)
    }

    func copyTranscript(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showMessage("Copied transcript.", isError: false)
    }

    func showTranscriptWindow() {
        guard !lastTranscript.isEmpty else { return }

        if transcriptWindowController == nil {
            transcriptWindowController = TranscriptWindowController(model: self)
        }

        transcriptWindowController?.show()
    }

    func showHomeWindow() {
        if homeWindowController == nil {
            homeWindowController = HomeWindowController(model: self)
        }

        homeWindowController?.show()
    }

    func handleIncomingAudioURL(_ url: URL) {
        if let request = AudioFileTranscriptionRequestStore.request(from: url) {
            showHomeWindow()
            Task { @MainActor in
                await requestAudioFileLanguageSelection(
                    for: [PendingAudioFileLanguageSelection.File(url: request.fileURL, displayName: request.displayName)]
                )
            }
            return
        }

        guard url.isFileURL else { return }
        showHomeWindow()
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
            showMessage("Choose a supported Apple speech language for that audio file.", isError: true, autoHide: false)
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
            showMessage("Stop dictation before queueing audio files.", isError: true)
            return
        }

        guard !files.isEmpty else { return }

        let languageOptions = await AudioTranscriptionLanguageOption.supportedOptions()
        guard let defaultLanguageID = AudioTranscriptionLanguageOption.defaultLanguageID(in: languageOptions) else {
            showMessage("Apple did not report any supported file transcription languages on this device.", isError: true, autoHide: false)
            return
        }

        let pendingFiles = (pendingAudioFileLanguageSelection?.files ?? []) + files
        pendingAudioFileLanguageSelection = PendingAudioFileLanguageSelection(
            files: pendingFiles,
            languageOptions: languageOptions,
            defaultLanguageID: defaultLanguageID
        )
        showHomeWindow()
    }

    func openTranscriptOutput(for job: AudioFileTranscriptionJob) {
        guard let outputURL = job.outputURL else { return }
        NSWorkspace.shared.open(outputURL)
    }

    private func enqueueAudioFile(
        at url: URL,
        displayName: String,
        language: AudioTranscriptionLanguageOption
    ) {
        audioFileTranscriptionJobs.append(
            AudioFileTranscriptionJob(sourceURL: url, displayName: displayName, language: language)
        )
        showHomeWindow()
        startAudioFileQueueIfNeeded()
    }

    private func beginRecording() async {
        hudDismissTask?.cancel()
        refreshPermissions()

        guard !isAudioFileTranscriptionActive else { return }

        guard permissions.accessibilityTrusted else {
            requestAccessibilityAccess()
            return
        }

        finalizedTranscript = ""
        volatileTranscript = ""
        audioLevel = 0
        insertionTarget = inserter.captureInsertionTarget()
        liveInsertionSession = liveInsertionEnabled ? inserter.beginLiveInsertionSession() : nil
        let contextualStrings = contextualVocabularyEnabled
            ? VocabularyImporter.mergedContextualStrings(
                importedLists: importedVocabulary.lists,
                runtimeWords: inserter.contextualVocabularyCandidates(limit: 40)
            )
            : []
        hudMode = .message("Requesting permissions and preparing Apple's on-device speech models…", isError: false)
        syncHUDVisibility()

        do {
            try await speechController.beginSession(contextualStrings: contextualStrings)
            refreshPermissions()
            hudMode = .recording
            syncHUDVisibility()
        } catch {
            refreshPermissions()
            liveInsertionSession = nil
            insertionTarget = nil
            showMessage(error.localizedDescription, isError: true)
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
        updateAudioFileJob(job.id) { $0.status = .preparing }

        let contextualStrings = contextualVocabularyEnabled
            ? VocabularyImporter.mergedContextualStrings(
                importedLists: importedVocabulary.lists,
                runtimeWords: []
            )
            : []

        do {
            let result = try await speechController.transcribeAudioFile(
                at: job.sourceURL,
                locale: job.language?.locale,
                contextualStrings: contextualStrings
            ) { [weak self] assembly in
                self?.updateAudioFileJob(job.id) {
                    $0.status = .transcribing
                    $0.preview = assembly.combinedText
                }
            }

            let transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                updateAudioFileJob(job.id) {
                    $0.status = .failed("No speech was found in that file.")
                }
                return
            }

            let outputURL = try AudioTranscriptOutputStore.saveTranscript(
                transcript,
                audioFileName: job.displayName
            )

            finalizedTranscript = transcript
            volatileTranscript = ""
            lastTranscript = transcript
            audioLevel = 0
            recordTranscriptHistory(transcript)
            updateAudioFileJob(job.id) {
                $0.status = .finished
                $0.preview = transcript
                $0.transcript = transcript
                $0.timedSegments = result.segments
                $0.outputURL = outputURL
            }
        } catch {
            audioLevel = 0
            updateAudioFileJob(job.id) {
                $0.status = .failed(error.localizedDescription)
            }
        }
    }

    private func updateAudioFileJob(
        _ id: AudioFileTranscriptionJob.ID,
        mutate: (inout AudioFileTranscriptionJob) -> Void
    ) {
        guard let index = audioFileTranscriptionJobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&audioFileTranscriptionJobs[index])
    }

    private func finishRecording() async {
        guard speechController.isRecording else { return }

        hudMode = .finalizing
        syncHUDVisibility()

        do {
            let text = try await speechController.finishSession()
            finalizedTranscript = text
            volatileTranscript = ""
            lastTranscript = text
            audioLevel = 0

            guard !text.isEmpty else {
                liveInsertionSession = nil
                insertionTarget = nil
                showMessage("No speech captured.", isError: true)
                return
            }

            recordTranscriptHistory(text)

            if var liveInsertionSession {
                let finalizedLiveInsert = await inserter.updateLiveInsertionSession(
                    &liveInsertionSession,
                    text: text,
                    finalizeSelection: true
                )
                self.liveInsertionSession = nil

                if finalizedLiveInsert {
                    let verified = await inserter.verifyLiveInsertion(text: text, session: liveInsertionSession)
                    insertionTarget = nil
                    if verified {
                        completeSuccessfulInsertion()
                    } else {
                        handleFailedInsertion(
                            text: text,
                            message: "GLSTT could not confirm the transcript appeared in the focused field."
                        )
                    }
                    return
                }
            }

            guard finalInsertionEnabled else {
                insertionTarget = nil
                showMessage("Captured transcript without automatic insertion.", isError: false)
                return
            }

            let insertionResult = await inserter.insert(text: text, preferredTarget: insertionTarget)
            insertionTarget = nil
            switch insertionResult {
            case .inserted(_, .confirmed):
                completeSuccessfulInsertion()

            case .inserted(_, .unverified):
                handleFailedInsertion(
                    text: text,
                    message: "GLSTT could not confirm the transcript appeared in the focused field."
                )

            case .noTarget:
                handleFailedInsertion(
                    text: text,
                    message: "No editable target was focused. The transcript was preserved."
                )

            case .accessibilityPermissionRequired:
                handleFailedInsertion(
                    text: text,
                    message: "Accessibility permission is required to insert into other apps."
                )

            case .failed(let message):
                handleFailedInsertion(text: text, message: message)
            }
        } catch {
            liveInsertionSession = nil
            insertionTarget = nil
            audioLevel = 0
            showMessage(error.localizedDescription, isError: true)
        }
    }

    private func completeSuccessfulInsertion() {
        hudDismissTask?.cancel()
        hudMode = .hidden
        syncHUDVisibility()
    }

    func dismissHUD() {
        hudDismissTask?.cancel()
        hudMode = .hidden
        syncHUDVisibility()
    }

    private func applyLiveInsertionUpdate(_ transcript: TranscriptAssembly) async {
        guard liveInsertionEnabled else { return }
        if var liveInsertionSession {
            let currentText = transcript.combinedText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !currentText.isEmpty else { return }

            let updated = await inserter.updateLiveInsertionSession(
                &liveInsertionSession,
                text: currentText,
                finalizeSelection: false
            )

            if updated {
                self.liveInsertionSession = liveInsertionSession
            }
        }
    }

    private func handleFailedInsertion(text: String, message: String) {
        if copyFailedInsertionsToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        if showTranscriptWindowOnFailure {
            if transcriptWindowController == nil {
                transcriptWindowController = TranscriptWindowController(model: self)
            }
            transcriptWindowController?.show()
        }

        let suffix = copyFailedInsertionsToClipboard ? " Copied to the clipboard." : ""
        showMessage(message + suffix, isError: true)
    }

    private func showMessage(_ message: String, isError: Bool, autoHide: Bool = true) {
        hudMode = .message(message, isError: isError)
        syncHUDVisibility()

        guard autoHide else { return }

        hudDismissTask?.cancel()
        hudDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            self?.hudMode = .hidden
            self?.syncHUDVisibility()
        }
    }

    private func syncHUDVisibility() {
        guard !previewMode else { return }
        guard hudDisplayMode != .off else {
            hudPanelController?.hide()
            return
        }

        hudPanelController?.show()
    }

    private func markOnboardingDismissed() {
        defaults.set(true, forKey: Self.onboardingDismissedKey)
    }

    private func maybePromptForLaunchAtLogin() {
        guard !previewMode else { return }
        guard !defaults.bool(forKey: Self.launchAtLoginPromptedKey) else { return }
        guard permissions.accessibilityTrusted else { return }
        guard permissions.speech == .granted, permissions.microphone == .granted else { return }
        guard !launchAtLoginEnabled else { return }

        defaults.set(true, forKey: Self.launchAtLoginPromptedKey)
        showMessage("Setup looks good. You can turn on launch at login in Settings whenever you want.", isError: false)
    }

    private var hotkeyConfiguration: HotkeyConfiguration {
        HotkeyConfiguration(
            holdKey: holdTriggerKey,
            toggleKey: toggleTriggerKey,
            toggleRequiresDoublePress: toggleTriggerRequiresDoublePress
        ).normalized
    }

    private func syncHotkeyPreferences(preferred: HotkeyPreferenceChange) {
        guard !previewMode, !isSyncingHotkeyPreferences else { return }

        isSyncingHotkeyPreferences = true
        defer { isSyncingHotkeyPreferences = false }

        if !holdTriggerKey.isSupportedGlobalShortcut {
            holdTriggerKey = .rightOption
        }
        if !toggleTriggerKey.isSupportedGlobalShortcut {
            toggleTriggerKey = toggleTriggerRequiresDoublePress ? holdTriggerKey : .rightCommand
        }

        if !toggleTriggerRequiresDoublePress, holdTriggerKey == toggleTriggerKey {
            switch preferred {
            case .hold:
                toggleTriggerKey = TriggerKey.firstAvailable(excluding: [holdTriggerKey])
            case .toggle, .toggleMode:
                toggleTriggerKey = TriggerKey.firstAvailable(excluding: [holdTriggerKey])
            }
        }

        defaults.set(Int(holdTriggerKey.keyCode), forKey: Self.holdTriggerKeyKey)
        defaults.set(Int(toggleTriggerKey.keyCode), forKey: Self.toggleTriggerKeyKey)
        defaults.set(toggleTriggerRequiresDoublePress, forKey: Self.toggleDoublePressKey)
        hotkeyMonitor.updateConfiguration(hotkeyConfiguration)
    }

    private func recordTranscriptHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        transcriptHistory.insert(TranscriptHistoryEntry(text: trimmed), at: 0)
    }

    func importVocabularyList(from url: URL) {
        do {
            importedVocabulary = try vocabularyStore.importingList(from: url, into: importedVocabulary)
            vocabularyStore.save(importedVocabulary)
            if let list = importedVocabulary.lists.first {
                showMessage("Imported \(list.words.count) words from \(list.name).", isError: false)
            }
        } catch {
            showMessage(error.localizedDescription, isError: true, autoHide: false)
        }
    }

    func removeImportedVocabularyList(_ list: ImportedVocabularyList) {
        importedVocabulary = vocabularyStore.removingList(list, from: importedVocabulary)
        vocabularyStore.save(importedVocabulary)
    }

    func clearImportedVocabularyLists() {
        importedVocabulary = vocabularyStore.clearing(importedVocabulary)
        vocabularyStore.save(importedVocabulary)
    }

    private func openSettingsPane(_ string: String) {
        if let url = URL(string: string), NSWorkspace.shared.open(url) {
            return
        }

        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in }
    }
}
#endif
