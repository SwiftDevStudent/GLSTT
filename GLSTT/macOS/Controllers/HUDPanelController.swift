#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class HUDPanelController: NSObject, NSWindowDelegate {
    private static let statusOriginXKey = "glstt.hud.status.origin.x"
    private static let statusOriginYKey = "glstt.hud.status.origin.y"
    private static let compactOriginXKey = "glstt.hud.compact.origin.x"
    private static let compactOriginYKey = "glstt.hud.compact.origin.y"

    private let statusPanel: NSPanel
    private let messagePanel: NSPanel
    private weak var model: AppModel?
    private var isApplyingSavedFrame = false

    init(model: AppModel) {
        self.model = model
        statusPanel = Self.makePanel(size: model.hudStatusPanelSize)
        messagePanel = Self.makePanel(size: Self.messagePanelSize)

        super.init()

        configureStatusPanel()
        configureMessagePanel()

        statusPanel.contentView = NSHostingView(rootView: HUDView().environment(model))
        messagePanel.contentView = NSHostingView(rootView: HUDMessageView().environment(model))
    }

    func show() {
        if updateStatusPanelFrame() {
            statusPanel.orderFrontRegardless()
        }
        updateMessagePanelVisibility()
    }

    func hide() {
        statusPanel.orderOut(nil)
        messagePanel.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingSavedFrame,
              let movedPanel = notification.object as? NSPanel,
              movedPanel === statusPanel
        else {
            return
        }

        guard let model else { return }

        let keys = originKeys(for: model.hudDisplayMode)
        UserDefaults.standard.set(statusPanel.frame.origin.x, forKey: keys.x)
        UserDefaults.standard.set(statusPanel.frame.origin.y, forKey: keys.y)
        updateMessagePanelVisibility()
    }

    private static func makePanel(size: CGSize) -> NSPanel {
        NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    private func configureStatusPanel() {
        configurePanel(statusPanel)
        statusPanel.isMovableByWindowBackground = true
        statusPanel.delegate = self
    }

    private func configureMessagePanel() {
        configurePanel(messagePanel)
        messagePanel.delegate = self
    }

    private func configurePanel(_ panel: NSPanel) {
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .utilityWindow
    }

    private func updateStatusPanelFrame() -> Bool {
        guard let model else { return false }
        let desiredSize = model.hudStatusPanelSize
        guard desiredSize != .zero else {
            hide()
            return false
        }
        statusPanel.hasShadow = model.hudDisplayMode == .transcript
        statusPanel.ignoresMouseEvents = model.hudDisplayMode == .menuBar
        statusPanel.isMovableByWindowBackground = model.hudDisplayMode != .menuBar

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return false }

        let savedOrigin = savedStatusOrigin(for: model.hudDisplayMode)
        let origin = clamp(
            savedOrigin ?? defaultStatusOrigin(for: desiredSize, on: screen, displayMode: model.hudDisplayMode),
            size: desiredSize,
            screen: screen
        )
        let frame = NSRect(origin: origin, size: desiredSize)

        guard statusPanel.frame != frame else { return true }
        isApplyingSavedFrame = true
        statusPanel.setFrame(frame, display: true)
        isApplyingSavedFrame = false
        return true
    }

    private func updateMessagePanelVisibility() {
        guard let model,
              model.hudDisplayMode != .menuBar,
              case .message = model.hudMode
        else {
            messagePanel.orderOut(nil)
            return
        }

        let desiredSize = Self.messagePanelSize
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(statusPanel.frame) }) ?? NSScreen.main
        guard let screen else { return }

        let origin = clamp(
            CGPoint(
                x: statusPanel.frame.midX - (desiredSize.width / 2),
                y: statusPanel.frame.minY - desiredSize.height - 10
            ),
            size: desiredSize,
            screen: screen
        )
        let frame = NSRect(origin: origin, size: desiredSize)

        if messagePanel.frame != frame {
            messagePanel.setFrame(frame, display: true)
        }
        messagePanel.orderFrontRegardless()
    }

    private func defaultStatusOrigin(
        for size: CGSize,
        on screen: NSScreen,
        displayMode: AppModel.HUDDisplayMode
    ) -> CGPoint {
        if displayMode == .menuBar {
            return CGPoint(
                x: screen.frame.midX - (size.width / 2),
                y: screen.frame.maxY - size.height
            )
        }

        let visibleFrame = screen.visibleFrame
        if displayMode == .compact {
            return CGPoint(
                x: visibleFrame.midX - (size.width / 2),
                y: visibleFrame.minY + 18
            )
        }

        return CGPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.maxY - size.height - 36
        )
    }

    private func savedStatusOrigin(for displayMode: AppModel.HUDDisplayMode) -> CGPoint? {
        guard displayMode != .menuBar else { return nil }

        let defaults = UserDefaults.standard
        let keys = originKeys(for: displayMode)
        guard defaults.object(forKey: keys.x) != nil,
              defaults.object(forKey: keys.y) != nil
        else {
            return nil
        }

        return CGPoint(
            x: defaults.double(forKey: keys.x),
            y: defaults.double(forKey: keys.y)
        )
    }

    private func originKeys(for displayMode: AppModel.HUDDisplayMode) -> (x: String, y: String) {
        displayMode == .compact
            ? (Self.compactOriginXKey, Self.compactOriginYKey)
            : (Self.statusOriginXKey, Self.statusOriginYKey)
    }

    private static var messagePanelSize: CGSize {
        CGSize(width: 224, height: 54)
    }

    private func clamp(_ origin: CGPoint, size: CGSize, screen: NSScreen) -> CGPoint {
        let frame = screen.visibleFrame
        return CGPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - size.width),
            y: min(max(origin.y, frame.minY), frame.maxY - size.height)
        )
    }
}

private struct HUDView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.hudDisplayMode == .compact {
            compactBody
        } else if model.hudDisplayMode == .menuBar {
            menuBarTopBody
        } else {
            transcriptBody
        }
    }

    private var compactBody: some View {
        CompactWaveBadge(level: statusAudioLevel, tint: statusAccentColor, isActive: statusIsAudioActive)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .background(backgroundShape)
    }

    private var menuBarTopBody: some View {
        HStack(spacing: 7) {
            if case .message = model.hudMode {
                Image(systemName: statusMessageIconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(statusAccentColor)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(statusAccentColor.opacity(0.16))
                    )

                Text(statusMessage)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MacAudioLevelMeter(
                    level: statusAudioLevel,
                    tint: statusAccentColor,
                    isActive: statusIsAudioActive,
                    style: .menuBar
                )
                .frame(width: 23, height: 19)
            }
        }
        .padding(.horizontal, menuBarHorizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundShape)
    }

    private var transcriptBody: some View {
        VStack(alignment: .leading, spacing: model.showsTranscriptHUD ? 10 : 6) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text(model.hudAppName)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)

                InlineWaveGlyph(level: statusAudioLevel, tint: statusAccentColor, isActive: statusIsAudioActive)

                Spacer()

                if statusIsSpinning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(statusTitle)
                .font(.system(.headline, design: .rounded, weight: .semibold))

            if model.showsTranscriptHUD,
               statusShowsTranscript,
               !model.finalizedTranscript.isEmpty || !model.volatileTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.finalizedTranscript)
                        .foregroundStyle(.primary)

                    if !model.volatileTranscript.isEmpty {
                        Text(model.volatileTranscript)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(.body, design: .rounded))
                .multilineTextAlignment(.leading)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.showsTranscriptHUD {
                Text(statusMessage)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(backgroundShape)
        .padding(8)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if model.hudDisplayMode == .compact {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.clear)
        } else if model.hudDisplayMode == .menuBar {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 15,
                bottomTrailingRadius: 15,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.black.opacity(0.88))
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(statusAccentColor.opacity(0.35), lineWidth: 1)
                }
            }
    }

    private var statusTitle: String {
        switch model.hudMode {
        case .recording:
            return model.hudDisplayMode == .compact ? "" : "Listening"
        case .finalizing:
            return model.hudDisplayMode == .compact ? "" : "Finalizing Transcript"
        case .hidden, .message:
            return "Not Listening"
        }
    }

    private var statusMessage: String {
        switch model.hudMode {
        case .recording:
            return model.hudMessage
        case .finalizing:
            return model.hudMessage
        case .message:
            return model.hudMessage
        case .hidden:
            return "Hold \(model.holdTriggerKey.shortTitle) to start dictation."
        }
    }

    private var statusAccentColor: Color {
        switch model.hudMode {
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

    private var menuBarHorizontalPadding: CGFloat {
        if case .message = model.hudMode { return 10 }
        return 12
    }

    private var statusMessageIconName: String {
        guard case .message(_, let isError) = model.hudMode else { return "waveform" }
        return isError ? "exclamationmark" : "checkmark"
    }

    private var statusAudioLevel: Double {
        switch model.hudMode {
        case .recording, .finalizing:
            return model.audioLevel
        case .hidden, .message:
            return 0
        }
    }

    private var statusIsSpinning: Bool {
        if case .finalizing = model.hudMode { return true }
        return false
    }

    private var statusIsAudioActive: Bool {
        switch model.hudMode {
        case .recording, .finalizing:
            return true
        case .hidden, .message:
            return false
        }
    }

    private var statusShowsTranscript: Bool {
        switch model.hudMode {
        case .recording, .finalizing:
            return true
        case .hidden, .message:
            return false
        }
    }
}

private struct HUDMessageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 21, height: 21)
                .background(
                    Circle()
                        .fill(tint.opacity(0.16))
                )

            Text(message)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                }
        )
        .padding(5)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            model.openTranscriptWindowFromHUD()
        }
    }

    private var message: String {
        guard case .message(let message, _) = model.hudMode else { return "" }
        return message
    }

    private var isError: Bool {
        guard case .message(_, let isError) = model.hudMode else { return false }
        return isError
    }

    private var tint: Color {
        switch messageKind {
        case .success:
            return .green
        case .failure:
            return .red
        case .warning:
            return .orange
        }
    }

    private var iconName: String {
        switch messageKind {
        case .success:
            return "checkmark"
        case .failure:
            return "xmark"
        case .warning:
            return "exclamationmark.triangle"
        }
    }

    private var messageKind: MessageKind {
        guard isError else { return .success }

        let lowercasedMessage = message.lowercased()
        if lowercasedMessage.contains("could not confirm")
            || lowercasedMessage.contains("failed")
            || lowercasedMessage.contains("unable to insert")
            || lowercasedMessage.contains("no editable target") {
            return .failure
        }

        return .warning
    }

    private enum MessageKind {
        case success
        case warning
        case failure
    }
}

private struct InlineWaveGlyph: View {
    let level: Double
    let tint: Color
    let isActive: Bool

    var body: some View {
        MacAudioLevelMeter(
            level: level,
            tint: tint,
            isActive: isActive,
            style: .inline
        )
        .frame(width: 110, height: 24)
    }
}

private struct CompactWaveBadge: View {
    let level: Double
    let tint: Color
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: 52, height: 52)

            MacAudioLevelMeter(
                level: level,
                tint: tint,
                isActive: isActive,
                style: .compactBadge
            )
            .frame(width: 36, height: 30)
        }
    }
}
#endif
