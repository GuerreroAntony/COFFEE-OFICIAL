import Foundation

// MARK: - User Model (from API Contract: POST /auth/signup, GET /auth/me, GET /profile)

struct User: Codable, Identifiable {
    let id: String
    var nome: String
    let email: String
    var plano: UserPlan
    var trialEnd: Date?
    var subscriptionActive: Bool
    var espmConnected: Bool
    var espmLogin: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, nome, email, plano
        case trialEnd = "trial_end"
        case subscriptionActive = "subscription_active"
        case espmConnected = "espm_connected"
        case espmLogin = "espm_login"
        case createdAt = "created_at"
    }
}

enum UserPlan: String, Codable {
    case trial
    case cafeCurto = "cafe_curto"
    case cafeComLeite = "cafe_com_leite"
    case black
    case expired

    /// Display name for UI
    var displayName: String {
        switch self {
        case .trial: return "Trial Black"
        case .cafeCurto: return "Café Curto"
        case .cafeComLeite: return "Café com Leite"
        case .black: return "Black"
        case .expired: return "Expirado"
        }
    }

    /// Whether this is an active paid plan
    var isPaid: Bool {
        self == .cafeCurto || self == .cafeComLeite || self == .black
    }
}

// MARK: - Auth Responses

struct AuthResponse: Codable {
    let user: User
    let token: String
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct SignupRequest: Codable {
    let nome: String
    let email: String
    let password: String
    var giftCode: String? = nil

    enum CodingKeys: String, CodingKey {
        case nome, email, password
        case giftCode = "gift_code"
    }
}

// MARK: - Profile

struct UserProfile: Codable {
    let id: String
    let nome: String
    let email: String
    let plano: UserPlan
    let trialEnd: Date?
    let subscriptionActive: Bool
    let espmConnected: Bool
    let espmLogin: String?
    let usage: UserUsage?
    let giftCodes: [GiftCode]?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, nome, email, plano, usage
        case trialEnd = "trial_end"
        case subscriptionActive = "subscription_active"
        case espmConnected = "espm_connected"
        case espmLogin = "espm_login"
        case giftCodes = "gift_codes"
        case createdAt = "created_at"
    }
}

struct UserUsage: Codable {
    let gravacoesTotal: Int
    let horasGravadas: Double
    let questionsRemaining: QuestionsRemaining
    let baristaUsage: BaristaUsage?
    let questionsResetAt: Date?

    enum CodingKeys: String, CodingKey {
        case gravacoesTotal = "gravacoes_total"
        case horasGravadas = "horas_gravadas"
        case questionsRemaining = "questions_remaining"
        case baristaUsage = "barista_usage"
        case questionsResetAt = "questions_reset_at"
    }
}

struct BaristaUsage: Codable {
    let usagePercent: Double
    let budgetUsd: Double
    let usedUsd: Double
    let remainingUsd: Double
    let cycleResetAt: Date?

    enum CodingKeys: String, CodingKey {
        case usagePercent = "usage_percent"
        case budgetUsd = "budget_usd"
        case usedUsd = "used_usd"
        case remainingUsd = "remaining_usd"
        case cycleResetAt = "cycle_reset_at"
    }
}

struct QuestionsRemaining: Codable {
    let espresso: Int   // -1 = unlimited (legacy)
    let lungo: Int
    let coldBrew: Int

    enum CodingKeys: String, CodingKey {
        case espresso, lungo
        case coldBrew = "cold_brew"
    }
}

struct GiftCode: Codable, Identifiable {
    var id: String { code }
    let code: String
    let redeemed: Bool
    let redeemedBy: String?
    let redeemedAt: Date?

    enum CodingKeys: String, CodingKey {
        case code, redeemed
        case redeemedBy = "redeemed_by"
        case redeemedAt = "redeemed_at"
    }
}
