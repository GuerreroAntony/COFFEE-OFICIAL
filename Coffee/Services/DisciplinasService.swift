import Foundation

struct DisciplinasListResponse: Decodable {
    let disciplinas: [Disciplina]
}

struct DisciplinaDetailResponse: Decodable {
    let disciplina: Disciplina
    let gravacoesCount: Int
    let materiaisCount: Int

    enum CodingKeys: String, CodingKey {
        case disciplina
        case gravacoesCount = "gravacoes_count"
        case materiaisCount = "materiais_count"
    }
}

private struct CriarDisciplinaBody: Encodable {
    let nome: String
    let professor: String
    let semestre: String
}

final class DisciplinasService {
    static let shared = DisciplinasService()
    private init() {}

    func criar(nome: String, professor: String = "", semestre: String = "") async throws -> Disciplina {
        let body = CriarDisciplinaBody(nome: nome, professor: professor, semestre: semestre)
        return try await NetworkService.shared.request(.POST, "/disciplinas", body: body)
    }

    func fetchDisciplinas() async throws -> [Disciplina] {
        let response: DisciplinasListResponse = try await NetworkService.shared.request(
            .GET, "/disciplinas"
        )
        return response.disciplinas
    }

    func fetchDisciplinaDetail(id: UUID) async throws -> DisciplinaDetailResponse {
        return try await NetworkService.shared.request(
            .GET, "/disciplinas/\(id.uuidString.lowercased())"
        )
    }
}
