import SwiftUI

// MARK: - Preview Helpers
// Convenience extensions for SwiftUI previews

extension Discipline {
    static let preview = MockData.disciplines[0]
    static let previewList = MockData.disciplines
}

extension Repository {
    static let preview = MockData.repositories[0]
    static let previewList = MockData.repositories
}

extension Recording {
    static let preview = MockData.recordings[0]
    static let previewList = MockData.recordings
}

extension User {
    static let preview = MockData.currentUser
}

extension UserProfile {
    static let preview = MockData.userProfile
}

extension SharedItem {
    static let preview = MockData.sharedItems[0]
    static let previewList = MockData.sharedItems
}

extension Chat {
    static let preview = MockData.chatHistory[0]
    static let previewList = MockData.chatHistory
}

extension SubscriptionPlan {
    static let preview = MockData.subscriptionPlans[0]
    static let previewList = MockData.subscriptionPlans
}

// MARK: - Preview Router

extension NavigationRouter {
    static var preview: NavigationRouter {
        let router = NavigationRouter()
        router.authState = .authenticated
        router.activeTab = .home
        return router
    }

    static var previewSplash: NavigationRouter {
        let router = NavigationRouter()
        router.authState = .splash
        return router
    }
}

// MARK: - Preview Container

/// Wraps a view with a NavigationRouter for previews
struct PreviewContainer<Content: View>: View {
    let router: NavigationRouter
    let content: Content

    init(
        authState: NavigationRouter.AuthState = .authenticated,
        @ViewBuilder content: () -> Content
    ) {
        let router = NavigationRouter()
        router.authState = authState
        self.router = router
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.router, router)
    }
}
