import Foundation

struct ConceitoChave: Codable {
    let termo: String
    let definicao: String
}

struct Topico: Codable {
    let titulo: String
    let conteudo: String
}

struct Resumo: Codable, Identifiable {
    let id: UUID
    let transcricaoId: UUID
    let titulo: String
    let topicos: [Topico]
    let conceitosChave: [ConceitoChave]
    let resumoGeral: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case transcricaoId  = "transcricao_id"
        case titulo
        case topicos
        case conceitosChave = "conceitos_chave"
        case resumoGeral    = "resumo_geral"
        case createdAt      = "created_at"
    }

    // Custom decoder: topicos can be [Topico] (new) or [String] (legacy)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        transcricaoId = try c.decode(UUID.self, forKey: .transcricaoId)
        titulo = try c.decode(String.self, forKey: .titulo)
        conceitosChave = try c.decode([ConceitoChave].self, forKey: .conceitosChave)
        resumoGeral = try c.decode(String.self, forKey: .resumoGeral)
        createdAt = try c.decode(Date.self, forKey: .createdAt)

        // Try new format [{titulo, conteudo}] first, fall back to [String]
        if let newTopicos = try? c.decode([Topico].self, forKey: .topicos) {
            topicos = newTopicos
        } else {
            let legacyStrings = try c.decode([String].self, forKey: .topicos)
            topicos = legacyStrings.map { Topico(titulo: $0, conteudo: "") }
        }
    }
}
