import Foundation
import SwiftUI
// import StoreKit  // Uncomment when adding StoreKit 2

// MARK: - Subscription Service
// StoreKit 2 integration for Apple In-App Purchases
// Two plans: Café com Leite (R$29,90) + Black (R$49,90)
// POST /subscription/verify, GET /subscription/status

@Observable
final class SubscriptionService {

    // Product identifiers matching App Store Connect
    static let cafeCurtoProductID = "com.coffee.cafe_curto.monthly"
    static let cafeComLeiteProductID = "com.coffee.cafe_com_leite.monthly"
    static let blackProductID = "com.coffee.black.monthly"

    var isSubscribed = false
    var currentPlan: SubscriptionPlan? = nil
    var subscriptionStatus: SubscriptionStatus? = nil
    var availablePlans: [SubscriptionPlan] = MockData.subscriptionPlans

    /// Tracks whether user has already used their free 7-day trial
    var hasUsedTrial = false

    /// Current user plan type from backend
    var userPlan: UserPlan = .trial

    /// Convenience: true when user has active paid subscription or valid trial
    var isPremium: Bool { isSubscribed }

    /// The Café Curto plan (entry)
    var cafeCurtoPlan: SubscriptionPlan? {
        availablePlans.first { $0.planId == "cafe_curto" }
    }

    /// The Café com Leite plan (mid-tier)
    var cafeComLeitePlan: SubscriptionPlan? {
        availablePlans.first { $0.planId == "cafe_com_leite" }
    }

    /// The Black plan (highlighted)
    var blackPlan: SubscriptionPlan? {
        availablePlans.first { $0.planId == "black" }
    }

    // MARK: - Sync with User Data

    /// Sync subscription state from user model (mock or API)
    func syncWithUser(_ user: User) {
        userPlan = user.plano
        let trialValid = user.plano == .trial && (user.trialEnd ?? .distantPast) > Date()
        isSubscribed = user.subscriptionActive || user.plano.isPaid || trialValid
        hasUsedTrial = user.plano != .trial
    }

    // MARK: - Load Products

    /// Fetch available subscription products from App Store
    func loadProducts() async {
        // StoreKit 2 implementation:
        // do {
        //     let products = try await Product.products(for: [
        //         Self.cafeComLeiteProductID,
        //         Self.blackProductID
        //     ])
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
        switch plan.planId {
        case "cafe_curto": userPlan = .cafeCurto
        case "cafe_com_leite": userPlan = .cafeComLeite
        case "black": userPlan = .black
        default: userPlan = .cafeComLeite
        }
        return true
    }

    // MARK: - Start Free Trial (7 dias grátis do plano Black)

    /// Activate 7-day free trial with Black limits
    func startFreeTrial() async {
        // Mock: instantly activate with trial limits (= Black)
        try? await Task.sleep(for: .seconds(0.8))
        isSubscribed = true
        hasUsedTrial = true
        userPlan = .trial
    }

    // MARK: - Cancel Subscription

    /// Cancel the current subscription — locks premium features immediately
    func cancelSubscription() {
        isSubscribed = false
        currentPlan = nil
        userPlan = .expired
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

    func verifyReceipt(receiptData: String, transactionId: String, plano: String) async throws -> SubscriptionStatus {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.5))
            let status = SubscriptionStatus(
                plano: plano,
                subscriptionActive: true,
                expiresAt: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
                giftCodes: nil
            )
            isSubscribed = true
            subscriptionStatus = status
            userPlan = plano == "black" ? .black : .cafeComLeite
            return status
        }

        let body = VerifyReceiptRequest(receiptData: receiptData, transactionId: transactionId, plano: plano)
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
