import Foundation

struct ProfileAPIService {
    static let shared = ProfileAPIService()

    private let session: URLSession

    init(session: URLSession = ProfileAPIService.defaultSession()) {
        self.session = session
    }

    private static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        if let anonKey = SupabaseConfig.anonKey {
            config.httpAdditionalHeaders = [
                "apikey": anonKey,
                "Authorization": "Bearer \(anonKey)",
            ]
        }
        return URLSession(configuration: config)
    }

    func fetchProfile(userId: String) async throws -> [String: Any] {
        let url = BackendConfig.baseURL.appendingPathComponent("profiles/\(userId)")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw OnboardingAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OnboardingAPIError.serverError(statusCode: http.statusCode, body: body)
        }
        return try parseProfile(from: data)
    }

    func updateProfile(userId: String, payload: [String: Any]) async throws -> [String: Any] {
        let url = BackendConfig.baseURL.appendingPathComponent("profiles/\(userId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OnboardingAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OnboardingAPIError.serverError(statusCode: http.statusCode, body: body)
        }
        return try parseProfile(from: data)
    }

    private func parseProfile(from data: Data) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = json as? [String: Any],
              let profile = dict["profile"] as? [String: Any]
        else {
            throw OnboardingAPIError.invalidResponse
        }
        return profile
    }
}
