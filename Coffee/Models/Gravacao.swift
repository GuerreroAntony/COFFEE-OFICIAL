import Foundation

struct Transcricao: Codable, Identifiable {
    let id: UUID
    let gravacaoId: UUID
    let texto: String
    let idioma: String
    let confianca: Double
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case gravacaoId  = "gravacao_id"
        case texto
        case idioma
        case confianca
        case createdAt   = "created_at"
    }
}

struct Gravacao: Codable, Identifiable {
    let id: UUID
    let disciplinaId: UUID
    let dataAula: Date
    let duracaoSegundos: Int
    let status: String
    let createdAt: Date
    let transcricao: Transcricao?

    enum CodingKeys: String, CodingKey {
        case id
        case disciplinaId    = "disciplina_id"
        case dataAula        = "data_aula"
        case duracaoSegundos = "duracao_segundos"
        case status
        case createdAt       = "created_at"
        case transcricao
    }
}
