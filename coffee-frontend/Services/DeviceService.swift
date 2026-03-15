import Foundation

// MARK: - Device Service
// POST /devices, DELETE /devices/{token}
// Manages FCM push notification token registration

enum DeviceService {

    // MARK: - Register FCM Token

    static func registerDevice(fcmToken: String) async throws {
        if APIClient.useMocks { return }

        let body = DeviceRegistrationRequest(token: fcmToken, platform: "ios")
        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.devices,
            method: .POST,
            body: body
        )
    }

    // MARK: - Remove FCM Token

    static func removeDevice(fcmToken: String) async throws {
        if APIClient.useMocks { return }

        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.device(token: fcmToken),
            method: .DELETE
        )
    }
}
