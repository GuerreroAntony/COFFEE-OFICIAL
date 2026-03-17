import Foundation

// MARK: - Discipline Model (from API Contract: GET /disciplinas)

struct Discipline: Codable, Identifiable, Hashable {
    let id: String
    let nome: String
    let turma: String?
    let semestre: String?
    let sala: String?
    let canvasCourseId: Int?
    var gravacoesCount: Int
    var materiaisCount: Int
    var aiActive: Bool
    var lastSyncedAt: Date?
    var icon: String?
    var iconColor: String?

    enum CodingKeys: String, CodingKey {
        case id, nome, turma, semestre, sala, icon
        case canvasCourseId = "canvas_course_id"
        case gravacoesCount = "gravacoes_count"
        case materiaisCount = "materiais_count"
        case aiActive = "ai_active"
        case lastSyncedAt = "last_synced_at"
        case iconColor = "icon_color"
    }

    // Custom decoder: ESPM connect response only sends id/nome/turma/semestre,
    // so counts and flags default to 0/false when absent.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        nome = try container.decode(String.self, forKey: .nome)
        turma = try container.decodeIfPresent(String.self, forKey: .turma)
        semestre = try container.decodeIfPresent(String.self, forKey: .semestre)
        sala = try container.decodeIfPresent(String.self, forKey: .sala)
        canvasCourseId = try container.decodeIfPresent(Int.self, forKey: .canvasCourseId)
        gravacoesCount = try container.decodeIfPresent(Int.self, forKey: .gravacoesCount) ?? 0
        materiaisCount = try container.decodeIfPresent(Int.self, forKey: .materiaisCount) ?? 0
        aiActive = try container.decodeIfPresent(Bool.self, forKey: .aiActive) ?? false
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        iconColor = try container.decodeIfPresent(String.self, forKey: .iconColor)
    }

    // Memberwise init for mock data and previews
    init(id: String, nome: String, turma: String? = nil, semestre: String? = nil,
         sala: String? = nil, canvasCourseId: Int? = nil, gravacoesCount: Int = 0,
         materiaisCount: Int = 0, aiActive: Bool = false, lastSyncedAt: Date? = nil,
         icon: String? = nil, iconColor: String? = nil) {
        self.id = id
        self.nome = nome
        self.turma = turma
        self.semestre = semestre
        self.sala = sala
        self.canvasCourseId = canvasCourseId
        self.gravacoesCount = gravacoesCount
        self.materiaisCount = materiaisCount
        self.aiActive = aiActive
        self.lastSyncedAt = lastSyncedAt
        self.icon = icon
        self.iconColor = iconColor
    }

    // For SwiftUI previews and list identity
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Discipline, rhs: Discipline) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Display Icon & Color

    /// Default icon/color rotation when user hasn't customized
    static let defaultStyles: [(icon: String, color: String)] = [
        ("text.bubble.fill", "715038"),
        ("heart.fill", "D4A574"),
        ("star.fill", "C4956A"),
        ("lightbulb.fill", "715038"),
        ("book.fill", "D4A574"),
        ("graduationcap.fill", "C4956A"),
    ]

    /// Resolved icon for display (custom or default by index)
    func displayIcon(at index: Int) -> String {
        icon ?? Self.defaultStyles[index % Self.defaultStyles.count].icon
    }

    /// Resolved color hex for display (custom or default by index)
    func displayColorHex(at index: Int) -> String {
        iconColor ?? Self.defaultStyles[index % Self.defaultStyles.count].color
    }
}

// MARK: - ESPM Connection

struct ESPMConnectRequest: Codable {
    let matricula: String
    let canvasToken: String
}

struct ESPMConnectResponse: Codable {
    let status: String
    let disciplinasFound: Int
    let disciplinas: [Discipline]

    enum CodingKeys: String, CodingKey {
        case status
        case disciplinasFound = "disciplinas_found"
        case disciplinas
    }
}

struct ESPMStatus: Codable {
    let connected: Bool
    let matricula: String?
    let disciplinasCount: Int?
    let tokenExpiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case connected, matricula
        case disciplinasCount = "disciplinas_count"
        case tokenExpiresAt = "token_expires_at"
    }
}

// MARK: - Appearance Update (PATCH /disciplinas/{id}/appearance)

struct UpdateAppearanceRequest: Codable {
    let icon: String
    let iconColor: String

    enum CodingKeys: String, CodingKey {
        case icon
        case iconColor = "icon_color"
    }
}

// MARK: - Sync Response (POST /disciplinas/{id}/sync)

struct SyncResponse: Codable {
    let status: String
    let lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case lastSyncedAt = "last_synced_at"
    }
}
