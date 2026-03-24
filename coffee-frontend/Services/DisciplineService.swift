import Foundation

// MARK: - Discipline Service
// GET /disciplinas, GET /disciplinas/{id}
// GET /repositorios, POST /repositorios, PATCH /repositorios/{id}, DELETE /repositorios/{id}
// POST /espm/connect, POST /espm/sync, GET /espm/status, POST /espm/disconnect
// POST /compartilhamentos, GET /compartilhamentos/received,
// POST /compartilhamentos/{id}/accept, POST /compartilhamentos/{id}/reject

enum DisciplineService {

    // MARK: - Disciplines

    static func getDisciplines() async throws -> [Discipline] {
        if APIClient.useMocks {
            return MockData.disciplines
        }
        return try await APIClient.shared.request(path: APIEndpoints.disciplinas)
    }

    static func getDiscipline(id: String) async throws -> Discipline {
        if APIClient.useMocks {
            return MockData.disciplines.first { $0.id == id } ?? MockData.disciplines[0]
        }
        return try await APIClient.shared.request(
            path: APIEndpoints.disciplina(id: id)
        )
    }

    static func updateAppearance(disciplinaId: String, icon: String, iconColor: String) async throws {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.3))
            return
        }

        let body = UpdateAppearanceRequest(icon: icon, iconColor: iconColor)
        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.disciplinaAppearance(id: disciplinaId),
            method: .PATCH,
            body: body
        )
    }

    // MARK: - Repositories

    static func getRepositories() async throws -> [Repository] {
        if APIClient.useMocks {
            return MockData.repositories
        }
        return try await APIClient.shared.request(path: APIEndpoints.repositorios)
    }

    static func createRepository(name: String, icon: String = "folder") async throws -> Repository {
        if APIClient.useMocks {
            return Repository(
                id: UUID().uuidString,
                nome: name,
                icone: icon,
                gravacoesCount: 0,
                aiActive: false,
                createdAt: Date()
            )
        }

        let body = CreateRepositoryRequest(nome: name, icone: icon)
        return try await APIClient.shared.request(
            path: APIEndpoints.repositorios,
            method: .POST,
            body: body
        )
    }

    static func renameRepository(id: String, name: String) async throws -> Repository {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.3))
            var repo = MockData.repositories.first { $0.id == id } ?? MockData.repositories[0]
            repo.nome = name
            return repo
        }

        let body = RenameRepositoryRequest(nome: name)
        return try await APIClient.shared.request(
            path: APIEndpoints.repositorio(id: id),
            method: .PATCH,
            body: body
        )
    }

    static func deleteRepository(id: String) async throws {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.3))
            return
        }

        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.repositorio(id: id),
            method: .DELETE
        )
    }

    // MARK: - ESPM Connection

    static func connectESPM(matricula: String, canvasToken: String) async throws -> ESPMConnectResponse {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(2))
            return ESPMConnectResponse(
                status: "connected",
                disciplinasFound: MockData.disciplines.count,
                disciplinas: MockData.disciplines
            )
        }

        let body = ESPMConnectRequest(matricula: matricula, canvasToken: canvasToken)
        return try await APIClient.shared.request(
            path: APIEndpoints.espmConnect,
            method: .POST,
            body: body
        )
    }

    static func syncESPM() async throws -> ESPMConnectResponse {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(1.5))
            return ESPMConnectResponse(
                status: "connected",
                disciplinasFound: MockData.disciplines.count,
                disciplinas: MockData.disciplines
            )
        }

        return try await APIClient.shared.request(
            path: APIEndpoints.espmSync,
            method: .POST
        )
    }

    static func getESPMStatus() async throws -> ESPMStatus {
        if APIClient.useMocks {
            return MockData.espmStatus
        }
        return try await APIClient.shared.request(path: APIEndpoints.espmStatus)
    }

    static func disconnectESPM() async throws {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.5))
            return
        }

        try await APIClient.shared.requestVoid(
            path: APIEndpoints.espmDisconnect,
            method: .POST
        )
    }

    // MARK: - Discipline Sync (Canvas materials)

    static func syncDiscipline(id: String) async throws -> SyncResponse {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(1))
            return SyncResponse(status: "triggered", lastSyncedAt: Date())
        }

        return try await APIClient.shared.request(
            path: APIEndpoints.disciplinaSync(id: id),
            method: .POST
        )
    }

    // MARK: - Compartilhamentos (Sharing)

    static func shareRecording(
        gravacaoId: String,
        recipientEmails: [String],
        sharedContent: [String],
        message: String?
    ) async throws -> ShareResponse {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(1))
            return ShareResponse(
                sharedCount: recipientEmails.count,
                notFoundEmails: [],
                results: recipientEmails.map { ShareResultItem(email: $0, status: "sent") }
            )
        }

        let body = ShareRequest(
            gravacaoId: gravacaoId,
            recipientEmails: recipientEmails,
            sharedContent: sharedContent,
            message: message
        )
        return try await APIClient.shared.request(
            path: APIEndpoints.compartilhamentos,
            method: .POST,
            body: body
        )
    }

    static func shareRecordingByIds(request: ShareByIdsRequest) async throws -> ShareResponse {
        return try await APIClient.shared.request(
            path: APIEndpoints.compartilhamentos,
            method: .POST,
            body: request
        )
    }

    static func getSharedItems() async throws -> [SharedItem] {
        if APIClient.useMocks {
            return MockData.sharedItems
        }
        return try await APIClient.shared.request(
            path: APIEndpoints.compartilhamentosReceived
        )
    }

    static func acceptSharedItem(id: String, destinationType: String, destinationId: String) async throws -> AcceptShareResponse {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.5))
            return AcceptShareResponse(
                gravacaoId: UUID().uuidString,
                destinationType: destinationType,
                destinationId: destinationId,
                status: "accepted"
            )
        }

        let body = AcceptShareRequest(destinationType: destinationType, destinationId: destinationId)
        return try await APIClient.shared.request(
            path: APIEndpoints.compartilhamentoAccept(id: id),
            method: .POST,
            body: body
        )
    }

    static func rejectSharedItem(id: String) async throws {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.3))
            return
        }

        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.compartilhamentoReject(id: id),
            method: .POST
        )
    }
}
