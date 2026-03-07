import Foundation

struct PersonalityConfig: Codable {
    var profundidade: Int = 50
    var linguagem: Int = 50
    var exemplos: Int = 50
    var questionamento: Int = 50
    var foco: Int = 50
}

enum PersonalityProfile: String, CaseIterable, Identifiable {
    case rapido
    case equilibrado
    case detalhado

    var id: String { rawValue }

    var config: PersonalityConfig {
        switch self {
        case .rapido:
            return PersonalityConfig(profundidade: 10, linguagem: 50, exemplos: 10, questionamento: 0, foco: 70)
        case .equilibrado:
            return PersonalityConfig(profundidade: 50, linguagem: 50, exemplos: 50, questionamento: 30, foco: 50)
        case .detalhado:
            return PersonalityConfig(profundidade: 100, linguagem: 30, exemplos: 80, questionamento: 50, foco: 30)
        }
    }

    var icon: String {
        switch self {
        case .rapido:      return "bolt.fill"
        case .equilibrado: return "equal.circle.fill"
        case .detalhado:   return "books.vertical.fill"
        }
    }

    var label: String {
        switch self {
        case .rapido:      return "Rápido"
        case .equilibrado: return "Equilibrado"
        case .detalhado:   return "Detalhado"
        }
    }

    var description: String {
        switch self {
        case .rapido:      return "Respostas curtas e diretas"
        case .equilibrado: return "Balanceado entre brevidade e profundidade"
        case .detalhado:   return "Análise profunda com exemplos"
        }
    }
}
