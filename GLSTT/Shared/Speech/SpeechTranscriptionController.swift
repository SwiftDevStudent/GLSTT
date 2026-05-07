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
    case audioFileUnavailable(String)
    case audioFileTranscriptionFailed(String)

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
        case .audioFileUnavailable(let detail):
            return "Unable to open that audio file: \(detail)"
        case .audioFileTranscriptionFailed(let detail):
            return "Unable to transcribe that audio file: \(detail)"
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

    private struct SplitAudioChannels {
        let directoryURL: URL
        let person1URL: URL
        let person2URL: URL
    }

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

    func transcribeAudioFile(
        at url: URL,
        locale requestedLocale: Locale? = nil,
        contextualStrings: [String] = [],
        onTranscriptUpdate fileTranscriptUpdateHandler: ((TranscriptAssembly) -> Void)? = nil
    ) async throws -> AudioFileTranscriptionResult {
        guard !isRecording else {
            throw SpeechTranscriptionError.alreadyRecording
        }

        guard await requestSpeechAccessIfNeeded() else {
            throw SpeechTranscriptionError.speechPermissionDenied
        }

        let didAccessSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw SpeechTranscriptionError.audioFileUnavailable(error.localizedDescription)
        }

        guard isUsableRecordingFormat(audioFile.processingFormat) else {
            throw SpeechTranscriptionError.unsupportedAudioFormat
        }

        if audioFile.processingFormat.channelCount >= 2 {
            do {
                let splitChannels = try splitFirstTwoAudioChannels(from: audioFile)
                defer {
                    try? FileManager.default.removeItem(at: splitChannels.directoryURL)
                }

                return try await transcribeSplitAudioChannels(
                    splitChannels,
                    locale: requestedLocale,
                    contextualStrings: contextualStrings,
                    updateHandler: fileTranscriptUpdateHandler
                )
            } catch {
                audioFile.framePosition = 0
            }
        }

        return try await transcribePreparedAudioFile(
            audioFile,
            locale: requestedLocale,
            contextualStrings: contextualStrings,
            updateHandler: fileTranscriptUpdateHandler
        )
    }

    private func transcribeSplitAudioChannels(
        _ channels: SplitAudioChannels,
        locale requestedLocale: Locale?,
        contextualStrings: [String],
        updateHandler: ((TranscriptAssembly) -> Void)?
    ) async throws -> AudioFileTranscriptionResult {
        let person1File = try AVAudioFile(forReading: channels.person1URL)
        var person1Preview = ""
        let person1Result = try await transcribePreparedAudioFile(
            person1File,
            locale: requestedLocale,
            contextualStrings: contextualStrings
        ) { [weak self] assembly in
            person1Preview = assembly.combinedText
            self?.emitFileTranscriptUpdate(
                Self.speakerTranscript(person1: person1Preview, person2: ""),
                to: updateHandler
            )
        }

        let person2File = try AVAudioFile(forReading: channels.person2URL)
        var person2Preview = ""
        let person2Result = try await transcribePreparedAudioFile(
            person2File,
            locale: requestedLocale,
            contextualStrings: contextualStrings
        ) { [weak self] assembly in
            person2Preview = assembly.combinedText
            self?.emitFileTranscriptUpdate(
                Self.speakerTranscript(person1: person1Result.text, person2: person2Preview),
                to: updateHandler
            )
        }

        let text = Self.speakerTranscript(person1: person1Result.text, person2: person2Result.text)
        let segments = person1Result.segments.map { segment in
            TimedTranscriptSegment(
                speaker: "Person 1",
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text
            )
        } + person2Result.segments.map { segment in
            TimedTranscriptSegment(
                speaker: "Person 2",
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text
            )
        }

        return AudioFileTranscriptionResult(text: text, segments: segments)
    }

    private func transcribePreparedAudioFile(
        _ audioFile: AVAudioFile,
        locale requestedLocale: Locale?,
        contextualStrings: [String],
        updateHandler fileTranscriptUpdateHandler: ((TranscriptAssembly) -> Void)?
    ) async throws -> AudioFileTranscriptionResult {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale ?? Locale.current) else {
            throw SpeechTranscriptionError.unsupportedLocale
        }

        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw SpeechTranscriptionError.assetInstallationFailed(error.localizedDescription)
        }

        let preferredAudioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: audioFile.processingFormat
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

        fileTranscriptUpdateHandler?(TranscriptAssembly())
        let resultsTask = consumeFileResults(
            from: transcriber,
            updateHandler: fileTranscriptUpdateHandler
        )

        do {
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let fileTranscriptAssembly = try await resultsTask.value
            return AudioFileTranscriptionResult(
                text: fileTranscriptAssembly.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ,
                segments: fileTranscriptAssembly.segments
            )
        } catch {
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw SpeechTranscriptionError.audioFileTranscriptionFailed(error.localizedDescription)
        }
    }

    private func splitFirstTwoAudioChannels(from audioFile: AVAudioFile) throws -> SplitAudioChannels {
        let sourceFormat = audioFile.processingFormat
        guard sourceFormat.channelCount >= 2 else {
            throw SpeechTranscriptionError.unsupportedAudioFormat
        }

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw SpeechTranscriptionError.unsupportedAudioFormat
        }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GLSTT-AudioChannels-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let person1URL = directoryURL.appendingPathComponent("Person-1.caf")
        let person2URL = directoryURL.appendingPathComponent("Person-2.caf")
        let person1File = try AVAudioFile(forWriting: person1URL, settings: monoFormat.settings)
        let person2File = try AVAudioFile(forWriting: person2URL, settings: monoFormat.settings)

        audioFile.framePosition = 0

        let chunkFrameCount: AVAudioFrameCount = 16_384
        while audioFile.framePosition < audioFile.length {
            let remainingFrames = audioFile.length - audioFile.framePosition
            let framesToRead = AVAudioFrameCount(min(Int64(chunkFrameCount), remainingFrames))
            guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: framesToRead) else {
                throw SpeechTranscriptionError.unsupportedAudioFormat
            }

            try audioFile.read(into: sourceBuffer, frameCount: framesToRead)
            guard sourceBuffer.frameLength > 0 else { break }

            guard
                let sourceChannels = sourceBuffer.floatChannelData,
                let person1Buffer = monoBuffer(format: monoFormat, frameLength: sourceBuffer.frameLength),
                let person2Buffer = monoBuffer(format: monoFormat, frameLength: sourceBuffer.frameLength),
                let person1Channel = person1Buffer.floatChannelData?[0],
                let person2Channel = person2Buffer.floatChannelData?[0]
            else {
                throw SpeechTranscriptionError.unsupportedAudioFormat
            }

            let frameLength = Int(sourceBuffer.frameLength)
            person1Channel.update(from: sourceChannels[0], count: frameLength)
            person2Channel.update(from: sourceChannels[1], count: frameLength)
            try person1File.write(from: person1Buffer)
            try person2File.write(from: person2Buffer)
        }

        audioFile.framePosition = 0

        return SplitAudioChannels(
            directoryURL: directoryURL,
            person1URL: person1URL,
            person2URL: person2URL
        )
    }

    private func monoBuffer(format: AVAudioFormat, frameLength: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }

        buffer.frameLength = frameLength
        return buffer
    }

    private func emitFileTranscriptUpdate(_ text: String, to updateHandler: ((TranscriptAssembly) -> Void)?) {
        var assembly = TranscriptAssembly()
        assembly.apply(TranscriptUpdate(text: text, isFinal: true))
        updateHandler?(assembly)
    }

    private static func speakerTranscript(person1: String, person2: String) -> String {
        let trimmedPerson1 = person1.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPerson2 = person2.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = []

        if !trimmedPerson1.isEmpty {
            sections.append("Person 1:\n\(trimmedPerson1)")
        }

        if !trimmedPerson2.isEmpty {
            sections.append("Person 2:\n\(trimmedPerson2)")
        }

        return sections.joined(separator: "\n\n")
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

    private func consumeFileResults(
        from transcriber: DictationTranscriber,
        updateHandler: ((TranscriptAssembly) -> Void)?
    ) -> Task<(text: String, segments: [TimedTranscriptSegment]), Error> {
        Task { @MainActor in
            var fileTranscriptAssembly = TranscriptAssembly()
            var timedSegments: [TimedTranscriptSegment] = []

            for try await result in transcriber.results {
                let update = TranscriptUpdate(
                    text: String(result.text.characters),
                    isFinal: result.isFinal
                )
                fileTranscriptAssembly.apply(update)
                if result.isFinal {
                    timedSegments.append(contentsOf: Self.timedSegments(from: result.text))
                }
                updateHandler?(fileTranscriptAssembly)
            }

            return (fileTranscriptAssembly.combinedText, timedSegments)
        }
    }

    private static func timedSegments(from text: AttributedString) -> [TimedTranscriptSegment] {
        text.runs.compactMap { run in
            let segmentText = String(text[run.range].characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segmentText.isEmpty else { return nil }

            let timeRange = run.audioTimeRange
            return TimedTranscriptSegment(
                speaker: nil,
                startTime: timeRange?.start.seconds,
                endTime: timeRange.map { $0.start.seconds + $0.duration.seconds },
                text: segmentText
            )
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
