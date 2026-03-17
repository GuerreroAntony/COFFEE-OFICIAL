import Foundation

// MARK: - Subscription Models
// Two plans: Café com Leite (R$29,90) + Black (R$49,90)

struct SubscriptionPlan: Identifiable {
    let id: String
    let planId: String          // "cafe_com_leite" or "black" — sent to backend
    let name: String
    let price: Double
    let originalPrice: Double?  // Shown as strikethrough when isPromo
    let isPromo: Bool
    let features: [PlanFeature]
    let isHighlighted: Bool     // "Mais Popular" badge
    let badge: String?          // e.g. "Lançamento"

    /// Feature with limit detail for comparison
    struct PlanFeature: Identifiable {
        let id = UUID()
        let text: String
        let detail: String?     // e.g. "75/mês" or "Ilimitado"
        let included: Bool
    }
}

// MARK: - Subscription Status (GET /subscription/status, POST /subscription/verify)

struct SubscriptionStatus: Codable {
    let plano: String
    let subscriptionActive: Bool
    let expiresAt: Date?
    let giftCodes: [GiftCode]?

    enum CodingKeys: String, CodingKey {
        case plano
        case subscriptionActive = "subscription_active"
        case expiresAt = "expires_at"
        case giftCodes = "gift_codes"
    }
}

// MARK: - Verify Receipt (POST /subscription/verify)

struct VerifyReceiptRequest: Codable {
    let receiptData: String
    let transactionId: String
    let plano: String           // "cafe_com_leite" or "black"

    enum CodingKeys: String, CodingKey {
        case receiptData = "receipt_data"
        case transactionId = "transaction_id"
        case plano
    }
}

// MARK: - Gift Code Responses (GET /gift-codes, POST /gift-codes/validate, POST /gift-codes/redeem)

struct GiftCodeListResponse: Codable {
    let codes: [GiftCode]
    let shareMessage: String?

    enum CodingKeys: String, CodingKey {
        case codes
        case shareMessage = "share_message"
    }
}

struct ValidateCodeResponse: Codable {
    let valid: Bool
    let ownerName: String?

    enum CodingKeys: String, CodingKey {
        case valid
        case ownerName = "owner_name"
    }
}

struct RedeemCodeResponse: Codable {
    let redeemed: Bool
    let daysAdded: Int?
    let newTrialEnd: Date?

    enum CodingKeys: String, CodingKey {
        case redeemed
        case daysAdded = "days_added"
        case newTrialEnd = "new_trial_end"
    }
}

// MARK: - Premium Benefits (for PremiumOfferView)

struct PremiumBenefit: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

// MARK: - Cancel Reason (for CancellationView)

struct CancelReason: Identifiable {
    let id = UUID()
    let icon: String
    let label: String

    static let all: [CancelReason] = [
        CancelReason(icon: CoffeeIcon.payments, label: "Está muito caro"),
        CancelReason(icon: CoffeeIcon.eventBusy, label: "Não uso o suficiente"),
        CancelReason(icon: CoffeeIcon.thumbDown, label: "Conteúdo inadequado"),
        CancelReason(icon: CoffeeIcon.bugReport, label: "Problemas técnicos"),
    ]
}
