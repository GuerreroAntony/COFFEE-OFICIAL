import SwiftUI

// MARK: - Navigation Router
// Centralized navigation state — replaces React's useState in App.jsx
// Uses @Observable (iOS 17+) for clean reactive updates

@Observable
final class NavigationRouter {

    // MARK: - Auth State

    enum AuthState {
        case splash
        case onboarding
        case login
        case signup
        case linkESPM
        case premiumOffer
        case authenticated
    }

    var authState: AuthState = .splash
    var currentUser: User? = nil

    // MARK: - Tab State

    enum Tab: String, CaseIterable {
        case home = "home"
        case record = "gravar"
        case ai = "ia"
    }

    var activeTab: Tab = .record

    // MARK: - Navigation State (Modals & Sheets)

    var selectedCourse: Discipline? = nil
    var selectedRepository: Repository? = nil
    var isRecordingActive = false
    var isChatActive = false

    // Sheets
    var showProfile = false
    var showSettings = false
    var showLinkESPM = false
    var showPayment = false
    var showPremiumGate = false
    var showPromoCodes = false
    var selectedPlan: SubscriptionPlan? = nil

    // AI Chat
    var aiInitialSource: AIChatSource? = nil

    // MARK: - Tab Bar Visibility

    var showTabBar: Bool {
        authState == .authenticated
        && activeTab != .ai
        && selectedCourse == nil
        && selectedRepository == nil
        && !isRecordingActive
        && !isChatActive
        && !showProfile
        && !showSettings
        && !showLinkESPM
        && !showPayment
    }

    // MARK: - Auth Actions

    func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.3)) {
            authState = .login
        }
    }

    func login(user: User) {
        currentUser = user
        withAnimation(.easeInOut(duration: 0.3)) {
            authState = .authenticated
            activeTab = .home
        }
    }

    func goToSignup() {
        withAnimation(.easeInOut(duration: 0.3)) {
            authState = .signup
        }
    }

    func goToLogin() {
        withAnimation(.easeInOut(duration: 0.3)) {
            authState = .login
        }
    }

    func goToLinkESPM() {
        withAnimation(.easeInOut(duration: 0.3)) {
            authState = .linkESPM
        }
    }

    func goToPremiumOffer() {
        withAnimation(.easeInOut(duration: 0.3)) {
            authState = .premiumOffer
        }
    }

    func logout() {
        Task {
            await AuthService.logout()
        }
        KeychainManager.clearAll()
        currentUser = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            authState = .login
            activeTab = .home
            selectedCourse = nil
            selectedRepository = nil
            showProfile = false
            showSettings = false
            showPayment = false
            showLinkESPM = false
            showPremiumGate = false
            showPromoCodes = false
        }
    }

    func showPremiumOffer() {
        showPremiumGate = true
    }

    // MARK: - Navigation Actions

    func selectCourse(_ discipline: Discipline) {
        selectedCourse = discipline
    }

    func selectRepository(_ repo: Repository) {
        selectedRepository = repo
    }

    func goBack() {
        if selectedCourse != nil {
            selectedCourse = nil
        } else if selectedRepository != nil {
            selectedRepository = nil
        }
    }

    func openAIFromCourse(disciplineName: String, recordingDate: String) {
        let source = AIChatSource(
            name: "\(disciplineName) — \(recordingDate)",
            icon: CoffeeIcon.sparkles,
            lectureDate: recordingDate
        )
        selectedCourse = nil
        aiInitialSource = source
        activeTab = .ai
    }

    func openPayment(plan: SubscriptionPlan) {
        selectedPlan = plan
        showPayment = true
    }

    func closePayment() {
        showPayment = false
        selectedPlan = nil
    }

    func switchTab(_ tab: Tab) {
        activeTab = tab
    }
}

// MARK: - AI Chat Source

struct AIChatSource {
    let name: String
    let icon: String
    let lectureDate: String
}

// MARK: - Environment Key

struct NavigationRouterKey: EnvironmentKey {
    static let defaultValue = NavigationRouter()
}

extension EnvironmentValues {
    var router: NavigationRouter {
        get { self[NavigationRouterKey.self] }
        set { self[NavigationRouterKey.self] = newValue }
    }
}

// MARK: - Preview Helper

extension NavigationRouter {
    static var preview: NavigationRouter {
        NavigationRouter()
    }
}
