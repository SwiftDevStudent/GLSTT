#if os(macOS) && DEBUG && canImport(Testing)
import Testing

@Suite("GLSTT Core Logic")
struct GLSTTCoreTests {
    @Test("Hotkey state machine starts recording after a hold debounce")
    func hotkeyHoldStartFlow() {
        var machine = HotkeyStateMachine()

        #expect(machine.handle(.keyPressed(.rightOption)) == [.scheduleHoldDebounce])
        #expect(machine.handle(.holdDebounceElapsed) == [.beginRecording])
        #expect(machine.handle(.keyReleased(.rightOption)) == [.endRecording])
    }

    @Test("Hotkey state machine starts recording on a right-Option double tap")
    func hotkeyDoubleTapStartFlow() {
        var machine = HotkeyStateMachine()

        #expect(machine.handle(.keyPressed(.rightOption)) == [.scheduleHoldDebounce])
        #expect(machine.handle(.keyReleased(.rightOption)) == [.cancelHoldDebounce, .scheduleDoubleTapWindow])
        #expect(machine.handle(.keyPressed(.rightOption)) == [.cancelDoubleTapWindow, .beginRecording])
        #expect(machine.handle(.keyReleased(.rightOption)).isEmpty)
    }

    @Test("Hotkey state machine stops recording on a second right-Option double tap")
    func hotkeyDoubleTapStopFlow() {
        var machine = HotkeyStateMachine()

        _ = machine.handle(.keyPressed(.rightOption))
        _ = machine.handle(.keyReleased(.rightOption))
        _ = machine.handle(.keyPressed(.rightOption))
        _ = machine.handle(.keyReleased(.rightOption))

        #expect(machine.handle(.keyPressed(.rightOption)).isEmpty)
        #expect(machine.handle(.keyReleased(.rightOption)) == [.scheduleDoubleTapWindow])
        #expect(machine.handle(.keyPressed(.rightOption)) == [.cancelDoubleTapWindow, .endRecording])
    }

    @Test("Hotkey state machine suppresses Option combinations")
    func hotkeySuppressionFlow() {
        var machine = HotkeyStateMachine()

        #expect(machine.handle(.keyPressed(.rightOption)) == [.scheduleHoldDebounce])
        #expect(machine.handle(.otherKeyPressed) == [.cancelHoldDebounce])
        #expect(machine.handle(.keyReleased(.rightOption)).isEmpty)
    }

    @Test("Hotkey configuration keeps single-press toggle keys distinct from hold keys")
    func hotkeyConfigurationNormalization() {
        let configuration = HotkeyConfiguration(
            holdKey: .rightOption,
            toggleKey: .rightOption,
            toggleRequiresDoublePress: false
        ).normalized

        #expect(configuration.holdKey == .rightOption)
        #expect(configuration.toggleKey != .rightOption)
    }

    @Test("Hotkey state machine reset clears a latched recording state")
    func hotkeyResetClearsLatchedRecordingState() {
        var machine = HotkeyStateMachine()

        _ = machine.handle(.keyPressed(.rightOption))
        _ = machine.handle(.keyReleased(.rightOption))
        #expect(machine.handle(.keyPressed(.rightOption)) == [.cancelDoubleTapWindow, .beginRecording])

        machine.reset()

        #expect(machine.handle(.keyPressed(.rightOption)) == [.scheduleHoldDebounce])
    }

    @Test("Transcript assembly keeps volatile text separate until final")
    func transcriptAssemblyFlow() {
        var assembly = TranscriptAssembly()

        assembly.apply(.init(text: "hello", isFinal: false))
        #expect(assembly.finalizedText.isEmpty)
        #expect(assembly.volatileText == "hello")

        assembly.apply(.init(text: "hello world", isFinal: true))
        #expect(assembly.finalizedText == "hello world")
        #expect(assembly.volatileText.isEmpty)
    }

    @Test("Insertion planner prefers AX text replacement before paste fallback")
    func insertionPlannerPrefersAX() {
        let selectedTextStrategy = AccessibilityInsertionPlanner.strategy(
            for: .init(hasFocusedElement: true, selectedTextSettable: true, valueSettable: true, hasSelectedTextRange: true)
        )
        #expect(selectedTextStrategy == .selectedText)

        let valueStrategy = AccessibilityInsertionPlanner.strategy(
            for: .init(hasFocusedElement: true, selectedTextSettable: false, valueSettable: true, hasSelectedTextRange: true)
        )
        #expect(valueStrategy == .valueAndRange)

        let pasteStrategy = AccessibilityInsertionPlanner.strategy(
            for: .init(hasFocusedElement: true, selectedTextSettable: false, valueSettable: false, hasSelectedTextRange: false)
        )
        #expect(pasteStrategy == .pasteFallback)

        let missingTarget = AccessibilityInsertionPlanner.strategy(
            for: .init(hasFocusedElement: false, selectedTextSettable: false, valueSettable: false, hasSelectedTextRange: false)
        )
        #expect(missingTarget == .noTarget)
    }
}
#endif
