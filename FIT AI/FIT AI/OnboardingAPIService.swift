import Foundation

enum OnboardingAPIError: LocalizedError {
    case missingBaseURL
    case invalidResponse
    case serverError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "Backend URL is not configured."
        case .invalidResponse:
            return "Received malformed response from the onboarding service."
        case .serverError(let statusCode, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Onboarding failed (HTTP \(statusCode))."
            }
            return "Onboarding failed (HTTP \(statusCode)): \(trimmed)"
        }
    }
}

struct OnboardingSubmissionResponse: Decodable {
    let userId: String?
    let workoutPlan: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case workoutPlan = "workout_plan"
    }

    init(userId: String?, workoutPlan: String?) {
        self.userId = userId
        self.workoutPlan = workoutPlan
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        workoutPlan = try container.decodeIfPresent(String.self, forKey: .workoutPlan)
    }
}

struct OnboardingAPIService {
    static let shared = OnboardingAPIService()

    private let session: URLSession

    init(session: URLSession = OnboardingAPIService.defaultSession()) {
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

    func submit(form: OnboardingForm, email: String, password: String) async throws -> OnboardingSubmissionResponse {
        let url = BackendConfig.baseURL.appendingPathComponent("onboarding")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let formData = try encoder.encode(form)
        var payload = (try JSONSerialization.jsonObject(with: formData) as? [String: Any]) ?? [:]
        if form.userId == nil || form.userId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            payload.removeValue(forKey: "user_id")
        }
        payload["email"] = email
        payload["password"] = password
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OnboardingAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OnboardingAPIError.serverError(statusCode: http.statusCode, body: body)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(OnboardingSubmissionResponse.self, from: data)
        } catch {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
               let payload = jsonObject as? [String: Any] {
                let userId = payload["user_id"] as? String ?? payload["userId"] as? String
                let workoutPlan = payload["workout_plan"] as? String ?? payload["workoutPlan"] as? String
                if userId != nil || workoutPlan != nil {
                    return OnboardingSubmissionResponse(userId: userId, workoutPlan: workoutPlan)
                }
            }
            return OnboardingSubmissionResponse(userId: nil, workoutPlan: nil)
        }
    }
}
