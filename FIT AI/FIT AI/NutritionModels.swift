import Combine
import Foundation
import SwiftUI

struct MacroTotals: Equatable {
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

enum MealType: String, CaseIterable, Identifiable {
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

enum PortionUnit: String, CaseIterable, Identifiable {
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

struct LoggedFoodItem: Identifiable {
    let id = UUID()
    let name: String
    let portionValue: Double
    let portionUnit: PortionUnit
    let macros: MacroTotals
    let detail: String
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
