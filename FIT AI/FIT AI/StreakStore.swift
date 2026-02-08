import Foundation
import Combine
import SwiftUI

// MARK: - StreakStore

@MainActor
final class StreakStore: ObservableObject {
    static let shared = StreakStore()
    
    // MARK: - Published State
    
    @Published private(set) var appStreak: AppStreakData = .empty
    @Published private(set) var nutritionStreak: NutritionStreakData = .empty
    @Published private(set) var weeklyWin: WeeklyWinData = .empty
    @Published private(set) var todaysCheckIn: DailyCheckInData?
    
    @Published private(set) var appStreakStatus: StreakStatus = .safe
    @Published private(set) var nutritionStreakStatus: StreakStatus = .safe
    @Published private(set) var weeklyWinStatus: StreakStatus = .safe
    
    @Published private(set) var timeUntilMidnight: TimeInterval = 0
    
    // MARK: - Private
    
    private var countdownTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let appStreak = "fitai.streak.app.data"
        static let nutritionStreak = "fitai.streak.nutrition.data"
        static let weeklyWin = "fitai.streak.weeklywin.data"
        static let todaysCheckIn = "fitai.checkin.today"
        static let lastCheckInDateKey = "fitai.checkin.lastdatekey"
        static let migrated = "fitai.streak.migrated.v2"
    }
    
    // MARK: - Init
    
    private init() {
        load()
        migrateIfNeeded()
        startCountdownTimer()
        checkForMissedDeadlines()
        setupNotificationObservers()
    }
    
    // MARK: - Load & Save
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: Keys.appStreak),
           let decoded = try? JSONDecoder().decode(AppStreakData.self, from: data) {
            appStreak = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: Keys.nutritionStreak),
           let decoded = try? JSONDecoder().decode(NutritionStreakData.self, from: data) {
            nutritionStreak = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: Keys.weeklyWin),
           let decoded = try? JSONDecoder().decode(WeeklyWinData.self, from: data) {
            weeklyWin = decoded
        }
        
        // Load today's check-in if it's still today
        let lastCheckInKey = UserDefaults.standard.string(forKey: Keys.lastCheckInDateKey)
        if lastCheckInKey == StreakCalculations.localDateKey(),
           let data = UserDefaults.standard.data(forKey: Keys.todaysCheckIn),
           let decoded = try? JSONDecoder().decode(DailyCheckInData.self, from: data) {
            todaysCheckIn = decoded
        } else {
            todaysCheckIn = nil
        }
        
        updateAllStatuses()
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(appStreak) {
            UserDefaults.standard.set(encoded, forKey: Keys.appStreak)
        }
        
        if let encoded = try? JSONEncoder().encode(nutritionStreak) {
            UserDefaults.standard.set(encoded, forKey: Keys.nutritionStreak)
        }
        
        if let encoded = try? JSONEncoder().encode(weeklyWin) {
            UserDefaults.standard.set(encoded, forKey: Keys.weeklyWin)
        }
        
        if let checkIn = todaysCheckIn, let encoded = try? JSONEncoder().encode(checkIn) {
            UserDefaults.standard.set(encoded, forKey: Keys.todaysCheckIn)
            UserDefaults.standard.set(StreakCalculations.localDateKey(), forKey: Keys.lastCheckInDateKey)
        }
    }
    
    // MARK: - Migration
    
    private func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Keys.migrated) else { return }
        
        // Migrate old app open streak
        let oldAppStreak = UserDefaults.standard.integer(forKey: "fitai.appOpen.streak")
        if oldAppStreak > 0 {
            appStreak.currentStreak = oldAppStreak
            appStreak.longestStreak = max(appStreak.longestStreak, oldAppStreak)
        }
        
        // Migrate old workout streak to initial weekly win progress
        let oldWorkoutStreak = UserDefaults.standard.integer(forKey: "fitai.workout.streak")
        if oldWorkoutStreak > 0 {
            weeklyWin.weeklyWinCount = oldWorkoutStreak / 7
        }
        
        // Migrate old nutrition streak
        let oldNutritionStreak = UserDefaults.standard.integer(forKey: "fitai.streak.nutrition")
        if oldNutritionStreak > 0 {
            nutritionStreak.currentStreak = oldNutritionStreak
            nutritionStreak.longestStreak = max(nutritionStreak.longestStreak, oldNutritionStreak)
        }
        
        UserDefaults.standard.set(true, forKey: Keys.migrated)
        save()
    }
    
    // MARK: - Countdown Timer
    
    private func startCountdownTimer() {
        updateTimeUntilMidnight()
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTimeUntilMidnight()
                self?.updateAllStatuses()
            }
        }
    }
    
    private func updateTimeUntilMidnight() {
        timeUntilMidnight = StreakCalculations.timeUntilMidnight()
    }
    
    // MARK: - Status Updates
    
    private func updateAllStatuses() {
        updateAppStreakStatus()
        updateNutritionStreakStatus()
        updateWeeklyWinStatus()
    }
    
    private func updateAppStreakStatus() {
        let today = StreakCalculations.localDateKey()
        
        if appStreak.lastCompletedDate == today {
            appStreakStatus = .safe
        } else if appStreak.currentStreak > 0 {
            appStreakStatus = .atRisk(timeRemaining: timeUntilMidnight)
        } else {
            appStreakStatus = .safe // No streak to lose
        }
    }
    
    private func updateNutritionStreakStatus() {
        let today = StreakCalculations.localDateKey()
        
        if nutritionStreak.lastHitDate == today {
            nutritionStreakStatus = .safe
        } else if nutritionStreak.currentStreak > 0 {
            nutritionStreakStatus = .atRisk(timeRemaining: timeUntilMidnight)
        } else {
            nutritionStreakStatus = .safe
        }
    }
    
    private func updateWeeklyWinStatus() {
        pruneWorkoutWindow()
        
        let workoutsNeeded = weeklyWin.weeklyGoal - weeklyWin.workoutsThisWindow.count
        
        if workoutsNeeded <= 0 {
            weeklyWinStatus = .safe
        } else if weeklyWin.currentWinStreak > 0 {
            // Calculate how many days left to complete remaining workouts
            weeklyWinStatus = .atRisk(timeRemaining: timeUntilMidnight)
        } else {
            weeklyWinStatus = .safe
        }
    }
    
    // MARK: - Check for Missed Deadlines
    
    private func checkForMissedDeadlines() {
        let today = StreakCalculations.localDateKey()
        let yesterday = StreakCalculations.yesterdayKey()
        
        // Check App Streak
        if let lastCompleted = appStreak.lastCompletedDate,
           lastCompleted != today && lastCompleted != yesterday && appStreak.currentStreak > 0 {
            // Streak was lost
            resetAppStreak()
        }
        
        // Check Nutrition Streak
        if let lastHit = nutritionStreak.lastHitDate,
           lastHit != today && lastHit != yesterday && nutritionStreak.currentStreak > 0 {
            resetNutritionStreak()
        }
        
        // Check Weekly Win - reset win streak if 7+ days without hitting goal
        checkWeeklyWinReset()
        
        // Apply pending goal change if new week
        applyPendingGoalChangeIfNeeded()
    }
    
    // MARK: - App Streak (Daily Check-In)
    
    func completeCheckIn(_ checkIn: DailyCheckInData) {
        let today = StreakCalculations.localDateKey()
        
        // Already completed today
        guard appStreak.lastCompletedDate != today else {
            todaysCheckIn = checkIn
            save()
            return
        }
        
        let yesterday = StreakCalculations.yesterdayKey()
        
        if appStreak.lastCompletedDate == yesterday {
            // Consecutive day - increment
            appStreak.currentStreak += 1
        } else {
            // New streak or broken streak
            appStreak.currentStreak = 1
            appStreak.streakStartDate = today
        }
        
        // Update longest if needed
        if appStreak.currentStreak > appStreak.longestStreak {
            appStreak.longestStreak = appStreak.currentStreak
            appStreak.longestStreakEndDate = today
            appStreak.longestStreakStartDate = appStreak.streakStartDate
        }
        
        appStreak.lastCompletedDate = today
        todaysCheckIn = checkIn
        
        save()
        updateAppStreakStatus()
        
        // Cancel pending notifications
        StreakNotifications.cancelAppStreakReminders()
        
        // Post notification
        NotificationCenter.default.post(name: .fitAIAppStreakUpdated, object: nil, userInfo: ["streak": appStreak.currentStreak])
        NotificationCenter.default.post(name: .fitAIDailyCheckInCompleted, object: nil)
    }
    
    private func resetAppStreak() {
        if appStreak.currentStreak > 0 {
            NotificationCenter.default.post(name: .fitAIStreakLost, object: nil, userInfo: ["type": StreakType.app])
        }
        appStreak.currentStreak = 0
        appStreak.streakStartDate = nil
        save()
    }
    
    var hasCompletedCheckInToday: Bool {
        appStreak.lastCompletedDate == StreakCalculations.localDateKey()
    }
    
    // MARK: - Nutrition Streak
    
    func checkNutritionStreak(logged: MacroTotals, target: MacroTotals) {
        let today = StreakCalculations.localDateKey()
        
        // Already credited for today
        guard nutritionStreak.lastHitDate != today else { return }
        
        // Check if macros are hit (within ±15%)
        guard MacroHitCalculator.isHit(logged: logged, target: target) else { return }
        
        let yesterday = StreakCalculations.yesterdayKey()
        
        if nutritionStreak.lastHitDate == yesterday {
            nutritionStreak.currentStreak += 1
        } else {
            nutritionStreak.currentStreak = 1
            nutritionStreak.streakStartDate = today
        }
        
        if nutritionStreak.currentStreak > nutritionStreak.longestStreak {
            nutritionStreak.longestStreak = nutritionStreak.currentStreak
            nutritionStreak.longestStreakEndDate = today
            nutritionStreak.longestStreakStartDate = nutritionStreak.streakStartDate
        }
        
        nutritionStreak.lastHitDate = today
        
        save()
        updateNutritionStreakStatus()
        
        StreakNotifications.cancelNutritionReminders()
        
        NotificationCenter.default.post(name: .fitAINutritionStreakHit, object: nil, userInfo: ["streak": nutritionStreak.currentStreak])
        Haptics.success()
    }
    
    private func resetNutritionStreak() {
        if nutritionStreak.currentStreak > 0 {
            NotificationCenter.default.post(name: .fitAIStreakLost, object: nil, userInfo: ["type": StreakType.nutrition])
        }
        nutritionStreak.currentStreak = 0
        nutritionStreak.streakStartDate = nil
        save()
    }
    
    var hasHitMacrosToday: Bool {
        nutritionStreak.lastHitDate == StreakCalculations.localDateKey()
    }
    
    // MARK: - Weekly Win
    
    func recordWorkout(date: Date = Date()) {
        let dateKey = StreakCalculations.localDateKey(for: date)
        
        // Add to window if not already recorded
        if !weeklyWin.workoutsThisWindow.contains(dateKey) {
            weeklyWin.workoutsThisWindow.append(dateKey)
        }
        
        pruneWorkoutWindow()
        checkWeeklyWinStatus()
        
        save()
        updateWeeklyWinStatus()
    }
    
    private func pruneWorkoutWindow() {
        weeklyWin.workoutsThisWindow = StreakCalculations.filterToWindow(
            weeklyWin.workoutsThisWindow,
            windowDays: 7
        )
    }
    
    private func checkWeeklyWinStatus() {
        let workoutsInWindow = weeklyWin.workoutsThisWindow.count
        
        if workoutsInWindow >= weeklyWin.weeklyGoal {
            let today = StreakCalculations.localDateKey()
            
            // Only credit once per achievement
            if weeklyWin.lastWinDate != today {
                weeklyWin.weeklyWinCount += 1
                weeklyWin.currentWinStreak += 1
                weeklyWin.lastWinDate = today
                
                if weeklyWin.winStreakStartDate == nil {
                    weeklyWin.winStreakStartDate = today
                }
                
                if weeklyWin.currentWinStreak > weeklyWin.longestWinStreak {
                    weeklyWin.longestWinStreak = weeklyWin.currentWinStreak
                    weeklyWin.longestWinStreakEndDate = today
                    weeklyWin.longestWinStreakStartDate = weeklyWin.winStreakStartDate
                }
                
                save()
                
                NotificationCenter.default.post(name: .fitAIWeeklyWinAchieved, object: nil, userInfo: ["wins": weeklyWin.weeklyWinCount])
                Haptics.success()
            }
        }
    }
    
    private func checkWeeklyWinReset() {
        guard let lastWinKey = weeklyWin.lastWinDate,
              let lastWinDate = StreakCalculations.dateFromKey(lastWinKey) else { return }
        
        let daysSinceWin = Calendar.current.dateComponents([.day], from: lastWinDate, to: Date()).day ?? 0
        
        if daysSinceWin > 7 && weeklyWin.workoutsThisWindow.count < weeklyWin.weeklyGoal {
            // Failed to maintain win streak
            weeklyWin.currentWinStreak = 0
            weeklyWin.winStreakStartDate = nil
            save()
        }
    }
    
    func setWeeklyGoal(_ newGoal: Int) -> String? {
        guard newGoal >= 1 && newGoal <= 7 else { return nil }
        guard newGoal != weeklyWin.weeklyGoal else { return nil }
        
        weeklyWin.pendingGoalChange = newGoal
        save()
        
        return "Goal will change to \(newGoal) workouts starting next week. Keep crushing your current goal of \(weeklyWin.weeklyGoal)!"
    }
    
    private func applyPendingGoalChangeIfNeeded() {
        guard let pendingGoal = weeklyWin.pendingGoalChange else { return }
        
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        
        // Apply on Sunday (weekday == 1)
        if weekday == 1 {
            weeklyWin.weeklyGoal = pendingGoal
            weeklyWin.pendingGoalChange = nil
            save()
        }
    }
    
    var workoutsThisWeek: Int {
        weeklyWin.workoutsThisWindow.count
    }
    
    var workoutsRemaining: Int {
        max(0, weeklyWin.weeklyGoal - weeklyWin.workoutsThisWindow.count)
    }
    
    // MARK: - At Risk Streaks
    
    var atRiskStreaks: [(StreakType, TimeInterval)] {
        var result: [(StreakType, TimeInterval)] = []
        
        if case .atRisk(let time) = appStreakStatus {
            result.append((.app, time))
        }
        if case .atRisk(let time) = nutritionStreakStatus {
            result.append((.nutrition, time))
        }
        if case .atRisk(let time) = weeklyWinStatus {
            result.append((.weeklyWin, time))
        }
        
        return result.sorted { $0.1 < $1.1 }
    }
    
    var shouldShowSaveStreakMode: Bool {
        !atRiskStreaks.isEmpty && StreakCalculations.isInCriticalWindow()
    }
    
    var mostUrgentCountdown: TimeInterval? {
        atRiskStreaks.first?.1
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Listen for nutrition updates to check streak
        NotificationCenter.default.publisher(for: .fitAINutritionLogged)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateNutritionStreakStatus()
                }
            }
            .store(in: &cancellables)
        
        // Listen for workout completions
        NotificationCenter.default.publisher(for: .fitAIWorkoutCompleted)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.recordWorkout()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Schedule Notifications
    
    func scheduleStreakNotifications() {
        // App streak reminders
        if !hasCompletedCheckInToday && appStreak.currentStreak > 0 {
            StreakNotifications.scheduleAppStreakReminders(currentStreak: appStreak.currentStreak)
        }
        
        // Nutrition reminders
        if !hasHitMacrosToday && nutritionStreak.currentStreak > 0 {
            StreakNotifications.scheduleNutritionReminders(macrosHit: false)
        }
        
        // Weekly win reminders
        if workoutsRemaining > 0 && weeklyWin.currentWinStreak > 0 {
            StreakNotifications.scheduleWeeklyWinReminder(
                workoutsDone: workoutsThisWeek,
                goal: weeklyWin.weeklyGoal,
                daysLeftInWindow: 7
            )
        }
    }
}


