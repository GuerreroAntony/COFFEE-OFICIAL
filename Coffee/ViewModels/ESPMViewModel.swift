import Foundation

@MainActor
class ESPMViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isConnected = false

    func connect(login: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await ESPMService.shared.connectPortal(login: login, password: password)
            isConnected = true

            // Schedule class reminders after ESPM sync
            if let disciplinas = try? await DisciplinasService.shared.fetchDisciplinas() {
                ClassReminderService.shared.scheduleReminders(disciplinas: disciplinas)
            }
        } catch let error as CoffeeAPIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
