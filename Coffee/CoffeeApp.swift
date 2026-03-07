import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationService.shared.registerToken(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Push registration failed: \(error)")
    }
}

@main
struct CoffeeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isLoading {
                    LoadingView()
                } else if authViewModel.isAuthenticated && authViewModel.needsESPMOnboarding {
                    ESPMOnboardingView()
                } else if authViewModel.needsOnboarding {
                    OnboardingView()
                } else if authViewModel.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(authViewModel)
            .task {
                await authViewModel.checkAuthOnLaunch()
                if authViewModel.isAuthenticated {
                    await PushNotificationService.shared.checkCurrentStatus()
                    if PushNotificationService.shared.isAuthorized {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }
    }
}
