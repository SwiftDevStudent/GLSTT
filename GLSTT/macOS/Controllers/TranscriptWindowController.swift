#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class TranscriptWindowController: NSWindowController {
    init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "GLSTT Transcript"
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.center()
        window.setFrameAutosaveName("GLSTTTranscriptWindow")
        window.contentView = NSHostingView(rootView: TranscriptWindowView().environment(model))

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

private struct TranscriptWindowView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Transcripts")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .padding([.top, .horizontal], 20)
                .padding(.bottom, 14)

            ScrollView {
                MacTranscriptHistoryList(
                    entries: appModel.transcriptHistory,
                    emptyMessage: "Use your shortcut to start dictation and your recent captures will show up here.",
                    copy: appModel.copyTranscript
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Divider()

            HStack {
                Button("Copy Latest", systemImage: "doc.on.doc") {
                    appModel.copyLastTranscript()
                }
                .disabled(appModel.lastTranscript.isEmpty)

                Spacer()
            }
            .padding(14)
            .background(.regularMaterial)
        }
    }
}
#endif
