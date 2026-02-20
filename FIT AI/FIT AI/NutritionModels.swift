import Combine
import Foundation
import SwiftUI

struct MacroTotals: Equatable, Codable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double

    static let zero = MacroTotals(calories: 0, protein: 0, carbs: 0, fats: 0)

    static func fromDictionary(_ dict: [String: Any]) -> MacroTotals {
        MacroTotals(
            calories: dict.doubleValue(for: "calories"),
            protein: dict.doubleValue(for: "protein"),
            carbs: dict.doubleValue(for: "carbs"),
            fats: dict.doubleValue(for: "fats")
        )
    }

    func adding(_ other: MacroTotals) -> MacroTotals {
        MacroTotals(
            calories: calories + other.calories,
            protein: protein + other.protein,
            carbs: carbs + other.carbs,
            fats: fats + other.fats
        )
    }
    
    func subtracting(_ other: MacroTotals) -> MacroTotals {
        MacroTotals(
            calories: max(0, calories - other.calories),
            protein: max(0, protein - other.protein),
            carbs: max(0, carbs - other.carbs),
            fats: max(0, fats - other.fats)
        )
    }

    static func fromLogTotals(_ totals: NutritionLogTotals?) -> MacroTotals {
        guard let totals else { return .zero }
        return MacroTotals(
            calories: totals.calories ?? 0,
            protein: totals.protein ?? 0,
            carbs: totals.carbs ?? 0,
            fats: totals.fats ?? 0
        )
    }
}

enum MealType: String, CaseIterable, Identifiable, Codable {
    case breakfast
    case lunch
    case dinner
    case snacks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snacks: return "Snacks"
        }
    }
}

enum PortionUnit: String, CaseIterable, Identifiable, Codable {
    case grams = "g"
    case ounces = "oz"
    case serving = "serving"  // Natural serving (1 egg, 1 banana, etc.)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grams: return "g"
        case .ounces: return "oz"
        case .serving: return "serving"
        }
    }
}

/// A serving option from FatSecret with pre-calculated macros
struct ServingOption: Identifiable, Equatable {
    let id: String
    let description: String
    let metricGrams: Double?
    let numberOfUnits: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    
    /// Creates macros scaled by the given quantity
    func macros(quantity: Double = 1.0) -> MacroTotals {
        MacroTotals(
            calories: calories * quantity,
            protein: protein * quantity,
            carbs: carbs * quantity,
            fats: fats * quantity
        )
    }
}

struct LoggedFoodItem: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let portionValue: Double
    let portionUnit: PortionUnit
    let macros: MacroTotals
    let detail: String
    let brandName: String?
    let restaurantName: String?
    let source: String?

    init(
        id: UUID = UUID(),
        name: String,
        portionValue: Double,
        portionUnit: PortionUnit,
        macros: MacroTotals,
        detail: String,
        brandName: String? = nil,
        restaurantName: String? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.name = name
        self.portionValue = portionValue
        self.portionUnit = portionUnit
        self.macros = macros
        self.detail = detail
        self.brandName = brandName
        self.restaurantName = restaurantName
        self.source = source
    }
}

struct NutritionLogTotals: Decodable {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fats: Double?
}

struct NutritionLogItem: Decodable {
    let name: String?
    let portionValue: Double?
    let portionUnit: String?
    let serving: String?
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fats: Double?
    let brand: String?
    let restaurant: String?
    let foodType: String?
    let source: String?
    let raw: String?

    enum CodingKeys: String, CodingKey {
        case name
        case portionValue = "portion_value"
        case portionUnit = "portion_unit"
        case serving
        case calories
        case protein
        case carbs
        case fats
        case brand
        case restaurant
        case foodType = "food_type"
        case source
        case raw
    }
}

struct NutritionLogEntry: Decodable, Identifiable {
    let id: String?
    let date: String
    let mealType: String
    let items: [NutritionLogItem]?
    let totals: NutritionLogTotals?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case mealType = "meal_type"
        case items
        case totals
    }
}

struct NutritionLogResponse: Decodable {
    let logs: [NutritionLogEntry]
}

private extension Dictionary where Key == String, Value == Any {
    func doubleValue(for key: String) -> Double {
        if let value = self[key] as? Double { return value }
        if let value = self[key] as? Int { return Double(value) }
        if let value = self[key] as? String { return Double(value) ?? 0 }
        return 0
    }
}

// MARK: - Saved Meals Feature

/// A single item within a saved meal
struct SavedMealItem: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    
    init(id: String = UUID().uuidString, name: String, detail: String, calories: Double, protein: Double, carbs: Double, fats: Double) {
        self.id = id
        self.name = name
        self.detail = detail
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
    }
    
    init(from loggedItem: LoggedFoodItem) {
        self.id = loggedItem.id.uuidString
        self.name = loggedItem.name
        self.detail = loggedItem.detail
        self.calories = loggedItem.macros.calories
        self.protein = loggedItem.macros.protein
        self.carbs = loggedItem.macros.carbs
        self.fats = loggedItem.macros.fats
    }
    
    var macros: MacroTotals {
        MacroTotals(calories: calories, protein: protein, carbs: carbs, fats: fats)
    }
    
    func toLoggedFoodItem() -> LoggedFoodItem {
        LoggedFoodItem(
            name: name,
            portionValue: 0,
            portionUnit: .serving,
            macros: macros,
            detail: detail
        )
    }
}

/// A saved meal containing multiple food items
struct SavedMeal: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var mealType: String? // breakfast, lunch, dinner, snacks
    var items: [SavedMealItem]
    let createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int
    
    init(id: String = UUID().uuidString, name: String, mealType: String? = nil, items: [SavedMealItem], createdAt: Date = Date(), lastUsedAt: Date? = nil, useCount: Int = 0) {
        self.id = id
        self.name = name
        self.mealType = mealType
        self.items = items
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
    
    var totalMacros: MacroTotals {
        items.reduce(MacroTotals.zero) { $0.adding($1.macros) }
    }
    
    var itemNames: String {
        items.map { $0.name }.joined(separator: ", ")
    }
}

/// Store for managing saved meals with local persistence
@MainActor
final class SavedMealsStore: ObservableObject {
    static let shared = SavedMealsStore()
    
    @Published private(set) var meals: [SavedMeal] = []
    
    private let storageKey = "fitai.savedMeals"
    
    private init() {
        loadMeals()
    }
    
    // MARK: - CRUD Operations
    
    func saveMeal(_ meal: SavedMeal) {
        // Check if meal with same name exists
        if let index = meals.firstIndex(where: { $0.name.lowercased() == meal.name.lowercased() }) {
            meals[index] = meal
        } else {
            meals.insert(meal, at: 0)
        }
        persistMeals()
    }
    
    func saveMealFromItems(name: String, mealType: MealType?, items: [LoggedFoodItem]) {
        let savedItems = items.map { SavedMealItem(from: $0) }
        let meal = SavedMeal(
            name: name,
            mealType: mealType?.rawValue,
            items: savedItems
        )
        saveMeal(meal)
    }
    
    func deleteMeal(_ meal: SavedMeal) {
        meals.removeAll { $0.id == meal.id }
        persistMeals()
    }
    
    func deleteMeal(at offsets: IndexSet) {
        meals.remove(atOffsets: offsets)
        persistMeals()
    }
    
    func updateMealUsage(_ meal: SavedMeal) {
        guard let index = meals.firstIndex(where: { $0.id == meal.id }) else { return }
        meals[index].lastUsedAt = Date()
        meals[index].useCount += 1
        persistMeals()
    }
    
    func renameMeal(_ meal: SavedMeal, to newName: String) {
        guard let index = meals.firstIndex(where: { $0.id == meal.id }) else { return }
        meals[index].name = newName
        persistMeals()
    }
    
    // MARK: - Filtering
    
    func meals(for mealType: MealType?) -> [SavedMeal] {
        guard let mealType else { return meals }
        return meals.filter { $0.mealType == mealType.rawValue || $0.mealType == nil }
    }
    
    var frequentlyUsed: [SavedMeal] {
        meals.sorted { ($0.useCount, $0.lastUsedAt ?? .distantPast) > ($1.useCount, $1.lastUsedAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }
    
    // MARK: - Persistence
    
    private func loadMeals() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedMeal].self, from: data) else {
            return
        }
        meals = decoded
    }
    
    private func persistMeals() {
        guard let data = try? JSONEncoder().encode(meals) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - Local Nutrition Logs Cache

struct NutritionDaySnapshot {
    let dateKey: String
    let meals: [MealType: [LoggedFoodItem]]
    let totals: MacroTotals
    let isPersisted: Bool

    var hasMeals: Bool {
        meals.values.contains { !$0.isEmpty }
    }
}

struct PendingNutritionLog: Codable, Identifiable, Equatable {
    let id: UUID
    let dateKey: String
    let mealType: MealType
    let item: LoggedFoodItem

    init(id: UUID = UUID(), dateKey: String, mealType: MealType, item: LoggedFoodItem) {
        self.id = id
        self.dateKey = dateKey
        self.mealType = mealType
        self.item = item
    }
}

@MainActor
final class NutritionLocalStore {
    static let shared = NutritionLocalStore()

    private struct PersistedNutritionLogs: Codable {
        var schemaVersion: Int = 1
        var days: [String: [String: [LoggedFoodItem]]] = [:]
        var pendingLogs: [PendingNutritionLog] = []
    }

    private let storagePrefix = "fitai.nutrition.logs.v1."
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private init() {}

    static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static var todayKey: String {
        dayKey(for: Calendar.current.startOfDay(for: Date()))
    }

    static func date(from dayKey: String) -> Date? {
        dayFormatter.date(from: dayKey)
    }

    func snapshot(userId: String, date: Date = Date()) -> NutritionDaySnapshot {
        let dayKey = Self.dayKey(for: date)
        let payload = loadPayload(userId: userId)
        let isPersisted = payload.days[dayKey] != nil
        let rawMeals = payload.days[dayKey] ?? [:]
        let meals = decodeMeals(rawMeals)
        return NutritionDaySnapshot(
            dateKey: dayKey,
            meals: meals,
            totals: totals(for: meals),
            isPersisted: isPersisted
        )
    }

    @discardableResult
    func replaceDay(
        userId: String,
        date: Date,
        meals: [MealType: [LoggedFoodItem]]
    ) -> NutritionDaySnapshot {
        let dayKey = Self.dayKey(for: date)
        var payload = loadPayload(userId: userId)
        payload.days[dayKey] = encodeMeals(meals)
        persistPayload(payload, userId: userId)
        return snapshot(userId: userId, date: date)
    }

    @discardableResult
    func appendItem(
        userId: String,
        date: Date,
        mealType: MealType,
        item: LoggedFoodItem
    ) -> NutritionDaySnapshot {
        let dayKey = Self.dayKey(for: date)
        var payload = loadPayload(userId: userId)
        var rawMeals = payload.days[dayKey] ?? [:]
        var items = rawMeals[mealType.rawValue] ?? []
        items.append(item)
        rawMeals[mealType.rawValue] = items
        payload.days[dayKey] = rawMeals
        persistPayload(payload, userId: userId)
        return snapshot(userId: userId, date: date)
    }

    @discardableResult
    func updateItem(
        userId: String,
        date: Date,
        mealType: MealType,
        original: LoggedFoodItem,
        updated: LoggedFoodItem
    ) -> NutritionDaySnapshot {
        let dayKey = Self.dayKey(for: date)
        var payload = loadPayload(userId: userId)
        var rawMeals = payload.days[dayKey] ?? [:]
        var items = rawMeals[mealType.rawValue] ?? []
        if let index = items.firstIndex(where: { $0.id == original.id }) {
            items[index] = updated
        }
        rawMeals[mealType.rawValue] = items
        payload.days[dayKey] = rawMeals
        persistPayload(payload, userId: userId)
        return snapshot(userId: userId, date: date)
    }

    @discardableResult
    func deleteItem(
        userId: String,
        date: Date,
        mealType: MealType,
        item: LoggedFoodItem
    ) -> NutritionDaySnapshot {
        let dayKey = Self.dayKey(for: date)
        var payload = loadPayload(userId: userId)
        var rawMeals = payload.days[dayKey] ?? [:]
        var items = rawMeals[mealType.rawValue] ?? []
        items.removeAll { $0.id == item.id }
        rawMeals[mealType.rawValue] = items
        payload.days[dayKey] = rawMeals
        persistPayload(payload, userId: userId)
        return snapshot(userId: userId, date: date)
    }

    func queuePendingLog(userId: String, date: Date, mealType: MealType, item: LoggedFoodItem) {
        var payload = loadPayload(userId: userId)
        let dayKey = Self.dayKey(for: date)
        let alreadyQueued = payload.pendingLogs.contains { pending in
            pending.item.id == item.id && pending.dateKey == dayKey && pending.mealType == mealType
        }
        guard !alreadyQueued else { return }
        payload.pendingLogs.append(
            PendingNutritionLog(dateKey: dayKey, mealType: mealType, item: item)
        )
        persistPayload(payload, userId: userId)
    }

    func pendingLogs(userId: String) -> [PendingNutritionLog] {
        loadPayload(userId: userId).pendingLogs
    }

    func removePendingLogs(userId: String, ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var payload = loadPayload(userId: userId)
        payload.pendingLogs.removeAll { ids.contains($0.id) }
        persistPayload(payload, userId: userId)
    }

    private func storageKey(for userId: String) -> String {
        storagePrefix + userId
    }

    private func loadPayload(userId: String) -> PersistedNutritionLogs {
        guard !userId.isEmpty,
              let data = UserDefaults.standard.data(forKey: storageKey(for: userId)),
              let decoded = try? decoder.decode(PersistedNutritionLogs.self, from: data) else {
            return PersistedNutritionLogs()
        }
        return decoded
    }

    private func persistPayload(_ payload: PersistedNutritionLogs, userId: String) {
        guard !userId.isEmpty, let data = try? encoder.encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(for: userId))
    }

    private func decodeMeals(_ raw: [String: [LoggedFoodItem]]) -> [MealType: [LoggedFoodItem]] {
        var meals: [MealType: [LoggedFoodItem]] = [:]
        for (mealRaw, items) in raw {
            guard let mealType = MealType(rawValue: mealRaw) else { continue }
            meals[mealType] = items
        }
        return meals
    }

    private func encodeMeals(_ meals: [MealType: [LoggedFoodItem]]) -> [String: [LoggedFoodItem]] {
        var raw: [String: [LoggedFoodItem]] = [:]
        for (mealType, items) in meals {
            raw[mealType.rawValue] = items
        }
        return raw
    }

    private func totals(for meals: [MealType: [LoggedFoodItem]]) -> MacroTotals {
        meals.values.flatMap { $0 }.reduce(.zero) { partial, item in
            partial.adding(item.macros)
        }
    }
}
