import Foundation

struct CheckinPhoto: Decodable, Identifiable {
    let id = UUID()
    let url: String
    let type: String?

    enum CodingKeys: String, CodingKey {
        case url
        case type
    }
}

struct CheckinSummaryMeta: Decodable {
    let comparisonSource: String?
    let photoCount: Int?

    enum CodingKeys: String, CodingKey {
        case comparisonSource = "comparison_source"
        case photoCount = "photo_count"
    }
}

struct CheckinSummaryParsed: Decodable {
    let improvements: [String]
    let needsWork: [String]
    let photoNotes: [String]
    let photoFocus: [String]
    let targets: [String]
    let summary: String?
    let macroDelta: MacroTotalsPayload?
    let newMacros: MacroTotalsPayload?
    let updateMacros: Bool?
    let cardioRecommendation: String?
    let cardioPlan: [String]

    enum CodingKeys: String, CodingKey {
        case improvements
        case improved
        case whatImproved = "what_improved"
        case needsWork = "needs_work"
        case needs
        case stillNeeds = "still_needs"
        case photoNotes = "photo_notes"
        case photoAnalysis = "photo_analysis"
        case photoComparison = "photo_comparison"
        case visualChanges = "visual_changes"
        case photoFocus = "photo_focus"
        case analysisFocus = "analysis_focus"
        case targets
        case nextWeekTargets = "next_week_targets"
        case nextWeek = "next_week"
        case summary
        case recap
        case coachRecap = "coach_recap"
        case macroDelta = "macro_delta"
        case newMacros = "new_macros"
        case nextWeekMacros = "next_week_macros"
        case macroTargets = "macro_targets"
        case updateMacros = "update_macros"
        case cardioUpdate = "cardio_update"
        case cardioRecommendation = "cardio_recommendation"
        case cardioPlan = "cardio_plan"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        improvements = Self.decodeStringList(from: container, keys: [.improvements, .improved, .whatImproved]) ?? []
        needsWork = Self.decodeStringList(from: container, keys: [.needsWork, .needs, .stillNeeds]) ?? []
        photoNotes = Self.decodeStringList(
            from: container,
            keys: [.photoNotes, .photoAnalysis, .photoComparison, .visualChanges]
        ) ?? []
        photoFocus = Self.decodeStringList(from: container, keys: [.photoFocus, .analysisFocus]) ?? []
        targets = Self.decodeStringList(from: container, keys: [.targets, .nextWeekTargets, .nextWeek]) ?? []

        summary = Self.decodeStringValue(from: container, keys: [.summary, .recap, .coachRecap])

        macroDelta = Self.decodeMacroPayload(from: container, keys: [.macroDelta])
        newMacros = Self.decodeMacroPayload(
            from: container,
            keys: [.newMacros, .nextWeekMacros, .macroTargets]
        )
        updateMacros = (try? container.decodeIfPresent(Bool.self, forKey: .updateMacros)) ?? nil

        if let update = (try? container.decodeIfPresent(CardioUpdate.self, forKey: .cardioUpdate)) ?? nil {
            cardioRecommendation = update.recommendation
            cardioPlan = update.plan ?? []
        } else {
            cardioRecommendation = Self.decodeStringValue(
                from: container,
                keys: [.cardioRecommendation]
            )
            cardioPlan = Self.decodeStringList(from: container, keys: [.cardioPlan]) ?? []
        }
    }

    private static func decodeStringValue(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func decodeStringList(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> [String]? {
        for key in keys {
            if let list = (try? container.decodeIfPresent([String].self, forKey: key)) ?? nil {
                let cleaned = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !cleaned.isEmpty { return cleaned }
            }
            if let value = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return [trimmed]
                }
            }
        }
        return nil
    }

    private static func decodeMacroPayload(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> MacroTotalsPayload? {
        for key in keys {
            if let value = try? container.decodeIfPresent(MacroTotalsPayload.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}

struct CheckinSummary: Decodable {
    let raw: String?
    let parsed: CheckinSummaryParsed?
    let meta: CheckinSummaryMeta?

    enum CodingKeys: String, CodingKey {
        case raw
        case parsed
        case meta
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            raw = try? container.decodeIfPresent(String.self, forKey: .raw)
            parsed = try? container.decodeIfPresent(CheckinSummaryParsed.self, forKey: .parsed)
            meta = try? container.decodeIfPresent(CheckinSummaryMeta.self, forKey: .meta)
            return
        }
        let single = try decoder.singleValueContainer()
        raw = try? single.decode(String.self)
        parsed = nil
        meta = nil
    }
}

struct MacroUpdate: Decodable {
    let suggested: Bool?
    let delta: MacroTotalsPayload?
    let newMacros: MacroTotalsPayload?
    let applied: Bool?

    enum CodingKeys: String, CodingKey {
        case suggested
        case delta
        case newMacros = "new_macros"
        case macros
        case applied
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            suggested = try? container.decodeIfPresent(Bool.self, forKey: .suggested)
            delta = try? container.decodeIfPresent(MacroTotalsPayload.self, forKey: .delta)
            if let newValue = try? container.decodeIfPresent(MacroTotalsPayload.self, forKey: .newMacros) {
                newMacros = newValue
            } else if let newValue = try? container.decodeIfPresent(MacroTotalsPayload.self, forKey: .macros) {
                newMacros = newValue
            } else {
                newMacros = nil
            }
            applied = try? container.decodeIfPresent(Bool.self, forKey: .applied)
            return
        }
        suggested = nil
        delta = nil
        newMacros = nil
        applied = nil
    }
}

struct CardioUpdate: Decodable {
    let suggested: Bool?
    let recommendation: String?
    let plan: [String]?

    enum CodingKeys: String, CodingKey {
        case suggested
        case recommendation
        case summary
        case change
        case notes
        case plan
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            suggested = try? container.decodeIfPresent(Bool.self, forKey: .suggested)
            recommendation = Self.decodeFirstString(from: container, keys: [.recommendation, .summary, .change, .notes])
            plan = try? container.decodeIfPresent([String].self, forKey: .plan)
            return
        }
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(String.self) {
            recommendation = value
            plan = nil
        } else if let list = try? single.decode([String].self) {
            recommendation = nil
            plan = list
        } else {
            recommendation = nil
            plan = nil
        }
        suggested = nil
    }

    private static func decodeFirstString(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }
}

struct WeeklyCheckin: Decodable, Identifiable {
    let rawId: String?
    let userId: String?
    let date: String?
    let createdAt: String?
    let weight: Double?
    let photos: [CheckinPhoto]?
    let aiSummary: CheckinSummary?
    let macroUpdate: MacroUpdate?
    let cardioUpdate: CardioUpdate?

    var id: String { rawId ?? date ?? createdAt ?? UUID().uuidString }

    var dateValue: Date? {
        if let date {
            return WeeklyCheckin.dateFormatter.date(from: date) ?? ISO8601DateFormatter().date(from: date)
        }
        if let createdAt {
            return ISO8601DateFormatter().date(from: createdAt)
        }
        return nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case userId = "user_id"
        case date
        case createdAt = "created_at"
        case weight
        case photos
        case aiSummary = "ai_summary"
        case macroUpdate = "macro_update"
        case cardioUpdate = "cardio_update"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawId = try container.decodeIfPresent(String.self, forKey: .rawId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        photos = try container.decodeIfPresent([CheckinPhoto].self, forKey: .photos)
        aiSummary = try container.decodeIfPresent(CheckinSummary.self, forKey: .aiSummary)
        macroUpdate = try? container.decodeIfPresent(MacroUpdate.self, forKey: .macroUpdate)
        cardioUpdate = try? container.decodeIfPresent(CardioUpdate.self, forKey: .cardioUpdate)
    }
}

struct CheckinListResponse: Decodable {
    let checkins: [WeeklyCheckin]
}

struct CheckinSubmitResponse: Decodable {
    let status: String?
    let aiResult: String?
    let checkin: WeeklyCheckin?

    enum CodingKeys: String, CodingKey {
        case status
        case aiResult = "ai_result"
        case checkin
    }
}

struct ProgressPhotoUploadResponse: Decodable {
    let status: String?
    let photoUrl: String?
    let photoType: String?
    let photoCategory: String?
    let date: String?

    enum CodingKeys: String, CodingKey {
        case status
        case photoUrl = "photo_url"
        case photoType = "photo_type"
        case photoCategory = "photo_category"
        case date
    }
}

struct ProgressPhoto: Decodable, Identifiable {
    let rawId: String?
    let userId: String?
    let date: String?
    let url: String
    let type: String?
    let category: String?

    var id: String { rawId ?? url }

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case userId = "user_id"
        case date
        case createdAt = "created_at"
        case url
        case type
        case photoType = "photo_type"
        case category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawId = try container.decodeIfPresent(String.self, forKey: .rawId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        url = try container.decode(String.self, forKey: .url)
        if let decodedDate = try container.decodeIfPresent(String.self, forKey: .date) {
            date = decodedDate
        } else {
            date = try container.decodeIfPresent(String.self, forKey: .createdAt)
        }
        if let decodedType = try container.decodeIfPresent(String.self, forKey: .type) {
            type = decodedType
        } else {
            type = try container.decodeIfPresent(String.self, forKey: .photoType)
        }
        category = try container.decodeIfPresent(String.self, forKey: .category)
    }
}

struct ProgressPhotoListResponse: Decodable {
    let photos: [ProgressPhoto]
}

struct MacroTotalsPayload: Decodable {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fats: Double?

    var totals: MacroTotals {
        MacroTotals(
            calories: calories ?? 0,
            protein: protein ?? 0,
            carbs: carbs ?? 0,
            fats: fats ?? 0
        )
    }
}

struct MacroAdherenceDay: Decodable, Identifiable {
    let date: String
    let logged: MacroTotalsPayload?
    let target: MacroTotalsPayload?

    var id: String { date }

    var dateValue: Date? {
        MacroAdherenceDay.dateFormatter.date(from: date) ?? ISO8601DateFormatter().date(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

struct MacroAdherenceResponse: Decodable {
    let days: [MacroAdherenceDay]
}

extension WeeklyCheckin {
    var suggestedMacros: MacroTotals? {
        if let totals = macroUpdate?.newMacros?.totals, totals != .zero {
            return totals
        }
        if let totals = aiSummary?.parsed?.newMacros?.totals, totals != .zero {
            return totals
        }
        return nil
    }

    var macroDeltaTotals: MacroTotals? {
        if let delta = macroUpdate?.delta?.totals, delta != .zero {
            return delta
        }
        if let delta = aiSummary?.parsed?.macroDelta?.totals, delta != .zero {
            return delta
        }
        return nil
    }

    var macroUpdateSuggested: Bool {
        if let suggested = macroUpdate?.suggested {
            return suggested
        }
        if let suggested = aiSummary?.parsed?.updateMacros {
            return suggested
        }
        return suggestedMacros != nil || macroDeltaTotals != nil
    }

    var cardioSummary: String? {
        if let recommendation = cardioUpdate?.recommendation,
           !recommendation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recommendation
        }
        if let recommendation = aiSummary?.parsed?.cardioRecommendation,
           !recommendation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recommendation
        }
        return nil
    }

    var cardioPlan: [String] {
        if let plan = cardioUpdate?.plan, !plan.isEmpty {
            return plan
        }
        let parsedPlan = aiSummary?.parsed?.cardioPlan ?? []
        return parsedPlan
    }
}

struct ProgressAPIService {
    static let shared = ProgressAPIService()

    private let session: URLSession
    private static let checkinDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    init(session: URLSession = ProgressAPIService.defaultSession()) {
        self.session = session
    }

    private static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90  // Increased for AI analysis
        if let anonKey = SupabaseConfig.anonKey {
            config.httpAdditionalHeaders = [
                "apikey": anonKey,
                "Authorization": "Bearer \(anonKey)",
            ]
        }
        return URLSession(configuration: config)
    }

    func fetchCheckins(userId: String, limit: Int = 12) async throws -> [WeeklyCheckin] {
        let url = BackendConfig.baseURL.appendingPathComponent("checkins")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "limit", value: String(limit)),
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
        let payload = try decoder.decode(CheckinListResponse.self, from: data)
        return payload.checkins
    }

    func fetchLatestCheckinSummary(userId: String) async throws -> String? {
        let url = BackendConfig.baseURL.appendingPathComponent("checkins")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let finalURL = components?.url else {
            throw OnboardingAPIError.invalidResponse
        }

        let (data, response) = try await session.data(from: finalURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any],
              let checkins = root["checkins"] as? [[String: Any]],
              let first = checkins.first
        else {
            return nil
        }

        if let summary = first["ai_summary"] as? [String: Any] {
            return summary["raw"] as? String
        }
        if let summary = first["ai_summary"] as? String {
            return summary
        }
        return nil
    }

    func uploadProgressPhoto(
        userId: String,
        checkinDate: Date,
        photoType: String?,
        photoCategory: String?,
        imageData: Data
    ) async throws -> ProgressPhotoUploadResponse {
        let url = BackendConfig.baseURL.appendingPathComponent("progress/photos")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendFormField(named: "user_id", value: userId, to: &body, boundary: boundary)
        appendFormField(
            named: "checkin_date",
            value: ProgressAPIService.checkinDateFormatter.string(from: checkinDate),
            to: &body,
            boundary: boundary
        )
        if let photoType {
            appendFormField(named: "photo_type", value: photoType, to: &body, boundary: boundary)
        }
        if let photoCategory {
            appendFormField(named: "photo_category", value: photoCategory, to: &body, boundary: boundary)
        }
        appendFileField(
            named: "photo",
            filename: "checkin.jpg",
            contentType: "image/jpeg",
            data: imageData,
            to: &body,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

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
        return try decoder.decode(ProgressPhotoUploadResponse.self, from: data)
    }

    func fetchProgressPhotos(
        userId: String,
        limit: Int = 60,
        category: String? = nil,
        photoType: String? = nil
    ) async throws -> [ProgressPhoto] {
        let url = BackendConfig.baseURL.appendingPathComponent("progress/photos")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let category {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if let photoType {
            queryItems.append(URLQueryItem(name: "photo_type", value: photoType))
        }
        components?.queryItems = queryItems
        guard let finalURL = components?.url else {
            throw OnboardingAPIError.invalidResponse
        }

        let (data, response) = try await session.data(from: finalURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(ProgressPhotoListResponse.self, from: data)
        return payload.photos
    }

    func fetchMacroAdherence(userId: String, rangeDays: Int) async throws -> [MacroAdherenceDay] {
        let url = BackendConfig.baseURL.appendingPathComponent("progress/macro-adherence")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "range_days", value: String(rangeDays)),
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
        let payload = try decoder.decode(MacroAdherenceResponse.self, from: data)
        return payload.days
    }

    func submitCheckin(
        userId: String,
        checkinDate: Date,
        adherence: [String: Any],
        photos: [[String: String]]
    ) async throws -> CheckinSubmitResponse {
        let url = BackendConfig.baseURL.appendingPathComponent("checkins/")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(
                name: "checkin_date",
                value: ProgressAPIService.checkinDateFormatter.string(from: checkinDate)
            ),
        ]
        guard let finalURL = components?.url else {
            throw OnboardingAPIError.invalidResponse
        }
        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let photoUrls = photos.compactMap { $0["url"] }
        var payload: [String: Any] = ["adherence": adherence]
        if !photoUrls.isEmpty {
            payload["photo_urls"] = photoUrls
        }

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
        return try decoder.decode(CheckinSubmitResponse.self, from: data)
    }
}

private func appendFormField(named name: String, value: String, to body: inout Data, boundary: String) {
    body.appendString("--\(boundary)\r\n")
    body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
    body.appendString("\(value)\r\n")
}

private func appendFileField(
    named name: String,
    filename: String,
    contentType: String,
    data: Data,
    to body: inout Data,
    boundary: String
) {
    body.appendString("--\(boundary)\r\n")
    body.appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
    body.appendString("Content-Type: \(contentType)\r\n\r\n")
    body.append(data)
    body.appendString("\r\n")
}

private extension Data {
    mutating func appendString(_ value: String) {
        if let data = value.data(using: .utf8) {
            append(data)
        }
    }
}
