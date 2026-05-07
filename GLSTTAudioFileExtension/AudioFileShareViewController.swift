import Foundation
import UniformTypeIdentifiers

#if os(iOS)
import UIKit

typealias PlatformViewController = UIViewController
typealias PlatformLabel = UILabel
typealias PlatformStackView = UIStackView
#elseif os(macOS)
import AppKit

typealias PlatformViewController = NSViewController
typealias PlatformLabel = NSTextField
typealias PlatformStackView = NSStackView
#endif

final class AudioFileShareViewController: PlatformViewController {
    private let titleLabel = PlatformLabel()
    private let detailLabel = PlatformLabel()

    #if os(iOS)
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        importFirstAudioFile()
    }
    #elseif os(macOS)
    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        importFirstAudioFile()
    }
    #endif

    private func importFirstAudioFile() {
        updateStatus(title: "Preparing audio", detail: "Sending the file to GLSTT for transcription.")

        Task { [weak self] in
            do {
                guard let provider = self?.firstAudioProvider() else {
                    throw AudioFileShareImportError.copyFailed("No audio attachment was found.")
                }

                let importedAudio = try await self?.importAudio(from: provider)
                guard let importedAudio else { return }

                await MainActor.run {
                    self?.updateStatus(title: "Opening GLSTT", detail: importedAudio.displayName)
                    self?.extensionContext?.open(importedAudio.deepLink) { success in
                        Task { @MainActor in
                            if success {
                                self?.extensionContext?.completeRequest(returningItems: nil)
                            } else {
                                self?.updateStatus(
                                    title: "Open GLSTT",
                                    detail: "Open GLSTT to start transcribing \(importedAudio.displayName)."
                                )
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self?.updateStatus(title: "Import failed", detail: error.localizedDescription)
                }
            }
        }
    }

    private func firstAudioProvider() -> NSItemProvider? {
        extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .first { $0.hasItemConformingToTypeIdentifier(UTType.audio.identifier) }
    }

    private func importAudio(from provider: NSItemProvider) async throws -> AudioFileShareImport {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AudioFileShareImport, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url else {
                    continuation.resume(throwing: AudioFileShareImportError.copyFailed("The host app did not provide a file URL."))
                    return
                }

                do {
                    let importedAudio = try AudioFileShareImportStore.importAudioFile(
                        from: url,
                        suggestedName: suggestedName ?? url.lastPathComponent
                    )
                    continuation.resume(returning: importedAudio)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

#if os(iOS)
private extension AudioFileShareViewController {
    func configureView() {
        view.backgroundColor = .systemBackground

        let stackView = PlatformStackView(arrangedSubviews: [titleLabel, detailLabel])
        stackView.axis = .vertical
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func updateStatus(title: String, detail: String) {
        titleLabel.text = title
        detailLabel.text = detail
    }
}
#elseif os(macOS)
private extension AudioFileShareViewController {
    func configureView() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stackView = PlatformStackView(views: [titleLabel, detailLabel])
        stackView.orientation = .vertical
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.alignment = .center
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        detailLabel.isEditable = false
        detailLabel.isBordered = false
        detailLabel.drawsBackground = false
        detailLabel.alignment = .center
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 0

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func updateStatus(title: String, detail: String) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
    }
}
#endif
