#if os(macOS)
import AppKit

enum AppRuntimeConfiguration {
    static let showDockIcon = true
    static let lsuiElement = false

    static var activationPolicy: NSApplication.ActivationPolicy {
        showDockIcon ? .regular : .accessory
    }
}
#endif
