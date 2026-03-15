import Foundation

// MARK: - Notification Service
// GET /notificacoes, PATCH /notificacoes/{id}/read

enum NotificationService {

    // MARK: - List Notifications (last 50)

    static func getNotifications() async throws -> [AppNotification] {
        if APIClient.useMocks {
            return MockData.notifications
        }
        return try await APIClient.shared.request(path: APIEndpoints.notificacoes)
    }

    // MARK: - Mark Notification as Read

    static func markAsRead(id: String) async throws -> AppNotification {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.2))
            var notification = MockData.notifications.first { $0.id == id } ?? MockData.notifications[0]
            notification.lida = true
            return notification
        }

        return try await APIClient.shared.request(
            path: APIEndpoints.notificacaoRead(id: id),
            method: .PATCH
        )
    }

    // MARK: - Unread Count

    static func getUnreadCount() async throws -> Int {
        let notifications = try await getNotifications()
        return notifications.filter { !$0.lida }.count
    }
}
