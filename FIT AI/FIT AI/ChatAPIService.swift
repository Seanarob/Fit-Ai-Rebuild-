import Foundation

struct ChatThread: Decodable, Identifiable {
    let id: String
    let title: String?
    let createdAt: String?
    let updatedAt: String?
    let lastMessageAt: String?
}

struct ChatMessagePayload: Decodable, Identifiable {
    let id: String
    let role: String
    let content: String
    let createdAt: String?
}

struct ChatThreadListResponse: Decodable {
    let threads: [ChatThread]
}

struct ChatThreadDetailResponse: Decodable {
    let thread: ChatThread
    let messages: [ChatMessagePayload]
    let summary: String?
}

struct ChatThreadCreateResponse: Decodable {
    let thread: ChatThread
}

struct ChatAPIService {
    static let shared = ChatAPIService()

    private let session: URLSession

    init(session: URLSession = ChatAPIService.defaultSession()) {
        self.session = session
    }

    private static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        // Increased timeouts to accommodate AI model response time
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        if let anonKey = SupabaseConfig.anonKey {
            config.httpAdditionalHeaders = [
                "apikey": anonKey,
                "Authorization": "Bearer \(anonKey)",
            ]
        }
        return URLSession(configuration: config)
    }

    func createThread(userId: String, title: String? = nil) async throws -> ChatThread {
        let url = BackendConfig.baseURL.appendingPathComponent("chat/thread")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = ["user_id": userId]
        if let title, !title.isEmpty {
            payload["title"] = title
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payloadResponse = try decoder.decode(ChatThreadCreateResponse.self, from: data)
        return payloadResponse.thread
    }

    func fetchThreads(userId: String) async throws -> [ChatThread] {
        let url = BackendConfig.baseURL.appendingPathComponent("chat/threads")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "user_id", value: userId)]
        guard let finalURL = components?.url else {
            return []
        }

        let (data, response) = try await session.data(from: finalURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payloadResponse = try decoder.decode(ChatThreadListResponse.self, from: data)
        return payloadResponse.threads
    }

    func fetchThreadDetail(userId: String, threadId: String) async throws -> ChatThreadDetailResponse {
        let url = BackendConfig.baseURL.appendingPathComponent("chat/thread/\(threadId)")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "user_id", value: userId)]
        guard let finalURL = components?.url else {
            throw OnboardingAPIError.invalidResponse
        }

        let (data, response) = try await session.data(from: finalURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ChatThreadDetailResponse.self, from: data)
    }

    func sendMessageStream(
        userId: String,
        threadId: String,
        content: String,
        onChunk: @escaping (String) -> Void
    ) async throws {
        let url = BackendConfig.baseURL.appendingPathComponent("chat/message")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let payload: [String: Any] = [
            "user_id": userId,
            "thread_id": threadId,
            "content": content,
            "stream": true,
        ]
        var payloadWithContext = payload
        if let snapshot = localWorkoutSnapshot() {
            payloadWithContext["local_workout_snapshot"] = snapshot
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payloadWithContext, options: [])

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let chunk = String(line.dropFirst(6))
            if chunk == "[DONE]" {
                break
            }
            if !chunk.isEmpty {
                onChunk(chunk)
            }
        }
    }

    private func localWorkoutSnapshot() -> [String: Any]? {
        guard let session = WorkoutSessionStore.load() else { return nil }

        var lastCompleted: [String: Any]? = nil
        for exercise in session.exercises {
            for setEntry in exercise.sets where setEntry.isComplete {
                lastCompleted = [
                    "exercise_name": exercise.name,
                    "reps": setEntry.reps,
                    "weight": setEntry.weight,
                    "is_warmup": setEntry.isWarmup,
                ]
            }
        }

        let exercises: [[String: Any]] = session.exercises.map { exercise in
            let sets: [[String: Any]] = exercise.sets.map { entry in
                [
                    "reps": entry.reps,
                    "weight": entry.weight,
                    "is_complete": entry.isComplete,
                    "is_warmup": entry.isWarmup,
                ]
            }
            return [
                "name": exercise.name,
                "sets": sets,
                "rest_seconds": exercise.restSeconds,
                "notes": exercise.notes,
            ]
        }

        var snapshot: [String: Any] = [
            "title": session.title,
            "workout_elapsed_seconds": session.workoutElapsed,
            "is_paused": session.isPaused,
            "rest_remaining": session.restRemaining,
            "rest_active": session.restActive,
            "exercises": exercises,
        ]

        if let lastCompleted {
            snapshot["last_completed_set"] = lastCompleted
        }

        return snapshot
    }
}
