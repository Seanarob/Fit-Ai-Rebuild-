import Foundation

struct FoodItemMetadata: Decodable {
    let foodId: String?
    let brand: String?
    let restaurant: String?
    let foodType: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case foodId = "food_id"
        case brand
        case restaurant
        case foodType = "food_type"
        case source
    }
}

struct FoodItem: Decodable, Identifiable {
    let id: String
    let fdcId: String?
    let source: String
    let name: String
    let serving: String?
    let protein: Double
    let carbs: Double
    let fats: Double
    let calories: Double
    let brand: String?
    let restaurant: String?
    let foodType: String?
    let isBranded: Bool?
    let servingOptions: [ServingOptionPayload]?
    let metadata: FoodItemMetadata?
    
    enum CodingKeys: String, CodingKey {
        case id
        case fdcId = "fdc_id"
        case source
        case name
        case serving
        case protein
        case carbs
        case fats
        case calories
        case brand
        case restaurant
        case foodType = "food_type"
        case isBranded = "is_branded"
        case servingOptions = "serving_options"
        case metadata
    }
    
    /// Convert serving options to the model struct
    var parsedServingOptions: [ServingOption] {
        guard let options = servingOptions else { return [] }
        return options.compactMap { opt in
            ServingOption(
                id: opt.id ?? UUID().uuidString,
                description: opt.description ?? "1 serving",
                metricGrams: opt.metricGrams,
                numberOfUnits: opt.numberOfUnits ?? 1.0,
                calories: opt.calories ?? 0,
                protein: opt.protein ?? 0,
                carbs: opt.carbs ?? 0,
                fats: opt.fats ?? 0
            )
        }
    }

    var brandName: String? {
        let direct = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct, !direct.isEmpty { return direct }
        let metadataBrand = metadata?.brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let metadataBrand, !metadataBrand.isEmpty { return metadataBrand }
        return nil
    }

    var foodTypeLabel: String? {
        let direct = foodType?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct, !direct.isEmpty { return direct }
        let metadataType = metadata?.foodType?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let metadataType, !metadataType.isEmpty { return metadataType }
        return nil
    }

    var restaurantName: String? {
        let direct = restaurant?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct, !direct.isEmpty { return direct }
        let metadataRestaurant = metadata?.restaurant?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let metadataRestaurant, !metadataRestaurant.isEmpty { return metadataRestaurant }
        if let foodTypeLabel, foodTypeLabel.lowercased().contains("restaurant") {
            return brandName
        }
        return nil
    }

    var isRestaurantResolved: Bool {
        if let restaurantName, !restaurantName.isEmpty { return true }
        if let foodTypeLabel, foodTypeLabel.lowercased().contains("restaurant") { return true }
        return false
    }

    var isBrandedResolved: Bool {
        if let isBranded { return isBranded }
        if let brandName, !brandName.isEmpty { return true }
        if let foodTypeLabel {
            let lowered = foodTypeLabel.lowercased()
            if lowered.contains("brand") || lowered.contains("restaurant") { return true }
        }
        return false
    }

    var displayBrandLabel: String? {
        if let restaurantName { return restaurantName }
        return brandName
    }
}

struct ServingOptionPayload: Decodable {
    let id: String?
    let description: String?
    let metricGrams: Double?
    let numberOfUnits: Double?
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fats: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case description
        case metricGrams = "metric_grams"
        case numberOfUnits = "number_of_units"
        case calories
        case protein
        case carbs
        case fats
    }
}

struct NutritionSearchResponse: Decodable {
    let results: [FoodItem]
}

struct MealPhotoScanResult {
    let food: FoodItem?
    let items: [String]
    let photoUrl: String?
    let query: String?
    let message: String?
}

struct MacroTargets {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double

    var asDictionary: [String: Double] {
        [
            "calories": calories,
            "protein": protein,
            "carbs": carbs,
            "fats": fats,
        ]
    }
}

struct MealPlanMeal: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var macros: MacroTotals
    var items: [String]
    
    // Convenience computed properties for direct macro access
    var calories: Int { Int(macros.calories) }
    var protein: Int { Int(macros.protein) }
    var carbs: Int { Int(macros.carbs) }
    var fats: Int { Int(macros.fats) }
    
    static func == (lhs: MealPlanMeal, rhs: MealPlanMeal) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct MealPlanSnapshot {
    var meals: [MealPlanMeal]
    let totals: MacroTotals?
    let notes: String?
}

struct NutritionAPIService {
    static let shared = NutritionAPIService()

    private let session: URLSession
    private let dateFormatter = NutritionAPIService.logDateFormatter()

    init(session: URLSession = NutritionAPIService.defaultSession()) {
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

    private static func logDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    func searchFoods(query: String, userId: String) async throws -> [FoodItem] {
        let url = BackendConfig.baseURL.appendingPathComponent("nutrition/fatsecret/search")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "user_id", value: userId),
        ]
        guard let finalURL = components?.url else {
            return []
        }

        let (data, response) = try await session.data(from: finalURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

#if DEBUG
        if let body = String(data: data, encoding: .utf8) {
            print("Nutrition search response:", body)
        }
#endif

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(NutritionSearchResponse.self, from: data)
        return payload.results
    }
    
    /// Lightweight autocomplete for food name suggestions while typing.
    /// Returns just string suggestions, not full food items.
    func autocompleteFoods(query: String, maxResults: Int = 10) async throws -> [String] {
        guard query.count >= 2 else { return [] }
        
        let url = BackendConfig.baseURL.appendingPathComponent("nutrition/fatsecret/autocomplete")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "max_results", value: String(maxResults)),
        ]
        guard let finalURL = components?.url else {
            return []
        }

        let (data, response) = try await session.data(from: finalURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["suggestions"] as? [String] ?? []
    }

    func fetchFoodByBarcode(code: String, userId: String? = nil) async throws -> FoodItem {
        let url = BackendConfig.baseURL.appendingPathComponent("nutrition/fatsecret/barcode")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "barcode", value: code)]
        if let userId {
            queryItems.append(URLQueryItem(name: "user_id", value: userId))
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
        return try decoder.decode(FoodItem.self, from: data)
    }

    func fetchFoodDetail(fdcId: String, userId: String? = nil) async throws -> FoodItem {
        var url = BackendConfig.baseURL.appendingPathComponent("nutrition/usda/food")
        url.appendPathComponent(fdcId)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let userId {
            components?.queryItems = [URLQueryItem(name: "user_id", value: userId)]
        }
        guard let finalURL = components?.url else {
            throw OnboardingAPIError.invalidResponse
        }

        let (data, response) = try await session.data(from: finalURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FoodItem.self, from: data)
    }

    func scanMealPhoto(userId: String, mealType: String, photoUrl: String) async throws -> MealPhotoScanResult {
        let url = BackendConfig.baseURL.appendingPathComponent("scan/meal-photo")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "user_id": userId,
            "meal_type": mealType,
            "photo_url": photoUrl,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        return try parseMealScanResponse(data: data)
    }

    func scanMealPhoto(userId: String, mealType: String, imageData: Data) async throws -> MealPhotoScanResult {
        let url = BackendConfig.baseURL.appendingPathComponent("scan/meal-photo")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendFormField(named: "user_id", value: userId, to: &body, boundary: boundary)
        appendFormField(named: "meal_type", value: mealType, to: &body, boundary: boundary)
        appendFileField(
            named: "photo",
            filename: "meal.jpg",
            contentType: "image/jpeg",
            data: imageData,
            to: &body,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        return try parseMealScanResponse(data: data)
    }

    func fetchDailyLogs(userId: String, date: Date = Date()) async throws -> [NutritionLogEntry] {
        let url = BackendConfig.baseURL.appendingPathComponent("nutrition/logs")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let dateString = dateFormatter.string(from: date)
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "log_date", value: dateString),
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
        let payload = try decoder.decode(NutritionLogResponse.self, from: data)
        return payload.logs
    }

    func logManualItem(
        userId: String,
        date: Date = Date(),
        mealType: String,
        item: LoggedFoodItem
    ) async throws {
        let url = BackendConfig.baseURL.appendingPathComponent("nutrition/logs/manual")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "user_id": userId,
            "meal_type": mealType,
            "log_date": dateFormatter.string(from: date),
            "item": [
                "name": item.name,
                "portion_value": item.portionValue,
                "portion_unit": item.portionUnit.rawValue,
                "calories": item.macros.calories,
                "protein": item.macros.protein,
                "carbs": item.macros.carbs,
                "fats": item.macros.fats,
                "serving": item.detail,
                "brand": item.brandName,
                "restaurant": item.restaurantName,
                "source": item.source,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }
    }

    func fetchFavorites(userId: String) async throws -> [FoodItem] {
        let url = BackendConfig.baseURL.appendingPathComponent("nutrition/favorites")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "limit", value: "100"),
        ]
        guard let finalURL = components?.url else {
            throw OnboardingAPIError.invalidResponse
        }

        let (data, response) = try await session.data(from: finalURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let favorites = json?["favorites"] as? [[String: Any]] ?? []
        let favoritesData = try JSONSerialization.data(withJSONObject: favorites, options: [])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([FoodItem].self, from: favoritesData)
    }

    func saveFavorite(userId: String, food: FoodItem) async throws {
        let url = BackendConfig.baseURL.appendingPathComponent("nutrition/favorites")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var foodPayload: [String: Any] = [
            "id": food.id,
            "source": food.source,
            "name": food.name,
            "protein": food.protein,
            "carbs": food.carbs,
            "fats": food.fats,
            "calories": food.calories,
        ]
        if let serving = food.serving {
            foodPayload["serving"] = serving
        }
        if let fdcId = food.fdcId {
            foodPayload["fdc_id"] = fdcId
        }

        var metadata: [String: Any] = ["source": food.source]
        if let metadataFoodId = food.metadata?.foodId {
            metadata["food_id"] = metadataFoodId
        } else if food.source == "fatsecret" {
            metadata["food_id"] = food.id
        }
        if let fdcId = food.fdcId {
            metadata["fdc_id"] = fdcId
        }
        if let brand = food.brandName {
            metadata["brand"] = brand
        }
        if let restaurant = food.restaurantName {
            metadata["restaurant"] = restaurant
        }
        if let foodType = food.foodTypeLabel {
            metadata["food_type"] = foodType
        }
        metadata["external_id"] = food.id
        foodPayload["metadata"] = metadata

        let payload: [String: Any] = [
            "user_id": userId,
            "food": foodPayload,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }
    }

    func fetchActiveMealPlan(userId: String) async throws -> MealPlanSnapshot? {
        let url = BackendConfig.baseURL.appendingPathComponent("mealplan/active")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "user_id", value: userId)]
        guard let finalURL = components?.url else {
            return nil
        }

        let (data, response) = try await session.data(from: finalURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data)
        return await MainActor.run {
            MealPlanSnapshotBuilder.snapshot(from: json)
        }
    }

    func generateMealPlan(userId: String, targets: MacroTargets) async throws -> MealPlanSnapshot? {
        let url = BackendConfig.baseURL.appendingPathComponent("mealplan/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "user_id": userId,
            "macro_targets": targets.asDictionary,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnboardingAPIError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data)
        return await MainActor.run {
            MealPlanSnapshotBuilder.snapshot(from: json)
        }
    }
}

private extension NutritionAPIService {
    func parseMealScanResponse(data: Data) throws -> MealPhotoScanResult {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let photoUrl = json?["photo_url"] as? String
        let query = json?["query"] as? String
        let message = (json?["message"] as? String) ?? (json?["ai_result"] as? String) ?? (json?["result"] as? String)
        var items = extractMealItems(from: json)

        if items.isEmpty, let aiResult = json?["ai_result"] as? String {
            items = parseMealItems(from: aiResult)
        }

        if items.isEmpty, let query, !query.isEmpty {
            items = parseMealItems(from: query)
        }

        if let match = json?["match"] as? [String: Any] {
            let matchData = try JSONSerialization.data(withJSONObject: match, options: [])
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let food = try decoder.decode(FoodItem.self, from: matchData)
            return MealPhotoScanResult(food: food, items: items, photoUrl: photoUrl, query: query, message: message)
        }

        return MealPhotoScanResult(food: nil, items: items, photoUrl: photoUrl, query: query, message: message ?? "Scan complete.")
    }

    func extractMealItems(from json: [String: Any]?) -> [String] {
        guard let json else { return [] }
        if let items = json["items"] as? [String] { return normalizeMealItems(items) }
        if let items = json["foods"] as? [String] { return normalizeMealItems(items) }
        if let items = json["detected_items"] as? [String] { return normalizeMealItems(items) }
        if let items = json["recognized_items"] as? [String] { return normalizeMealItems(items) }
        if let items = json["meal_items"] as? [String] { return normalizeMealItems(items) }
        if let items = json["food_items"] as? [String] { return normalizeMealItems(items) }
        if let items = json["ingredients"] as? [String] { return normalizeMealItems(items) }
        if let items = json["items"] as? [[String: Any]] {
            let names = items.compactMap { $0["name"] as? String ?? $0["item"] as? String ?? $0["food"] as? String }
            return normalizeMealItems(names)
        }
        if let items = json["foods"] as? [[String: Any]] {
            let names = items.compactMap { $0["name"] as? String ?? $0["item"] as? String ?? $0["food"] as? String }
            return normalizeMealItems(names)
        }
        if let items = json["detected_items"] as? [[String: Any]] {
            let names = items.compactMap { $0["name"] as? String ?? $0["item"] as? String ?? $0["food"] as? String }
            return normalizeMealItems(names)
        }
        if let query = json["query"] as? String {
            return parseMealItems(from: query)
        }
        return []
    }

    func extractMealItems(from array: [Any]) -> [String] {
        var names: [String] = []
        for value in array {
            if let string = value as? String {
                names.append(string)
                continue
            }
            if let dict = value as? [String: Any] {
                if let name = dict["name"] as? String ?? dict["item"] as? String ?? dict["food"] as? String {
                    names.append(name)
                    continue
                }
                if let nested = dict["items"] as? [String] {
                    names.append(contentsOf: nested)
                }
            }
        }
        return normalizeMealItems(names)
    }

    func parseMealItems(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let jsonItems = extractItemsFromEmbeddedJSON(in: trimmed) {
            return jsonItems
        }

        var cleanedText = trimmed
        cleanedText = cleanedText.replacingOccurrences(of: "•", with: "\n")
        cleanedText = cleanedText.replacingOccurrences(of: " - ", with: "\n")

        if cleanedText.range(of: " and ", options: .caseInsensitive) != nil && !cleanedText.contains(",") {
            cleanedText = cleanedText.replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
        }

        let separators = CharacterSet(charactersIn: ",;\n")
        let pieces = cleanedText.components(separatedBy: separators)
        if pieces.count > 1 {
            return normalizeMealItems(pieces)
        }

        let lines = cleanedText.split(separator: "\n").map { String($0) }
        if lines.count > 1 {
            return normalizeMealItems(lines)
        }

        return normalizeMealItems([cleanedText])
    }

    func extractItemsFromEmbeddedJSON(in text: String) -> [String]? {
        let data = text.data(using: .utf8)
        if let data {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let items = extractMealItems(from: json)
                if !items.isEmpty {
                    return items
                }
            }
            if let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                let items = extractMealItems(from: array)
                if !items.isEmpty {
                    return items
                }
            }
        }

        guard let startIndex = text.firstIndex(of: "{"),
              let endIndex = text.lastIndex(of: "}") else {
            return nil
        }

        let substring = String(text[startIndex...endIndex])
        guard let data = substring.data(using: .utf8) else {
            return nil
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let items = extractMealItems(from: json)
            return items.isEmpty ? nil : items
        }

        if let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            let items = extractMealItems(from: array)
            return items.isEmpty ? nil : items
        }

        return nil
    }

    func normalizeMealItems(_ items: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for item in items {
            var cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned = cleaned.replacingOccurrences(of: #"^\s*[-•*\d\.\)\]]+\s*"#, with: "", options: .regularExpression)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(cleaned)
        }
        return result
    }
}

@MainActor
private enum MealPlanSnapshotBuilder {
    static func snapshot(from json: Any) -> MealPlanSnapshot? {
        if let root = json as? [String: Any] {
            if let plan = root["plan"] {
                return snapshot(fromPlan: plan, notes: root["summary"] as? String)
            }
            if let plan = root["meal_plan"] {
                return snapshot(fromPlan: plan, notes: root["summary"] as? String)
            }
            if let plan = root["data"] {
                return snapshot(fromPlan: plan, notes: root["summary"] as? String)
            }
            return snapshot(fromPlan: root, notes: root["summary"] as? String)
        }
        return nil
    }

    private static func snapshot(fromPlan plan: Any, notes: String?) -> MealPlanSnapshot? {
        if let planDict = plan as? [String: Any] {
            if let meals = parseMeals(from: planDict) {
                let totals = parseTotals(from: planDict)
                return MealPlanSnapshot(meals: meals, totals: totals, notes: notes)
            }
            if let days = planDict["days"] as? [[String: Any]], let first = days.first {
                let meals = parseMeals(from: first) ?? []
                let totals = parseTotals(from: first) ?? parseTotals(from: planDict)
                return MealPlanSnapshot(meals: meals, totals: totals, notes: notes)
            }
        }
        if let planArray = plan as? [[String: Any]], let first = planArray.first {
            let meals = parseMeals(from: first) ?? []
            let totals = parseTotals(from: first)
            return MealPlanSnapshot(meals: meals, totals: totals, notes: notes)
        }
        return nil
    }

    private static func parseMeals(from dict: [String: Any]) -> [MealPlanMeal]? {
        if let mealsArray = dict["meals"] as? [[String: Any]] {
            return mealsArray.compactMap(parseMeal)
        }
        if let mealMap = dict["meal_map"] as? [[String: Any]] {
            return mealMap.compactMap(parseMeal)
        }
        return nil
    }

    private static func parseMeal(from dict: [String: Any]) -> MealPlanMeal? {
        let name = (dict["name"] as? String) ?? (dict["title"] as? String) ?? "Meal"
        let macros = parseTotals(from: dict) ?? MacroTotals.zero
        let items = parseMealItems(from: dict)
        return MealPlanMeal(name: name, macros: macros, items: items)
    }

    private static func parseMealItems(from dict: [String: Any]) -> [String] {
        if let items = dict["items"] {
            return normalizeMealPlanItems(items)
        }
        if let ingredients = dict["ingredients"] {
            return normalizeMealPlanItems(ingredients)
        }
        if let foods = dict["foods"] {
            return normalizeMealPlanItems(foods)
        }
        return []
    }

    private static func normalizeMealPlanItems(_ raw: Any) -> [String] {
        if let items = raw as? [String] {
            return items.compactMap(cleanItemString)
        }
        if let items = raw as? [Any] {
            return items.compactMap(formatMealPlanItem)
        }
        if let dict = raw as? [String: Any], let formatted = formatMealPlanItem(dict) {
            return [formatted]
        }
        return []
    }

    private static func formatMealPlanItem(_ value: Any) -> String? {
        if let string = value as? String {
            return cleanItemString(string)
        }
        if let dict = value as? [String: Any] {
            return formatMealPlanItem(dict)
        }
        return nil
    }

    private static func formatMealPlanItem(_ dict: [String: Any]) -> String? {
        let name = stringValue(dict["name"])
            ?? stringValue(dict["item"])
            ?? stringValue(dict["ingredient"])
            ?? stringValue(dict["food"])
            ?? stringValue(dict["title"])
        let quantity = extractQuantity(from: dict)

        if let name, let quantity {
            if name.localizedCaseInsensitiveContains(quantity) {
                return name
            }
            return "\(name) - \(quantity)"
        }
        if let name { return name }
        if let quantity { return quantity }
        return nil
    }

    private static func extractQuantity(from dict: [String: Any]) -> String? {
        if let quantityDict = dict["quantity"] as? [String: Any],
           let nested = quantityFromComponents(quantityDict) {
            return nested
        }
        if let servingDict = dict["serving"] as? [String: Any],
           let nested = quantityFromComponents(servingDict) {
            return nested
        }

        let quantityString = stringValue(dict["quantity"])
            ?? stringValue(dict["qty"])
            ?? stringValue(dict["amount"])
            ?? stringValue(dict["portion"])
            ?? stringValue(dict["serving"])
            ?? stringValue(dict["servings"])
            ?? stringValue(dict["size"])
            ?? stringValue(dict["serving_size"])

        let unit = stringValue(dict["unit"])
            ?? stringValue(dict["units"])
            ?? stringValue(dict["measurement"])
            ?? stringValue(dict["measure"])

        if let quantityString {
            if let unit, !quantityString.localizedCaseInsensitiveContains(unit) {
                return "\(quantityString) \(unit)"
            }
            return quantityString
        }

        if let unit { return unit }
        return nil
    }

    private static func quantityFromComponents(_ dict: [String: Any]) -> String? {
        let amount = stringValue(dict["value"])
            ?? stringValue(dict["amount"])
            ?? stringValue(dict["qty"])
            ?? stringValue(dict["quantity"])
        let unit = stringValue(dict["unit"])
            ?? stringValue(dict["units"])
            ?? stringValue(dict["measure"])
            ?? stringValue(dict["measurement"])

        if let amount {
            if let unit { return "\(amount) \(unit)" }
            return amount
        }
        return unit
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let int = value as? Int {
            return "\(int)"
        }
        if let double = value as? Double {
            let rounded = (double * 100).rounded() / 100
            if rounded == floor(rounded) {
                return "\(Int(rounded))"
            }
            return "\(rounded)"
        }
        if let float = value as? Float {
            let rounded = (Double(float) * 100).rounded() / 100
            if rounded == floor(rounded) {
                return "\(Int(rounded))"
            }
            return "\(rounded)"
        }
        return nil
    }

    private static func cleanItemString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseTotals(from dict: [String: Any]) -> MacroTotals? {
        if let totals = dict["totals"] as? [String: Any] {
            return MacroTotals.fromDictionary(totals)
        }
        if let totals = dict["daily_totals"] as? [String: Any] {
            return MacroTotals.fromDictionary(totals)
        }
        if let macros = dict["macros"] as? [String: Any] {
            return MacroTotals.fromDictionary(macros)
        }
        return nil
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
