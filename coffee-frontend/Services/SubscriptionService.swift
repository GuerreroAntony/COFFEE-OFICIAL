import Foundation
import SwiftUI
// import StoreKit  // Uncomment when adding StoreKit 2

// MARK: - Subscription Service
// StoreKit 2 integration for Apple In-App Purchases
// POST /subscription/verify, GET /subscription/status
// GET /gift-codes, POST /gift-codes/validate, POST /gift-codes/redeem
// Pricing: R$59,90/mes (cheio), R$29,90/mes (promo lancamento). So mensal.

@Observable
final class SubscriptionService {

    // Product identifier matching App Store Connect (monthly only)
    static let monthlyProductID = "com.coffee.premium.monthly"

    var isSubscribed = false
    var currentPlan: SubscriptionPlan? = nil
    var subscriptionStatus: SubscriptionStatus? = nil
    var availablePlans: [SubscriptionPlan] = MockData.subscriptionPlans

    /// Tracks whether user has already used their free 7-day trial
    var hasUsedTrial = false

    /// Convenience: true when user has active premium subscription
    var isPremium: Bool { isSubscribed }

    // MARK: - Sync with User Data

    /// Sync subscription state from user model (mock or API)
    func syncWithUser(_ user: User) {
        isSubscribed = user.subscriptionActive || user.plano == .premium
    }

    // MARK: - Load Products

    /// Fetch available subscription products from App Store
    func loadProducts() async {
        // StoreKit 2 implementation:
        // do {
        //     let products = try await Product.products(for: [Self.monthlyProductID])
        //     // Map to SubscriptionPlan
        // } catch {
        //     print("Failed to load products: \(error)")
        // }

        // Mock
        availablePlans = MockData.subscriptionPlans
    }

    // MARK: - Purchase

    /// Purchase a subscription plan
    func purchase(plan: SubscriptionPlan) async throws -> Bool {
        // Mock
        try await Task.sleep(for: .seconds(1.5))
        isSubscribed = true
        currentPlan = plan
        return true
    }

    // MARK: - Start Free Trial (no card needed)

    /// Activate 7-day free trial — only available once
    func startFreeTrial() async {
        // Mock: instantly activate premium for 7 days
        try? await Task.sleep(for: .seconds(0.8))
        isSubscribed = true
        hasUsedTrial = true
    }

    // MARK: - Cancel Subscription

    /// Cancel the current subscription — locks premium features immediately
    func cancelSubscription() {
        isSubscribed = false
        currentPlan = nil
        hasUsedTrial = true
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        // Mock
        isSubscribed = MockData.currentUser.subscriptionActive
    }

    // MARK: - Manage Subscription

    /// Opens system subscription management
    func manageSubscription() async {
        // StoreKit 2: Opens the system subscription management sheet
        // if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
        //     try? await AppStore.showManageSubscriptions(in: windowScene)
        // }
    }

    // MARK: - Verify Receipt with Backend (POST /subscription/verify)

    func verifyReceipt(receiptData: String, transactionId: String) async throws -> SubscriptionStatus {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.5))
            let status = SubscriptionStatus(
                plano: "premium",
                subscriptionActive: true,
                expiresAt: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
                giftCodes: nil
            )
            isSubscribed = true
            subscriptionStatus = status
            return status
        }

        let body = VerifyReceiptRequest(receiptData: receiptData, transactionId: transactionId)
        let status: SubscriptionStatus = try await APIClient.shared.request(
            path: APIEndpoints.subscriptionVerify,
            method: .POST,
            body: body
        )

        isSubscribed = status.subscriptionActive
        subscriptionStatus = status
        return status
    }

    // MARK: - Get Subscription Status (GET /subscription/status)

    func getStatus() async throws -> SubscriptionStatus {
        if APIClient.useMocks {
            return SubscriptionStatus(
                plano: MockData.currentUser.plano.rawValue,
                subscriptionActive: MockData.currentUser.subscriptionActive,
                expiresAt: nil,
                giftCodes: nil
            )
        }

        let status: SubscriptionStatus = try await APIClient.shared.request(
            path: APIEndpoints.subscriptionStatus
        )
        isSubscribed = status.subscriptionActive
        subscriptionStatus = status
        return status
    }

    // MARK: - Gift Codes (GET /gift-codes)

    func getGiftCodes() async throws -> GiftCodeListResponse {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.3))
            return GiftCodeListResponse(
                codes: [
                    GiftCode(code: "ABC12345", redeemed: false, redeemedBy: nil, redeemedAt: nil),
                    GiftCode(code: "XYZ67890", redeemed: true, redeemedBy: "Ana", redeemedAt: Date()),
                ],
                shareMessage: "Usa meu codigo ABC12345 no Coffee e ganha 7 dias gratis!"
            )
        }

        return try await APIClient.shared.request(path: APIEndpoints.giftCodes)
    }

    // MARK: - Validate Gift Code (POST /gift-codes/validate)

    func validateGiftCode(_ code: String) async throws -> ValidateCodeResponse {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.5))
            let isValid = MockData.validPromoCodes.contains(code.uppercased())
            return ValidateCodeResponse(valid: isValid, ownerName: isValid ? "Gabriel" : nil)
        }

        struct ValidateBody: Encodable { let code: String }
        let body = ValidateBody(code: code)
        return try await APIClient.shared.request(
            path: APIEndpoints.giftCodesValidate,
            method: .POST,
            body: body
        )
    }

    // MARK: - Redeem Gift Code (POST /gift-codes/redeem)

    func redeemGiftCode(_ code: String) async throws -> RedeemCodeResponse {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.5))
            let isValid = MockData.validPromoCodes.contains(code.uppercased())
            if !isValid { throw APIError.invalidCode }
            return RedeemCodeResponse(
                redeemed: true,
                daysAdded: 7,
                newTrialEnd: Calendar.current.date(byAdding: .day, value: 7, to: Date())
            )
        }

        struct RedeemBody: Encodable { let code: String }
        let body = RedeemBody(code: code)
        return try await APIClient.shared.request(
            path: APIEndpoints.giftCodesRedeem,
            method: .POST,
            body: body
        )
    }
}

// MARK: - Environment Key

struct SubscriptionServiceKey: EnvironmentKey {
    static let defaultValue = SubscriptionService()
}

extension EnvironmentValues {
    var subscriptionService: SubscriptionService {
        get { self[SubscriptionServiceKey.self] }
        set { self[SubscriptionServiceKey.self] = newValue }
    }
}
