import Foundation
import AVFoundation

@MainActor
class GravacaoViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isUploading = false
    @Published var isGeneratingResumo = false
    @Published var duration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var uploadedGravacao: Gravacao?
    @Published var resumo: Resumo?

    private let recorder = AudioRecorder()
    private var recordedURL: URL?

    /// Exposes the underlying AVAudioEngine (valid after startRecording())
    var audioEngine: AVAudioEngine { recorder.engine }

    var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    func requestPermission() async -> Bool {
        await recorder.requestPermission()
    }

    func startRecording() {
        do {
            recordedURL = try recorder.startRecording()
            isRecording = true
        } catch {
            errorMessage = "Não foi possível iniciar a gravação: \(error.localizedDescription)"
        }
    }

    func stopRecording() -> URL? {
        let url = recorder.stopRecording()
        isRecording = false
        return url
    }

    // Observes recorder duration
    func observeDuration() {
        recorder.$duration
            .receive(on: RunLoop.main)
            .assign(to: &$duration)
    }

    func uploadRecording(fileURL: URL, disciplinaId: UUID, dataAula: Date) async {
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            let gravacao = try await GravacoesService.shared.criar(
                disciplinaId: disciplinaId,
                dataAula: dataAula
            )
            let completed = try await GravacoesService.shared.upload(
                gravacaoId: gravacao.id,
                fileURL: fileURL
            )
            uploadedGravacao = completed
            if let transcricaoId = completed.transcricao?.id {
                await gerarResumo(transcricaoId: transcricaoId)
            }
        } catch let e as CoffeeAPIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func gerarResumo(transcricaoId: UUID) async {
        isGeneratingResumo = true
        defer { isGeneratingResumo = false }
        resumo = try? await ResumosService.shared.gerar(transcricaoId: transcricaoId)
    }
}
