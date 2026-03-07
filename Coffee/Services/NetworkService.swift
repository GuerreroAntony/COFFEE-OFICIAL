import Foundation

enum HTTPMethod: String {
    case GET, POST, PUT, DELETE, PATCH
}

enum CoffeeAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "URL inválida."
        case .unauthorized:        return "Sessão expirada. Faça login novamente."
        case .serverError(let c, let m): return "Erro \(c): \(m)"
        case .decodingError(let e):  return "Erro ao decodificar resposta: \(e)"
        case .networkError(let e):   return "Erro de rede: \(e)"
        }
    }
}

final class NetworkService {
    static let shared = NetworkService()
    private init() {}

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let formatters: [(DateFormatter, String)] = [
                {
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
                    return (f, str)
                }(),
                {
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
                    return (f, str)
                }(),
                {
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.dateFormat = "yyyy-MM-dd"
                    return (f, str)
                }()
            ]
            for (fmt, s) in formatters {
                if let date = fmt.date(from: s) { return date }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    func request<T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: (some Encodable)? = nil as String?,
        authenticated: Bool = true,
        timeout: TimeInterval = 60
    ) async throws -> T {
        guard let url = URL(string: AppConfig.apiURL + path) else {
            throw CoffeeAPIError.invalidURL
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: timeout)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = KeychainService.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoffeeAPIError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 {
            KeychainService.shared.deleteToken()
            NotificationCenter.default.post(name: .coffeeUnauthorized, object: nil)
            throw CoffeeAPIError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CoffeeAPIError.serverError(httpResponse.statusCode, message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CoffeeAPIError.decodingError(error)
        }
    }

    func upload<T: Decodable>(
        _ path: String,
        fileURL: URL,
        fieldName: String = "file"
    ) async throws -> T {
        guard let url = URL(string: AppConfig.apiURL + path) else {
            throw CoffeeAPIError.invalidURL
        }

        let boundary = UUID().uuidString
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = KeychainService.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mimeType = filename.hasSuffix(".m4a") ? "audio/m4a" : "audio/wav"

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        urlRequest.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoffeeAPIError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 {
            KeychainService.shared.deleteToken()
            NotificationCenter.default.post(name: .coffeeUnauthorized, object: nil)
            throw CoffeeAPIError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CoffeeAPIError.serverError(httpResponse.statusCode, message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CoffeeAPIError.decodingError(error)
        }
    }

    func stream(
        _ method: HTTPMethod,
        _ path: String,
        body: (some Encodable)?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let url = URL(string: AppConfig.apiURL + path) else {
                    continuation.finish(throwing: CoffeeAPIError.invalidURL)
                    return
                }

                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = method.rawValue
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                if let token = KeychainService.shared.getToken() {
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }

                if let body {
                    urlRequest.httpBody = try? JSONEncoder().encode(body)
                }

                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: urlRequest)
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let content = String(line.dropFirst(6))
                            if content != "[DONE]" {
                                continuation.yield(content)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: CoffeeAPIError.networkError(error))
                }
            }
        }
    }
}

extension Notification.Name {
    static let coffeeUnauthorized = Notification.Name("coffeeUnauthorized")
}
