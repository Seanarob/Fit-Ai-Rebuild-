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
        
        // Check nutrition streak after logging
        checkNutritionStreak()
        
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
    
    /// Check if macros are hit and update streak
    func checkNutritionStreak() {
        // Get macro targets from profile or UserDefaults
        let targets = getMacroTargets()
        guard targets != .zero else { return }
        
        // Check streak using StreakStore
        Task { @MainActor in
            StreakStore.shared.checkNutritionStreak(logged: totals, target: targets)
        }
    }
    
    private func getMacroTargets() -> MacroTotals {
        // Try to get from locally saved onboarding form
        guard let data = UserDefaults.standard.data(forKey: "fitai.onboarding.form"),
              let form = try? JSONDecoder().decode(OnboardingForm.self, from: data) else {
            return .zero
        }
        
        let calories = Double(form.macroCalories) ?? 0
        let protein = Double(form.macroProtein) ?? 0
        let carbs = Double(form.macroCarbs) ?? 0
        let fats = Double(form.macroFats) ?? 0
        
        return MacroTotals(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats
        )
    }

    private func applyLocalLog(_ item: LoggedFoodItem, mealType: MealType) {
        var updated = dailyMeals
        updated[mealType, default: []].append(item)
        dailyMeals = updated
        totals = totals.adding(item.macros)
    }

    /// Update a logged food item with new values
    func updateLoggedItem(original: LoggedFoodItem, updated: LoggedFoodItem, mealType: MealType, date: Date) async {
        // Update local state immediately for responsive UI
        var meals = dailyMeals
        if var items = meals[mealType] {
            if let index = items.firstIndex(where: { $0.id == original.id }) {
                // Subtract old macros and add new ones
                totals = totals.subtracting(items[index].macros)
                items[index] = updated
                totals = totals.adding(updated.macros)
                meals[mealType] = items
                dailyMeals = meals
            }
        }
        
        Haptics.success()
        NotificationCenter.default.post(
            name: .fitAINutritionLogged,
            object: nil,
            userInfo: ["macros": macroDictionary(from: totals)]
        )
        
        // TODO: Sync update to backend when API supports it
        // For now, just reload to ensure consistency
        await loadDailyLogs(date: date, silently: true)
    }
    
    /// Delete a logged food item
    func deleteLoggedItem(item: LoggedFoodItem, mealType: MealType, date: Date) async {
        // Update local state immediately
        var meals = dailyMeals
        if var items = meals[mealType] {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                totals = totals.subtracting(items[index].macros)
                items.remove(at: index)
                meals[mealType] = items
                dailyMeals = meals
            }
        }
        
        Haptics.medium()
        NotificationCenter.default.post(
            name: .fitAINutritionLogged,
            object: nil,
            userInfo: ["macros": macroDictionary(from: totals)]
        )
        
        // TODO: Sync deletion to backend when API supports it
        // For now, just reload to ensure consistency
        await loadDailyLogs(date: date, silently: true)
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
        if let serving = item.serving, !serving.isEmpty {
            detail = serving
        } else if portionValue > 0 {
            detail = "\(formattedPortionValue(portionValue)) \(portionUnit.title)"
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

    private func formattedPortionValue(_ value: Double, maxFractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

extension Notification.Name {
    static let fitAINutritionLogged = Notification.Name("fitai.nutrition.logged")
}
