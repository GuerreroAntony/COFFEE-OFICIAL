import Foundation

@MainActor
final class DisciplinasViewModel: ObservableObject {
    @Published var disciplinas: [Disciplina] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadDisciplinas() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            disciplinas = try await DisciplinasService.shared.fetchDisciplinas()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func criar(nome: String, professor: String, semestre: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let nova = try await DisciplinasService.shared.criar(nome: nome, professor: professor, semestre: semestre)
            disciplinas.append(nova)
        } catch let e as CoffeeAPIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
