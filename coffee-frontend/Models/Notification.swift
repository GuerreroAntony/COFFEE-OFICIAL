import Foundation

// MARK: - Notification Model (from API Contract: GET /notificacoes)

struct AppNotification: Codable, Identifiable {
    let id: String
    let tipo: String                    // "compartilhamento" (unico tipo por ora)
    let titulo: String
    let corpo: String
    let dataPayload: NotificationPayload?
    var lida: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, tipo, titulo, corpo, lida
        case dataPayload = "data_payload"
        case createdAt = "created_at"
    }
}

struct NotificationPayload: Codable {
    let compartilhamentoId: String?
    let deepLink: String?

    enum CodingKeys: String, CodingKey {
        case compartilhamentoId = "compartilhamento_id"
        case deepLink = "deep_link"
    }
}

// MARK: - Device Registration (POST /devices)

struct DeviceRegistrationRequest: Codable {
    let token: String
    let platform: String    // "ios"
}

// MARK: - Support Contact (POST /support/contact)

struct ContactRequest: Codable {
    let subject: String
    let message: String
}

// MARK: - Settings Response (GET /settings)

struct SettingsResponse: Codable {
    let espmConnected: Bool
    let espmLogin: String?

    enum CodingKeys: String, CodingKey {
        case espmConnected = "espm_connected"
        case espmLogin = "espm_login"
    }
}

// MARK: - Delete Account Request (DELETE /account)

struct DeleteAccountRequest: Codable {
    let confirm: Bool
}

// MARK: - Logout Request (POST /auth/logout)

struct LogoutRequest: Codable {
    let deviceToken: String?

    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
    }
}

// MARK: - Forgot Password Request (POST /auth/forgot-password)

struct ForgotPasswordRequest: Codable {
    let email: String
}

// MARK: - Profile Update Request (PATCH /profile)

struct UpdateProfileRequest: Codable {
    let nome: String
}

// MARK: - Rename Repository Request (PATCH /repositorios/{id})

struct RenameRepositoryRequest: Codable {
    let nome: String
}

// MARK: - Move Recording Request (PATCH /gravacoes/{id})

struct MoveRecordingRequest: Codable {
    let sourceType: String
    let sourceId: String

    enum CodingKeys: String, CodingKey {
        case sourceType = "source_type"
        case sourceId = "source_id"
    }
}
