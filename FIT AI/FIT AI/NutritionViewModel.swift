import Combine
import Foundation

@MainActor
final class NutritionViewModel: ObservableObject {
    @Published private(set) var dailyMeals: [MealType: [LoggedFoodItem]] = [:]
    @Published private(set) var totals: MacroTotals = MacroTotals.zero
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let userId: String

    init(userId: String) {
        self.userId = userId
    }

    func loadDailyLogs(date: Date = Date(), silently: Bool = false) async {
        guard !userId.isEmpty else { return }
        if !silently {
            isLoading = true
            errorMessage = nil
        }
        do {
            let logs = try await NutritionAPIService.shared.fetchDailyLogs(userId: userId, date: date)
            let meals = buildMeals(from: logs)
            let totalMacros = buildTotals(from: logs, meals: meals)
            dailyMeals = meals
            totals = totalMacros
        } catch {
            if !silently {
                errorMessage = nil
            }
        }
        if !silently {
            isLoading = false
        }
    }

    func logManualItem(item: LoggedFoodItem, mealType: MealType, date: Date = Date()) async -> Bool {
        guard !userId.isEmpty else { return false }
        applyLocalLog(item, mealType: mealType)
        errorMessage = nil
        Haptics.success()
        NotificationCenter.default.post(
            name: .fitAINutritionLogged,
            object: nil,
            userInfo: ["macros": macroDictionary(from: totals)]
        )
        do {
            try await NutritionAPIService.shared.logManualItem(
                userId: userId,
                date: date,
                mealType: mealType.rawValue,
                item: item
            )
            Task { await loadDailyLogs(date: date, silently: true) }
            return true
        } catch {
            errorMessage = "Unable to log item."
            return false
        }
    }

    private func applyLocalLog(_ item: LoggedFoodItem, mealType: MealType) {
        var updated = dailyMeals
        updated[mealType, default: []].append(item)
        dailyMeals = updated
        totals = totals.adding(item.macros)
    }

    private func macroDictionary(from totals: MacroTotals) -> [String: Any] {
        [
            "calories": totals.calories,
            "protein": totals.protein,
            "carbs": totals.carbs,
            "fats": totals.fats
        ]
    }

    private func buildMeals(from logs: [NutritionLogEntry]) -> [MealType: [LoggedFoodItem]] {
        var result: [MealType: [LoggedFoodItem]] = [:]

        for log in logs {
            guard let meal = normalizedMealType(from: log.mealType) else { continue }
            let items = (log.items ?? []).map(makeLoggedItem(from:))
            if result[meal] != nil {
                result[meal, default: []].append(contentsOf: items)
            } else {
                result[meal] = items
            }
        }

        return result
    }

    private func normalizedMealType(from rawValue: String) -> MealType? {
        let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let meal = MealType(rawValue: cleaned) {
            return meal
        }
        if cleaned.hasPrefix("breakfast") { return .breakfast }
        if cleaned.hasPrefix("lunch") { return .lunch }
        if cleaned.hasPrefix("dinner") { return .dinner }
        if cleaned.hasPrefix("snack") { return .snacks }
        return nil
    }

    private func buildTotals(
        from logs: [NutritionLogEntry],
        meals: [MealType: [LoggedFoodItem]]
    ) -> MacroTotals {
        var total = MacroTotals.zero
        for log in logs {
            let entryTotal = MacroTotals.fromLogTotals(log.totals)
            if entryTotal != MacroTotals.zero {
                total = total.adding(entryTotal)
                continue
            }

            let items = log.items ?? []
            let itemTotals = items.map(makeLoggedItem(from:)).reduce(MacroTotals.zero) { partial, item in
                partial.adding(item.macros)
            }
            total = total.adding(itemTotals)
        }
        if total == MacroTotals.zero {
            total = meals.values.flatMap { $0 }.reduce(MacroTotals.zero) { partial, item in
                partial.adding(item.macros)
            }
        }
        return total
    }

    private func makeLoggedItem(from item: NutritionLogItem) -> LoggedFoodItem {
        let portionValue = item.portionValue ?? 0
        let portionUnit = PortionUnit(rawValue: item.portionUnit ?? "") ?? .grams
        let macros = MacroTotals(
            calories: item.calories ?? 0,
            protein: item.protein ?? 0,
            carbs: item.carbs ?? 0,
            fats: item.fats ?? 0
        )
        let name = item.name ?? (item.raw == nil ? "Logged item" : "Scan result")
        let detail: String
        if portionValue > 0 {
            detail = "\(Int(portionValue)) \(portionUnit.title)"
        } else if let serving = item.serving, !serving.isEmpty {
            detail = serving
        } else {
            detail = "Logged"
        }
        return LoggedFoodItem(
            name: name,
            portionValue: portionValue,
            portionUnit: portionUnit,
            macros: macros,
            detail: detail
        )
    }
}

extension Notification.Name {
    static let fitAINutritionLogged = Notification.Name("fitai.nutrition.logged")
}
