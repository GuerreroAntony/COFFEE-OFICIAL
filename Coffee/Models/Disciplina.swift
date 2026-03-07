import Foundation

struct HorarioSlot: Codable {
    let day: String
    let timeStart: String
    let timeEnd: String

    enum CodingKeys: String, CodingKey {
        case day
        case timeStart = "time_start"
        case timeEnd = "time_end"
    }
}

struct Disciplina: Codable, Identifiable {
    let id: UUID
    let nome: String
    let professor: String
    let horario: String
    let semestre: String
    let gravacoesCount: Int
    let horarios: [HorarioSlot]?

    enum CodingKeys: String, CodingKey {
        case id
        case nome
        case professor
        case horario
        case semestre
        case gravacoesCount = "gravacoes_count"
        case horarios
    }
}
