// NOTE: Requires WhisperKit Swift Package.
// Add via Xcode → File → Add Package Dependencies:
//   https://github.com/argmaxinc/WhisperKit  (Up To Next Major, from 0.9.0)
// Then add WhisperKit to the "Coffee" target.

import Foundation
import AVFoundation
import WhisperKit

@MainActor
final class WhisperLiveService: ObservableObject {
    @Published var liveText = ""

    private var whisperKit: WhisperKit?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var transcribeTask: Task<Void, Never>?
    private var tapInstalled = false
    private weak var tappedInputNode: AVAudioInputNode?

    // MARK: - Prepare (downloads model once, ~40MB)

    func prepare() async {
        guard whisperKit == nil else { return }
        whisperKit = try? await WhisperKit(model: "openai_whisper-tiny")
    }

    // MARK: - Start / Stop

    /// Call after `AudioRecorder.startRecording()` so the engine is live.
    func startLiveTranscription(engine: AVAudioEngine) {
        guard whisperKit != nil, !tapInstalled else { return }

        let inputNode = engine.inputNode
        tappedInputNode = inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let sampleRate = Float(format.sampleRate)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: count))
            self.bufferLock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.bufferLock.unlock()
        }
        tapInstalled = true

        transcribeTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await transcribeAccumulated(sampleRate: sampleRate)
            }
        }
    }

    func stop() {
        transcribeTask?.cancel()
        transcribeTask = nil
        if tapInstalled {
            tappedInputNode?.removeTap(onBus: 0)
        }
        tapInstalled = false
        tappedInputNode = nil
        bufferLock.lock()
        audioBuffer = []
        bufferLock.unlock()
        liveText = ""
    }

    // MARK: - Private

    private func transcribeAccumulated(sampleRate: Float) async {
        bufferLock.lock()
        let samples = audioBuffer
        bufferLock.unlock()

        // Need at least 1 second of audio before transcribing
        guard Float(samples.count) >= sampleRate else { return }

        guard let result = try? await whisperKit?.transcribe(audioArray: samples) else { return }
        let text = result.map(\.text).joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            liveText = trimmed
        }
    }
}
