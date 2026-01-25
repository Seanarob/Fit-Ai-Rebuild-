import Foundation

struct WorkoutTemplate: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let mode: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case mode
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let rawTitle = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmedTitle.isEmpty ? "Workout" : trimmedTitle
        description = try container.decodeIfPresent(String.self, forKey: .description)
        let rawMode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "manual"
        let trimmedMode = rawMode.trimmingCharacters(in: .whitespacesAndNewlines)
        mode = trimmedMode.isEmpty ? "manual" : trimmedMode
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct WorkoutSession: Decodable, Identifiable {
    let id: String
    let templateId: String?
    let templateTitle: String?
    let status: String
    let durationSeconds: Int?
    let createdAt: String?
}

struct WorkoutTemplateExercise: Decodable, Identifiable {
    let exerciseId: String?
    let name: String
    let muscleGroups: [String]
    let equipment: [String]
    let sets: Int?
    let reps: Int?
    let restSeconds: Int?
    let notes: String?
    let position: Int?

    var id: String { exerciseId ?? "\(name)-\(position ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case exerciseId
        case name
        case muscleGroups
        case equipment
        case sets
        case reps
        case restSeconds
        case notes
        case position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func decodeStringArray(_ key: CodingKeys) -> [String] {
            if let array = try? container.decode([String].self, forKey: key) {
                return array
            }
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? [] : [trimmed]
            }
            return []
        }

        func decodeInt(_ key: CodingKeys) -> Int? {
            if let value = try? container.decode(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(Double.self, forKey: key) {
                return Int(value)
            }
            if let value = try? container.decode(String.self, forKey: key) {
                return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }

        exerciseId = try container.decodeIfPresent(String.self, forKey: .exerciseId)
        let rawName = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmedName.isEmpty ? "Exercise" : trimmedName
        muscleGroups = decodeStringArray(.muscleGroups)
        equipment = decodeStringArray(.equipment)
        sets = decodeInt(.sets)
        reps = decodeInt(.reps)
        restSeconds = decodeInt(.restSeconds)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        position = try container.decodeIfPresent(Int.self, forKey: .position)
    }
}

struct WorkoutTemplateDetailResponse: Decodable {
    let template: WorkoutTemplate
    let exercises: [WorkoutTemplateExercise]

    enum CodingKeys: String, CodingKey {
        case template
        case exercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        template = try container.decode(WorkoutTemplate.self, forKey: .template)
        exercises = (try? container.decode([WorkoutTemplateExercise].self, forKey: .exercises)) ?? []
    }
}

struct WorkoutTemplateResponse: Decodable {
    let templates: [WorkoutTemplate]
}

struct WorkoutSessionResponse: Decodable {
    let sessions: [WorkoutSession]
}

struct WorkoutTemplateCreateResponse: Decodable {
    let templateId: String
}

struct WorkoutTemplateUpdateResponse: Decodable {
    let templateId: String
}

struct WorkoutTemplateDuplicateResponse: Decodable {
    let templateId: String
}

struct WorkoutStartSessionResponse: Decodable {
    let sessionId: String
}

struct WorkoutSessionPRUpdate: Decodable, Identifiable {
    let exerciseName: String
    let value: Double
    let previousValue: Double?

    var id: String { exerciseName }
}

struct WorkoutSessionCompleteResponse: Decodable {
    let sessionId: String
    let status: String
    let durationSeconds: Int
    let prs: [WorkoutSessionPRUpdate]
}

struct WorkoutSessionLogEntry: Decodable, Identifiable {
    let id: String
    let exerciseName: String
    let sets: Int
    let reps: Int
    let weight: Double
    let durationMinutes: Int?
    let notes: String?
    let createdAt: String?
}

struct WorkoutSessionLogsResponse: Decodable {
    let sessionId: String
    let logs: [WorkoutSessionLogEntry]
}

struct ExerciseHistoryBestSet: Decodable {
    let weight: Double
    let reps: Int
    let estimated1rm: Double
}

struct ExerciseHistoryEntry: Decodable, Identifiable {
    let id: String
    let date: String?
    let sets: Int
    let reps: Int
    let weight: Double
    let estimated1rm: Double
}

struct ExerciseHistoryTrendEntry: Decodable, Identifiable {
    let date: String?
    let estimated1rm: Double

    var id: String {
        "\(date ?? "unknown")-\(estimated1rm)"
    }
}

struct ExerciseHistoryResponse: Decodable {
    let exerciseName: String
    let entries: [ExerciseHistoryEntry]
    let bestSet: ExerciseHistoryBestSet?
    let estimated1rm: Double
    let trend: [ExerciseHistoryTrendEntry]
}

struct WorkoutExerciseInput: Encodable {
    let name: String
    let muscleGroups: [String]
    let equipment: [String]
    let sets: Int?
    let reps: Int?
    let restSeconds: Int?
    let notes: String?
}

struct WorkoutAPIService {
    static let shared = WorkoutAPIService()

    private let session: URLSession

    init(session: URLSession = WorkoutAPIService.defaultSession()) {
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

    func fetchTemplates(userId: String) async throws -> [WorkoutTemplate] {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/templates")
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
        let payload = try decoder.decode(WorkoutTemplateResponse.self, from: data)
        return payload.templates
    }

    func fetchSessions(userId: String) async throws -> [WorkoutSession] {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/sessions")
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
        let payload = try decoder.decode(WorkoutSessionResponse.self, from: data)
        return payload.sessions
    }

    func fetchTemplateDetail(templateId: String) async throws -> WorkoutTemplateDetailResponse {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/templates/\(templateId)")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(WorkoutTemplateDetailResponse.self, from: data)
    }

    func createTemplate(
        userId: String,
        title: String,
        description: String?,
        mode: String = "manual",
        exercises: [WorkoutExerciseInput]
    ) async throws -> String {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/templates")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let exercisesPayload: [[String: Any]] = exercises.map { exercise in
            var entry: [String: Any] = [
                "name": exercise.name,
                "muscle_groups": exercise.muscleGroups,
                "equipment": exercise.equipment,
            ]
            if let sets = exercise.sets { entry["sets"] = sets }
            if let reps = exercise.reps { entry["reps"] = reps }
            if let rest = exercise.restSeconds { entry["rest_seconds"] = rest }
            if let notes = exercise.notes { entry["notes"] = notes }
            return entry
        }

        var payload: [String: Any] = [
            "user_id": userId,
            "title": title,
            "mode": mode,
            "exercises": exercisesPayload,
        ]
        if let description {
            payload["description"] = description
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(WorkoutTemplateCreateResponse.self, from: data)
        return result.templateId
    }

    func updateTemplate(
        templateId: String,
        title: String,
        description: String?,
        mode: String = "manual",
        exercises: [WorkoutExerciseInput]
    ) async throws -> String {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/templates/\(templateId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let exercisesPayload: [[String: Any]] = exercises.map { exercise in
            var entry: [String: Any] = [
                "name": exercise.name,
                "muscle_groups": exercise.muscleGroups,
                "equipment": exercise.equipment,
            ]
            if let sets = exercise.sets { entry["sets"] = sets }
            if let reps = exercise.reps { entry["reps"] = reps }
            if let rest = exercise.restSeconds { entry["rest_seconds"] = rest }
            if let notes = exercise.notes { entry["notes"] = notes }
            return entry
        }

        var payload: [String: Any] = [
            "title": title,
            "mode": mode,
            "exercises": exercisesPayload,
        ]
        if let description {
            payload["description"] = description
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(WorkoutTemplateUpdateResponse.self, from: data)
        return result.templateId
    }

    func deleteTemplate(templateId: String) async throws {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/templates/\(templateId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }
    }

    func duplicateTemplate(templateId: String, userId: String) async throws -> String {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/templates/\(templateId)/duplicate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["user_id": userId],
            options: []
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(WorkoutTemplateDuplicateResponse.self, from: data)
        return result.templateId
    }

    func startSession(userId: String, templateId: String?) async throws -> String {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/sessions/start")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = ["user_id": userId]
        if let templateId {
            payload["template_id"] = templateId
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(WorkoutStartSessionResponse.self, from: data)
        return result.sessionId
    }

    func logExerciseSet(
        sessionId: String,
        exerciseName: String,
        sets: Int,
        reps: Int,
        weight: Double,
        notes: String?
    ) async throws {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/sessions/\(sessionId)/log")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "exercise_name": exerciseName,
            "sets": sets,
            "reps": reps,
            "weight": weight,
        ]
        if let notes {
            payload["notes"] = notes
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }
    }

    func logCardioDuration(
        sessionId: String,
        exerciseName: String,
        durationMinutes: Int,
        notes: String?
    ) async throws {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/sessions/\(sessionId)/log")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "exercise_name": exerciseName,
            "duration_minutes": durationMinutes,
        ]
        if let notes {
            payload["notes"] = notes
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }
    }

    func completeSession(sessionId: String, durationSeconds: Int) async throws -> WorkoutSessionCompleteResponse {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/sessions/\(sessionId)/complete")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["duration_seconds": durationSeconds, "status": "completed"],
            options: []
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(WorkoutSessionCompleteResponse.self, from: data)
    }

    func fetchSessionLogs(sessionId: String) async throws -> [WorkoutSessionLogEntry] {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/sessions/\(sessionId)/logs")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(WorkoutSessionLogsResponse.self, from: data)
        return payload.logs
    }

    func fetchExerciseHistory(userId: String, exerciseName: String) async throws -> ExerciseHistoryResponse {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/exercises/history")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "exercise_name", value: exerciseName),
        ]
        guard let finalURL = components?.url else {
            throw OnboardingAPIError.invalidResponse
        }

        let (data, response) = try await session.data(from: finalURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ExerciseHistoryResponse.self, from: data)
    }

    func searchExercises(query: String) async throws -> [ExerciseDefinition] {
        let url = BackendConfig.baseURL.appendingPathComponent("exercises/search")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "30"),
        ]
        guard let finalURL = components?.url else {
            return []
        }

        let (data, response) = try await session.data(from: finalURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        struct ExerciseSearchResponse: Decodable {
            let results: [ExerciseDefinitionResponse]
        }

        struct EquipmentValue: Decodable {
            let values: [String]

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let string = try? container.decode(String.self) {
                    values = [string]
                    return
                }
                if let array = try? container.decode([String].self) {
                    values = array
                    return
                }
                values = []
            }
        }

        struct ExerciseDefinitionResponse: Decodable {
            let name: String
            let muscleGroups: [String]?
            let primaryMuscles: [String]?
            let equipment: EquipmentValue?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(ExerciseSearchResponse.self, from: data)
        return payload.results.map {
            let muscles = $0.muscleGroups ?? $0.primaryMuscles ?? []
            let equipment = $0.equipment?.values ?? []
            return ExerciseDefinition(
                name: $0.name,
                muscleGroups: muscles,
                equipment: equipment
            )
        }
    }

    func generateWorkout(
        userId: String,
        muscleGroups: [String],
        workoutType: String?,
        equipment: [String]?,
        durationMinutes: Int?
    ) async throws -> String {
        let url = BackendConfig.baseURL.appendingPathComponent("workouts/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "user_id": userId,
            "muscle_groups": muscleGroups,
        ]
        if let workoutType {
            payload["workout_type"] = workoutType
        }
        if let equipment, !equipment.isEmpty {
            payload["equipment"] = equipment
        }
        if let durationMinutes {
            payload["duration_minutes"] = durationMinutes
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["template"] as? String ?? ""
    }
}
