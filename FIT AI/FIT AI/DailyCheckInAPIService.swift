import Foundation

// MARK: - Daily Check-In API Service

actor DailyCheckInAPIService {
    static let shared = DailyCheckInAPIService()
    
    private init() {}
    
    // MARK: - Models
    
    struct CheckInRequest: Encodable {
        let user_id: String
        let hit_macros: Bool
        let training_status: String
        let sleep_quality: String
    }
    
    struct CheckInResponse: Decodable {
        let coach_response: String
        let streak_saved: Bool
        let current_streak: Int?
    }
    
    struct CheckInStatusResponse: Decodable {
        let completed: Bool
        let checkin: CheckInData?
    }
    
    struct CheckInData: Decodable {
        let id: String?
        let date: String?
        let hit_macros: Bool?
        let training_status: String?
        let sleep_quality: String?
        let coach_response: String?
    }
    
    // MARK: - API Calls
    
    /// Submit daily check-in and get AI coach response
    func submitCheckIn(
        userId: String,
        hitMacros: Bool,
        trainingStatus: DailyCheckInData.TrainingStatus,
        sleepQuality: DailyCheckInData.SleepQuality
    ) async throws -> CheckInResponse {
        let url = BackendConfig.baseURL.appendingPathComponent("streaks/daily-checkin")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = CheckInRequest(
            user_id: userId,
            hit_macros: hitMacros,
            training_status: trainingStatus.rawValue,
            sleep_quality: sleepQuality.rawValue
        )
        
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        return try JSONDecoder().decode(CheckInResponse.self, from: data)
    }
    
    /// Check if user has completed today's check-in
    func getCheckInStatus(userId: String) async throws -> CheckInStatusResponse {
        var components = URLComponents(url: BackendConfig.baseURL.appendingPathComponent("streaks/daily-checkin/status"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "user_id", value: userId)]
        
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        return try JSONDecoder().decode(CheckInStatusResponse.self, from: data)
    }
    
    // MARK: - Errors
    
    enum APIError: LocalizedError {
        case invalidResponse
        case networkError(Error)
        
        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from server"
            case .networkError(let error):
                return error.localizedDescription
            }
        }
    }
}


