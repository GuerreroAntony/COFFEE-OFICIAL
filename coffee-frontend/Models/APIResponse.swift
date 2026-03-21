import Foundation

// MARK: - API Response Envelope
// From API Contract: Every response follows { data, error, message }

struct APIResponse<T: Decodable>: Decodable {
    let data: T?
    let error: String?
    let message: String?
}

// MARK: - Paginated Response

struct PaginatedResponse<T: Decodable>: Decodable {
    let data: [T]?
    let pagination: Pagination?
    let error: String?
    let message: String?
}

struct Pagination: Decodable {
    let page: Int
    let perPage: Int
    let total: Int
    let pages: Int

    enum CodingKeys: String, CodingKey {
        case page, total, pages
        case perPage = "per_page"
    }
}

// MARK: - API Error

enum APIError: Error, LocalizedError {
    case invalidCredentials
    case tokenExpired
    case espmAuthFailed
    case accessDenied
    case subscriptionRequired   // 403 — plano expirado, redirecionar pro paywall
    case notFound
    case chatNotFound
    case userNotFound
    case invalidCode
    case recipientNotFound
    case emailExists
    case codeAlreadyUsed
    case alreadyRedeemed
    case validationError(String)
    case questionLimit
    case syncCooldown(nextAvailableAt: Date?)  // 429 — retorna next_sync_available_at
    case internalError
    case aiError
    case espmUnavailable
    case espmTimeout
    case updateRequired             // 426 — app desatualizado, forçar atualização
    case networkError(Error)
    case decodingError(Error)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Email ou senha incorretos"
        case .tokenExpired: return "Sessao expirada. Faca login novamente."
        case .espmAuthFailed: return "Credenciais ESPM invalidas"
        case .accessDenied: return "Acesso negado"
        case .subscriptionRequired: return "Assine para continuar usando o Coffee."
        case .updateRequired: return "Atualize o Coffee para continuar usando."
        case .notFound: return "Recurso nao encontrado"
        case .chatNotFound: return "Conversa nao encontrada"
        case .userNotFound: return "Email nao cadastrado"
        case .invalidCode: return "Codigo invalido"
        case .recipientNotFound: return "Destinatario nao encontrado no Coffee"
        case .emailExists: return "Este email ja esta cadastrado"
        case .codeAlreadyUsed: return "Este codigo ja foi usado"
        case .alreadyRedeemed: return "Voce ja resgatou um codigo"
        case .validationError(let msg): return msg
        case .questionLimit: return "Limite mensal de perguntas atingido"
        case .syncCooldown: return "Aguarde 1 hora entre sincronizacoes"
        case .internalError: return "Erro interno do servidor"
        case .aiError: return "Erro no servico de IA"
        case .espmUnavailable: return "Canvas indisponivel"
        case .espmTimeout: return "Canvas nao respondeu"
        case .networkError(let err): return "Erro de rede: \(err.localizedDescription)"
        case .decodingError: return "Erro ao processar resposta"
        case .unknown(let msg): return msg
        }
    }

    /// Whether this error should trigger paywall redirect
    var requiresPaywall: Bool {
        if case .subscriptionRequired = self { return true }
        return false
    }

    /// Map from API error code string to typed error
    static func from(code: String, message: String? = nil) -> APIError {
        switch code {
        case "INVALID_CREDENTIALS": return .invalidCredentials
        case "TOKEN_EXPIRED": return .tokenExpired
        case "ESPM_AUTH_FAILED": return .espmAuthFailed
        case "ACCESS_DENIED": return .accessDenied
        case "SUBSCRIPTION_REQUIRED": return .subscriptionRequired
        case "UPDATE_REQUIRED": return .updateRequired
        case "NOT_FOUND": return .notFound
        case "CHAT_NOT_FOUND": return .chatNotFound
        case "USER_NOT_FOUND": return .userNotFound
        case "INVALID_CODE": return .invalidCode
        case "RECIPIENT_NOT_FOUND": return .recipientNotFound
        case "EMAIL_EXISTS": return .emailExists
        case "CODE_ALREADY_USED": return .codeAlreadyUsed
        case "ALREADY_REDEEMED": return .alreadyRedeemed
        case "VALIDATION_ERROR": return .validationError(message ?? "Dados invalidos")
        case "QUESTION_LIMIT": return .questionLimit
        case "SYNC_COOLDOWN": return .syncCooldown(nextAvailableAt: nil)
        case "INTERNAL_ERROR": return .internalError
        case "AI_ERROR": return .aiError
        case "ESPM_UNAVAILABLE": return .espmUnavailable
        case "ESPM_TIMEOUT": return .espmTimeout
        default: return .unknown(message ?? code)
        }
    }
}
