#if os(macOS)
import AppKit
import ApplicationServices

enum AccessibilityInsertionStrategy: Equatable {
    case selectedText
    case valueAndRange
    case pasteFallback
    case noTarget
}

enum AccessibilityInsertionVerification: Equatable {
    case confirmed
    case unverified
}

struct AccessibilityInsertionTarget: Equatable {
    let processIdentifier: pid_t
}

struct LiveInsertionSession {
    enum Strategy {
        case selectedText
        case valueAndRange
    }

    let element: AXUIElement
    let target: AccessibilityInsertionTarget?
    let strategy: Strategy
    let insertionLocation: Int
    let shouldInsertLeadingSpace: Bool
    var insertedLength: Int
}

struct AccessibilityTargetCapabilities: Equatable {
    var hasFocusedElement: Bool
    var selectedTextSettable: Bool
    var valueSettable: Bool
    var hasSelectedTextRange: Bool
}

struct AccessibilityInsertionPlanner {
    static func strategy(for capabilities: AccessibilityTargetCapabilities) -> AccessibilityInsertionStrategy {
        guard capabilities.hasFocusedElement else { return .noTarget }
        if capabilities.selectedTextSettable { return .selectedText }
        if capabilities.valueSettable && capabilities.hasSelectedTextRange { return .valueAndRange }
        return .pasteFallback
    }
}

enum AccessibilityInsertionResult: Equatable {
    case inserted(AccessibilityInsertionStrategy, AccessibilityInsertionVerification)
    case noTarget
    case accessibilityPermissionRequired
    case failed(String)
}

@MainActor
final class AccessibilityInserter {
    func captureInsertionTarget() -> AccessibilityInsertionTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        guard application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }

        return AccessibilityInsertionTarget(processIdentifier: application.processIdentifier)
    }

    func insert(text: String, preferredTarget: AccessibilityInsertionTarget?) async -> AccessibilityInsertionResult {
        guard AXIsProcessTrusted() else {
            return .accessibilityPermissionRequired
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed("No speech captured.")
        }

        if let preferredTarget,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != preferredTarget.processIdentifier {
            await reactivate(preferredTarget)
        }

        guard let element = focusedElement() else {
            if await pasteIntoFocusedApp(text: text) {
                return .inserted(.pasteFallback, await verifyInsertedText(text, using: nil))
            }

            return .noTarget
        }

        let capabilities = capabilities(for: element)
        let strategy = AccessibilityInsertionPlanner.strategy(for: capabilities)

        switch strategy {
        case .selectedText:
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if result == .success {
                return .inserted(.selectedText, await verifyInsertedText(text, using: element))
            }

        case .valueAndRange:
            if replaceSelection(in: element, with: text) {
                return .inserted(.valueAndRange, await verifyInsertedText(text, using: element))
            }

        case .pasteFallback, .noTarget:
            if await pasteIntoFocusedApp(text: text) {
                return .inserted(.pasteFallback, await verifyInsertedText(text, using: element))
            }
        }

        if await pasteIntoFocusedApp(text: text) {
            return .inserted(.pasteFallback, await verifyInsertedText(text, using: element))
        }

        if strategy == .noTarget {
            return .noTarget
        }

        return .failed("Unable to insert into the focused field.")
    }

    func verifyLiveInsertion(text: String, session: LiveInsertionSession) async -> Bool {
        await verifyInsertedText(text, using: session.element) == .confirmed
    }

    func beginLiveInsertionSession() -> LiveInsertionSession? {
        guard AXIsProcessTrusted(), let element = focusedElement() else {
            return nil
        }

        let capabilities = capabilities(for: element)
        guard let selectedRange = copySelectedCFRange(from: element) else {
            return nil
        }

        let target = captureInsertionTarget()

        if capabilities.selectedTextSettable {
            return LiveInsertionSession(
                element: element,
                target: target,
                strategy: .selectedText,
                insertionLocation: selectedRange.location,
                shouldInsertLeadingSpace: shouldInsertLeadingSpace(in: element, at: selectedRange.location),
                insertedLength: selectedRange.length
            )
        }

        if capabilities.valueSettable {
            return LiveInsertionSession(
                element: element,
                target: target,
                strategy: .valueAndRange,
                insertionLocation: selectedRange.location,
                shouldInsertLeadingSpace: shouldInsertLeadingSpace(in: element, at: selectedRange.location),
                insertedLength: selectedRange.length
            )
        }

        return nil
    }

    func updateLiveInsertionSession(
        _ session: inout LiveInsertionSession,
        text: String,
        finalizeSelection: Bool
    ) async -> Bool {
        if let target = session.target,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            await reactivate(target)
        }

        let succeeded: Bool
        let adjustedText = adjustedInsertionText(
            text,
            shouldInsertLeadingSpace: session.shouldInsertLeadingSpace
        )
        switch session.strategy {
        case .selectedText:
            succeeded = replaceRangeInSelectedTextSession(
                element: session.element,
                location: session.insertionLocation,
                currentLength: session.insertedLength,
                text: adjustedText,
                finalizeSelection: finalizeSelection
            )
        case .valueAndRange:
            succeeded = replaceRangeInValueSession(
                element: session.element,
                location: session.insertionLocation,
                currentLength: session.insertedLength,
                text: adjustedText,
                finalizeSelection: finalizeSelection
            )
        }

        if succeeded {
            session.insertedLength = adjustedText.utf16.count
        }

        return succeeded
    }

    func contextualVocabularyCandidates(limit: Int = 40) -> [String] {
        guard let element = focusedElement() else {
            return []
        }

        var sources: [String] = []
        if let selectedText = copyStringAttribute(kAXSelectedTextAttribute as CFString, from: element) {
            sources.append(selectedText)
        }
        if let value = copyStringAttribute(kAXValueAttribute as CFString, from: element) {
            sources.append(value)
        }

        let combined = sources.joined(separator: "\n")
        guard !combined.isEmpty else {
            return []
        }

        let spellChecker = NSSpellChecker.shared
        let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9][A-Za-z0-9_\-\.]{1,}"#)
        let nsText = combined as NSString
        let matches = regex?.matches(in: combined, range: NSRange(location: 0, length: nsText.length)) ?? []

        var seen = Set<String>()
        var phrases: [String] = []

        for match in matches {
            let candidate = nsText.substring(with: match.range)
                .trimmingCharacters(in: .punctuationCharacters)

            guard candidate.count >= 2 else { continue }

            let normalized = candidate.lowercased()
            guard seen.insert(normalized).inserted else { continue }

            let isProjectish = candidate.contains("_")
                || candidate.contains("-")
                || candidate.contains(".")
                || candidate.rangeOfCharacter(from: .decimalDigits) != nil
                || candidate != candidate.lowercased()

            let misspelling = spellChecker.checkSpelling(of: candidate, startingAt: 0)
            let isUnknownWord = misspelling.location != NSNotFound

            guard isProjectish || isUnknownWord else { continue }

            phrases.append(candidate)
            if phrases.count >= limit {
                break
            }
        }

        return phrases
    }

    private func reactivate(_ target: AccessibilityInsertionTarget) async {
        guard let application = NSRunningApplication(processIdentifier: target.processIdentifier) else {
            return
        }

        application.activate(options: [])
        try? await Task.sleep(for: .milliseconds(120))
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)

        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func capabilities(for element: AXUIElement) -> AccessibilityTargetCapabilities {
        AccessibilityTargetCapabilities(
            hasFocusedElement: true,
            selectedTextSettable: isAttributeSettable(kAXSelectedTextAttribute as CFString, on: element),
            valueSettable: isAttributeSettable(kAXValueAttribute as CFString, on: element),
            hasSelectedTextRange: copySelectedRange(from: element) != nil
        )
    }

    private func isAttributeSettable(_ attribute: CFString, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return result == .success && settable.boolValue
    }

    private func replaceSelection(in element: AXUIElement, with text: String) -> Bool {
        guard let existingValue = copyStringAttribute(kAXValueAttribute as CFString, from: element),
              let selectedRange = copySelectedCFRange(from: element)
        else {
            return false
        }

        guard let range = Range(NSRange(location: selectedRange.location, length: selectedRange.length), in: existingValue) else {
            return false
        }

        let replacement = existingValue.replacingCharacters(in: range, with: text)
        let setValueResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, replacement as CFTypeRef)
        guard setValueResult == .success else {
            return false
        }

        let insertionLocation = selectedRange.location + text.count
        var newRange = CFRange(location: insertionLocation, length: 0)
        guard let rangeValue = AXValueCreate(.cfRange, &newRange) else {
            return true
        }

        let rangeResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        return rangeResult == .success
    }

    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func copySelectedRange(from element: AXUIElement) -> Range<String.Index>? {
        guard let cfRange = copySelectedCFRange(from: element),
              let value = copyStringAttribute(kAXValueAttribute as CFString, from: element)
        else {
            return nil
        }

        guard let nsRange = Range(NSRange(location: cfRange.location, length: cfRange.length), in: value) else {
            return nil
        }

        return nsRange
    }

    private func copySelectedCFRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard result == .success, let rawValue = value else { return nil }

        let rangeValue = rawValue as! AXValue
        guard AXValueGetType(rangeValue) == .cfRange else { return nil }

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private func replaceRangeInSelectedTextSession(
        element: AXUIElement,
        location: Int,
        currentLength: Int,
        text: String,
        finalizeSelection: Bool
    ) -> Bool {
        guard setSelectedRange(on: element, location: location, length: currentLength) else {
            return false
        }

        let replaceResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard replaceResult == .success else {
            return false
        }

        let selectionLength = finalizeSelection ? 0 : text.utf16.count
        let selectionLocation = finalizeSelection ? location + text.utf16.count : location
        return setSelectedRange(on: element, location: selectionLocation, length: selectionLength)
    }

    private func replaceRangeInValueSession(
        element: AXUIElement,
        location: Int,
        currentLength: Int,
        text: String,
        finalizeSelection: Bool
    ) -> Bool {
        guard let existingValue = copyStringAttribute(kAXValueAttribute as CFString, from: element) else {
            return false
        }

        let nsValue = existingValue as NSString
        let replaceRange = NSRange(location: location, length: currentLength)
        guard NSMaxRange(replaceRange) <= nsValue.length else {
            return false
        }

        let replacement = nsValue.replacingCharacters(in: replaceRange, with: text)
        let setValueResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            replacement as CFTypeRef
        )
        guard setValueResult == .success else {
            return false
        }

        let selectionLength = finalizeSelection ? 0 : text.utf16.count
        let selectionLocation = finalizeSelection ? location + text.utf16.count : location
        return setSelectedRange(on: element, location: selectionLocation, length: selectionLength)
    }

    private func setSelectedRange(on element: AXUIElement, location: Int, length: Int) -> Bool {
        var range = CFRange(location: location, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return false
        }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )
        return result == .success
    }

    private func adjustedInsertionText(_ text: String, shouldInsertLeadingSpace: Bool) -> String {
        guard shouldInsertLeadingSpace else { return text }
        guard let first = text.first, first.isLetter || first.isNumber else { return text }
        guard !text.hasPrefix(" ") else { return text }
        return " " + text
    }

    private func shouldInsertLeadingSpace(in element: AXUIElement, at location: Int) -> Bool {
        guard location > 0,
              let value = copyStringAttribute(kAXValueAttribute as CFString, from: element)
        else {
            return false
        }

        let nsValue = value as NSString
        guard location - 1 < nsValue.length else {
            return false
        }

        let previousScalar = nsValue.substring(with: NSRange(location: location - 1, length: 1)).unicodeScalars.first
        guard let previousScalar else {
            return false
        }

        return CharacterSet.alphanumerics.contains(previousScalar)
    }

    private func pasteIntoFocusedApp(text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(into: pasteboard)
            return false
        }

        let didPaste = postPasteShortcut()
        try? await Task.sleep(for: .milliseconds(250))
        snapshot.restore(into: pasteboard)
        return didPaste
    }

    private func postPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        let keyCode: CGKeyCode = 9
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func verifyInsertedText(_ text: String, using element: AXUIElement?) async -> AccessibilityInsertionVerification {
        try? await Task.sleep(for: .milliseconds(1_100))

        if let element, elementContainsInsertedText(text, element) {
            return .confirmed
        }

        if let focusedElement = focusedElement(), elementContainsInsertedText(text, focusedElement) {
            return .confirmed
        }

        return .unverified
    }

    private func elementContainsInsertedText(_ text: String, _ element: AXUIElement) -> Bool {
        let expected = normalizedInsertedText(text)
        guard !expected.isEmpty else { return false }

        let values = [
            copyStringAttribute(kAXValueAttribute as CFString, from: element),
            copyStringAttribute(kAXSelectedTextAttribute as CFString, from: element)
        ].compactMap { $0 }

        return values.contains { normalizedInsertedText($0).contains(expected) }
    }

    private func normalizedInsertedText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct PasteboardSnapshot {
    private struct Item {
        var payloads: [NSPasteboard.PasteboardType: Data]
    }

    private let items: [Item]

    static func capture(from pasteboard: NSPasteboard) -> Self {
        let items = pasteboard.pasteboardItems?.map { item in
            Item(
                payloads: Dictionary(
                    uniqueKeysWithValues: item.types.compactMap { type in
                        guard let data = item.data(forType: type) else { return nil }
                        return (type, data)
                    }
                )
            )
        } ?? []

        return Self(items: items)
    }

    func restore(into pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        for item in items {
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item.payloads {
                pasteboardItem.setData(data, forType: type)
            }
            pasteboard.writeObjects([pasteboardItem])
        }
    }
}
#endif
