#if os(macOS)
import SwiftUI

struct SoftwareUpdateSectionView: View {
    @Environment(AppUpdater.self) private var updater

    let compact: Bool

    init(compact: Bool = false) {
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Software Update")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Text(updater.currentVersionSummary)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge
            }

            Text(updater.statusSummary)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(statusTint)

            Text(updater.lastCheckedSummary)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            if let update = updater.availableUpdate {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Available: \(update.displayVersion)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))

                    if let notes = update.notes,
                       !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(notes)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(compact ? 3 : 6)
                            .textSelection(.enabled)
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Check for Updates") {
                    Task {
                        await updater.checkForUpdates()
                    }
                }
                .modifier(MacUpdateActionButtonStyleModifier(compact: compact, prominent: false))
                .disabled(!updater.canCheckForUpdates)

                if updater.availableUpdate != nil {
                    Button("Install Update") {
                        Task {
                            await updater.installAvailableUpdate()
                        }
                    }
                    .modifier(MacUpdateActionButtonStyleModifier(compact: compact, prominent: true))
                    .disabled(!updater.canInstallAvailableUpdate)
                }
            }
        }
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(statusTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(statusTint.opacity(0.14))
            )
    }

    private var statusLabel: String {
        switch updater.state {
        case .idle:
            return updater.availableUpdate == nil ? "Idle" : "Ready"
        case .checking:
            return "Checking"
        case .updateAvailable:
            return "Available"
        case .downloading:
            return "Downloading"
        case .installing:
            return "Installing"
        case .upToDate:
            return "Current"
        case .failed:
            return "Error"
        }
    }

    private var statusTint: Color {
        switch updater.state {
        case .idle:
            return updater.availableUpdate == nil ? .secondary : .blue
        case .checking, .downloading:
            return .orange
        case .installing:
            return .orange
        case .updateAvailable:
            return .blue
        case .upToDate:
            return .green
        case .failed:
            return .orange
        }
    }
}

private struct MacUpdateActionButtonStyleModifier: ViewModifier {
    let compact: Bool
    let prominent: Bool

    func body(content: Content) -> some View {
        if compact {
            content.buttonStyle(.plain)
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
#endif
