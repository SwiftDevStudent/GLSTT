#if os(macOS)
import AppKit
import SwiftUI

enum ShortcutCaptureTarget: String, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hold:
            return "Hold Key"
        case .toggle:
            return "Toggle Key"
        }
    }
}

struct ShortcutCaptureSheet: View {
    let target: ShortcutCaptureTarget
    let onCapture: (TriggerKey) -> Void
    let onCancel: () -> Void

    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Press a key for \(target.title)")
                .font(.system(.title2, design: .rounded, weight: .bold))

            Text("Modifier keys and function keys work best for global shortcuts.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.orange)
            }

            ShortcutCaptureRepresentable(
                onCapture: { key in
                    guard key.isSupportedGlobalShortcut else {
                        errorMessage = "Use a modifier key or an F-key."
                        return
                    }

                    onCapture(key)
                },
                onCancel: onCancel
            )
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct ShortcutCaptureRepresentable: NSViewRepresentable {
    let onCapture: (TriggerKey) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class ShortcutCaptureNSView: NSView {
    var onCapture: ((TriggerKey) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        onCapture?(TriggerKey(keyCode: event.keyCode))
    }

    override func flagsChanged(with event: NSEvent) {
        onCapture?(TriggerKey(keyCode: event.keyCode))
    }
}
#endif
