#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class HUDPanelController: NSObject, NSWindowDelegate {
    private static let statusOriginXKey = "glstt.hud.status.origin.x"
    private static let statusOriginYKey = "glstt.hud.status.origin.y"

    private let statusPanel: NSPanel
    private let messagePanel: NSPanel
    private weak var model: AppModel?
    private var isApplyingSavedFrame = false

    init(model: AppModel) {
        self.model = model
        statusPanel = Self.makePanel(size: model.hudStatusPanelSize)
        messagePanel = Self.makePanel(size: CGSize(width: 420, height: 76))

        super.init()

        configureStatusPanel()
        configureMessagePanel()

        statusPanel.contentView = NSHostingView(rootView: HUDView().environment(model))
        messagePanel.contentView = NSHostingView(rootView: HUDMessageView().environment(model))
    }

    func show() {
        updateStatusPanelFrame()
        statusPanel.orderFrontRegardless()
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

        UserDefaults.standard.set(statusPanel.frame.origin.x, forKey: Self.statusOriginXKey)
        UserDefaults.standard.set(statusPanel.frame.origin.y, forKey: Self.statusOriginYKey)
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

    private func updateStatusPanelFrame() {
        guard let model else { return }
        let desiredSize = model.hudStatusPanelSize
        guard desiredSize != .zero else {
            hide()
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let savedOrigin = savedStatusOrigin()
        let origin = clamp(
            savedOrigin ?? defaultStatusOrigin(for: desiredSize, on: screen),
            size: desiredSize,
            screen: screen
        )
        let frame = NSRect(origin: origin, size: desiredSize)

        guard statusPanel.frame != frame else { return }
        isApplyingSavedFrame = true
        statusPanel.setFrame(frame, display: true)
        isApplyingSavedFrame = false
    }

    private func updateMessagePanelVisibility() {
        guard let model,
              case .message = model.hudMode
        else {
            messagePanel.orderOut(nil)
            return
        }

        let desiredSize = CGSize(width: 420, height: 76)
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

    private func defaultStatusOrigin(for size: CGSize, on screen: NSScreen) -> CGPoint {
        let visibleFrame = screen.visibleFrame
        return CGPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.maxY - size.height - 36
        )
    }

    private func savedStatusOrigin() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.statusOriginXKey) != nil,
              defaults.object(forKey: Self.statusOriginYKey) != nil
        else {
            return nil
        }

        return CGPoint(
            x: defaults.double(forKey: Self.statusOriginXKey),
            y: defaults.double(forKey: Self.statusOriginYKey)
        )
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
        } else {
            transcriptBody
        }
    }

    private var compactBody: some View {
        VStack(spacing: 10) {
            CompactWaveBadge(level: statusAudioLevel, tint: statusAccentColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(backgroundShape)
        .padding(6)
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

                InlineWaveGlyph(level: statusAudioLevel, tint: statusAccentColor)

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

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: model.hudDisplayMode == .compact ? 28 : 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: model.hudDisplayMode == .compact ? 28 : 24, style: .continuous)
                    .strokeBorder(statusAccentColor.opacity(0.35), lineWidth: 1)
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
        case .hidden, .message:
            return "Hold \(model.holdTriggerKey.shortTitle) to start dictation."
        }
    }

    private var statusAccentColor: Color {
        switch model.hudMode {
        case .recording:
            return .green
        case .finalizing:
            return .orange
        case .hidden, .message:
            return .secondary
        }
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
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(tint.opacity(0.16))
                )

            Text(message)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if model.canDismissHUD {
                Button {
                    model.dismissHUD()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                }
        )
        .padding(6)
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

    var body: some View {
        CenterOutLevelMeter(
            level: level,
            tint: tint,
            barCount: 11,
            barSize: CGSize(width: 6, height: 16),
            spacing: 4
        )
        .frame(width: 110, height: 24)
        .animation(.easeOut(duration: 0.06), value: level)
    }
}

private struct CompactWaveBadge: View {
    let level: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
                .frame(width: 72, height: 72)

            CenterOutLevelMeter(
                level: level,
                tint: tint,
                barCount: 9,
                barSize: CGSize(width: 5, height: 18),
                spacing: 3
            )
            .frame(width: 54, height: 24)
        }
    }
}

private struct CenterOutLevelMeter: View {
    let level: Double
    let tint: Color
    let barCount: Int
    let barSize: CGSize
    let spacing: CGFloat

    private var centerIndex: Int {
        barCount / 2
    }

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(fill(for: index))
                    .frame(width: barSize.width, height: barSize.height)
                    .scaleEffect(x: 1, y: scale(for: index), anchor: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fill(for index: Int) -> Color {
        let activation = activation(for: index)
        let baseOpacity = 0.14 + (0.7 * activation)
        return tint.opacity(baseOpacity)
    }

    private func scale(for index: Int) -> CGFloat {
        let activation = activation(for: index)
        return 0.3 + (0.7 * activation)
    }

    private func activation(for index: Int) -> Double {
        let distance = abs(index - centerIndex)
        let normalizedDistance = centerIndex == 0 ? 0 : Double(distance) / Double(centerIndex)
        let boostedLevel = max(0.08, pow(level, 0.75))
        let leadingEdge = boostedLevel * 1.12
        let falloff = max(0, 1 - (normalizedDistance / max(leadingEdge, 0.18)))
        let highlight = max(0, 1 - normalizedDistance * 1.35)
        return min(1, max(falloff, boostedLevel * highlight))
    }
}
#endif
