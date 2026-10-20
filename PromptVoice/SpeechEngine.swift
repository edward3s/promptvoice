import AVFoundation
import Speech

/// Motor de dictado: micrófono -> SpeechAnalyzer (100% en el dispositivo) -> texto.
@MainActor
@Observable
final class SpeechEngine {
    enum Phase {
        case idle, preparing, recording, finishing
    }

    private(set) var phase: Phase = .idle
    private(set) var liveText = ""
    private(set) var level: Double = 0
    var errorMessage: String?

    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var audioEngine: AVAudioEngine?
    private var audioContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var finalText = ""

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { phase == .preparing || phase == .finishing }
    var isActive: Bool { phase != .idle }

    /// Texto consolidado + lo que se está reconociendo ahora mismo.
    var displayText: String {
        let live = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !live.isEmpty else { return finalText }
        return finalText.isEmpty ? live : finalText + " " + live
    }

    // MARK: - Grabación

    func start(localeIdentifier: String) async {
        guard phase == .idle else { return }
        errorMessage = nil
        finalText = ""
        liveText = ""
        phase = .preparing

        do {
            guard await Platform.requestMicrophonePermission() else {
                throw PromptVoiceError.microphoneDenied
            }

            let transcriber = try await makeTranscriber(localeIdentifier: localeIdentifier)
            self.transcriber = transcriber

            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            #endif

            #if os(macOS)
            guard AVCaptureDevice.default(for: .audio) != nil else { throw PromptVoiceError.noMicrophone }
            #endif

            let audio = AVAudioEngine()
            let input = audio.inputNode
            let naturalFormat = input.outputFormat(forBus: 0)
            guard naturalFormat.sampleRate > 0 else { throw PromptVoiceError.noMicrophone }

            var targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber],
                considering: naturalFormat
            )
            if targetFormat == nil {
                targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            }
            guard let targetFormat else { throw PromptVoiceError.audioSetup }

            let converter: AVAudioConverter?
            if naturalFormat == targetFormat {
                converter = nil
            } else {
                converter = AVAudioConverter(from: naturalFormat, to: targetFormat)
                guard converter != nil else { throw PromptVoiceError.audioSetup }
            }

            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            audioContinuation = continuation

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            resultsTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        if result.isFinal {
                            self.appendFinal(text)
                            self.liveText = ""
                        } else {
                            self.liveText = text
                        }
                    }
                } catch {
                    guard self.phase == .recording else { return }
                    self.errorMessage = "La transcripción se detuvo: \(error.localizedDescription)"
                }
            }

            try await analyzer.start(inputSequence: stream)

            let levelSink: @Sendable (Double) -> Void = { [weak self] value in
                Task { @MainActor in self?.level = value }
            }

            input.installTap(onBus: 0, bufferSize: 4096, format: naturalFormat) { buffer, _ in
                levelSink(Self.normalizedLevel(buffer))
                guard let converter else {
                    continuation.yield(AnalyzerInput(buffer: buffer))
                    return
                }
                if let converted = Self.convert(buffer, using: converter, to: targetFormat) {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
            }

            audio.prepare()
            try audio.start()
            audioEngine = audio
            phase = .recording
        } catch {
            resultsTask?.cancel()
            resultsTask = nil
            await teardown()
            phase = .idle
            errorMessage = (error as? PromptVoiceError)?.message ?? error.localizedDescription
        }
    }

    /// Detiene la grabación y devuelve el texto final.
    func stop() async -> String {
        guard phase == .recording || phase == .preparing else { return "" }
        phase = .finishing

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        audioContinuation?.finish()
        audioContinuation = nil

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        await resultsTask?.value
        resultsTask = nil

        var text = finalText
        let tail = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            text = text.isEmpty ? tail : text + " " + tail
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        await teardown()
        phase = .idle
        finalText = ""
        liveText = ""
        level = 0
        return text
    }

    func cancel() async {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        audioContinuation?.finish()
        audioContinuation = nil
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        resultsTask = nil
        await teardown()
        phase = .idle
        finalText = ""
        liveText = ""
        level = 0
    }

    // MARK: - Modelos de idioma

    private func makeTranscriber(localeIdentifier: String) async throws -> DictationTranscriber {
        let requested = Locale(identifier: localeIdentifier)
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) else {
            throw PromptVoiceError.localeNotSupported(localeIdentifier)
        }

        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        var status = await AssetInventory.status(forModules: [transcriber])

        if status == .unsupported { throw PromptVoiceError.localeNotSupported(localeIdentifier) }

        if status != .installed, let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try? await request.downloadAndInstall()
            status = await AssetInventory.status(forModules: [transcriber])
        }

        // Mientras el sistema termina de descargar, esperamos un poco.
        var waited = 0
        while status == .downloading, waited < 40 {
            try? await Task.sleep(for: .milliseconds(500))
            status = await AssetInventory.status(forModules: [transcriber])
            waited += 1
        }

        guard status != .downloading, status != .unsupported else { throw PromptVoiceError.modelNotReady }

        let reserved = await AssetInventory.reservedLocales
        if !reserved.contains(locale) {
            _ = try? await AssetInventory.reserve(locale: locale)
        }
        return transcriber
    }

    private func teardown() async {
        audioEngine?.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        analyzer = nil
        transcriber = nil
        audioEngine = nil
        audioContinuation = nil
    }

    private func appendFinal(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        guard !finalText.isEmpty else {
            finalText = chunk
            return
        }
        let punctuation = [".", ",", ";", ":", "!", "?", ")"]
        let needsSpace = !finalText.hasSuffix(" ")
            && !chunk.hasPrefix(" ")
            && !chunk.hasPrefix("\n")
            && !punctuation.contains(where: chunk.hasPrefix)
        finalText += needsSpace ? " " + chunk : chunk
    }

    // MARK: - Audio helpers (hilo de audio)

    nonisolated private static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        return min(1, max(0, Double(rms) * 12))
    }

    nonisolated private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}

enum PromptVoiceError: Error {
    case microphoneDenied
    case noMicrophone
    case audioSetup
    case localeNotSupported(String)
    case modelNotReady

    var message: String {
        switch self {
        case .microphoneDenied:
            return "Sin permiso de micrófono. Actívalo en Ajustes del sistema > Privacidad > Micrófono."
        case .noMicrophone:
            return "No se ha detectado ningún micrófono."
        case .audioSetup:
            return "No se pudo preparar el audio de entrada."
        case .localeNotSupported(let id):
            return "El idioma \(id) no está disponible para dictado en este dispositivo."
        case .modelNotReady:
            return "El modelo de dictado aún se está descargando. Prueba de nuevo en unos segundos."
        }
    }
}
