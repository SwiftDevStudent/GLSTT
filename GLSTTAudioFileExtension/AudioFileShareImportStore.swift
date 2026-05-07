import Foundation

enum AudioFileShareImportError: LocalizedError {
    case sharedContainerUnavailable
    case copyFailed(String)
    case deepLinkUnavailable

    var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable:
            return "The shared GLSTT container is unavailable."
        case .copyFailed(let detail):
            return "Unable to import that audio file: \(detail)"
        case .deepLinkUnavailable:
            return "Unable to open GLSTT for transcription."
        }
    }
}

struct AudioFileShareImport {
    let displayName: String
    let deepLink: URL
}

enum AudioFileShareImportStore {
    private static let appGroupIdentifier = "group.com.swiftdev.GLSTT"
    private static let urlScheme = "glstt"
    private static let transcribeHost = "transcribe-audio"

    static func importAudioFile(from sourceURL: URL, suggestedName: String?) throws -> AudioFileShareImport {
        guard let sharedContainerURL else {
            throw AudioFileShareImportError.sharedContainerUnavailable
        }

        let displayName = sanitizedDisplayName(suggestedName ?? sourceURL.lastPathComponent)
        let storedFilename = "\(UUID().uuidString)-\(displayName)"
        let destinationDirectory = sharedContainerURL.appendingPathComponent("IncomingAudio", isDirectory: true)
        let destinationURL = destinationDirectory.appendingPathComponent(storedFilename, isDirectory: false)

        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw AudioFileShareImportError.copyFailed(error.localizedDescription)
        }

        guard let deepLink = deepLink(storedFilename: storedFilename, displayName: displayName) else {
            throw AudioFileShareImportError.deepLinkUnavailable
        }

        return AudioFileShareImport(displayName: displayName, deepLink: deepLink)
    }

    private static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    private static func deepLink(storedFilename: String, displayName: String) -> URL? {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = transcribeHost
        components.queryItems = [
            URLQueryItem(name: "file", value: storedFilename),
            URLQueryItem(name: "name", value: displayName),
        ]
        return components.url
    }

    private static func sanitizedDisplayName(_ name: String) -> String {
        let fallback = "Audio File"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? fallback : trimmed
        let allowedCharacters = CharacterSet(charactersIn: "/:")
        let sanitized = source
            .components(separatedBy: allowedCharacters)
            .joined(separator: "-")
        return sanitized.isEmpty ? fallback : sanitized
    }
}
