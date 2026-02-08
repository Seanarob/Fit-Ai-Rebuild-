import Foundation
import UserNotifications

// MARK: - Streak Notifications

enum StreakNotifications {
    private static let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Notification IDs
    
    private enum NotificationID {
        static let appStreak6pm = "fitai.streak.app.6pm"
        static let appStreak10pm = "fitai.streak.app.10pm"
        static let appStreak1130pm = "fitai.streak.app.1130pm"
        static let nutrition6pm = "fitai.streak.nutrition.6pm"
        static let nutrition8pm = "fitai.streak.nutrition.8pm"
        static let weeklyWin = "fitai.streak.weeklywin"
    }
    
    // MARK: - Request Permissions
    
    static func requestPermissions() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted
        } catch {
            print("Failed to request notification permissions: \(error)")
            return false
        }
    }
    
    static func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Schedule App Streak Reminders
    
    static func scheduleAppStreakReminders(currentStreak: Int) {
        cancelAppStreakReminders()
        
        guard currentStreak > 0 else { return }
        
        let today = Calendar.current.startOfDay(for: Date())
        
        // 6 PM reminder (only for streaks > 3)
        if currentStreak > 3 {
            if let date = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: today) {
                scheduleNotification(
                    id: NotificationID.appStreak6pm,
                    title: "Don't lose your \(currentStreak) day streak! 🔥",
                    body: "Quick check-in takes 10 seconds. Keep the momentum going!",
                    date: date
                )
            }
        }
        
        // 10 PM reminder (2 hours before midnight)
        if let date = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: today) {
            scheduleNotification(
                id: NotificationID.appStreak10pm,
                title: "⚠️ Streak at risk!",
                body: "2 hours left to save your \(currentStreak) day streak. Tap to check in.",
                date: date
            )
        }
        
        // 11:30 PM reminder (30 min before midnight, streaks > 3)
        if currentStreak > 3 {
            if let date = Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: today) {
                scheduleNotification(
                    id: NotificationID.appStreak1130pm,
                    title: "🚨 LAST CHANCE!",
                    body: "30 minutes to save your \(currentStreak) day streak! Don't let it reset!",
                    date: date
                )
            }
        }
    }
    
    static func cancelAppStreakReminders() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            NotificationID.appStreak6pm,
            NotificationID.appStreak10pm,
            NotificationID.appStreak1130pm
        ])
    }
    
    // MARK: - Schedule Nutrition Reminders
    
    static func scheduleNutritionReminders(macrosHit: Bool) {
        cancelNutritionReminders()
        
        guard !macrosHit else { return }
        
        let today = Calendar.current.startOfDay(for: Date())
        
        // 6 PM reminder
        if let date = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: today) {
            scheduleNotification(
                id: NotificationID.nutrition6pm,
                title: "Hit your macros today! 🥗",
                body: "Log your remaining meals to keep your nutrition streak alive.",
                date: date
            )
        }
        
        // 8 PM reminder
        if let date = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: today) {
            scheduleNotification(
                id: NotificationID.nutrition8pm,
                title: "⚠️ Macros at risk!",
                body: "Still time to hit your targets. Tap to log food.",
                date: date
            )
        }
    }
    
    static func cancelNutritionReminders() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            NotificationID.nutrition6pm,
            NotificationID.nutrition8pm
        ])
    }
    
    // MARK: - Schedule Weekly Win Reminders
    
    static func scheduleWeeklyWinReminder(workoutsDone: Int, goal: Int, daysLeftInWindow: Int) {
        cancelWeeklyWinReminders()
        
        let workoutsNeeded = goal - workoutsDone
        
        guard workoutsNeeded > 0 else { return }
        
        // Calculate if behind pace
        let expectedPace = Double(goal) / 7.0
        let daysUsed = max(1, 7 - daysLeftInWindow)
        let currentPace = Double(workoutsDone) / Double(daysUsed)
        
        guard currentPace < expectedPace else { return }
        
        // Schedule for 10 AM tomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        if let notificationDate = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) {
            scheduleNotification(
                id: NotificationID.weeklyWin,
                title: "Time to train! 💪",
                body: "You need \(workoutsNeeded) more workout\(workoutsNeeded > 1 ? "s" : "") to hit your weekly goal.",
                date: notificationDate
            )
        }
    }
    
    static func cancelWeeklyWinReminders() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            NotificationID.weeklyWin
        ])
    }
    
    // MARK: - Cancel All Streak Notifications
    
    static func cancelAllStreakNotifications() {
        cancelAppStreakReminders()
        cancelNutritionReminders()
        cancelWeeklyWinReminders()
    }
    
    // MARK: - Helper
    
    private static func scheduleNotification(id: String, title: String, body: String, date: Date) {
        // Don't schedule if date is in the past
        guard date > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "STREAK_REMINDER"
        content.threadIdentifier = "streak-reminders"
        
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule notification \(id): \(error)")
            }
        }
    }
    
    // MARK: - Debug: List Pending Notifications
    
    static func listPendingNotifications() async {
        let pending = await notificationCenter.pendingNotificationRequests()
        print("Pending notifications: \(pending.count)")
        for notification in pending {
            print("  - \(notification.identifier): \(notification.content.title)")
        }
    }
}

// MARK: - Notification Actions

extension StreakNotifications {
    static func setupNotificationCategories() {
        let checkInAction = UNNotificationAction(
            identifier: "CHECK_IN_ACTION",
            title: "Check In Now",
            options: [.foreground]
        )
        
        let logFoodAction = UNNotificationAction(
            identifier: "LOG_FOOD_ACTION",
            title: "Log Food",
            options: [.foreground]
        )
        
        let startWorkoutAction = UNNotificationAction(
            identifier: "START_WORKOUT_ACTION",
            title: "Start Workout",
            options: [.foreground]
        )
        
        let category = UNNotificationCategory(
            identifier: "STREAK_REMINDER",
            actions: [checkInAction, logFoodAction, startWorkoutAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([category])
    }
}


