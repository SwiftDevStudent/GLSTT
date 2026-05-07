import AVFAudio
import Speech
#if os(macOS)
import ApplicationServices
#endif

enum AccessState: Equatable {
    case granted
    case denied
    case notDetermined
    case restricted
}

struct AppPermissionsState: Equatable {
    var accessibilityTrusted: Bool
    var speech: AccessState
    var microphone: AccessState

    static func current() -> Self {
        Self(
            accessibilityTrusted: currentAccessibilityTrust,
            speech: Self.mapSpeechStatus(SFSpeechRecognizer.authorizationStatus()),
            microphone: Self.mapMicrophoneStatus(AVAudioApplication.shared.recordPermission)
        )
    }

    var accessibilitySummary: String {
        #if os(macOS)
        return accessibilityTrusted ? "Enabled for global hotkey capture and insertion." : "Required for the global hotkey and cross-app text insertion."
        #else
        return "Not needed for in-app dictation on iPhone."
        #endif
    }

    var speechSummary: String {
        switch speech {
        case .granted:
            return "Speech recognition is ready."
        case .denied:
            return "Speech recognition access was denied."
        case .restricted:
            return "Speech recognition is restricted on this Mac."
        case .notDetermined:
            return "Speech recognition has not been requested yet."
        }
    }

    var microphoneSummary: String {
        switch microphone {
        case .granted:
            return "Microphone access is ready."
        case .denied:
            return "Microphone access was denied."
        case .restricted:
            return "Microphone access is restricted on this Mac."
        case .notDetermined:
            return "Microphone access has not been requested yet."
        }
    }

    private static func mapSpeechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> AccessState {
        switch status {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }

    private static func mapMicrophoneStatus(_ status: AVAudioApplication.recordPermission) -> AccessState {
        switch status {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }

    private static var currentAccessibilityTrust: Bool {
        #if os(macOS)
        return AXIsProcessTrusted()
        #else
        return true
        #endif
    }
}
