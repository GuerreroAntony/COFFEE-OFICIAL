import Foundation
import AVFoundation
import Accelerate

// MARK: - Audio Quality Analyzer
// Analyzes recorded audio to produce a quality score (0.0-1.0).
// Uses Accelerate framework for fast DSP: VAD, SNR, duration scoring.

enum AudioQualityAnalyzer {

    /// Analyze audio file and return quality score (0.0-1.0).
    /// Score = 0.4 * VAD + 0.4 * SNR_normalized + 0.2 * duration_score
    static func calculateQualityScore(
        audioURL: URL,
        expectedDurationSeconds: Int = 3000
    ) -> Double {
        guard let samples = loadAudioSamples(from: audioURL) else {
            return 0.0
        }

        let sampleRate: Double = 16000
        let actualDuration = Double(samples.count) / sampleRate

        // Frame-level energy analysis (20ms frames)
        let frameSamples = Int(sampleRate * 0.02)  // 320 samples per frame
        let frameCount = samples.count / frameSamples
        guard frameCount > 0 else { return 0.0 }

        // Compute RMS energy per frame using vDSP
        var frameEnergies = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let offset = i * frameSamples
            var rms: Float = 0
            samples.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                vDSP_rmsqv(base.advanced(by: offset), 1, &rms, vDSP_Length(frameSamples))
            }
            frameEnergies[i] = rms
        }

        // Adaptive threshold: median energy * 2
        let sortedEnergies = frameEnergies.sorted()
        let medianEnergy = sortedEnergies[frameCount / 2]
        let threshold = medianEnergy * 2.0

        // VAD: classify frames as speech vs silence
        var speechFrames = 0
        var speechEnergySum: Float = 0
        var silenceEnergySum: Float = 0
        var silenceFrames = 0

        for energy in frameEnergies {
            if energy > threshold {
                speechFrames += 1
                speechEnergySum += energy * energy
            } else {
                silenceFrames += 1
                silenceEnergySum += energy * energy
            }
        }

        // VAD score (% of frames with speech)
        let vadScore = Double(speechFrames) / Double(frameCount)

        // SNR (Signal-to-Noise Ratio)
        let meanSpeechEnergy = speechFrames > 0 ? speechEnergySum / Float(speechFrames) : 0
        let meanSilenceEnergy = silenceFrames > 0 ? silenceEnergySum / Float(silenceFrames) : 1e-10
        let snrDb = 10.0 * log10(Double(max(meanSpeechEnergy, 1e-10)) / Double(max(meanSilenceEnergy, 1e-10)))
        // Normalize: 5dB = 0.0, 30dB = 1.0
        let snrNormalized = min(1.0, max(0.0, (snrDb - 5.0) / 25.0))

        // Duration score (penalty if < 50% of expected)
        let expectedDuration = Double(expectedDurationSeconds)
        let durationScore = min(1.0, actualDuration / (expectedDuration * 0.5))

        // Final score
        let score = 0.4 * vadScore + 0.4 * snrNormalized + 0.2 * durationScore
        return min(1.0, max(0.0, score))
    }

    // MARK: - Audio Loading

    /// Load audio file as Float32 PCM samples
    private static func loadAudioSamples(from url: URL) -> [Float]? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }

        do {
            try audioFile.read(into: buffer)
        } catch {
            return nil
        }

        guard let channelData = buffer.floatChannelData else { return nil }
        let samples = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(buffer.frameLength)
        ))
        return samples
    }
}
