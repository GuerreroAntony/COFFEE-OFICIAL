import AVFoundation
import Combine

final class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0

    private(set) var audioEngine = AVAudioEngine()

    var engine: AVAudioEngine { audioEngine }
    private var mixerNode = AVAudioMixerNode()
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var timer: AnyCancellable?

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Recording

    func startRecording() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true)

        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        outputURL = url

        audioEngine = AVAudioEngine()
        mixerNode = AVAudioMixerNode()
        // Note: audioEngine is reassigned here; callers that cache `engine`
        // must re-read it after startRecording() returns.

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        audioEngine.attach(mixerNode)
        audioEngine.connect(inputNode, to: mixerNode, format: inputFormat)

        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!

        audioFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)

        mixerNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }

        try audioEngine.start()
        isRecording = true
        duration = 0

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.duration += 1 }

        return url
    }

    func stopRecording() -> URL? {
        guard isRecording else { return nil }

        timer?.cancel()
        timer = nil

        mixerNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false)
        return outputURL
    }
}
