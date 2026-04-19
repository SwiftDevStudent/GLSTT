#if os(macOS)
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(spacing: 14) {
                PermissionCard(
                    title: "Accessibility",
                    subtitle: "Needed for \(appModel.holdTriggerSummary.lowercased()) and inserting text into other apps.",
                    detail: appModel.permissions.accessibilitySummary,
                    isGranted: appModel.isAccessibilityGranted,
                    primaryTitle: "Request Access",
                    primaryAction: appModel.requestAccessibilityAccess,
                    secondaryTitle: "Open Settings",
                    secondaryAction: appModel.openAccessibilitySettings
                )

                PermissionCard(
                    title: "Speech Recognition",
                    subtitle: "Needed to transcribe speech with Apple's Speech framework.",
                    detail: appModel.permissions.speechSummary,
                    isGranted: appModel.isSpeechGranted,
                    primaryTitle: "Request Access",
                    primaryAction: {
                        Task {
                            await appModel.requestSpeechAccess()
                        }
                    },
                    secondaryTitle: "Open Settings",
                    secondaryAction: appModel.openSpeechSettings
                )

                PermissionCard(
                    title: "Microphone",
                    subtitle: "Needed to capture your voice for push-to-talk dictation. GLSTT will try a brief local recording attempt to trigger the system prompt.",
                    detail: appModel.permissions.microphoneSummary,
                    isGranted: appModel.isMicrophoneGranted,
                    primaryTitle: "Try Recording",
                    primaryAction: {
                        Task {
                            await appModel.requestMicrophoneAccess()
                        }
                    },
                    secondaryTitle: "Open Settings",
                    secondaryAction: appModel.openMicrophoneSettings
                )
            }

            footer
        }
        .padding(22)
        .frame(width: 520)
        .task {
            appModel.refreshPermissions()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set Up GLSTT")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Grant the permissions GLSTT needs. After you close this once, future missing-permission reminders can stay in the floating HUD.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh Status") {
                appModel.refreshPermissions()
            }

            Spacer()

            Button("Continue") {
                appModel.dismissOnboarding()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct PermissionCard: View {
    let title: String
    let subtitle: String
    let detail: String
    let isGranted: Bool
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String
    let secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isGranted ? Color.green : Color.orange)
                    .frame(width: 11, height: 11)

                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                Spacer()

                Text(isGranted ? "Ready" : "Needed")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(isGranted ? .green : .orange)
            }

            Text(subtitle)
                .font(.system(.body, design: .rounded))

            Text(detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(primaryTitle, action: primaryAction)
                Button(secondaryTitle, action: secondaryAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder((isGranted ? Color.green : Color.orange).opacity(0.3), lineWidth: 1)
                }
        )
    }
}

#Preview {
    OnboardingView()
        .environment(AppModel(previewMode: true))
}
#endif
