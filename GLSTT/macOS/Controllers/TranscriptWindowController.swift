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
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcript")
                .font(.system(.title2, design: .rounded, weight: .semibold))

            ScrollView {
                Text(appModel.lastTranscript.isEmpty ? "Nothing captured yet." : appModel.lastTranscript)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(appModel.lastTranscript.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }

            HStack {
                Button("Copy Transcript") {
                    appModel.copyLastTranscript()
                }

                Spacer()
            }
        }
        .padding(20)
    }
}
#endif
