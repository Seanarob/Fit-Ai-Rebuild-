import Foundation

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

    var id: String { rawValue }

    var title: String { rawValue }
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
