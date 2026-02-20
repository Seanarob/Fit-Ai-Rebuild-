import Foundation

protocol MealAPIClientProtocol: Sendable {
    func analyzeVoiceMeal(_ request: VoiceMealAnalyzeRequest) async throws -> VoiceMealAnalyzeResponse
    func repriceVoiceMeal(_ request: VoiceMealRepriceRequest) async throws -> VoiceMealRepriceResponse
    func logMeal(_ request: VoiceMealLogRequest) async throws -> VoiceMealLogResponse
}

final class MealAPIClient: MealAPIClientProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let cache = VoiceLogAnalyzeCache()
    
    init(baseURL: URL = BackendConfig.baseURL, session: URLSession = MealAPIClient.defaultSession()) {
        self.baseURL = baseURL
        self.session = session
    }
    
    func analyzeVoiceMeal(_ request: VoiceMealAnalyzeRequest) async throws -> VoiceMealAnalyzeResponse {
        if let cached = await cache.get(transcript: request.transcript) {
            return cached
        }
        
        let perform = { [baseURL, session] in
            try await Self.postJSON(
                session: session,
                url: baseURL.appendingPathComponent("meal/voice/analyze"),
                body: request,
                responseType: VoiceMealAnalyzeResponse.self
            )
        }
        
        do {
            let response = try await perform()
            await cache.put(transcript: request.transcript, response: response)
            return response
        } catch {
            guard Self.shouldRetry(error: error) else { throw error }
            // One retry with exponential backoff.
            try await Task.sleep(nanoseconds: 300_000_000 * 2)
            let response = try await perform()
            await cache.put(transcript: request.transcript, response: response)
            return response
        }
    }
    
    func repriceVoiceMeal(_ request: VoiceMealRepriceRequest) async throws -> VoiceMealRepriceResponse {
        try await Self.postJSON(
            session: session,
            url: baseURL.appendingPathComponent("meal/voice/reprice"),
            body: request,
            responseType: VoiceMealRepriceResponse.self
        )
    }
    
    func logMeal(_ request: VoiceMealLogRequest) async throws -> VoiceMealLogResponse {
        try await Self.postJSON(
            session: session,
            url: baseURL.appendingPathComponent("meal/log"),
            body: request,
            responseType: VoiceMealLogResponse.self
        )
    }
    
    private static func postJSON<Body: Encodable, Response: Decodable>(
        session: URLSession,
        url: URL,
        body: Body,
        responseType: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.withoutEscapingSlashes]
        request.httpBody = try encoder.encode(body)
        
#if DEBUG
        if let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8) {
            print("VoiceLog request:", url.absoluteString, bodyString)
        }
#endif
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoiceLogAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = (message["detail"] as? String) ?? (message["error"] as? String) {
                throw VoiceLogAPIError.server(message: detail)
            }
            throw VoiceLogAPIError.server(message: "Request failed (\(http.statusCode)). Please try again.")
        }
        
#if DEBUG
        if let bodyString = String(data: data, encoding: .utf8) {
            print("VoiceLog response:", url.absoluteString, bodyString)
        }
#endif
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw VoiceLogAPIError.decoding
        }
    }
    
    private static func shouldRetry(error: Error) -> Bool {
        if error is URLError { return true }
        if let apiError = error as? VoiceLogAPIError, case .invalidResponse = apiError { return true }
        return false
    }

    private static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        if let anonKey = SupabaseConfig.anonKey {
            config.httpAdditionalHeaders = [
                "apikey": anonKey,
                "Authorization": "Bearer \(anonKey)",
            ]
        }
        return URLSession(configuration: config)
    }
}

actor VoiceLogAnalyzeCache {
    private struct Entry {
        var response: VoiceMealAnalyzeResponse
        var insertedAt: Date
    }
    
    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 60 * 5
    
    func get(transcript: String) -> VoiceMealAnalyzeResponse? {
        let key = transcript.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let entry = entries[key] else { return nil }
        if Date().timeIntervalSince(entry.insertedAt) > ttl {
            entries[key] = nil
            return nil
        }
        return entry.response
    }
    
    func put(transcript: String, response: VoiceMealAnalyzeResponse) {
        let key = transcript.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        entries[key] = Entry(response: response, insertedAt: Date())
    }
}
