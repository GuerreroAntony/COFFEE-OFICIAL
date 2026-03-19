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

    /// Increments when an interruption auto-pauses/resumes. Observe this to sync UI.
    var interruptionEvent: Int = 0

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
            // .playAndRecord required for AVAudioRecorder to capture audio.
            // .default mode keeps AGC + noise reduction ON — helps clean audio
            // before sending to GPT-4o Transcribe (server handles the rest).
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
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
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL!, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            let started = audioRecorder?.record() ?? false

            if !started {
                state = .error("Não foi possível iniciar a gravação")
                return
            }

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
                interruptionEvent += 1
            }
        case .ended:
            // Interruption ended — check if we should resume
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume), case .paused = state {
                    resumeRecording()
                    interruptionEvent += 1
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Timer & Metering

    private func startTimer() {
        timer?.invalidate()
        // Use DisplayLink-style timer on main RunLoop to ensure it fires
        // even when called from async Task context
        let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }

            self.currentTime = recorder.currentTime

            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            // Natural response: reacts to voice without being jumpy.
            // Map -50...-5 dB → 0...1 with gentle curve.
            let clamped = max(-50.0, min(-5.0, power))
            let linear = (clamped + 50.0) / 45.0
            let curved = pow(linear, 0.6)
            // Smooth attack/decay for fluid movement
            let blend: Float = Float(curved) > self.audioLevel ? 0.5 : 0.25
            let smoothed = self.audioLevel * (1.0 - blend) + Float(curved) * blend
            self.audioLevel = smoothed
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
