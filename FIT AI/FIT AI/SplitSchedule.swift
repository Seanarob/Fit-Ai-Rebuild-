import Foundation

struct SplitSnapshot {
    var mode: SplitCreationMode = .ai
    var daysPerWeek: Int = 3
    var trainingDays: [String] = []
    var focus: String = "Strength"
    var name: String = "Full Body"
    var splitType: SplitType = .smart
    var dayPlans: [String: SplitDayPlan] = [:]
}

enum SplitSchedule {
    static let splitPreferencesKey = "fitai.onboarding.split.preferences"
    static let onboardingFormKey = "fitai.onboarding.form"

    static func loadSnapshot() -> (snapshot: SplitSnapshot, hasPreferences: Bool) {
        let calendar = Calendar.current
        var hasPreferences = false
        var mode: SplitCreationMode = .ai
        var daysPerWeek = 3
        var trainingDays: [String] = []
        var focus = "Strength"
        var splitType: SplitType = .smart
        var dayPlans: [String: SplitDayPlan] = [:]
        var focusOverride: String?

        if let data = UserDefaults.standard.data(forKey: splitPreferencesKey),
           let decoded = try? JSONDecoder().decode(SplitSetupPreferences.self, from: data) {
            mode = SplitCreationMode(rawValue: decoded.mode) ?? .ai
            daysPerWeek = min(max(decoded.daysPerWeek, 2), 7)
            trainingDays = normalizedTrainingDays(decoded.trainingDays, targetCount: daysPerWeek)
            splitType = decoded.splitType ?? .smart
            dayPlans = decoded.dayPlans ?? [:]
            focusOverride = decoded.focus
            let trimmedFocus = decoded.focus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let legacyConfigured =
                decoded.splitType != nil ||
                (decoded.dayPlans?.isEmpty == false) ||
                !trimmedFocus.isEmpty
            hasPreferences = decoded.isUserConfigured ?? legacyConfigured
        } else if let data = UserDefaults.standard.data(forKey: onboardingFormKey),
                  let form = try? JSONDecoder().decode(OnboardingForm.self, from: data) {
            daysPerWeek = min(max(form.workoutDaysPerWeek, 2), 7)
            trainingDays = normalizedTrainingDays([], targetCount: daysPerWeek)
            focus = focusForGoal(form.goal)
        } else {
            trainingDays = normalizedTrainingDays([], targetCount: daysPerWeek)
        }

        if let data = UserDefaults.standard.data(forKey: onboardingFormKey),
           let form = try? JSONDecoder().decode(OnboardingForm.self, from: data) {
            focus = focusForGoal(form.goal)
        }

        if let override = focusOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            focus = override
        }

        if trainingDays.isEmpty {
            let weekdays = calendar.weekdaySymbols
            trainingDays = weekdays.prefix(daysPerWeek).map { $0 }
        }

        let validWeekdays = Set(calendar.weekdaySymbols)
        dayPlans = dayPlans.filter { validWeekdays.contains($0.key) }

        let name = splitDisplayName(daysPerWeek: daysPerWeek, mode: mode, splitType: splitType)
        let snapshot = SplitSnapshot(
            mode: mode,
            daysPerWeek: daysPerWeek,
            trainingDays: trainingDays,
            focus: focus,
            name: name,
            splitType: splitType,
            dayPlans: dayPlans
        )

        return (snapshot: snapshot, hasPreferences: hasPreferences)
    }

    static func splitLabel(for date: Date, snapshot: SplitSnapshot) -> String? {
        let weekday = weekdaySymbol(for: date)
        if let plan = snapshot.dayPlans[weekday] {
            if let focus = cleanedPlanText(plan.focus, source: plan.source) {
                return focus
            }
            if let title = cleanedPlanText(plan.templateTitle, source: plan.source) {
                return title
            }
        }
        guard let index = snapshot.trainingDays.firstIndex(of: weekday) else {
            return nil
        }
        let rows = defaultSplitDayNames(for: snapshot.daysPerWeek, splitType: snapshot.splitType)
        return index < rows.count ? rows[index] : rows.last
    }

    static func planForDate(_ date: Date, snapshot: SplitSnapshot) -> SplitDayPlan? {
        let weekday = weekdaySymbol(for: date)
        return snapshot.dayPlans[weekday]
    }

    static func plannedWorkoutName(plan: SplitDayPlan?, fallback: String) -> String {
        guard let plan else { return fallback }
        if let title = plan.templateTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        let trimmed = plan.focus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        switch plan.source {
        case .saved:
            return "Saved workout"
        case .create:
            return "Custom workout"
        case .ai:
            return "AI workout"
        }
    }

    static func nextTrainingDayDetail(after date: Date, snapshot: SplitSnapshot) -> (dayName: String, workoutName: String)? {
        let calendar = Calendar.current
        let symbols = calendar.weekdaySymbols
        for offset in 1...14 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            guard let label = splitLabel(for: candidate, snapshot: snapshot) else { continue }
            let plan = planForDate(candidate, snapshot: snapshot)
            let workoutName = plannedWorkoutName(plan: plan, fallback: label)
            let index = max(0, min(symbols.count - 1, calendar.component(.weekday, from: candidate) - 1))
            let dayName = symbols[index]
            return (dayName, workoutName)
        }
        return nil
    }

    private static func cleanedPlanText(_ text: String?, source: SplitPlanSource) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if source == .ai, trimmed.caseInsensitiveCompare("AI workout") == .orderedSame {
            return nil
        }
        return trimmed
    }

    private static func focusForGoal(_ goal: OnboardingForm.Goal?) -> String {
        switch goal {
        case .gainWeight:
            return "Hypertrophy"
        case .loseWeight, .loseWeightFast:
            return "Fat loss + muscle"
        case .maintain:
            return "Strength"
        case .none:
            return "Strength"
        }
    }

    private static func splitDisplayName(daysPerWeek: Int, mode: SplitCreationMode, splitType: SplitType) -> String {
        if mode == .custom {
            return "Custom Split"
        }
        let resolved = resolvedSplitType(splitType, daysPerWeek: daysPerWeek)
        return resolved.title
    }

    private static func defaultSplitDayNames(for daysPerWeek: Int, splitType: SplitType) -> [String] {
        let clamped = min(max(daysPerWeek, 2), 7)
        if splitType == .smart {
            switch clamped {
            case 2:
                return ["Upper", "Lower"]
            case 3:
                return ["Full Body A", "Full Body B", "Full Body C"]
            case 4:
                return ["Upper", "Lower", "Upper", "Lower"]
            case 5:
                return ["Push", "Pull", "Legs", "Upper", "Lower"]
            case 6:
                return ["Push", "Pull", "Legs", "Push", "Pull", "Legs"]
            case 7:
                return ["Full Body", "Full Body", "Full Body", "Full Body", "Full Body", "Full Body", "Full Body"]
            default:
                return ["Full Body"]
            }
        }
        return splitType.dayLabels(for: clamped)
    }

    private static func resolvedSplitType(_ splitType: SplitType, daysPerWeek: Int) -> SplitType {
        let clamped = min(max(daysPerWeek, 2), 7)
        guard splitType == .smart else { return splitType }
        switch clamped {
        case 2:
            return .upperLower
        case 3:
            return .fullBody
        case 4:
            return .upperLower
        case 5:
            return .hybrid
        case 6:
            return .pushPullLegs
        default:
            return .fullBody
        }
    }

    private static func weekdaySymbol(for date: Date) -> String {
        let calendar = Calendar.current
        let index = max(0, min(calendar.weekdaySymbols.count - 1, calendar.component(.weekday, from: date) - 1))
        return calendar.weekdaySymbols[index]
    }

    private static func normalizedTrainingDays(_ days: [String], targetCount: Int) -> [String] {
        let availableDays = Calendar.current.weekdaySymbols
        let filtered = days.filter { availableDays.contains($0) }
        var ordered = availableDays.filter { filtered.contains($0) }

        if ordered.count > targetCount {
            ordered = Array(ordered.prefix(targetCount))
        }

        if ordered.count < targetCount {
            for day in availableDays where !ordered.contains(day) {
                ordered.append(day)
                if ordered.count == targetCount {
                    break
                }
            }
        }

        return ordered
    }
}
