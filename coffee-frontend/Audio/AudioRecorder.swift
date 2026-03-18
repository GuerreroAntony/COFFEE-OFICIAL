import Foundation
import AVFoundation

// MARK: - Audio Recorder
// AVFoundation audio recording for lecture capture
// Records to m4a format (AAC 16kHz mono) optimized for cloud transcription

@Observable
final class AudioRecorder: NSObject {

    enum RecordingState {
        case idle, recording, paused, stopped, error(String)
    }

    var state: RecordingState = .idle
    var currentTime: TimeInterval = 0
    var audioLevel: Float = 0 // 0...1 normalized

    /// Public access to the recorded file URL for upload
    var currentFileURL: URL? { fileURL }

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    override init() {
        super.init()
        // Listen for audio session interruptions (phone calls, alarms)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

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
            // .record category + .measurement mode = maximum mic sensitivity,
            // no signal processing (AGC, noise reduction off).
            // Ideal for capturing distant audio (professor in lecture hall).
            // Audio is NOT played back — only recorded for cloud transcription.
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error("Erro ao configurar audio: \(error.localizedDescription)")
            return
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        fileURL = documentsPath.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,  // 16kHz — optimal for speech transcription
            AVNumberOfChannelsKey: 1,   // Mono — reduces file size, speech is mono
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64000, // 64kbps — good quality, ~24MB per 50min
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
        // Re-activate audio session (may have been deactivated by interruption)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

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

    // MARK: - Interruption Handling

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            // Phone call, alarm, etc. — auto-pause
            if case .recording = state {
                pauseRecording()
                print("[AudioRecorder] Interrupted — paused recording")
            }
        case .ended:
            // Interruption ended — check if we should resume
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume), case .paused = state {
                    resumeRecording()
                    print("[AudioRecorder] Interruption ended — resumed recording")
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Timer & Metering

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }

            self.currentTime = recorder.currentTime

            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            // Exaggerated response: any sound should make the waveform jump.
            // Distant lecture mic: -45dB (silence) to -10dB (loud).
            // Map -40...-8 → 0...1, then boost aggressively.
            let clamped = max(-40.0, min(-8.0, power))
            let linear = (clamped + 40.0) / 32.0  // 0...1
            // Aggressive exponential: pow(0.35) makes even whispers visible
            let curved = pow(linear, 0.35)
            // Boost: multiply by 1.4 and clamp — any real sound hits 0.5+
            let boosted = min(1.0, curved * 1.4)
            // Fast attack (0.85), slower decay (0.4) — snappy response
            let blend: Float = Float(boosted) > self.audioLevel ? 0.85 : 0.4
            let smoothed = self.audioLevel * (1.0 - blend) + Float(boosted) * blend
            self.audioLevel = smoothed
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
