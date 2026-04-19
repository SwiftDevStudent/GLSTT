@preconcurrency import AVFAudio
@preconcurrency import AVFoundation
import Foundation
import Speech
#if os(macOS)
import AppKit
#endif

enum SpeechTranscriptionError: LocalizedError {
    case speechPermissionDenied
    case microphonePermissionDenied
    case speechRecognitionUnavailable
    case unsupportedLocale
    case unsupportedAudioFormat
    case unavailableAudioInput(String)
    case alreadyRecording
    case notRecording
    case failedToStartAudioEngine(String)
    case assetInstallationFailed(String)

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return "Speech recognition permission is required."
        case .microphonePermissionDenied:
            return "Microphone permission is required."
        case .speechRecognitionUnavailable:
            return "Apple dictation transcription is unavailable on this Mac."
        case .unsupportedLocale:
            return "The current locale is not supported by Apple's on-device speech models."
        case .unsupportedAudioFormat:
            return "Unable to determine a compatible audio format for transcription."
        case .unavailableAudioInput(let detail):
            return detail
        case .alreadyRecording:
            return "A dictation session is already in progress."
        case .notRecording:
            return "No dictation session is running."
        case .failedToStartAudioEngine(let detail):
            return "Failed to start audio capture: \(detail)"
        case .assetInstallationFailed(let detail):
            return "Failed to install Apple speech assets: \(detail)"
        }
    }
}

@MainActor
final class SpeechTranscriptionController {
    var onTranscriptUpdate: ((TranscriptAssembly) -> Void)?
    var onAudioLevelUpdate: ((Double) -> Void)?

    private(set) var isRecording = false

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var transcriptAssembly = TranscriptAssembly()
    private var targetAudioFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private let microphoneProbe = AVAudioEngine()
    private var captureProbeSession: AVCaptureSession?

    func requestSpeechAndMicrophoneAccess() async {
        _ = await requestSpeechAccessIfNeeded()
        _ = await requestMicrophoneAccessIfNeeded()
    }

    func requestSpeechAccess() async -> Bool {
        await requestSpeechAccessIfNeeded()
    }

    func requestMicrophoneAccess() async -> Bool {
        await requestMicrophoneAccessIfNeeded()
    }

    func beginSession(contextualStrings: [String] = []) async throws {
        guard !isRecording else {
            throw SpeechTranscriptionError.alreadyRecording
        }

        guard await requestSpeechAccessIfNeeded() else {
            throw SpeechTranscriptionError.speechPermissionDenied
        }

        try configureAudioSessionIfNeeded()

        guard await requestMicrophoneAccessIfNeeded() else {
            throw SpeechTranscriptionError.microphonePermissionDenied
        }

        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            throw SpeechTranscriptionError.unsupportedLocale
        }

        let transcriber = DictationTranscriber(
            locale: locale,
            preset: .progressiveLongDictation
        )

        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw SpeechTranscriptionError.assetInstallationFailed(error.localizedDescription)
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard isUsableRecordingFormat(inputFormat) else {
            throw unavailableAudioInputError()
        }

        let preferredAudioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: inputFormat
        )
        let targetAudioFormat: AVAudioFormat?
        if let preferredAudioFormat {
            targetAudioFormat = preferredAudioFormat
        } else {
            targetAudioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        }

        guard let targetAudioFormat else {
            throw SpeechTranscriptionError.unsupportedAudioFormat
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = Array(contextualStrings.prefix(100))
            try await analyzer.setContext(context)
        }
        try await analyzer.prepareToAnalyze(in: targetAudioFormat)

        let (inputStream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: inputStream)

        transcriptAssembly.reset()
        onTranscriptUpdate?(transcriptAssembly)

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.inputContinuation = continuation
        self.targetAudioFormat = targetAudioFormat
        self.converter = inputFormat == targetAudioFormat ? nil : AVAudioConverter(from: inputFormat, to: targetAudioFormat)
        self.resultsTask = consumeResults(from: transcriber)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in
                self.processAudioBuffer(buffer)
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.inputContinuation?.finish()
            self.inputContinuation = nil
            self.analyzer = nil
            self.transcriber = nil
            self.resultsTask?.cancel()
            self.resultsTask = nil
            throw SpeechTranscriptionError.failedToStartAudioEngine(error.localizedDescription)
        }

        isRecording = true
    }

    func finishSession() async throws -> String {
        guard isRecording else {
            throw SpeechTranscriptionError.notRecording
        }

        isRecording = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()

        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await analyzer.cancelAndFinishNow()
            }
        }

        _ = await resultsTask?.result

        let text = transcriptAssembly.combinedText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        cleanup()
        return text
    }

    private func cleanup() {
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        inputContinuation = nil
        converter = nil
        targetAudioFormat = nil
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let continuation = inputContinuation else { return }

        onAudioLevelUpdate?(audioLevel(for: buffer))

        guard let transformedBuffer = convertIfNeeded(buffer) else {
            return
        }

        continuation.yield(AnalyzerInput(buffer: transformedBuffer))
    }

    private func convertIfNeeded(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let targetAudioFormat else { return nil }
        guard buffer.format != targetAudioFormat else { return buffer }
        guard let converter else { return nil }

        let frameCapacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * targetAudioFormat.sampleRate / buffer.format.sampleRate)
        )

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetAudioFormat, frameCapacity: max(frameCapacity, 1)) else {
            return nil
        }

        var didSupplyInput = false
        var conversionError: NSError?

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didSupplyInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didSupplyInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil else {
            return nil
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return outputBuffer
        case .error:
            return nil
        @unknown default:
            return nil
        }
    }

    private func consumeResults(from transcriber: DictationTranscriber) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    await MainActor.run {
                        self?.apply(result: result)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.onAudioLevelUpdate?(0)
                    self?.cleanup()
                    self?.isRecording = false
                }
            }
        }
    }

    private func apply(result: DictationTranscriber.Result) {
        let update = TranscriptUpdate(
            text: String(result.text.characters),
            isFinal: result.isFinal
        )

        transcriptAssembly.apply(update)
        onTranscriptUpdate?(transcriptAssembly)
    }

    private func requestSpeechAccessIfNeeded() async -> Bool {
        activateForPermissionPromptIfNeeded()
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else {
            return current == .authorized
        }

        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        return authorization == .authorized
    }

    private func requestMicrophoneAccessIfNeeded() async -> Bool {
        activateForPermissionPromptIfNeeded()

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            ensureMicrophoneRegistration()
            return true
        case .denied:
            return false
        case .undetermined:
            let probeGranted = await attemptMicrophonePromptThroughRecording()
            if probeGranted {
                ensureMicrophoneRegistration()
                return true
            }

            guard AVAudioApplication.shared.recordPermission == .undetermined else {
                return false
            }

            let granted = await AVAudioApplication.requestRecordPermission()
            if granted {
                ensureMicrophoneRegistration()
                return true
            }

            guard AVAudioApplication.shared.recordPermission == .undetermined else {
                return false
            }

            let fallbackGranted = await requestMicrophoneViaCaptureFlow()
            if fallbackGranted {
                ensureMicrophoneRegistration()
            }
            return fallbackGranted
        @unknown default:
            return false
        }
    }

    private func attemptMicrophonePromptThroughRecording() async -> Bool {
        let inputNode = microphoneProbe.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard isUsableRecordingFormat(inputFormat) else {
            return false
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 256, format: inputFormat) { _, _ in }

        defer {
            microphoneProbe.stop()
            inputNode.removeTap(onBus: 0)
        }

        do {
            microphoneProbe.prepare()
            try microphoneProbe.start()
            try? await Task.sleep(for: .milliseconds(350))
        } catch {
            microphoneProbe.stop()
        }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        @unknown default:
            return false
        }
    }

    private func requestMicrophoneViaCaptureFlow() async -> Bool {
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: microphone)
            let session = AVCaptureSession()

            if session.canAddInput(input) {
                session.addInput(input)
            }

            captureProbeSession = session
            session.startRunning()
            session.stopRunning()
            captureProbeSession = nil
        } catch {
            captureProbeSession = nil
        }

        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if currentStatus != .notDetermined {
            return currentStatus == .authorized
        }

        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func ensureMicrophoneRegistration() {
        _ = AVCaptureDevice.default(for: .audio)

        let inputNode = microphoneProbe.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard isUsableRecordingFormat(inputFormat) else {
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 256, format: inputFormat) { _, _ in }

        do {
            microphoneProbe.prepare()
            try microphoneProbe.start()
            microphoneProbe.stop()
        } catch {
            microphoneProbe.stop()
        }

        inputNode.removeTap(onBus: 0)
    }

    private func audioLevel(for buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else {
            return 0
        }

        let channel = channelData[0]
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return 0
        }

        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channel[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameCount))
        let boosted = min(max(Double(rms) * 22.0, 0), 1)
        let normalized = pow(boosted, 0.55)
        return normalized
    }

    private func activateForPermissionPromptIfNeeded() {
        #if os(macOS)
        _ = NSRunningApplication.current.activate(options: [])
        #endif
    }

    private func isUsableRecordingFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }

    private func unavailableAudioInputError() -> SpeechTranscriptionError {
        #if targetEnvironment(simulator)
        return .unavailableAudioInput("Microphone input isn't available in this simulator session. Enable Audio Input for the simulator run destination or use a physical device.")
        #else
        return .unavailableAudioInput("Microphone input isn't available right now. Check your device audio input and try again.")
        #endif
    }

    private func configureAudioSessionIfNeeded() throws {
        #if os(iOS) || os(tvOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true)
        #endif
    }
}
