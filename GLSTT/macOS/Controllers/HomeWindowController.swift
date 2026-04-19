#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class HomeWindowController: NSWindowController {
    init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "GLSTT"
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.center()
        window.setFrameAutosaveName("GLSTTHomeWindow")
        window.contentView = NSHostingView(rootView: HomeWindowView().environment(model))

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        _ = NSRunningApplication.current.activate(options: [])
    }
}

private struct HomeWindowView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            transcriptSection
            footer
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("GLSTT")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))

                Text(appModel.triggerSummary)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    HomeBadge(title: appModel.statusSummary, tint: appModel.isRecordingActive ? .green : .secondary)
                    HomeBadge(title: appModel.hudDisplayMode.title, tint: .blue)
                    HomeBadge(title: appModel.launchAtLoginBadgeTitle, tint: appModel.launchAtLoginEnabled ? .green : .secondary)
                }
            }
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Transcripts")
                .font(.system(.title3, design: .rounded, weight: .bold))

            ScrollView {
                MacTranscriptHistoryList(
                    entries: appModel.transcriptHistory,
                    emptyMessage: "Use your shortcut to start dictation and your recent captures will show up here."
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Copy Latest") {
                appModel.copyLastTranscript()
            }
            .disabled(appModel.lastTranscript.isEmpty)

            Spacer()

            SettingsLink {
                Text("Open Settings")
            }
        }
    }
}

private struct HomeBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }
}
#endif
