import Foundation

@MainActor
final class ResumoViewModel: ObservableObject {
    @Published var resumo: Resumo?
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var errorMessage: String?

    func load(transcricaoId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            resumo = try await ResumosService.shared.buscar(transcricaoId: transcricaoId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func gerar(transcricaoId: UUID) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            resumo = try await ResumosService.shared.gerar(transcricaoId: transcricaoId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
