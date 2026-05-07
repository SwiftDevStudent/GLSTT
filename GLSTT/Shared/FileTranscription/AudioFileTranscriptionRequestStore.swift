import Foundation

struct AudioFileTranscriptionRequest: Equatable {
    let fileURL: URL
    let displayName: String
}

enum AudioFileTranscriptionRequestStore {
    static let appGroupIdentifier = "group.com.swiftdev.GLSTT"

    private static let urlScheme = "glstt"
    private static let transcribeHost = "transcribe-audio"
    private static let storedFilenameQueryItem = "file"
    private static let displayNameQueryItem = "name"

    static func request(from url: URL) -> AudioFileTranscriptionRequest? {
        guard url.scheme == urlScheme, url.host == transcribeHost else {
            return nil
        }

        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let storedFilename = components.queryItems?.first(where: { $0.name == storedFilenameQueryItem })?.value,
            !storedFilename.isEmpty,
            !storedFilename.contains("/"),
            let sharedContainerURL
        else {
            return nil
        }

        let displayName = components.queryItems?.first(where: { $0.name == displayNameQueryItem })?.value
            ?? storedFilename
        let fileURL = sharedContainerURL
            .appendingPathComponent("IncomingAudio", isDirectory: true)
            .appendingPathComponent(storedFilename, isDirectory: false)

        return AudioFileTranscriptionRequest(fileURL: fileURL, displayName: displayName)
    }

    private static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
}
