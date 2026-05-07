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

        MenuBarExtra("GLSTT", systemImage: appModel.menuBarIconName) {
            ContentView()
                .environment(appModel)
                .environment(appUpdater)
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
