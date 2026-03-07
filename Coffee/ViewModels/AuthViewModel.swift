import Foundation
import SwiftUI
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var needsESPMOnboarding = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false

    var needsOnboarding: Bool {
        isAuthenticated && !hasCompletedOnboarding
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .coffeeUnauthorized)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.logout() }
            .store(in: &cancellables)
    }

    func checkAuthOnLaunch() async {
        isLoading = true
        defer { isLoading = false }
        if let user = await AuthService.shared.checkAuth() {
            currentUser = user
            isAuthenticated = true

            // Refresh class reminders on launch
            if let disciplinas = try? await DisciplinasService.shared.fetchDisciplinas() {
                ClassReminderService.shared.scheduleReminders(disciplinas: disciplinas)
            }
        }
    }

    func login(email: String, senha: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let user = try await AuthService.shared.login(email: email, senha: senha)
            currentUser = user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signup(nome: String, email: String, senha: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let user = try await AuthService.shared.signup(nome: nome, email: email, senha: senha)
            currentUser = user
            isAuthenticated = true
            needsESPMOnboarding = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeESPMOnboarding() {
        needsESPMOnboarding = false
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func logout() {
        AuthService.shared.logout()
        PushNotificationService.shared.unregisterToken()
        ClassReminderService.shared.cancelAllReminders()
        currentUser = nil
        isAuthenticated = false
        needsESPMOnboarding = false
        hasCompletedOnboarding = false
    }
}
