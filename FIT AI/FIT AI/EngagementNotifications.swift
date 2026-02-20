import Foundation
import UserNotifications

@MainActor
enum EngagementNotifications {
    private static let notificationCenter = UNUserNotificationCenter.current()

    private enum ID {
        static let goodMorning = "fitai.engagement.goodmorning.recurring"
        static let weeklyCheckin = "fitai.engagement.weekly.checkin.recurring"

        static func workoutPrompt(dateKey: String) -> String { "fitai.engagement.workout.\(dateKey)" }
        static func restDay(dateKey: String) -> String { "fitai.engagement.restday.\(dateKey)" }
        static func macrosSet(dateKey: String) -> String { "fitai.engagement.macrosset.\(dateKey)" }
        static func lateLog(dateKey: String) -> String { "fitai.engagement.latelog.\(dateKey)" }
        static func niceWorkYesterday(dateKey: String) -> String { "fitai.engagement.niceyesterday.\(dateKey)" }
        static func missedYesterday(dateKey: String) -> String { "fitai.engagement.missedyesterday.\(dateKey)" }
        static func proteinLow(dateKey: String) -> String { "fitai.engagement.proteinlow.\(dateKey)" }
        static func caloriesOnTrack(dateKey: String) -> String { "fitai.engagement.caloriesontrack.\(dateKey)" }
        static func logFoodNow(dateKey: String) -> String { "fitai.engagement.logfood.\(dateKey)" }
        static func workoutAtRisk(dateKey: String) -> String { "fitai.engagement.workout.atrisk.\(dateKey)" }
        static func macrosAdjusted(dateKey: String) -> String { "fitai.engagement.macros.adjusted.\(dateKey)" }
        static func progressUpdate(dateKey: String) -> String { "fitai.engagement.progressupdate.\(dateKey)" }
        static func strengthClimbing(dateKey: String) -> String { "fitai.engagement.strengthclimbing.\(dateKey)" }
        static func niceWorkToday(dateKey: String) -> String { "fitai.engagement.nicetoday.\(dateKey)" }
        static func recap(dateKey: String) -> String { "fitai.engagement.recap.\(dateKey)" }
    }

    private enum Keys {
        static let lastNutritionLogTimestamp = "fitai.nutrition.lastLogTimestamp"
        static let lastNutritionLogDateKey = "fitai.nutrition.lastLogDateKey"
    }

    static func updateLastNutritionLog(dateKey: String, timestamp: Date = Date()) {
        UserDefaults.standard.set(timestamp.timeIntervalSince1970, forKey: Keys.lastNutritionLogTimestamp)
        UserDefaults.standard.set(dateKey, forKey: Keys.lastNutritionLogDateKey)
    }

    static func refreshSchedule(userId: String) async {
        guard !userId.isEmpty else { return }
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        await scheduleGoodMorning()
        await scheduleWeeklyCheckin()
        await scheduleMorningAndDailyNudges(userId: userId)
        await rescheduleNutritionNudges(userId: userId)
        await rescheduleWorkoutAtRiskNudge()
    }

    static func handleMacrosUpdated() async {
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let todayKey = StreakCalculations.localDateKey()
        let now = Date()
        await scheduleNotification(
            id: ID.macrosAdjusted(dateKey: todayKey),
            title: "Macros adjusted ⚙️ Check the details",
            body: "Your targets were updated. Tap to review today’s plan.",
            date: now.addingTimeInterval(2),
            destination: .nutrition,
            priority: .normal
        )
    }

    static func handleProgressUpdate() async {
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let todayKey = StreakCalculations.localDateKey()
        let now = Date()
        await scheduleNotification(
            id: ID.progressUpdate(dateKey: todayKey),
            title: "Progress update 📈 Plan tuned for you",
            body: "Your coach updated your plan based on your latest check-in.",
            date: now.addingTimeInterval(2),
            destination: .progress,
            priority: .low
        )
    }

    static func handleStrengthClimbing() async {
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let todayKey = StreakCalculations.localDateKey()
        let now = Date()
        await scheduleNotification(
            id: ID.strengthClimbing(dateKey: todayKey),
            title: "Strength is climbing 🚀 Keep pushing",
            body: "New PR energy. Keep stacking wins.",
            date: now.addingTimeInterval(2),
            destination: .workout,
            priority: .low
        )
    }

    static func handleNiceWorkToday() async {
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let todayKey = StreakCalculations.localDateKey()
        let now = Date()
        await scheduleNotification(
            id: ID.niceWorkToday(dateKey: todayKey),
            title: "Nice work today 👏 You showed up",
            body: "Recovery + food now. Tomorrow gets easier.",
            date: now.addingTimeInterval(2),
            destination: .nutrition,
            priority: .low
        )
    }

    static func handleRecapReady() async {
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let todayKey = StreakCalculations.localDateKey()
        let now = Date()
        await scheduleNotification(
            id: ID.recap(dateKey: todayKey),
            title: "Check today’s recap 📊 See the wins",
            body: "Quick look at training + nutrition today.",
            date: now.addingTimeInterval(2),
            destination: .home,
            priority: .low
        )
    }

    // MARK: - Recurring & daily scheduling

    private static func scheduleGoodMorning() async {
        await cancelPending(ids: [ID.goodMorning])
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: 7, minute: 15),
            repeats: true
        )
        let content = baseContent(
            title: "Good morning 👋 Your plan is ready",
            body: "Open the app. Today’s plan is simple.",
            destination: .home
        )
        let request = UNNotificationRequest(identifier: ID.goodMorning, content: content, trigger: trigger)
        _ = try? await notificationCenter.add(request)
    }

    private static func scheduleWeeklyCheckin() async {
        await cancelPending(ids: [ID.weeklyCheckin])
        let stored = UserDefaults.standard.object(forKey: "checkinDay") as? Int
        let weekdayIndex = (stored ?? 0) // 0 = Sunday ... 6 = Saturday
        let weekday = max(1, min(7, weekdayIndex + 1)) // UNCalendar: 1=Sunday ... 7=Saturday
        var components = DateComponents()
        components.weekday = weekday
        components.hour = 8
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )
        let content = baseContent(
            title: "Weekly check-in time 📝 Two minutes. Big impact",
            body: "Tap to check in and tune your plan for the week.",
            destination: .checkin
        )
        let request = UNNotificationRequest(identifier: ID.weeklyCheckin, content: content, trigger: trigger)
        _ = try? await notificationCenter.add(request)
    }

    private static func scheduleMorningAndDailyNudges(userId: String) async {
        let todayKey = StreakCalculations.localDateKey()
        await cancelPending(ids: [
            ID.workoutPrompt(dateKey: todayKey),
            ID.restDay(dateKey: todayKey),
            ID.macrosSet(dateKey: todayKey),
            ID.lateLog(dateKey: todayKey),
            ID.niceWorkYesterday(dateKey: todayKey),
            ID.missedYesterday(dateKey: todayKey)
        ])

        let calendar = Calendar.current
        let now = Date()
        let morningWindowEnd = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now
        guard now < morningWindowEnd else { return }

        let todayTraining = TodayTrainingStore.todaysTraining()
        let hasWorkoutToday = todayTraining != nil
        if hasWorkoutToday {
            if let promptDate = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) {
                let (title, body) = workoutPromptCopy(training: todayTraining)
                await scheduleNotification(
                    id: ID.workoutPrompt(dateKey: todayKey),
                    title: title,
                    body: body,
                    date: promptDate,
                    destination: .workout,
                    priority: .high
                )
            }
        } else {
            if let restDate = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) {
                await scheduleNotification(
                    id: ID.restDay(dateKey: todayKey),
                    title: "Rest day vibes 😌 Recover and recharge",
                    body: "Recovery counts too. Take a walk and fuel up.",
                    date: restDate,
                    destination: .progress,
                    priority: .low
                )
            }
        }

        if let targets = macroTargetsFromOnboarding(), targets.calories > 0 {
            if let macroDate = calendar.date(bySettingHour: 8, minute: 15, second: 0, of: now) {
                await scheduleNotification(
                    id: ID.macrosSet(dateKey: todayKey),
                    title: "Macros for today are set 🍽️ You’re good",
                    body: "Tap to see today’s targets and log food.",
                    date: macroDate,
                    destination: .nutrition,
                    priority: .normal
                )
            }
        }

        let yesterdayKey = StreakCalculations.yesterdayKey()
        if let lastLogKey = UserDefaults.standard.string(forKey: Keys.lastNutritionLogDateKey),
           lastLogKey == yesterdayKey,
           let timestamp = UserDefaults.standard.object(forKey: Keys.lastNutritionLogTimestamp) as? TimeInterval {
            let lastDate = Date(timeIntervalSince1970: timestamp)
            let hour = calendar.component(.hour, from: lastDate)
            if hour >= 22, let lateDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) {
                await scheduleNotification(
                    id: ID.lateLog(dateKey: todayKey),
                    title: "Late log yesterday ⏰ Let’s lock it in earlier today",
                    body: "Log earlier today so it’s stress-free tonight.",
                    date: lateDate,
                    destination: .nutrition,
                    priority: .normal
                )
            }
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           WorkoutCompletionStore.hasCompletion(on: yesterday),
           let niceDate = calendar.date(bySettingHour: 9, minute: 10, second: 0, of: now) {
            await scheduleNotification(
                id: ID.niceWorkYesterday(dateKey: todayKey),
                title: "Nice work yesterday 💥 Fuel up today",
                body: "Recovery and protein today = better performance next session.",
                date: niceDate,
                destination: .nutrition,
                priority: .low
            )
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
            let missedWorkout = !WorkoutCompletionStore.hasCompletion(on: yesterday)
            let missedNutrition = !NutritionLocalStore.shared.snapshot(
                userId: userId,
                date: calendar.startOfDay(for: yesterday)
            ).hasMeals
            if (missedWorkout || missedNutrition),
               let missedDate = calendar.date(bySettingHour: 9, minute: 20, second: 0, of: now) {
                await scheduleNotification(
                    id: ID.missedYesterday(dateKey: todayKey),
                    title: "Missed yesterday 😅 Today’s a fresh start",
                    body: "No pressure—just progress. Open the app and knock out one win.",
                    date: missedDate,
                    destination: .home,
                    priority: .normal
                )
            }
        }
    }

    static func rescheduleNutritionNudges(userId: String) async {
        guard !userId.isEmpty else { return }
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let todayKey = StreakCalculations.localDateKey()
        await cancelPending(ids: [
            ID.proteinLow(dateKey: todayKey),
            ID.caloriesOnTrack(dateKey: todayKey),
            ID.logFoodNow(dateKey: todayKey)
        ])

        guard let targets = macroTargetsFromOnboarding(), targets.calories > 0 else { return }
        let calendar = Calendar.current
        let now = Date()
        let snapshot = NutritionLocalStore.shared.snapshot(userId: userId, date: calendar.startOfDay(for: now))
        let logged = snapshot.totals

        if let middayDate = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: now),
           now < middayDate {
            let expectedProtein = targets.protein * 0.45
            if targets.protein > 0, logged.protein < expectedProtein {
                await scheduleNotification(
                    id: ID.proteinLow(dateKey: todayKey),
                    title: "Protein’s a little low 🍗 Easy fix today",
                    body: "Add a protein-forward meal and you’re back on pace.",
                    date: middayDate,
                    destination: .nutrition,
                    priority: .normal
                )
            }
        }

        if let eveningDate = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now),
           now < eveningDate {
            let ratio = targets.calories > 0 ? (logged.calories / targets.calories) : 0
            if ratio >= 0.85 && ratio <= 1.15 {
                await scheduleNotification(
                    id: ID.caloriesOnTrack(dateKey: todayKey),
                    title: "Calories on track ✅ Finish strong tonight",
                    body: "You’re close. Keep it clean and land the day.",
                    date: eveningDate,
                    destination: .nutrition,
                    priority: .low
                )
            }
        }

        if let nightDate = calendar.date(bySettingHour: 21, minute: 30, second: 0, of: now),
           now < nightDate {
            let ratio = targets.calories > 0 ? (logged.calories / targets.calories) : 0
            if ratio < 0.8 {
                await scheduleNotification(
                    id: ID.logFoodNow(dateKey: todayKey),
                    title: "Log food now 🍽️ Tomorrow you will thank you",
                    body: "Quick log now keeps your plan accurate.",
                    date: nightDate,
                    destination: .nutrition,
                    priority: .high
                )
            }
        }
    }

    static func rescheduleWorkoutAtRiskNudge() async {
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let todayKey = StreakCalculations.localDateKey()
        await cancelPending(ids: [ID.workoutAtRisk(dateKey: todayKey)])

        let calendar = Calendar.current
        let now = Date()
        guard let date = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) else { return }
        guard now < date else { return }

        guard TodayTrainingStore.todaysTraining() != nil else { return }
        guard WorkoutCompletionStore.todaysCompletion() == nil else { return }

        await scheduleNotification(
            id: ID.workoutAtRisk(dateKey: todayKey),
            title: "Streak almost broken 😬 Save it now",
            body: "Quick session counts. Open the workout and get it done.",
            date: date,
            destination: .workout,
            priority: .high
        )
    }

    // MARK: - Helpers

    private static func workoutPromptCopy(training: TodayTrainingSnapshot?) -> (String, String) {
        let titleLower = (training?.title ?? "").lowercased()
        let isLeg = titleLower.contains("leg")
            || titleLower.contains("lower")
            || titleLower.contains("glute")
            || titleLower.contains("hamstring")
            || titleLower.contains("quad")

        if isLeg {
            return ("Leg day reminder 🦵 You got this", "No stress. Show up and get your sets in.")
        }
        return ("Workout ready 💪 No stress. Let’s move", "Today’s workout is waiting. Tap when you’re ready.")
    }

    private static func macroTargetsFromOnboarding() -> MacroTotals? {
        guard let data = UserDefaults.standard.data(forKey: "fitai.onboarding.form"),
              let form = try? JSONDecoder().decode(OnboardingForm.self, from: data) else {
            return nil
        }

        let calories = Double(form.macroCalories) ?? 0
        let protein = Double(form.macroProtein) ?? 0
        let carbs = Double(form.macroCarbs) ?? 0
        let fats = Double(form.macroFats) ?? 0

        return MacroTotals(calories: calories, protein: protein, carbs: carbs, fats: fats)
    }

    private static func baseContent(title: String, body: String, destination: FitDeepLinkDestination) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "fitai-engagement"
        content.userInfo = ["destination": destination.rawValue]
        return content
    }

    private static func scheduleNotification(
        id: String,
        title: String,
        body: String,
        date: Date,
        destination: FitDeepLinkDestination,
        priority: FitNotificationPriority = .normal
    ) async {
        guard date > Date() else { return }

        let categoryKey = NotificationThrottler.defaultCategoryKey(for: id)
        let decision = await NotificationThrottler.evaluate(
            center: notificationCenter,
            identifier: id,
            fireDate: date,
            category: categoryKey,
            priority: priority
        )
        guard decision.allow else { return }
        if !decision.removeIdentifiers.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: decision.removeIdentifiers)
        }

        let triggerComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let content = baseContent(title: title, body: body, destination: destination)
        NotificationThrottler.attachThrottleMetadata(
            to: content,
            category: categoryKey,
            priority: priority
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        _ = try? await notificationCenter.add(request)
    }

    private static func cancelPending(ids: [String]) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
