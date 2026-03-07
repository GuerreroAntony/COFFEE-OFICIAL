import Foundation

struct CriarGravacaoRequest: Encodable {
    let disciplinaId: UUID
    let dataAula: String  // ISO date "yyyy-MM-dd"

    enum CodingKeys: String, CodingKey {
        case disciplinaId = "disciplina_id"
        case dataAula     = "data_aula"
    }
}

struct GravacaoListResponse: Decodable {
    let gravacoes: [Gravacao]
}

final class GravacoesService {
    static let shared = GravacoesService()
    private init() {}

    private let net = NetworkService.shared

    func criar(disciplinaId: UUID, dataAula: Date) async throws -> Gravacao {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let body = CriarGravacaoRequest(disciplinaId: disciplinaId, dataAula: fmt.string(from: dataAula))
        return try await net.request(.POST, "/gravacoes", body: body)
    }

    func upload(gravacaoId: UUID, fileURL: URL) async throws -> Gravacao {
        return try await net.upload("/gravacoes/\(gravacaoId)/upload", fileURL: fileURL)
    }

    func listar(disciplinaId: UUID) async throws -> [Gravacao] {
        let resp: GravacaoListResponse = try await net.request(.GET, "/gravacoes/disciplina/\(disciplinaId)")
        return resp.gravacoes
    }

    func get(gravacaoId: UUID) async throws -> Gravacao {
        return try await net.request(.GET, "/gravacoes/\(gravacaoId)")
    }

    func deletar(gravacaoId: UUID) async throws {
        let _: EmptyResponse = try await net.request(.DELETE, "/gravacoes/\(gravacaoId)")
    }
}

private struct EmptyResponse: Decodable {}
