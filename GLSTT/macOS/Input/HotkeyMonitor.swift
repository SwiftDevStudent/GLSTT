#if os(macOS)
import AppKit

struct TriggerKey: Hashable, Codable, Identifiable {
    let keyCode: UInt16

    var id: UInt16 { keyCode }

    static let leftCommand = TriggerKey(keyCode: 55)
    static let leftShift = TriggerKey(keyCode: 56)
    static let leftOption = TriggerKey(keyCode: 58)
    static let leftControl = TriggerKey(keyCode: 59)
    static let rightCommand = TriggerKey(keyCode: 54)
    static let rightShift = TriggerKey(keyCode: 60)
    static let rightOption = TriggerKey(keyCode: 61)
    static let rightControl = TriggerKey(keyCode: 62)

    static let suggestedKeys: [TriggerKey] = [
        .rightOption, .rightCommand, .rightControl, .rightShift,
        .leftOption, .leftCommand, .leftControl, .leftShift,
        TriggerKey(keyCode: 122), TriggerKey(keyCode: 120), TriggerKey(keyCode: 99),
        TriggerKey(keyCode: 118), TriggerKey(keyCode: 96), TriggerKey(keyCode: 97),
        TriggerKey(keyCode: 98), TriggerKey(keyCode: 100), TriggerKey(keyCode: 101),
        TriggerKey(keyCode: 109), TriggerKey(keyCode: 103), TriggerKey(keyCode: 111)
    ]

    var title: String {
        TriggerKey.displayName(for: keyCode)
    }

    var shortTitle: String {
        switch keyCode {
        case 54:
            return "R Cmd"
        case 55:
            return "L Cmd"
        case 56:
            return "L Shift"
        case 58:
            return "L Option"
        case 59:
            return "L Ctrl"
        case 60:
            return "R Shift"
        case 61:
            return "R Option"
        case 62:
            return "R Ctrl"
        default:
            return title
        }
    }

    var isModifier: Bool {
        Self.modifierKeyCodes.contains(keyCode)
    }

    var isFunctionKey: Bool {
        Self.functionKeyCodes.contains(keyCode)
    }

    var isSupportedGlobalShortcut: Bool {
        isModifier || isFunctionKey
    }

    static func from(keyCode: UInt16) -> Self {
        TriggerKey(keyCode: keyCode)
    }

    static func firstAvailable(excluding excludedKeys: some Sequence<TriggerKey>) -> TriggerKey {
        let excluded = Set(excludedKeys)
        return suggestedKeys.first { !excluded.contains($0) } ?? .rightCommand
    }

    static func displayName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 54:
            return "Right Command"
        case 55:
            return "Left Command"
        case 56:
            return "Left Shift"
        case 58:
            return "Left Option"
        case 59:
            return "Left Control"
        case 60:
            return "Right Shift"
        case 61:
            return "Right Option"
        case 62:
            return "Right Control"
        case 122:
            return "F1"
        case 120:
            return "F2"
        case 99:
            return "F3"
        case 118:
            return "F4"
        case 96:
            return "F5"
        case 97:
            return "F6"
        case 98:
            return "F7"
        case 100:
            return "F8"
        case 101:
            return "F9"
        case 109:
            return "F10"
        case 103:
            return "F11"
        case 111:
            return "F12"
        case 105:
            return "F13"
        case 107:
            return "F14"
        case 113:
            return "F15"
        default:
            return "Key \(keyCode)"
        }
    }

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62]
    private static let functionKeyCodes: Set<UInt16> = [96, 97, 98, 99, 100, 101, 103, 105, 107, 109, 111, 113, 118, 120, 122]
}

struct HotkeyConfiguration: Equatable, Codable {
    var holdKey: TriggerKey
    var toggleKey: TriggerKey
    var toggleRequiresDoublePress: Bool

    static let `default` = Self(
        holdKey: .rightOption,
        toggleKey: .rightOption,
        toggleRequiresDoublePress: true
    )

    var normalized: Self {
        guard !toggleRequiresDoublePress, holdKey == toggleKey else {
            return self
        }

        var copy = self
        copy.toggleKey = TriggerKey.firstAvailable(excluding: [holdKey])
        return copy
    }
}

enum HotkeyStateMachineEvent: Equatable {
    case keyPressed(TriggerKey)
    case keyReleased(TriggerKey)
    case otherKeyPressed
    case holdDebounceElapsed
    case doubleTapWindowElapsed
}

enum HotkeyStateMachineCommand: Equatable {
    case scheduleHoldDebounce
    case cancelHoldDebounce
    case scheduleDoubleTapWindow
    case cancelDoubleTapWindow
    case beginRecording
    case endRecording
}

struct HotkeyStateMachine {
    private(set) var configuration: HotkeyConfiguration

    private var isHoldPressed = false
    private var isHoldSuppressed = false
    private var isRecordingByHold = false
    private var isRecordingByToggle = false
    private var awaitingSecondTapToStart = false
    private var awaitingSecondTapToStop = false
    private var ignoreNextToggleRelease = false

    init(configuration: HotkeyConfiguration = .default) {
        self.configuration = configuration.normalized
    }

    mutating func updateConfiguration(_ configuration: HotkeyConfiguration) {
        self = Self(configuration: configuration)
    }

    mutating func reset() {
        self = Self(configuration: configuration)
    }

    mutating func handle(_ event: HotkeyStateMachineEvent) -> [HotkeyStateMachineCommand] {
        switch event {
        case .keyPressed(let key):
            return handleKeyPressed(key)

        case .keyReleased(let key):
            return handleKeyReleased(key)

        case .otherKeyPressed:
            guard isHoldPressed, !isRecordingByHold else {
                return []
            }

            isHoldSuppressed = true
            return [.cancelHoldDebounce]

        case .holdDebounceElapsed:
            guard isHoldPressed, !isHoldSuppressed, !isRecordingByToggle else {
                return []
            }

            isRecordingByHold = true
            return [.beginRecording]

        case .doubleTapWindowElapsed:
            awaitingSecondTapToStart = false
            awaitingSecondTapToStop = false
            return []
        }
    }

    private mutating func handleKeyPressed(_ key: TriggerKey) -> [HotkeyStateMachineCommand] {
        var commands: [HotkeyStateMachineCommand] = []

        if key == configuration.toggleKey {
            let toggleCommands = handleToggleKeyPressed()
            commands.append(contentsOf: toggleCommands)

            if key == configuration.holdKey, !toggleCommands.isEmpty {
                return commands
            }
        }

        if key == configuration.holdKey {
            commands.append(contentsOf: handleHoldKeyPressed())
        }

        return commands
    }

    private mutating func handleKeyReleased(_ key: TriggerKey) -> [HotkeyStateMachineCommand] {
        if key == configuration.holdKey, key == configuration.toggleKey {
            if isRecordingByHold || isHoldSuppressed {
                return handleHoldKeyReleased()
            }

            var commands = handleHoldKeyReleased()
            commands.append(contentsOf: handleToggleKeyReleased())
            return commands
        }

        var commands: [HotkeyStateMachineCommand] = []

        if key == configuration.holdKey {
            commands.append(contentsOf: handleHoldKeyReleased())
        }

        if key == configuration.toggleKey {
            commands.append(contentsOf: handleToggleKeyReleased())
        }

        return commands
    }

    private mutating func handleHoldKeyPressed() -> [HotkeyStateMachineCommand] {
        guard !isRecordingByToggle else {
            return []
        }

        isHoldPressed = true
        isHoldSuppressed = false
        return [.scheduleHoldDebounce]
    }

    private mutating func handleHoldKeyReleased() -> [HotkeyStateMachineCommand] {
        defer {
            isHoldPressed = false
            isHoldSuppressed = false
        }

        if isRecordingByHold {
            isRecordingByHold = false
            return [.endRecording]
        }

        guard isHoldPressed else {
            return []
        }

        if isHoldSuppressed {
            return []
        }

        return [.cancelHoldDebounce]
    }

    private mutating func handleToggleKeyPressed() -> [HotkeyStateMachineCommand] {
        guard configuration.toggleRequiresDoublePress else {
            guard !isRecordingByHold else {
                return []
            }

            if isRecordingByToggle {
                isRecordingByToggle = false
                awaitingSecondTapToStop = false
                return [.endRecording]
            }

            isRecordingByToggle = true
            awaitingSecondTapToStart = false
            return [.beginRecording]
        }

        if awaitingSecondTapToStart, !isRecordingByToggle, !isRecordingByHold {
            awaitingSecondTapToStart = false
            ignoreNextToggleRelease = true
            isRecordingByToggle = true
            return [.cancelDoubleTapWindow, .beginRecording]
        }

        if awaitingSecondTapToStop, isRecordingByToggle {
            awaitingSecondTapToStop = false
            ignoreNextToggleRelease = true
            isRecordingByToggle = false
            return [.cancelDoubleTapWindow, .endRecording]
        }

        return []
    }

    private mutating func handleToggleKeyReleased() -> [HotkeyStateMachineCommand] {
        guard configuration.toggleRequiresDoublePress else {
            return []
        }

        if ignoreNextToggleRelease {
            ignoreNextToggleRelease = false
            return []
        }

        guard !isRecordingByHold else {
            return []
        }

        if isRecordingByToggle {
            awaitingSecondTapToStop = true
        } else {
            awaitingSecondTapToStart = true
        }

        return [.scheduleDoubleTapWindow]
    }
}

@MainActor
final class HotkeyMonitor {
    enum Action {
        case beginRecording
        case endRecording
    }

    var onAction: ((Action) -> Void)?

    private let holdDebounce: Duration = .milliseconds(180)
    private let doubleTapWindow: Duration = .milliseconds(320)

    private var machine = HotkeyStateMachine()
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var pressedKeys = Set<TriggerKey>()
    private var suppressedTriggerKeys = Set<TriggerKey>()
    private var holdDebounceTask: Task<Void, Never>?
    private var doubleTapTask: Task<Void, Never>?

    func start() {
        guard globalFlagsMonitor == nil else { return }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event)
            }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyDown(event)
            }
        }
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyUp(event)
            }
        }
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
            return event
        }
    }

    func stop() {
        removeEventMonitors()
        resetState()
    }

    func restart() {
        let configuration = machine.configuration
        stop()
        machine.updateConfiguration(configuration)
        start()
    }

    func resetState() {
        holdDebounceTask?.cancel()
        doubleTapTask?.cancel()
        holdDebounceTask = nil
        doubleTapTask = nil
        pressedKeys.removeAll()
        suppressedTriggerKeys.removeAll()
        machine.reset()
    }

    func updateConfiguration(_ configuration: HotkeyConfiguration) {
        resetState()
        machine.updateConfiguration(configuration.normalized)
    }

    private func removeEventMonitors() {
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
            self.globalKeyDownMonitor = nil
        }
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }
        if let globalKeyUpMonitor {
            NSEvent.removeMonitor(globalKeyUpMonitor)
            self.globalKeyUpMonitor = nil
        }
        if let localKeyUpMonitor {
            NSEvent.removeMonitor(localKeyUpMonitor)
            self.localKeyUpMonitor = nil
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let key = TriggerKey.from(keyCode: event.keyCode)
        guard key.isModifier else {
            return
        }

        if pressedKeys.contains(key) {
            handlePhysicalKeyReleased(key)
        } else {
            handlePhysicalKeyPressed(key)
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard !event.isARepeat else { return }

        let key = TriggerKey.from(keyCode: event.keyCode)
        handlePhysicalKeyPressed(key)
    }

    private func handleKeyUp(_ event: NSEvent) {
        let key = TriggerKey.from(keyCode: event.keyCode)
        handlePhysicalKeyReleased(key)
    }

    private func handlePhysicalKeyPressed(_ key: TriggerKey) {
        guard !pressedKeys.contains(key) else { return }

        let isConfiguredTrigger = key == machine.configuration.holdKey || key == machine.configuration.toggleKey
        let isPartOfExistingChord = !pressedKeys.isEmpty
        pressedKeys.insert(key)

        if isConfiguredTrigger {
            guard !isPartOfExistingChord else {
                suppressedTriggerKeys.insert(key)
                return
            }

            apply(machine.handle(.keyPressed(key)))
        } else {
            apply(machine.handle(.otherKeyPressed))
        }
    }

    private func handlePhysicalKeyReleased(_ key: TriggerKey) {
        guard pressedKeys.remove(key) != nil else { return }

        if suppressedTriggerKeys.remove(key) != nil {
            return
        }

        if key == machine.configuration.holdKey || key == machine.configuration.toggleKey {
            apply(machine.handle(.keyReleased(key)))
        }
    }

    private func apply(_ commands: [HotkeyStateMachineCommand]) {
        for command in commands {
            switch command {
            case .scheduleHoldDebounce:
                holdDebounceTask?.cancel()
                let holdDebounce = self.holdDebounce
                holdDebounceTask = Task { [weak self] in
                    try? await Task.sleep(for: holdDebounce)
                    guard !Task.isCancelled else { return }
                    self?.handleHoldDebounceElapsed()
                }

            case .cancelHoldDebounce:
                holdDebounceTask?.cancel()
                holdDebounceTask = nil

            case .scheduleDoubleTapWindow:
                doubleTapTask?.cancel()
                let doubleTapWindow = self.doubleTapWindow
                doubleTapTask = Task { [weak self] in
                    try? await Task.sleep(for: doubleTapWindow)
                    guard !Task.isCancelled else { return }
                    self?.handleDoubleTapWindowElapsed()
                }

            case .cancelDoubleTapWindow:
                doubleTapTask?.cancel()
                doubleTapTask = nil

            case .beginRecording:
                onAction?(.beginRecording)

            case .endRecording:
                onAction?(.endRecording)
            }
        }
    }

    private func handleHoldDebounceElapsed() {
        holdDebounceTask = nil
        apply(machine.handle(.holdDebounceElapsed))
    }

    private func handleDoubleTapWindowElapsed() {
        doubleTapTask = nil
        apply(machine.handle(.doubleTapWindowElapsed))
    }
}
#endif
