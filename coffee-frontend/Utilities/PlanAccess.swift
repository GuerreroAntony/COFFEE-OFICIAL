import Foundation

/// Centralized plan-based feature access checks.
/// Source of truth for which plans can use which features.
enum PlanAccess {

    // MARK: - Feature Checks

    /// Barista IA: Café com Leite, Black, Trial
    static func canUseBarista(_ plano: UserPlan?) -> Bool {
        guard let p = plano else { return false }
        return p == .cafeComLeite || p == .black || p == .trial
    }

    /// Compartilhar: Black, Trial only
    static func canShare(_ plano: UserPlan?) -> Bool {
        guard let p = plano else { return false }
        return p == .black || p == .trial
    }

    /// Calendário ESPM: Black, Trial only
    static func canUseCalendar(_ plano: UserPlan?) -> Bool {
        canShare(plano)
    }

    /// Mapa mental: Black, Trial only
    static func canUseMindMap(_ plano: UserPlan?) -> Bool {
        canShare(plano)
    }

    /// Social (amigos, grupos): Black, Trial only
    static func canUseSocial(_ plano: UserPlan?) -> Bool {
        canShare(plano)
    }

    // MARK: - Limits

    /// Recording hours limit (-1 = unlimited)
    static func recordingHoursLimit(_ plano: UserPlan?) -> Double {
        switch plano {
        case .black, .trial: return -1
        case .cafeComLeite: return 40
        default: return 20
        }
    }

    // MARK: - Upgrade Messages

    static func upgradeMessage(for feature: LockedFeature) -> (title: String, message: String, requiredPlan: String) {
        switch feature {
        case .barista:
            return ("Barista IA", "O assistente de IA esta disponivel a partir do plano Cafe com Leite.", "Cafe com Leite")
        case .share:
            return ("Compartilhar", "Compartilhe aulas com seus colegas no plano Black.", "Black")
        case .calendar:
            return ("Calendario ESPM", "Acompanhe prazos e entregas do Canvas no plano Black.", "Black")
        case .mindMap:
            return ("Mapa Mental", "Mapas mentais automaticos estao disponiveis no plano Black.", "Black")
        case .social:
            return ("Social", "Adicione amigos e compartilhe aulas no plano Black.", "Black")
        }
    }

    enum LockedFeature {
        case barista, share, calendar, mindMap, social
    }
}
