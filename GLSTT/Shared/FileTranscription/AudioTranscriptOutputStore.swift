import Foundation

enum AudioTranscriptOutputStore {
    static func saveTranscript(_ transcript: String, audioFileName: String) throws -> URL {
        let directory = try outputDirectory()
        let baseName = sanitizedBaseName(for: audioFileName)
        var outputURL = directory.appendingPathComponent(baseName, isDirectory: false)
            .appendingPathExtension("txt")
        var suffix = 2

        while FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = directory.appendingPathComponent("\(baseName) \(suffix)", isDirectory: false)
                .appendingPathExtension("txt")
            suffix += 1
        }

        try transcript.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private static func outputDirectory() throws -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = supportDirectory
            .appendingPathComponent("GLSTT", isDirectory: true)
            .appendingPathComponent("Audio Transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func sanitizedBaseName(for audioFileName: String) -> String {
        let name = (audioFileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = name.isEmpty ? "Audio Transcript" : name
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        let sanitized = source
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
        return sanitized.isEmpty ? "Audio Transcript" : sanitized
    }
}
