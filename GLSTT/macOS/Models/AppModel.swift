#if os(macOS)
import AppKit
import ApplicationServices
import AVFAudio
import CoreGraphics
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    private static let onboardingDismissedKey = "glstt.permissions.onboarding.dismissed"
    private static let launchAtLoginPromptedKey = "glstt.settings.launchAtLogin.prompted"
    private static let hudDisplayModeKey = "glstt.settings.hudDisplayMode"
    private static let showMenuBarInformationalMessagesKey = "glstt.settings.menuBarMessages.informational"
    private static let showMenuBarInsertionMessagesKey = "glstt.settings.menuBarMessages.insertion"
    private static let showMenuBarImportantMessagesKey = "glstt.settings.menuBarMessages.important"
    private static let holdTriggerKeyKey = "glstt.settings.holdTriggerKey"
    private static let toggleTriggerKeyKey = "glstt.settings.toggleTriggerKey"
    private static let toggleDoublePressKey = "glstt.settings.toggleDoublePress"
    private static let liveInsertionKey = "glstt.settings.liveInsertion"
    private static let finalInsertionKey = "glstt.settings.finalInsertion"
    private static let contextualVocabularyKey = "glstt.settings.contextualVocabulary"
    private static let importedVocabularyListsKey = "glstt.settings.importedVocabularyLists"
    private static let copyFailedInsertionsKey = "glstt.settings.copyFailedInsertions"
    private static let showTranscriptWindowOnFailureKey = "glstt.settings.showTranscriptWindowOnFailure"
    private static let cursorTextFieldKey = "glstt.settings.cursorTextField"
    private static let savedAudioRecordingsKey = "glstt.macos.savedAudioRecordings"
    private static let transcriptDatabaseName = "mac-transcripts.sqlite"

    enum HUDMode: Equatable {
        case hidden
        case recording
        case finalizing
        case message(String, isError: Bool)
    }

    enum HUDDisplayMode: String, CaseIterable, Identifiable {
        case off
        case compact
        case menuBar
        case transcript

        var id: Self { self }

        var title: String {
            switch self {
            case .off:
                return "Off"
            case .compact:
                return "Compact"
            case .menuBar:
                return "Menu Bar"
            case .transcript:
                return "Transcript"
            }
        }
    }

    enum HUDMessageKind {
        case informational
        case insertion
        case important
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
    private(set) var savedAudioRecordings: [SavedAudioRecording] = []
    private(set) var isFileRecording = false
    private(set) var fileRecordingElapsedSeconds: TimeInterval = 0
    private(set) var cursorTextFieldFinalTranscript = ""
    var launchAtLoginEnabled = false {
        didSet {
            guard !previewMode, !isSyncingLaunchAtLogin, launchAtLoginEnabled != oldValue else { return }
            isSyncingLaunchAtLogin = true
            defer { isSyncingLaunchAtLogin = false }

            do {
                try loginItemController.setEnabled(launchAtLoginEnabled)
                if loginItemController.state == .requiresApproval {
                    showMessage("Approve GLSTT in Login Items to finish enabling launch at login.", isError: false, kind: .important)
                }
            } catch {
                launchAtLoginEnabled = oldValue
                showMessage("Unable to change launch-at-login right now.", isError: true, kind: .important, autoHide: false)
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
    var showMenuBarInformationalMessages = false {
        didSet {
            guard !previewMode else { return }
            defaults.set(showMenuBarInformationalMessages, forKey: Self.showMenuBarInformationalMessagesKey)
        }
    }
    var showMenuBarInsertionMessages = true {
        didSet {
            guard !previewMode else { return }
            defaults.set(showMenuBarInsertionMessages, forKey: Self.showMenuBarInsertionMessagesKey)
        }
    }
    var showMenuBarImportantMessages = true {
        didSet {
            guard !previewMode else { return }
            defaults.set(showMenuBarImportantMessages, forKey: Self.showMenuBarImportantMessagesKey)
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
    var cursorTextFieldEnabled = false {
        didSet {
            guard !previewMode else { return }
            defaults.set(cursorTextFieldEnabled, forKey: Self.cursorTextFieldKey)
            syncCursorTextField()
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
    private let fileManager = FileManager.default
    @ObservationIgnored
    private let vocabularyStore: ImportedVocabularyStore
    @ObservationIgnored
    private let transcriptStore: TranscriptHistoryStore
    @ObservationIgnored
    private var hudPanelController: HUDPanelController?
    @ObservationIgnored
    private var cursorTextFieldController: CursorTextFieldPanelController?
    @ObservationIgnored
    private var onboardingWindowController: OnboardingWindowController?
    private var homeWindowController: HomeWindowController?
    @ObservationIgnored
    private var hudDismissTask: Task<Void, Never>?
    @ObservationIgnored
    private var insertionTarget: AccessibilityInsertionTarget?
    @ObservationIgnored
    private var liveInsertionSession: LiveInsertionSession?
    @ObservationIgnored
    private var audioFileTranscriptionTask: Task<Void, Never>?
    @ObservationIgnored
    private var audioRecorder: AVAudioRecorder?
    @ObservationIgnored
    private var fileRecordingStartedAt: Date?
    @ObservationIgnored
    private var fileRecordingTimerTask: Task<Void, Never>?
    @ObservationIgnored
    private var applicationActiveObserver: NSObjectProtocol?
    @ObservationIgnored
    private var workspaceWakeObserver: NSObjectProtocol?
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
        self.transcriptStore = TranscriptHistoryStore(filename: Self.transcriptDatabaseName)
        self.hudPanelController = nil
        self.onboardingWindowController = nil
        self.homeWindowController = nil
        let loginItemState = loginItemController.state
        self.launchAtLoginEnabled = previewMode
            ? false
            : (loginItemState == .enabled || loginItemState == .requiresApproval)
        self.hudDisplayMode = previewMode
            ? .compact
            : HUDDisplayMode(rawValue: defaults.string(forKey: Self.hudDisplayModeKey) ?? "") ?? .compact
        self.showMenuBarInformationalMessages = previewMode
            ? true
            : defaults.object(forKey: Self.showMenuBarInformationalMessagesKey) as? Bool ?? false
        self.showMenuBarInsertionMessages = previewMode
            ? true
            : defaults.object(forKey: Self.showMenuBarInsertionMessagesKey) as? Bool ?? true
        self.showMenuBarImportantMessages = previewMode
            ? true
            : defaults.object(forKey: Self.showMenuBarImportantMessagesKey) as? Bool ?? true
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
        self.transcriptHistory = previewMode ? [] : transcriptStore.loadEntries()
        self.lastTranscript = transcriptHistory.first?.text ?? ""
        self.savedAudioRecordings = previewMode ? [] : loadSavedAudioRecordings()
        self.copyFailedInsertionsToClipboard = previewMode ? true : defaults.object(forKey: Self.copyFailedInsertionsKey) as? Bool ?? true
        self.showTranscriptWindowOnFailure = previewMode ? false : defaults.object(forKey: Self.showTranscriptWindowOnFailureKey) as? Bool ?? false
        self.cursorTextFieldEnabled = previewMode ? false : defaults.object(forKey: Self.cursorTextFieldKey) as? Bool ?? false

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
            self.syncCursorTextField()
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
            cursorTextFieldController = CursorTextFieldPanelController(model: self)
            syncHotkeyPreferences(preferred: .toggle)
            hotkeyMonitor.start()
            installHotkeyRecoveryObservers()
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
        if let applicationActiveObserver {
            NotificationCenter.default.removeObserver(applicationActiveObserver)
        }
        if let workspaceWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeObserver)
        }
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

    var usesMenuBarLevelMeter: Bool {
        hudDisplayMode == .menuBar
    }

    var isMenuBarLevelMeterActive: Bool {
        switch hudMode {
        case .recording, .finalizing:
            return true
        case .hidden, .message:
            return false
        }
    }

    var isMenuBarStatusPanelVisible: Bool {
        guard hudDisplayMode == .menuBar else { return false }

        switch hudMode {
        case .recording, .finalizing, .message:
            return true
        case .hidden:
            return false
        }
    }

    var isFinalizingStatus: Bool {
        if case .finalizing = hudMode { return true }
        return false
    }

    var menuBarLevelMeterLevel: Double {
        guard isMenuBarLevelMeterActive else { return 0 }

        switch hudMode {
        case .recording:
            return min(1, max(0.12, audioLevel))
        case .finalizing:
            return 0.65
        case .hidden, .message:
            return 0
        }
    }

    var statusSummary: String {
        switch hudMode {
        case .hidden:
            if isFileRecording {
                return "Recording"
            }
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

    var hudDisplayModeSummary: String {
        switch hudDisplayMode {
        case .off:
            return "No floating status indicator."
        case .compact:
            return "Shows a small floating waveform only while dictation is active."
        case .menuBar:
            return "Shows the active waveform in the menu bar instead of a floating indicator."
        case .transcript:
            return "Shows a floating live transcript while dictation is active."
        }
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

    var isBusyWithAudioWork: Bool {
        speechController.isRecording || isFileRecording || isAudioFileTranscriptionActive
    }

    var canStopCurrentSession: Bool {
        speechController.isRecording
            || isFileRecording
            || isAudioFileTranscriptionActive
            || pendingAudioFileLanguageSelection != nil
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
        case .menuBar:
            return menuBarStatusPanelSize
        case .compact:
            switch hudMode {
            case .hidden:
                return CGSize(width: 68, height: 68)
            case .message:
                return CGSize(width: 260, height: 86)
            case .recording, .finalizing:
                return CGSize(width: 68, height: 68)
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
        case .menuBar:
            return menuBarStatusPanelSize
        case .compact:
            return CGSize(width: 68, height: 68)
        case .transcript:
            return CGSize(width: 620, height: 220)
        }
    }

    var shouldPresentOnboarding: Bool {
        !defaults.bool(forKey: Self.onboardingDismissedKey)
    }

    private var menuBarStatusPanelSize: CGSize {
        guard isMenuBarStatusPanelVisible else { return .zero }

        if case .message(let message, _) = hudMode {
            let width = min(260, max(150, 54 + (CGFloat(message.count) * 6.2)))
            return CGSize(width: width, height: 38)
        }

        return CGSize(width: 56, height: 34)
    }

    var showsTranscriptHUD: Bool {
        hudDisplayMode == .transcript
    }

    var isCursorTextFieldVisible: Bool {
        guard cursorTextFieldEnabled else { return false }
        return speechController.isRecording || isFinalizingStatus || !cursorTextFieldFinalTranscript.isEmpty
    }

    var cursorTextFieldTitle: String {
        if speechController.isRecording {
            return "Listening"
        }
        if isFinalizingStatus {
            return "Finalizing"
        }
        return "Transcript"
    }

    var cursorTextFieldText: String {
        let liveText = (finalizedTranscript + volatileTranscript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if speechController.isRecording || isFinalizingStatus {
            return liveText.isEmpty ? "Speak now..." : liveText
        }
        return cursorTextFieldFinalTranscript
    }

    var cursorTextFieldShowsCopy: Bool {
        !cursorTextFieldFinalTranscript.isEmpty
            && !speechController.isRecording
            && !isFinalizingStatus
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

    func refreshMenuBarState() {
        refreshPermissions()
        recoverHotkeyMonitorIfIdle()
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
        showMessage("Accessibility permission is needed for the global hotkey and cross-app insertion.", isError: !permissions.accessibilityTrusted, kind: .important, autoHide: false)
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
        showMessage("Speech and microphone permissions were refreshed.", isError: false, kind: .informational)
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
        showMessage("Copied transcript.", isError: false, kind: .informational)
    }

    func copyCursorTextFieldTranscript() {
        let text = cursorTextFieldFinalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        copyTranscript(text)
        cursorTextFieldFinalTranscript = ""
        syncCursorTextField()
    }

    func turnOffCursorTextField() {
        cursorTextFieldEnabled = false
        cursorTextFieldFinalTranscript = ""
        syncCursorTextField()
    }

    func showTranscriptWindow() {
        guard !lastTranscript.isEmpty else { return }
        showHomeWindow()
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

    func toggleFileRecording() {
        Task {
            if isFileRecording {
                await stopFileRecording()
            } else {
                await startFileRecording()
            }
        }
    }

    func stopCurrentSession() {
        Task { @MainActor in
            await stopCurrentSessionNow()
        }
    }

    func transcribeSavedRecording(_ recording: SavedAudioRecording) {
        guard let url = urlForSavedRecording(recording) else {
            showMessage("Recording file is missing.", isError: true, kind: .important)
            savedAudioRecordings.removeAll { $0.id == recording.id }
            persistSavedAudioRecordings()
            return
        }

        enqueueAudioFiles([url])
    }

    func deleteSavedRecording(_ recording: SavedAudioRecording) {
        guard !isFileRecording else {
            showMessage("Stop recording before deleting saved files.", isError: true, kind: .important)
            return
        }

        if let url = urlForSavedRecording(recording) {
            try? fileManager.removeItem(at: url)
        }
        savedAudioRecordings.removeAll { $0.id == recording.id }
        persistSavedAudioRecordings()
    }

    func revealSavedRecording(_ recording: SavedAudioRecording) {
        guard let url = urlForSavedRecording(recording) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openSavedRecordingsFolder() {
        if let directory = try? recordingsDirectory() {
            NSWorkspace.shared.open(directory)
        }
    }

    func urlForSavedRecording(_ recording: SavedAudioRecording) -> URL? {
        let url = recordingURL(fileName: recording.fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
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
            showMessage("Choose a supported Apple speech language for that audio file.", isError: true, kind: .important, autoHide: false)
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
            showMessage("Stop dictation before queueing audio files.", isError: true, kind: .important)
            return
        }

        guard !files.isEmpty else { return }

        let languageOptions = await AudioTranscriptionLanguageOption.supportedOptions()
        guard let defaultLanguageID = AudioTranscriptionLanguageOption.defaultLanguageID(in: languageOptions) else {
            showMessage("Apple did not report any supported file transcription languages on this device.", isError: true, kind: .important, autoHide: false)
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

        guard !isFileRecording else {
            hotkeyMonitor.resetState()
            return
        }
        guard !isAudioFileTranscriptionActive else {
            hotkeyMonitor.resetState()
            return
        }

        guard permissions.accessibilityTrusted else {
            hotkeyMonitor.resetState()
            requestAccessibilityAccess()
            return
        }

        finalizedTranscript = ""
        volatileTranscript = ""
        cursorTextFieldFinalTranscript = ""
        audioLevel = 0
        insertionTarget = inserter.captureInsertionTarget()
        liveInsertionSession = liveInsertionEnabled ? inserter.beginLiveInsertionSession() : nil
        let contextualStrings = contextualVocabularyEnabled
            ? VocabularyImporter.mergedContextualStrings(
                importedLists: importedVocabulary.lists,
                runtimeWords: inserter.contextualVocabularyCandidates(limit: 40)
            )
            : []
        if shouldPresentMessage(kind: .informational) {
            hudMode = .message("Requesting permissions and preparing Apple's on-device speech models…", isError: false)
            syncHUDVisibility()
        } else {
            hudMode = .hidden
            syncHUDVisibility()
        }

        do {
            try await speechController.beginSession(contextualStrings: contextualStrings)
            refreshPermissions()
            hudMode = .recording
            syncHUDVisibility()
            syncCursorTextField()
        } catch {
            refreshPermissions()
            liveInsertionSession = nil
            insertionTarget = nil
            cursorTextFieldFinalTranscript = ""
            syncCursorTextField()
            hotkeyMonitor.resetState()
            showMessage(error.localizedDescription, isError: true, kind: .important)
        }
    }

    private func startFileRecording() async {
        hudDismissTask?.cancel()
        refreshPermissions()

        guard !speechController.isRecording else {
            showMessage("Stop dictation first.", isError: true, kind: .important)
            return
        }

        guard !isAudioFileTranscriptionActive else {
            showMessage("Finish the current transcription first.", isError: true, kind: .important)
            return
        }

        guard await speechController.requestMicrophoneAccess() else {
            refreshPermissions()
            showMessage("Microphone access is needed.", isError: true, kind: .important)
            return
        }

        do {
            let url = try nextRecordingURL()
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw CocoaError(.fileWriteUnknown)
            }

            audioRecorder = recorder
            fileRecordingStartedAt = Date()
            fileRecordingElapsedSeconds = 0
            audioLevel = 0
            isFileRecording = true
            startFileRecordingTimer()
            refreshPermissions()
        } catch {
            audioRecorder = nil
            fileRecordingStartedAt = nil
            fileRecordingElapsedSeconds = 0
            audioLevel = 0
            isFileRecording = false
            showMessage(error.localizedDescription, isError: true, kind: .important)
        }
    }

    private func stopFileRecording() async {
        guard isFileRecording, let recorder = audioRecorder else { return }

        let url = recorder.url
        let startedAt = fileRecordingStartedAt ?? Date()
        recorder.stop()
        stopFileRecordingTimer()

        audioRecorder = nil
        fileRecordingStartedAt = nil
        isFileRecording = false
        audioLevel = 0
        fileRecordingElapsedSeconds = 0

        let recording = SavedAudioRecording(
            id: UUID(),
            fileName: url.lastPathComponent,
            createdAt: startedAt,
            durationSeconds: max(Date().timeIntervalSince(startedAt), 0),
            fileSize: savedRecordingFileSize(for: url)
        )
        savedAudioRecordings.insert(recording, at: 0)
        persistSavedAudioRecordings()
        showHomeWindow()
    }

    private func startFileRecordingTimer() {
        fileRecordingTimerTask?.cancel()
        fileRecordingTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run {
                    guard let self, self.isFileRecording, let startedAt = self.fileRecordingStartedAt else { return }
                    self.fileRecordingElapsedSeconds = Date().timeIntervalSince(startedAt)
                    self.audioRecorder?.updateMeters()
                    if let recorder = self.audioRecorder {
                        self.audioLevel = Self.normalizedAudioLevel(fromAveragePower: recorder.averagePower(forChannel: 0))
                    }
                }
            }
        }
    }

    private func stopFileRecordingTimer() {
        fileRecordingTimerTask?.cancel()
        fileRecordingTimerTask = nil
    }

    private static func normalizedAudioLevel(fromAveragePower power: Float) -> Double {
        guard power.isFinite else { return 0 }
        let normalized = pow(10, Double(power) / 35.0)
        return min(max(normalized * 1.8, 0), 1)
    }

    private func nextRecordingURL() throws -> URL {
        let directory = try recordingsDirectory()
        let stamp = Self.recordingFileStamp(from: Date())
        var candidate = directory.appendingPathComponent("GLSTT Recording \(stamp).m4a")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("GLSTT Recording \(stamp) \(suffix).m4a")
            suffix += 1
        }
        return candidate
    }

    private static func recordingFileStamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }

    private func recordingsDirectory() throws -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        let directory = documentsDirectory.appendingPathComponent("GLSTT Recordings", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func recordingURL(fileName: String) -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return documentsDirectory
            .appendingPathComponent("GLSTT Recordings", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private func savedRecordingFileSize(for url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }

    private func loadSavedAudioRecordings() -> [SavedAudioRecording] {
        guard let data = defaults.data(forKey: Self.savedAudioRecordingsKey),
              let decoded = try? JSONDecoder().decode([SavedAudioRecording].self, from: data)
        else {
            return []
        }

        return decoded.filter { urlForSavedRecording($0) != nil }
    }

    private func persistSavedAudioRecordings() {
        guard let data = try? JSONEncoder().encode(savedAudioRecordings) else { return }
        defaults.set(data, forKey: Self.savedAudioRecordingsKey)
    }

    private func stopCurrentSessionNow() async {
        let hadSession = canStopCurrentSession

        hudDismissTask?.cancel()
        pendingAudioFileLanguageSelection = nil
        liveInsertionSession = nil
        insertionTarget = nil
        finalizedTranscript = ""
        volatileTranscript = ""
        audioLevel = 0

        if speechController.isRecording {
            await speechController.cancelCurrentSession()
        }

        if isFileRecording {
            await stopFileRecording()
        } else {
            audioRecorder?.stop()
            stopFileRecordingTimer()
            audioRecorder = nil
            fileRecordingStartedAt = nil
            fileRecordingElapsedSeconds = 0
            isFileRecording = false
        }

        if audioFileTranscriptionTask != nil || audioFileTranscriptionJobs.contains(where: { !$0.isComplete }) {
            audioFileTranscriptionTask?.cancel()
            audioFileTranscriptionTask = nil
            for index in audioFileTranscriptionJobs.indices where !audioFileTranscriptionJobs[index].isComplete {
                audioFileTranscriptionJobs[index].status = .failed("Stopped by user.")
            }
        }

        hotkeyMonitor.resetState()
        refreshPermissions()

        if hadSession {
            showMessage("Stopped current session.", isError: false, kind: .informational)
        } else {
            showMessage("No active session to stop.", isError: false, kind: .informational)
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
        guard speechController.isRecording else {
            hotkeyMonitor.resetState()
            return
        }

        defer {
            hotkeyMonitor.resetState()
        }

        hudMode = .finalizing
        syncHUDVisibility()

        do {
            let text = try await speechController.finishSession()
            finalizedTranscript = text
            volatileTranscript = ""
            lastTranscript = text
            audioLevel = 0
            cursorTextFieldFinalTranscript = text.trimmingCharacters(in: .whitespacesAndNewlines)
            syncCursorTextField()

            guard !text.isEmpty else {
                liveInsertionSession = nil
                insertionTarget = nil
                cursorTextFieldFinalTranscript = ""
                syncCursorTextField()
                showMessage("No speech captured.", isError: false, kind: .informational)
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
                showMessage("Captured transcript without automatic insertion.", isError: false, kind: .insertion)
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
            cursorTextFieldFinalTranscript = ""
            syncCursorTextField()
            audioLevel = 0
            showMessage(error.localizedDescription, isError: true, kind: .important)
        }
    }

    private func completeSuccessfulInsertion() {
        hudDismissTask?.cancel()
        hudMode = .hidden
        syncHUDVisibility()
        syncCursorTextField()
    }

    func dismissHUD() {
        hudDismissTask?.cancel()
        hudMode = .hidden
        syncHUDVisibility()
        syncCursorTextField()
    }

    func openTranscriptWindowFromHUD() {
        showHomeWindow()
        dismissHUD()
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

        if showTranscriptWindowOnFailure, !copyFailedInsertionsToClipboard {
            showHomeWindow()
        }

        showMessage(shortInsertionMessage(for: message), isError: true, kind: .insertion, autoHideDelay: .milliseconds(1600))
    }

    private func shortInsertionMessage(for message: String) -> String {
        if copyFailedInsertionsToClipboard {
            return "Clipboard ready"
        }

        let lowercased = message.lowercased()
        if lowercased.contains("could not confirm") {
            return "Check field"
        }
        if lowercased.contains("accessibility") {
            return "Needs access"
        }
        if lowercased.contains("no editable target") || lowercased.contains("no target") {
            return "No field"
        }
        if lowercased.contains("no speech") {
            return "No speech"
        }
        return "Not inserted"
    }

    private func showMessage(
        _ message: String,
        isError: Bool,
        kind: HUDMessageKind? = nil,
        autoHide: Bool = true,
        autoHideDelay: Duration = .seconds(2.8)
    ) {
        let resolvedKind = kind ?? (isError ? .important : .informational)
        guard shouldPresentMessage(kind: resolvedKind) else {
            hudMode = .hidden
            syncHUDVisibility()
            return
        }

        hudMode = .message(message, isError: isError)
        syncHUDVisibility()
        syncCursorTextField()

        guard autoHide else { return }

        hudDismissTask?.cancel()
        hudDismissTask = Task { [weak self] in
            try? await Task.sleep(for: autoHideDelay)
            guard !Task.isCancelled else { return }
            self?.hudMode = .hidden
            self?.syncHUDVisibility()
            self?.syncCursorTextField()
        }
    }

    private func shouldPresentMessage(kind: HUDMessageKind) -> Bool {
        guard hudDisplayMode == .menuBar else { return true }

        switch kind {
        case .informational:
            return showMenuBarInformationalMessages
        case .insertion:
            return showMenuBarInsertionMessages
        case .important:
            return showMenuBarImportantMessages
        }
    }

    private func syncHUDVisibility() {
        guard !previewMode else { return }
        switch hudDisplayMode {
        case .off:
            hudPanelController?.hide()
        case .menuBar:
            if isMenuBarStatusPanelVisible {
                hudPanelController?.show()
            } else {
                hudPanelController?.hide()
            }
        case .compact:
            if case .hidden = hudMode {
                hudPanelController?.hide()
            } else {
                hudPanelController?.show()
            }
        case .transcript:
            hudPanelController?.show()
        }
    }

    private func syncCursorTextField() {
        guard !previewMode else { return }
        if isCursorTextFieldVisible {
            cursorTextFieldController?.show(followMouse: speechController.isRecording || isFinalizingStatus)
        } else {
            cursorTextFieldController?.hide()
        }
    }

    private func markOnboardingDismissed() {
        defaults.set(true, forKey: Self.onboardingDismissedKey)
    }

    private func installHotkeyRecoveryObservers() {
        applicationActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recoverHotkeyMonitorIfIdle()
            }
        }

        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recoverHotkeyMonitorIfIdle()
            }
        }
    }

    private func recoverHotkeyMonitorIfIdle() {
        guard !previewMode else { return }
        guard !speechController.isRecording, !isFileRecording else { return }
        hotkeyMonitor.restart()
    }

    private func maybePromptForLaunchAtLogin() {
        guard !previewMode else { return }
        guard !defaults.bool(forKey: Self.launchAtLoginPromptedKey) else { return }
        guard permissions.accessibilityTrusted else { return }
        guard permissions.speech == .granted, permissions.microphone == .granted else { return }
        guard !launchAtLoginEnabled else { return }

        defaults.set(true, forKey: Self.launchAtLoginPromptedKey)
        showMessage("Setup looks good. You can turn on launch at login in Settings whenever you want.", isError: false, kind: .informational)
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

        let entry = TranscriptHistoryEntry(text: trimmed)
        transcriptHistory.removeAll { $0.text == trimmed }
        transcriptHistory.insert(entry, at: 0)

        if !previewMode {
            transcriptStore.save(entry)
        }
    }

    func importVocabularyList(from url: URL) {
        do {
            importedVocabulary = try vocabularyStore.importingList(from: url, into: importedVocabulary)
            vocabularyStore.save(importedVocabulary)
            if let list = importedVocabulary.lists.first {
                showMessage("Imported \(list.words.count) words from \(list.name).", isError: false, kind: .informational)
            }
        } catch {
            showMessage(error.localizedDescription, isError: true, kind: .important, autoHide: false)
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
