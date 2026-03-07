import Foundation

private struct GerarResumoRequest: Encodable {
    let transcricaoId: UUID

    enum CodingKeys: String, CodingKey {
        case transcricaoId = "transcricao_id"
    }
}

private struct ResumoListResponse: Decodable {
    let resumos: [Resumo]
}

final class ResumosService {
    static let shared = ResumosService()
    private init() {}

    private let net = NetworkService.shared

    func gerar(transcricaoId: UUID) async throws -> Resumo {
        let body = GerarResumoRequest(transcricaoId: transcricaoId)
        return try await net.request(.POST, "/resumos", body: body)
    }

    /// Returns nil if no resumo exists yet (404).
    func buscar(transcricaoId: UUID) async throws -> Resumo? {
        do {
            let resumo: Resumo = try await net.request(.GET, "/resumos/\(transcricaoId)")
            return resumo
        } catch CoffeeAPIError.serverError(404, _) {
            return nil
        }
    }

    func listar(disciplinaId: UUID) async throws -> [Resumo] {
        let resp: ResumoListResponse = try await net.request(
            .GET, "/resumos?disciplina_id=\(disciplinaId)"
        )
        return resp.resumos
    }

    func atualizarTitulo(resumoId: UUID, titulo: String) async throws -> Resumo {
        struct Body: Encodable { let titulo: String }
        return try await net.request(.PATCH, "/resumos/\(resumoId)/titulo", body: Body(titulo: titulo))
    }
}
