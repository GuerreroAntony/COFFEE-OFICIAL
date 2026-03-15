import Foundation
import AVFoundation

// MARK: - Audio Recorder
// AVFoundation audio recording for lecture capture
// Records to m4a format (AAC) for WhisperKit compatibility

@Observable
final class AudioRecorder: NSObject {

    enum RecordingState {
        case idle, recording, paused, stopped, error(String)
    }

    var state: RecordingState = .idle
    var currentTime: TimeInterval = 0
    var audioLevel: Float = 0 // 0...1 normalized

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    // MARK: - Permissions

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Recording

    func startRecording() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            state = .error("Erro ao configurar audio: \(error.localizedDescription)")
            return
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        fileURL = documentsPath.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,  // 16kHz for WhisperKit
            AVNumberOfChannelsKey: 1,   // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL!, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            state = .recording
            startTimer()
        } catch {
            state = .error("Erro ao iniciar gravação: \(error.localizedDescription)")
        }
    }

    func pauseRecording() {
        audioRecorder?.pause()
        state = .paused
        timer?.invalidate()
    }

    func resumeRecording() {
        audioRecorder?.record()
        state = .recording
        startTimer()
    }

    func stopRecording() -> URL? {
        audioRecorder?.stop()
        timer?.invalidate()
        state = .stopped

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false)

        return fileURL
    }

    func discardRecording() {
        audioRecorder?.stop()
        timer?.invalidate()

        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }

        state = .idle
        currentTime = 0
        audioLevel = 0
        fileURL = nil
    }

    // MARK: - Timer & Metering

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }

            self.currentTime = recorder.currentTime

            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            // Normalize: -160dB...0dB → 0...1
            let normalized = max(0, min(1, (power + 50) / 50))
            self.audioLevel = normalized
        }
    }

    // MARK: - Cleanup

    func deleteRecordingFile() {
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
            fileURL = nil
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            state = .error("Gravação interrompida inesperadamente")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        state = .error(error?.localizedDescription ?? "Erro de encoding")
    }
}
