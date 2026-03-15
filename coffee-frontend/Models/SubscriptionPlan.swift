import Foundation

// MARK: - Subscription Models (from API Contract v3.1)
// Pricing: R$59,90/mês (cheio), R$29,90/mês (promo lançamento). Só mensal.

struct SubscriptionPlan: Identifiable {
    let id: String
    let name: String
    let price: Double           // R$59.90 cheio or R$29.90 promo
    let originalPrice: Double?  // R$59.90 shown as strikethrough when promo
    let isPromo: Bool
    let features: [String]
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

    enum CodingKeys: String, CodingKey {
        case receiptData = "receipt_data"
        case transactionId = "transaction_id"
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
}
