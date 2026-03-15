import Foundation

// MARK: - WhisperKit Manager
// On-device speech-to-text using WhisperKit (CoreML)
// whisper-tiny (~39MB) for preview, whisper-base (~74MB) for final
// Audio never leaves the device

@Observable
final class WhisperKitManager {

    enum TranscriptionState {
        case idle
        case loading    // Model loading
        case ready      // Model loaded, ready to transcribe
        case transcribing
        case completed
        case error(String)
    }

    var state: TranscriptionState = .idle
    var transcription: String = ""
    var progress: Double = 0 // 0...1
    var isModelLoaded = false

    // Model configuration
    private let modelName = "whisper-tiny" // ~39MB, fast preview
    // Use "whisper-base" (~74MB) for final transcription quality

    // MARK: - Initialize Model

    /// Load the WhisperKit model
    /// In production, this uses WhisperKit SPM package
    /// For now, this is a mock implementation
    func loadModel() async {
        state = .loading

        // Simulate model loading time
        try? await Task.sleep(for: .seconds(2))

        isModelLoaded = true
        state = .ready
    }

    // MARK: - Transcribe Audio File

    /// Transcribe an audio file to text
    /// - Parameter audioURL: URL of the audio file (m4a, wav, etc.)
    /// - Returns: Transcribed text
    func transcribe(audioURL: URL) async -> String {
        if !isModelLoaded {
            await loadModel()
        }

        state = .transcribing
        progress = 0
        transcription = ""

        // Mock transcription — in production, use WhisperKit:
        // let whisper = try await WhisperKit(model: modelName)
        // let result = try await whisper.transcribe(audioPath: audioURL.path)
        // return result.text

        // Simulate progressive transcription
        let mockSegments = [
            "Bom dia a todos, vamos começar a aula de hoje.",
            " O tema que vamos abordar é muito importante para a prova.",
            " Vamos revisar os conceitos fundamentais primeiro.",
            " Como vimos na última aula, existem três pilares principais.",
            " O primeiro pilar é a análise de mercado.",
            " Precisamos entender o comportamento do consumidor.",
            " Vamos ver alguns exemplos práticos agora.",
            " Observem este gráfico na tela.",
            " A curva de demanda mostra uma tendência clara.",
            " Alguma dúvida até aqui?",
        ]

        for (index, segment) in mockSegments.enumerated() {
            try? await Task.sleep(for: .milliseconds(500))
            transcription += segment
            progress = Double(index + 1) / Double(mockSegments.count)
        }

        state = .completed
        return transcription
    }

    // MARK: - Real-time Preview Transcription

    /// Start streaming transcription from microphone
    /// Uses whisper-tiny for fast preview
    func startRealtimeTranscription() async -> AsyncStream<String> {
        if !isModelLoaded {
            await loadModel()
        }

        return AsyncStream { continuation in
            // In production, use WhisperKit's streaming API:
            // whisperKit.transcribeStream(...)

            // Mock streaming
            Task {
                let phrases = [
                    "Bom dia a todos...",
                    " vamos começar a aula de hoje.",
                    " O tema de hoje é marketing digital.",
                    " Vamos falar sobre os 4Ps.",
                ]

                for phrase in phrases {
                    try? await Task.sleep(for: .seconds(3))
                    continuation.yield(phrase)
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Cleanup

    func reset() {
        state = .idle
        transcription = ""
        progress = 0
    }
}
