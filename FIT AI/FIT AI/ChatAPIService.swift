import Foundation

enum ChatStreamEvent {
    case delta(String)
    case replace(String)
    case coachAction(CoachActionProposal)
}

private struct ChatStreamPayload: Decodable {
    let type: String
    let text: String?
    let action: CoachActionProposal?
}

enum CoachActionType: String, Decodable {
    case updateMacros = "update_macros"
    case updateWorkoutSplit = "update_workout_split"
}

struct CoachMacroTargets: Decodable {
    let calories: Int?
    let protein: Int?
    let carbs: Int?
    let fats: Int?
}

struct CoachSplitTargets: Decodable {
    let daysPerWeek: Int?
    let trainingDays: [String]?
    let splitType: String?
    let mode: String?
    let focus: String?

    enum CodingKeys: String, CodingKey {
        case daysPerWeek = "days_per_week"
        case trainingDays = "training_days"
        case splitType = "split_type"
        case mode
        case focus
    }
}

struct CoachActionProposal: Decodable, Identifiable {
    let id: String
    let actionType: CoachActionType
    let title: String
    let description: String
    let confirmationPrompt: String?
    let macros: CoachMacroTargets?
    let split: CoachSplitTargets?

    enum CodingKeys: String, CodingKey {
        case id
        case actionType = "action_type"
        case title
        case description
        case confirmationPrompt = "confirmation_prompt"
        case macros
        case split
    }

    init(
        id: String = UUID().uuidString,
        actionType: CoachActionType,
        title: String = "Coach update",
        description: String = "",
        confirmationPrompt: String? = nil,
        macros: CoachMacroTargets? = nil,
        split: CoachSplitTargets? = nil
    ) {
        self.id = id
        self.actionType = actionType
        self.title = title
        self.description = description
        self.confirmationPrompt = confirmationPrompt
        self.macros = macros
        self.split = split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        actionType = try container.decode(CoachActionType.self, forKey: .actionType)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Coach update"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        confirmationPrompt = try container.decodeIfPresent(String.self, forKey: .confirmationPrompt)
        macros = try container.decodeIfPresent(CoachMacroTargets.self, forKey: .macros)
        split = try container.decodeIfPresent(CoachSplitTargets.self, forKey: .split)
    }
}

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
    private let streamSession: URLSession

    init(
        session: URLSession = ChatAPIService.defaultSession(),
        streamSession: URLSession = ChatAPIService.streamingSession()
    ) {
        self.session = session
        self.streamSession = streamSession
    }

    private static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        applySupabaseHeaders(to: config)
        return URLSession(configuration: config)
    }

    private static func streamingSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 480
        applySupabaseHeaders(to: config)
        return URLSession(configuration: config)
    }

    private static func applySupabaseHeaders(to config: URLSessionConfiguration) {
        if let anonKey = SupabaseConfig.anonKey {
            config.httpAdditionalHeaders = [
                "apikey": anonKey,
                "Authorization": "Bearer \(anonKey)",
            ]
        }
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

        var request = URLRequest(url: finalURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
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

        var request = URLRequest(url: finalURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
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
        onEvent: @escaping (ChatStreamEvent) -> Void
    ) async throws {
        let url = BackendConfig.baseURL.appendingPathComponent("chat/message")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 240

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

        let (bytes, response) = try await streamSession.bytes(for: request)
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
                if let event = Self.parseStreamEvent(chunk) {
                    onEvent(event)
                } else {
                    onEvent(.delta(chunk))
                }
            }
        }
    }

    private static func parseStreamEvent(_ chunk: String) -> ChatStreamEvent? {
        guard let data = chunk.data(using: .utf8) else { return nil }
        guard let payload = try? JSONDecoder().decode(ChatStreamPayload.self, from: data) else { return nil }
        switch payload.type {
        case "delta":
            guard let text = payload.text else { return nil }
            return .delta(text)
        case "replace":
            guard let text = payload.text else { return nil }
            return .replace(text)
        case "coach_action":
            guard let action = payload.action else { return nil }
            return .coachAction(action)
        default:
            return nil
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
