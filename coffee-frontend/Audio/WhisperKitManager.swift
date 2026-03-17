import Foundation
import AVFoundation
import Speech

// MARK: - WhisperKit Manager
// Real-time Portuguese speech-to-text using Apple SFSpeechRecognizer
// Optimized for LECTURE RECORDING: .measurement mode for maximum mic sensitivity,
// input gain at 1.0, taskHint = .dictation for continuous speech.
// Uses APPEND-ONLY transcription: once a word is recognized, it's never deleted.
// Apple's recognizer auto-corrects/removes words in partial results — we prevent
// that by locking segments once they stabilize. GPT handles cleanup later.

@Observable
final class WhisperKitManager {

    enum TranscriptionState: Equatable {
        case idle
        case loading
        case ready
        case transcribing
        case completed
        case error(String)
    }

    var state: TranscriptionState = .idle
    var transcription: String = ""
    var isModelLoaded = false
    var audioLevel: Float = 0 // 0...1 normalized, updated from audio buffer

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))

    // MARK: - Append-only segment tracking
    // Segments that have been stable across updates get "locked" and never removed.
    // Only the tail (last 1-2 segments) can be revised by Apple's recognizer.
    private var lockedText: String = ""           // confirmed text from previous sessions + locked segments
    private var committedSegmentCount: Int = 0    // how many segments from current session are locked
    private var previousSegmentTexts: [String] = [] // segment texts from last partial result (for stability comparison)

    // MARK: - Load Model / Request Permissions

    func loadModel() async {
        state = .loading

        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        if authorized {
            isModelLoaded = true
            state = .ready
        } else {
            state = .error("Permissao de reconhecimento de fala negada")
        }
    }

    // MARK: - Start Real-time Transcription

    /// Starts listening to microphone and calls onUpdate with cumulative transcription text.
    /// Uses append-only mode: words are never deleted from transcription.
    /// Pass `baseText` to preserve text from previous sessions (pause/resume, camera, restart).
    func startRealtimeTranscription(baseText: String = "", onUpdate: @escaping (String) -> Void) throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .error("Reconhecimento de fala indisponivel")
            return
        }

        state = .transcribing
        lockedText = baseText
        committedSegmentCount = 0
        previousSegmentTexts = []
        transcription = baseText

        let audioSession = AVAudioSession.sharedInstance()
        // .measurement = raw audio, maximum sensitivity, no echo cancellation or AGC
        // Critical for lectures: professor is meters away, we need every sound captured
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Maximize analog input gain (hardware amplification)
        if audioSession.isInputGainSettable {
            try audioSession.setInputGain(1.0)
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation  // Optimized for continuous speech (lectures)
        if #available(iOS 16, *) {
            recognitionRequest.addsPunctuation = true
        }

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            recognitionRequest.append(buffer)

            // Compute RMS audio level from buffer
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrtf(sum / Float(max(frameLength, 1)))
            let normalized = min(1.0, rms * 8)
            DispatchQueue.main.async {
                self?.audioLevel = normalized
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let segments = result.bestTranscription.segments
                let segmentTexts = segments.map { $0.substring }

                // --- Append-only logic ---
                // Find how many segments from the start match the previous update.
                // Segments that haven't changed are "stable" and can be locked.
                var matchCount = 0
                for i in 0..<min(segmentTexts.count, self.previousSegmentTexts.count) {
                    if segmentTexts[i] == self.previousSegmentTexts[i] {
                        matchCount = i + 1
                    } else {
                        break
                    }
                }

                // Lock segments that are stable AND not in the tail (last 1 segment can still be revised)
                let lockUpTo = max(self.committedSegmentCount, min(matchCount, max(0, segmentTexts.count - 1)))

                if lockUpTo > self.committedSegmentCount {
                    let newLocked = segmentTexts[self.committedSegmentCount..<lockUpTo].joined(separator: " ")
                    if !self.lockedText.isEmpty && !newLocked.isEmpty {
                        self.lockedText += " " + newLocked
                    } else if !newLocked.isEmpty {
                        self.lockedText = newLocked
                    }
                    self.committedSegmentCount = lockUpTo
                }

                // Build full text: locked (permanent) + live tail (can still change)
                let tailSegments = segmentTexts.count > self.committedSegmentCount
                    ? Array(segmentTexts[self.committedSegmentCount...])
                    : []
                let liveText = tailSegments.joined(separator: " ")

                let fullText: String
                if !self.lockedText.isEmpty && !liveText.isEmpty {
                    fullText = self.lockedText + " " + liveText
                } else {
                    fullText = self.lockedText + liveText
                }

                self.transcription = fullText
                onUpdate(fullText)
                self.previousSegmentTexts = segmentTexts
            }

            if let error {
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    // Recognition timed out (~60s limit) — restart automatically
                    self.restartRecognition(onUpdate: onUpdate)
                } else if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 209 {
                    // Audio session was interrupted (e.g. camera opened) — will be resumed externally
                    print("[WhisperKit] Audio interrupted (code 209), waiting for resume...")
                    self.stopEngine()
                } else {
                    print("[WhisperKit] Recognition error: \(error.localizedDescription) (code: \(nsError.code))")
                    // Try to restart on unknown errors too
                    self.restartRecognition(onUpdate: onUpdate)
                }
            }

            if result?.isFinal == true {
                self.restartRecognition(onUpdate: onUpdate)
            }
        }
    }

    // MARK: - Restart Recognition (for continuous transcription beyond 1-min limit)

    private func restartRecognition(onUpdate: @escaping (String) -> Void) {
        // Lock in ALL current text before restarting
        let currentText = transcription

        stopEngine()

        guard state == .transcribing else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.state == .transcribing else { return }

            do {
                try self.startRealtimeTranscription(baseText: currentText, onUpdate: onUpdate)
            } catch {
                print("[WhisperKit] Failed to restart recognition: \(error)")
            }
        }
    }

    // MARK: - Resume After Interruption (camera, phone call, etc.)

    /// Resumes transcription after an external interruption (e.g. camera opened).
    /// Preserves all previously captured text. Call this when the interrupting
    /// activity (camera, etc.) is dismissed.
    func resumeAfterInterruption(onUpdate: @escaping (String) -> Void) {
        guard state == .transcribing || state == .completed else { return }

        let currentText = transcription
        stopEngine()
        state = .transcribing

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }

            do {
                try self.startRealtimeTranscription(baseText: currentText, onUpdate: onUpdate)
                print("[WhisperKit] Resumed after interruption with \(currentText.split(separator: " ").count) words preserved")
            } catch {
                print("[WhisperKit] Failed to resume after interruption: \(error)")
                // Keep the text even if we can't restart
                self.transcription = currentText
            }
        }
    }

    // MARK: - Stop Transcription

    @discardableResult
    func stopRealtimeTranscription() -> String {
        state = .completed
        stopEngine()
        return transcription
    }

    private func stopEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        audioLevel = 0
        recognitionRequest = nil
        audioEngine = nil
    }

    // MARK: - Reset

    func reset() {
        _ = stopRealtimeTranscription()
        state = .idle
        transcription = ""
        lockedText = ""
        committedSegmentCount = 0
        previousSegmentTexts = []
    }
}
