//
//  GLSTTApp.swift
//  GLSTT
//
//  Created by Naftali Antebi on 4/19/26.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct GLSTTApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()
    @State private var appUpdater = AppUpdater()
    #else
    @State private var appModel = PhoneAppModel()
    #endif

    var body: some Scene {
        #if os(macOS)
        let _ = appDelegate.appModel = appModel
        let _ = appDelegate.appUpdater = appUpdater

        MenuBarExtra {
            ContentView()
                .environment(appModel)
                .environment(appUpdater)
        } label: {
            MenuBarStatusLabel(appModel: appModel)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Picker("Status Display", selection: $appModel.hudDisplayMode) {
                    ForEach(AppModel.HUDDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(appModel)
                .environment(appUpdater)
        }
        #else
        WindowGroup {
            PhoneHomeView()
                .environment(appModel)
                .onOpenURL { url in
                    appModel.handleIncomingAudioURL(url)
                }
        }
        #endif
    }
}

#if os(macOS)
private struct MenuBarStatusLabel: View {
    let appModel: AppModel

    var body: some View {
        if appModel.usesMenuBarLevelMeter, appModel.isMenuBarLevelMeterActive {
            Image(nsImage: MenuBarLevelIcon.image(level: appModel.menuBarLevelMeterLevel, tint: activeTint))
                .renderingMode(.original)
                .accessibilityLabel(appModel.statusSummary)
                .help(appModel.statusSummary)
        } else {
            Image(systemName: appModel.menuBarIconName)
                .accessibilityLabel("GLSTT")
                .help(appModel.statusSummary)
        }
    }

    private var activeTint: NSColor {
        appModel.isFinalizingStatus ? .systemOrange : .systemGreen
    }
}

private enum MenuBarLevelIcon {
    static func image(level: Double, tint: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 21, height: 18))
        image.isTemplate = false

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        let backgroundRect = NSRect(x: 1.5, y: 0.5, width: 17, height: 17)
        let backgroundPath = NSBezierPath(ovalIn: backgroundRect)
        NSColor.black.withAlphaComponent(0.32).setFill()
        backgroundPath.fill()
        tint.withAlphaComponent(0.18).setStroke()
        backgroundPath.lineWidth = 0.7
        backgroundPath.stroke()

        let barWidth: CGFloat = 2
        let spacing: CGFloat = 2.1
        let maxHeight: CGFloat = 12
        let minHeight: CGFloat = 2.4
        let xOrigin = (image.size.width - ((barWidth * 3) + (spacing * 2))) / 2
        let yCenter = image.size.height / 2
        let profile: [CGFloat] = [0.42, 1.0, 0.42]
        let alpha: [CGFloat] = [0.68, 1.0, 0.68]
        let normalizedLevel = CGFloat(min(1, max(0.12, level)))

        for index in 0..<3 {
            let height = minHeight + ((maxHeight - minHeight) * profile[index] * (0.36 + (normalizedLevel * 0.64)))
            let rect = NSRect(
                x: xOrigin + (CGFloat(index) * (barWidth + spacing)),
                y: yCenter - (height / 2),
                width: barWidth,
                height: height
            )
            tint.withAlphaComponent(alpha[index]).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2).fill()
        }

        return image
    }
}
#endif
