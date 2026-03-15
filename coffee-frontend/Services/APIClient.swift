import Foundation

// MARK: - API Client
// URLSession-based API client with mock/live toggle
// Base URL: https://api-coffee.up.railway.app/api/v1

final class APIClient: @unchecked Sendable {

    // MARK: - Configuration

    static let shared = APIClient()

    /// Toggle between mock data and live API
    static var useMocks = false

    private let baseURL = "https://coffee-oficial-production.up.railway.app/api/v1"
    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.decoder = .coffeeDecoder
    }

    // MARK: - HTTP Methods

    enum HTTPMethod: String {
        case GET, POST, PUT, PATCH, DELETE
    }

    // MARK: - Request Builder

    private func buildRequest(
        path: String,
        method: HTTPMethod = .GET,
        body: Encodable? = nil,
        authenticated: Bool = true
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.unknown("URL invalida: \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = KeychainManager.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    // MARK: - Generic Request

    func request<T: Decodable>(
        path: String,
        method: HTTPMethod = .GET,
        body: Encodable? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let request = try buildRequest(
            path: path,
            method: method,
            body: body,
            authenticated: authenticated
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown("Resposta invalida")
        }

        // Handle error responses
        if httpResponse.statusCode >= 400 {
            if let errorResponse = try? decoder.decode(APIResponse<EmptyData>.self, from: data) {
                throw APIError.from(
                    code: errorResponse.error ?? "UNKNOWN",
                    message: errorResponse.message
                )
            }
            throw APIError.unknown("Erro HTTP \(httpResponse.statusCode)")
        }

        // Decode successful response
        do {
            let apiResponse = try decoder.decode(APIResponse<T>.self, from: data)
            guard let result = apiResponse.data else {
                throw APIError.unknown(apiResponse.message ?? "Dados vazios")
            }
            return result
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Paginated Request

    func paginatedRequest<T: Decodable>(
        path: String,
        page: Int = 1,
        perPage: Int = 20
    ) async throws -> ([T], Pagination?) {
        let separator = path.contains("?") ? "&" : "?"
        let paginatedPath = "\(path)\(separator)page=\(page)&per_page=\(perPage)"

        let request = try buildRequest(path: paginatedPath)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode < 400 else {
            throw APIError.unknown("Erro na requisicao paginada")
        }

        let paginatedResponse = try decoder.decode(PaginatedResponse<T>.self, from: data)
        return (paginatedResponse.data ?? [], paginatedResponse.pagination)
    }

    // MARK: - SSE Stream (for AI Chat)

    /// Streams SSE events from the backend.
    /// Backend sends JSON lines: {"token": "word"} for text, {"done": true, ...} to finish.
    /// This method parses the JSON and yields only the token text.
    func streamRequest(
        path: String,
        body: Encodable
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = try buildRequest(path: path, method: .POST, body: body)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: APIError.aiError)
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))

                            // Legacy plain-text done marker
                            if data == "[DONE]" {
                                continuation.finish()
                                return
                            }

                            // Parse JSON payload
                            guard let jsonData = data.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                                // Not JSON — yield raw text as fallback
                                continuation.yield(data)
                                continue
                            }

                            // Done event: {"done": true, "message_id": ..., "sources": [...], ...}
                            if let done = json["done"] as? Bool, done {
                                continuation.finish()
                                return
                            }

                            // Token event: {"token": "word"}
                            if let token = json["token"] as? String {
                                continuation.yield(token)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Empty Data (for error-only responses)

struct EmptyData: Decodable {}
