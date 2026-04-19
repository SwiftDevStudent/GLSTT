#if os(macOS)
import AppKit
import CryptoKit
import Foundation
import Observation
import Security

@MainActor
@Observable
final class AppUpdater {
    private static let lastCheckDateKey = "glstt.updater.lastCheckDate"
    private static let automaticCheckInterval: TimeInterval = 60 * 60 * 12

    enum State: Equatable {
        case idle
        case checking
        case updateAvailable
        case downloading
        case installing
        case upToDate
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var availableUpdate: AppUpdateRelease?
    private(set) var lastCheckedAt: Date?

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let session: URLSession
    @ObservationIgnored
    private var hasStarted = false

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) {
        self.defaults = defaults
        self.session = session
        self.lastCheckedAt = defaults.object(forKey: Self.lastCheckDateKey) as? Date
    }

    var currentVersionSummary: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "0"
        return "Version \(version) (\(build))"
    }

    var statusSummary: String {
        guard configuration != nil else {
            return "Updates are disabled until GLSTTUpdateFeedURL is configured."
        }

        switch state {
        case .idle:
            if let release = availableUpdate {
                return "Update \(release.displayVersion) is ready to install."
            }
            return "Automatic checks run in the background."
        case .checking:
            return "Checking for a newer build…"
        case .updateAvailable:
            guard let release = availableUpdate else {
                return "A newer build is available."
            }
            return "Update \(release.displayVersion) is available."
        case .downloading:
            guard let release = availableUpdate else {
                return "Downloading the update…"
            }
            return "Downloading \(release.displayVersion)…"
        case .installing:
            return "Closing GLSTT to replace the app bundle…"
        case .upToDate:
            return "You already have the latest compatible build."
        case .failed(let message):
            return message
        }
    }

    var lastCheckedSummary: String {
        guard let lastCheckedAt else {
            return "Never checked"
        }

        return "Last checked \(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var canCheckForUpdates: Bool {
        !isBusy
    }

    var canInstallAvailableUpdate: Bool {
        availableUpdate != nil && !isBusy
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing:
            return true
        case .idle, .updateAvailable, .upToDate, .failed:
            return false
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        Task {
            await checkForUpdates(userInitiated: false)
        }
    }

    func checkForUpdates(userInitiated: Bool = true) async {
        guard !isBusy else { return }

        guard let configuration else {
            if userInitiated {
                state = .failed("Set GLSTTUpdateFeedURL in the target build settings to enable updates.")
            }
            return
        }

        if !userInitiated,
           let lastCheckedAt,
           Date().timeIntervalSince(lastCheckedAt) < Self.automaticCheckInterval {
            return
        }

        state = .checking

        do {
            let feed = try await fetchFeed(from: configuration.feedURL)
            let nextRelease = bestAvailableRelease(in: feed, configuration: configuration)
            let checkDate = Date()
            lastCheckedAt = checkDate
            defaults.set(checkDate, forKey: Self.lastCheckDateKey)
            availableUpdate = nextRelease
            state = nextRelease == nil ? .upToDate : .updateAvailable
        } catch {
            if userInitiated {
                state = .failed(error.localizedDescription)
            } else if availableUpdate == nil {
                state = .idle
            }
        }
    }

    func installAvailableUpdate() async {
        guard !isBusy else { return }

        guard let configuration else {
            state = .failed("Updates are not configured for this build.")
            return
        }

        guard let update = availableUpdate else {
            state = .failed("Check for updates first.")
            return
        }

        do {
            try validateInstallLocation(configuration.installationURL)
            state = .downloading

            let stagingDirectory = try makeStagingDirectory()
            let archiveURL = try await downloadArchive(for: update, into: stagingDirectory)
            try verifyArchiveHash(at: archiveURL, expectedHash: update.sha256)

            let extractedAppURL = try extractArchive(at: archiveURL, into: stagingDirectory)
            try verifyExtractedApplication(
                at: extractedAppURL,
                expectedBundleIdentifier: configuration.bundleIdentifier,
                expectedTeamIdentifier: configuration.expectedTeamIdentifier
            )

            state = .installing
            try launchInstaller(
                sourceAppURL: extractedAppURL,
                destinationAppURL: configuration.installationURL,
                stagingDirectoryURL: stagingDirectory
            )
            NSApplication.shared.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private var configuration: AppUpdaterConfiguration? {
        guard let feedString = Bundle.main.object(forInfoDictionaryKey: "GLSTTUpdateFeedURL") as? String else {
            return nil
        }

        let trimmedFeedString = feedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFeedString.isEmpty else {
            return nil
        }

        guard let feedURL = URL(string: trimmedFeedString) else {
            return nil
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        guard !bundleIdentifier.isEmpty else {
            return nil
        }

        let teamIdentifier = (
            Bundle.main.object(forInfoDictionaryKey: "GLSTTUpdaterExpectedTeamID") as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        return AppUpdaterConfiguration(
            feedURL: feedURL,
            bundleIdentifier: bundleIdentifier,
            expectedTeamIdentifier: teamIdentifier?.isEmpty == false ? teamIdentifier : currentTeamIdentifier(),
            installedVersion: InstalledAppVersion.current(),
            installationURL: Bundle.main.bundleURL.resolvingSymlinksInPath()
        )
    }

    private func currentTeamIdentifier() -> String? {
        try? codeSignatureInfo(for: Bundle.main.bundleURL).teamIdentifier
    }

    private func fetchFeed(from url: URL) async throws -> AppUpdateFeed {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AppUpdaterError.invalidServerResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(AppUpdateFeed.self, from: data)
        } catch {
            throw AppUpdaterError.invalidFeed
        }
    }

    private func bestAvailableRelease(
        in feed: AppUpdateFeed,
        configuration: AppUpdaterConfiguration
    ) -> AppUpdateRelease? {
        let compatibleUpdates = feed.updates.filter { update in
            guard update.bundleIdentifier.map({ $0 == configuration.bundleIdentifier }) ?? true else {
                return false
            }

            if let expectedTeamIdentifier = configuration.expectedTeamIdentifier {
                guard update.teamIdentifier.map({ $0 == expectedTeamIdentifier }) ?? true else {
                    return false
                }
            }

            guard update.archiveURL.pathExtension.lowercased() == "zip" else {
                return false
            }

            if let minimumSystemVersion = update.minimumSystemVersion {
                guard minimumSystemVersion.isCompatibleWithCurrentSystem else {
                    return false
                }
            }

            return update.isNewer(than: configuration.installedVersion)
        }

        return compatibleUpdates.max()
    }

    private func makeStagingDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GLSTTUpdater-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func downloadArchive(
        for update: AppUpdateRelease,
        into directory: URL
    ) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: update.archiveURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AppUpdaterError.invalidServerResponse
        }

        let archiveName = update.archiveURL.lastPathComponent.isEmpty ? "GLSTTUpdate.zip" : update.archiveURL.lastPathComponent
        let archiveURL = directory.appendingPathComponent(archiveName)
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: archiveURL)
        return archiveURL
    }

    private func verifyArchiveHash(at archiveURL: URL, expectedHash: String) throws {
        let archiveData = try Data(contentsOf: archiveURL)
        let digest = SHA256.hash(data: archiveData).hexString
        guard digest.caseInsensitiveCompare(expectedHash) == .orderedSame else {
            throw AppUpdaterError.hashMismatch
        }
    }

    private func extractArchive(at archiveURL: URL, into stagingDirectory: URL) throws -> URL {
        let extractionDirectory = stagingDirectory.appendingPathComponent("Extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, extractionDirectory.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AppUpdaterError.archiveExtractionFailed
        }

        guard let extractedAppURL = findApplicationBundle(in: extractionDirectory) else {
            throw AppUpdaterError.extractedAppMissing
        }

        return extractedAppURL
    }

    private func findApplicationBundle(in directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let nextObject = enumerator?.nextObject() as? URL {
            guard nextObject.pathExtension == "app" else { continue }
            return nextObject
        }

        return nil
    }

    private func verifyExtractedApplication(
        at applicationURL: URL,
        expectedBundleIdentifier: String,
        expectedTeamIdentifier: String?
    ) throws {
        guard let bundle = Bundle(url: applicationURL) else {
            throw AppUpdaterError.extractedAppMissing
        }

        let candidateBundleIdentifier = bundle.bundleIdentifier ?? ""
        guard candidateBundleIdentifier == expectedBundleIdentifier else {
            throw AppUpdaterError.bundleIdentifierMismatch
        }

        let codeSignature = try codeSignatureInfo(for: applicationURL)

        if let expectedTeamIdentifier {
            guard codeSignature.teamIdentifier == expectedTeamIdentifier else {
                throw AppUpdaterError.teamIdentifierMismatch
            }
        }
    }

    private func codeSignatureInfo(for applicationURL: URL) throws -> CodeSignatureInfo {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(applicationURL as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            throw AppUpdaterError.signatureValidationFailed
        }

        let validityStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
        guard validityStatus == errSecSuccess else {
            throw AppUpdaterError.signatureValidationFailed
        }

        var signingInformation: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard infoStatus == errSecSuccess,
              let signingInformation = signingInformation as? [String: Any] else {
            throw AppUpdaterError.signatureValidationFailed
        }

        return CodeSignatureInfo(
            teamIdentifier: signingInformation[kSecCodeInfoTeamIdentifier as String] as? String
        )
    }

    private func validateInstallLocation(_ applicationURL: URL) throws {
        let resolvedURL = applicationURL.resolvingSymlinksInPath()
        guard !resolvedURL.path.contains("/AppTranslocation/") else {
            throw AppUpdaterError.translocatedApp
        }

        let parentDirectory = resolvedURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDirectory.path) else {
            throw AppUpdaterError.installLocationNotWritable(parentDirectory.path)
        }
    }

    private func launchInstaller(
        sourceAppURL: URL,
        destinationAppURL: URL,
        stagingDirectoryURL: URL
    ) throws {
        let backupURL = destinationAppURL.deletingLastPathComponent()
            .appendingPathComponent("\(destinationAppURL.deletingPathExtension().lastPathComponent)-previous.app")
        let scriptURL = stagingDirectoryURL.appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/zsh
        set -euo pipefail

        SOURCE_APP="$1"
        DEST_APP="$2"
        BACKUP_APP="$3"
        PID_TO_WAIT="$4"
        STAGING_DIR="$5"

        while kill -0 "$PID_TO_WAIT" >/dev/null 2>&1; do
            sleep 1
        done

        /bin/rm -rf "$BACKUP_APP"
        /bin/mv "$DEST_APP" "$BACKUP_APP"

        if /usr/bin/ditto "$SOURCE_APP" "$DEST_APP"; then
            /bin/rm -rf "$BACKUP_APP"
            /usr/bin/xattr -d -r com.apple.quarantine "$DEST_APP" >/dev/null 2>&1 || true
            /usr/bin/open "$DEST_APP"
        else
            /bin/rm -rf "$DEST_APP"
            /bin/mv "$BACKUP_APP" "$DEST_APP"
            exit 1
        fi

        /bin/rm -rf "$STAGING_DIR"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            sourceAppURL.path,
            destinationAppURL.path,
            backupURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            stagingDirectoryURL.path
        ]
        try process.run()
    }
}

private struct AppUpdaterConfiguration {
    let feedURL: URL
    let bundleIdentifier: String
    let expectedTeamIdentifier: String?
    let installedVersion: InstalledAppVersion
    let installationURL: URL
}

private struct AppUpdateFeed: Decodable {
    let updates: [AppUpdateRelease]
}

struct AppUpdateRelease: Decodable, Equatable, Comparable {
    let version: String
    let build: String
    let minimumSystemVersion: String?
    let archiveURL: URL
    let sha256: String
    let notes: String?
    let publishedAt: Date?
    let bundleIdentifier: String?
    let teamIdentifier: String?

    var displayVersion: String {
        "\(version) (\(build))"
    }

    fileprivate func isNewer(than installedVersion: InstalledAppVersion) -> Bool {
        let versionComparison = version.compare(installedVersion.version, options: .numeric)
        if versionComparison != .orderedSame {
            return versionComparison == .orderedDescending
        }

        return build.compare(installedVersion.build, options: .numeric) == .orderedDescending
    }

    static func < (lhs: AppUpdateRelease, rhs: AppUpdateRelease) -> Bool {
        let versionComparison = lhs.version.compare(rhs.version, options: .numeric)
        if versionComparison != .orderedSame {
            return versionComparison == .orderedAscending
        }

        return lhs.build.compare(rhs.build, options: .numeric) == .orderedAscending
    }
}

private struct InstalledAppVersion {
    let version: String
    let build: String

    static func current() -> InstalledAppVersion {
        InstalledAppVersion(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            build: Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "0"
        )
    }
}

private struct CodeSignatureInfo {
    let teamIdentifier: String?
}

private enum AppUpdaterError: LocalizedError {
    case invalidServerResponse
    case invalidFeed
    case hashMismatch
    case archiveExtractionFailed
    case extractedAppMissing
    case bundleIdentifierMismatch
    case signatureValidationFailed
    case teamIdentifierMismatch
    case translocatedApp
    case installLocationNotWritable(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerResponse:
            return "The update server returned an invalid response."
        case .invalidFeed:
            return "The update feed could not be decoded."
        case .hashMismatch:
            return "The downloaded archive does not match the published SHA-256."
        case .archiveExtractionFailed:
            return "The downloaded archive could not be extracted."
        case .extractedAppMissing:
            return "The archive did not contain a macOS app bundle."
        case .bundleIdentifierMismatch:
            return "The downloaded app does not match GLSTT's bundle identifier."
        case .signatureValidationFailed:
            return "The downloaded app failed code-signature validation."
        case .teamIdentifierMismatch:
            return "The downloaded app was signed by the wrong Apple team."
        case .translocatedApp:
            return "Move GLSTT out of the translocated launch path before installing updates."
        case .installLocationNotWritable(let path):
            return "GLSTT cannot replace itself in \(path). Move it into a user-writable Applications folder first."
        }
    }
}

private extension SHA256Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var isCompatibleWithCurrentSystem: Bool {
        guard let version = OperatingSystemVersion(self) else {
            return true
        }

        return ProcessInfo.processInfo.isOperatingSystemAtLeast(version)
    }
}

private extension OperatingSystemVersion {
    init?(_ string: String) {
        let components = string
            .split(separator: ".")
            .compactMap { Int($0) }

        guard !components.isEmpty else {
            return nil
        }

        self.init(
            majorVersion: components[safe: 0] ?? 0,
            minorVersion: components[safe: 1] ?? 0,
            patchVersion: components[safe: 2] ?? 0
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
#endif
