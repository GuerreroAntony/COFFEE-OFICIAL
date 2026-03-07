import Foundation

struct AppConfig {
    #if DEBUG
    static let apiBaseURL = "http://localhost:8000"
    #else
    static let apiBaseURL = "https://coffee-api.up.railway.app"
    #endif
    static let apiVersion = "/api/v1"
    static var apiURL: String { apiBaseURL + apiVersion }
}
