#if os(macOS)
import SwiftUI

struct MacAudioLevelMeter: View {
    enum Style: Equatable {
        case inline
        case compactBadge
        case menuBar
        case fileRecording

        var barCount: Int {
            switch self {
            case .inline:
                return 11
            case .compactBadge, .menuBar, .fileRecording:
                return 5
            }
        }

        var barWidth: CGFloat {
            switch self {
            case .inline:
                return 5
            case .compactBadge, .fileRecording:
                return 3.4
            case .menuBar:
                return 2.2
            }
        }

        var maxBarHeight: CGFloat {
            switch self {
            case .inline:
                return 18
            case .compactBadge, .fileRecording:
                return 30
            case .menuBar:
                return 18
            }
        }

        var spacing: CGFloat {
            switch self {
            case .inline, .compactBadge:
                return 4
            case .menuBar:
                return 1.8
            case .fileRecording:
                return 3
            }
        }

        var minHeightRatio: Double {
            switch self {
            case .inline:
                return 0.22
            case .compactBadge:
                return 0.20
            case .menuBar:
                return 0.18
            case .fileRecording:
                return 0.22
            }
        }
    }

    let level: Double
    let tint: Color
    let isActive: Bool
    let style: Style

    var body: some View {
        HStack(alignment: .center, spacing: style.spacing) {
            ForEach(0..<style.barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(fill(for: index))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(strokeOpacity(for: index)), lineWidth: strokeWidth)
                    }
                    .frame(width: style.barWidth, height: height(for: index))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.06), value: level)
        .animation(.easeOut(duration: 0.12), value: isActive)
        .accessibilityHidden(true)
    }

    private var centerIndex: Int {
        style.barCount / 2
    }

    private var normalizedLevel: Double {
        min(1, max(0, level))
    }

    private var responsiveLevel: Double {
        guard isActive else { return 0 }
        return max(0.12, pow(normalizedLevel, 0.68))
    }

    private var strokeWidth: CGFloat {
        style == .menuBar ? 0.5 : 0.75
    }

    private func fill(for index: Int) -> Color {
        if !isActive {
            return tint.opacity(style == .menuBar ? 0.52 : 0.36)
        }

        let profile = centerProfile(for: index)
        let opacity = min(1, 0.48 + (0.36 * profile) + (0.14 * responsiveLevel))
        return tint.opacity(opacity)
    }

    private func strokeOpacity(for index: Int) -> Double {
        guard isActive else { return style == .menuBar ? 0.28 : 0.16 }
        let edgeBoost = 1 - centerProfile(for: index)
        return min(0.34, 0.16 + (edgeBoost * 0.12) + (responsiveLevel * 0.08))
    }

    private func height(for index: Int) -> CGFloat {
        let profile = centerProfile(for: index)
        let quietRatio = style.minHeightRatio + (0.42 * profile)
        let liveRatio = responsiveLevel * (0.10 + (0.34 * profile))
        let ratio = min(1, quietRatio + liveRatio)
        return max(style.barWidth + 2, style.maxBarHeight * ratio)
    }

    private func centerProfile(for index: Int) -> Double {
        guard centerIndex > 0 else { return 1 }

        let distance = abs(index - centerIndex)
        let normalizedDistance = Double(distance) / Double(centerIndex)
        return 0.18 + (0.82 * pow(max(0, 1 - normalizedDistance), 1.12))
    }
}
#endif
