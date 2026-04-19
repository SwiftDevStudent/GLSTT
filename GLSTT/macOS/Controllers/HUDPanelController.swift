#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class HUDPanelController {
    private let panel: NSPanel
    private weak var model: AppModel?
    private var lastPanelSize: CGSize?

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: model.hudPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

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

        panel.contentView = NSHostingView(rootView: HUDView().environment(model))
    }

    func show() {
        updateSizeIfNeeded()
        updatePosition()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func updateSizeIfNeeded() {
        guard let model else { return }
        let desiredSize = model.hudPanelSize
        guard lastPanelSize != desiredSize else { return }
        lastPanelSize = desiredSize

        let origin = panel.frame.origin
        DispatchQueue.main.async { [weak self] in
            self?.panel.setFrame(NSRect(origin: origin, size: desiredSize), display: true)
        }
    }

    private func updatePosition() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = CGPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.maxY - size.height - 36
        )

        panel.setFrameOrigin(origin)
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
            CompactWaveBadge(level: model.audioLevel, tint: model.hudAccentColor)

            if case .message = model.hudMode {
                Text(model.hudMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            guard model.canDismissHUD else { return }
            model.dismissHUD()
        }
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

                InlineWaveGlyph(level: model.audioLevel, tint: model.hudAccentColor)

                Spacer()

                if model.isHUDSpinning {
                    ProgressView()
                        .controlSize(.small)
                } else if model.canDismissHUD {
                    Button {
                        model.dismissHUD()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(model.hudTitle)
                .font(.system(.headline, design: .rounded, weight: .semibold))

            if model.showsTranscriptHUD,
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
                Text(model.hudMessage)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !model.hudMessage.isEmpty {
                Text(model.hudMessage)
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
        .onTapGesture {
            guard model.canDismissHUD else { return }
            model.dismissHUD()
        }
        .background(backgroundShape)
        .padding(8)
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: model.hudDisplayMode == .compact ? 28 : 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: model.hudDisplayMode == .compact ? 28 : 24, style: .continuous)
                    .strokeBorder(model.hudBorderColor, lineWidth: 1)
            }
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
