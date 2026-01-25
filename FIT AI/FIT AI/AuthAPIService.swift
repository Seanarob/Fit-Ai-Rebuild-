import Foundation

struct AuthRegisterResponse: Decodable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

struct AuthLoginResponse: Decodable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

struct AuthAPIService {
    static let shared = AuthAPIService()

    private let session: URLSession

    init(session: URLSession = AuthAPIService.defaultSession()) {
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

    func register(email: String, password: String, role: String = "user") async throws -> AuthRegisterResponse {
        let url = BackendConfig.baseURL.appendingPathComponent("auth/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["email": email, "password": password, "role": role]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OnboardingAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OnboardingAPIError.serverError(statusCode: http.statusCode, body: body)
        }

        guard !data.isEmpty else {
            throw OnboardingAPIError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(AuthRegisterResponse.self, from: data)
        } catch {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
               let payload = jsonObject as? [String: Any],
               let userId = payload["user_id"] as? String ?? payload["userId"] as? String {
                return AuthRegisterResponse(userId: userId)
            }
            throw error
        }
    }

    func login(email: String, password: String) async throws -> AuthLoginResponse {
        let url = BackendConfig.baseURL.appendingPathComponent("auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OnboardingAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OnboardingAPIError.serverError(statusCode: http.statusCode, body: body)
        }

        guard !data.isEmpty else {
            throw OnboardingAPIError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(AuthLoginResponse.self, from: data)
        } catch {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
               let payload = jsonObject as? [String: Any],
               let userId = payload["user_id"] as? String ?? payload["userId"] as? String {
                return AuthLoginResponse(userId: userId)
            }
            throw error
        }
    }
}
