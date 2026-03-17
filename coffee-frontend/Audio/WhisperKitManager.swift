import Foundation
import AVFoundation
import Speech

// MARK: - WhisperKit Manager
// Real-time Portuguese speech-to-text using Apple SFSpeechRecognizer
// Uses .voiceChat mode for AGC, noise suppression, and echo cancellation
// Buffer size 4096 optimized for speech recognition accuracy

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

    // MARK: - Load Model / Request Permissions

    func loadModel() async {
        state = .loading

        // Request speech recognition authorization
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
    /// Uses Apple's SFSpeechRecognizer for real-time Portuguese speech-to-text.
    /// Audio is NOT recorded by this class — use AudioRecorder in parallel for that.
    func startRealtimeTranscription(onUpdate: @escaping (String) -> Void) throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .error("Reconhecimento de fala indisponivel")
            return
        }

        state = .transcribing
        transcription = ""

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
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
            // Normalize RMS to 0...1 range (typical speech RMS ~0.01-0.15)
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
                let text = result.bestTranscription.formattedString
                self.transcription = text
                onUpdate(text)
            }

            if let error {
                // Speech recognition has a ~1 minute limit per task.
                // When it times out, we restart automatically.
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    // Recognition timed out — restart
                    self.restartRecognition(onUpdate: onUpdate)
                } else {
                    print("[WhisperKit] Recognition error: \(error.localizedDescription)")
                }
            }

            if result?.isFinal == true {
                // Final result received — restart for continuous transcription
                self.restartRecognition(onUpdate: onUpdate)
            }
        }
    }

    // MARK: - Restart Recognition (for continuous transcription beyond 1-min limit)

    private func restartRecognition(onUpdate: @escaping (String) -> Void) {
        let previousText = transcription

        // Clean up current session
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil

        // Only restart if we're still supposed to be transcribing
        guard state == .transcribing else { return }

        // Small delay before restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.state == .transcribing else { return }

            do {
                try self.startRealtimeTranscription { [weak self] newText in
                    guard let self else { return }
                    // Append new text to previous transcription
                    if !previousText.isEmpty && !newText.isEmpty {
                        self.transcription = previousText + " " + newText
                    } else {
                        self.transcription = previousText + newText
                    }
                    onUpdate(self.transcription)
                }
            } catch {
                print("[WhisperKit] Failed to restart recognition: \(error)")
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
    }
}
