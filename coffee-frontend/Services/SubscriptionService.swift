import Foundation
import SwiftUI
import RevenueCat

// MARK: - Subscription Service
// StoreKit 2 integration for Apple In-App Purchases
// Three plans: Café Curto (R$29,90) + Café com Leite (R$49,90) + Black (R$69,90)
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

    /// Fetch available subscription products from RevenueCat
    func loadProducts() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let currentOffering = offerings.current else {
                print("⚠️ No offerings configured in RevenueCat")
                availablePlans = MockData.subscriptionPlans
                return
            }
            
            // Map RevenueCat packages to SubscriptionPlan
            // TODO: Configurar ofertas no RevenueCat Dashboard
            availablePlans = MockData.subscriptionPlans
            print("✅ Produtos carregados do RevenueCat: \(currentOffering.availablePackages.count) pacotes")
        } catch {
            print("❌ Erro ao carregar produtos: \(error)")
            availablePlans = MockData.subscriptionPlans
        }
    }

    // MARK: - Purchase

    /// Purchase a subscription plan via RevenueCat
    func purchase(plan: SubscriptionPlan) async throws -> Bool {
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let currentOffering = offerings.current else {
                throw NSError(domain: "SubscriptionService", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Nenhuma oferta disponível"])
            }

            // Find package by product ID (3 plans)
            let targetProductID: String
            switch plan.planId {
            case "cafe_curto": targetProductID = Self.cafeCurtoProductID
            case "cafe_com_leite": targetProductID = Self.cafeComLeiteProductID
            case "black": targetProductID = Self.blackProductID
            default: targetProductID = Self.cafeComLeiteProductID
            }

            guard let package = currentOffering.availablePackages.first(where: {
                $0.storeProduct.productIdentifier == targetProductID
            }) else {
                throw NSError(domain: "SubscriptionService", code: -2,
                             userInfo: [NSLocalizedDescriptionKey: "Produto não encontrado"])
            }

            let result = try await Purchases.shared.purchase(package: package)
            let customerInfo = result.customerInfo

            // Update subscription state
            isSubscribed = !customerInfo.activeSubscriptions.isEmpty
            currentPlan = plan
            switch plan.planId {
            case "cafe_curto": userPlan = .cafeCurto
            case "cafe_com_leite": userPlan = .cafeComLeite
            case "black": userPlan = .black
            default: userPlan = .cafeComLeite
            }

            print("✅ Compra realizada com sucesso: \(plan.name)")
            return true
        } catch {
            print("❌ Erro na compra: \(error)")
            throw error
        }
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
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            isSubscribed = !customerInfo.activeSubscriptions.isEmpty
            
            if let activeSubscription = customerInfo.activeSubscriptions.first {
                // Determine which plan user has
                if activeSubscription == Self.blackProductID {
                    userPlan = .black
                } else if activeSubscription == Self.cafeComLeiteProductID {
                    userPlan = .cafeComLeite
                } else if activeSubscription == Self.cafeCurtoProductID {
                    userPlan = .cafeCurto
                }
            }
            
            print("✅ Compras restauradas: \(customerInfo.activeSubscriptions.count) assinaturas ativas")
        } catch {
            print("❌ Erro ao restaurar compras: \(error)")
        }
    }

    // MARK: - Manage Subscription

    /// Opens system subscription management
    func manageSubscription() async {
        do {
            if let url = try await Purchases.shared.customerInfo().managementURL {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
            }
        } catch {
            print("❌ Erro ao abrir gerenciamento de assinatura: \(error)")
        }
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
            switch plano {
            case "cafe_curto": userPlan = .cafeCurto
            case "black": userPlan = .black
            default: userPlan = .cafeComLeite
            }
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
