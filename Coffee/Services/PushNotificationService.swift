import Foundation
import UserNotifications
import UIKit

@MainActor
final class PushNotificationService: ObservableObject {
    static let shared = PushNotificationService()

    @Published var isAuthorized = false

    private var currentToken: String?

    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            print("Push permission error: \(error)")
            return false
        }
    }

    func checkCurrentStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Token Registration

    func registerToken(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        currentToken = token

        Task {
            do {
                let body = ["token": token, "platform": "ios"]
                let _: DeviceTokenResponse = try await NetworkService.shared.request(
                    .POST, "/devices", body: body
                )
                print("FCM token registered: \(token.prefix(12))...")
            } catch {
                print("Failed to register device token: \(error)")
            }
        }
    }

    func unregisterToken() {
        guard let token = currentToken else { return }
        Task {
            do {
                let _: DeviceTokenResponse = try await NetworkService.shared.request(
                    .DELETE, "/devices/\(token)"
                )
                currentToken = nil
            } catch {
                print("Failed to unregister device token: \(error)")
            }
        }
    }
}

// MARK: - Response Model

private struct DeviceTokenResponse: Decodable {
    let success: Bool
}
