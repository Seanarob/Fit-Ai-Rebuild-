import Foundation

// MARK: - Streak Calculations

enum StreakCalculations {
    
    // MARK: - Date Keys (Local Timezone)
    
    /// Get date key in "yyyy-MM-dd" format using device's local timezone
    static func localDateKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    /// Convert date key back to Date
    static func dateFromKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.date(from: key)
    }
    
    /// Get yesterday's date key
    static func yesterdayKey(from date: Date = Date()) -> String {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        return localDateKey(for: yesterday)
    }
    
    // MARK: - Time Until Midnight
    
    /// Seconds remaining until local midnight
    static func timeUntilMidnight(from date: Date = Date()) -> TimeInterval {
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: date) ?? date)
        return tomorrow.timeIntervalSince(date)
    }
    
    /// Check if we're within the critical window (< 6 hours to midnight)
    static func isInCriticalWindow(from date: Date = Date()) -> Bool {
        timeUntilMidnight(from: date) < 6 * 3600
    }
    
    // MARK: - Urgency Level
    
    /// Get urgency level based on time remaining
    static func urgencyLevel(seconds: TimeInterval) -> UrgencyLevel {
        let hours = seconds / 3600
        if hours <= 0.5 { return .critical }
        if hours <= 2 { return .high }
        if hours <= 6 { return .medium }
        return .low
    }
    
    // MARK: - Countdown Formatting
    
    /// Format countdown for display
    static func formatCountdown(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        } else if minutes > 0 {
            return "\(minutes)m left"
        } else {
            return "< 1m left"
        }
    }
    
    /// Format countdown with "to save" suffix
    static func formatCountdownWithContext(_ seconds: TimeInterval, streakName: String) -> String {
        "\(formatCountdown(seconds)) to save your \(streakName) streak"
    }
    
    // MARK: - Rolling Window
    
    /// Check if a date is within the rolling window
    static func isWithinWindow(dateKey: String, windowDays: Int, from referenceDate: Date = Date()) -> Bool {
        guard let date = dateFromKey(dateKey) else { return false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: referenceDate) ?? referenceDate
        return date >= cutoff
    }
    
    /// Get date key for N days ago
    static func dateKeyDaysAgo(_ days: Int, from date: Date = Date()) -> String {
        let pastDate = Calendar.current.date(byAdding: .day, value: -days, to: date) ?? date
        return localDateKey(for: pastDate)
    }
    
    /// Filter dates to only those within rolling window
    static func filterToWindow(_ dateKeys: [String], windowDays: Int, from referenceDate: Date = Date()) -> [String] {
        let cutoffKey = dateKeyDaysAgo(windowDays, from: referenceDate)
        return dateKeys.filter { $0 >= cutoffKey }
    }
    
    // MARK: - Consecutive Day Check
    
    /// Check if two date keys are consecutive days
    static func areConsecutiveDays(_ earlier: String, _ later: String) -> Bool {
        guard let earlierDate = dateFromKey(earlier),
              let laterDate = dateFromKey(later) else { return false }
        
        let calendar = Calendar.current
        let dayAfterEarlier = calendar.date(byAdding: .day, value: 1, to: earlierDate)
        return calendar.isDate(laterDate, inSameDayAs: dayAfterEarlier ?? laterDate)
    }
    
    /// Check if date key is today
    static func isToday(_ dateKey: String) -> Bool {
        dateKey == localDateKey()
    }
    
    /// Check if date key is yesterday
    static func isYesterday(_ dateKey: String) -> Bool {
        dateKey == yesterdayKey()
    }
    
    // MARK: - Date Formatting for Display
    
    /// Format date key for display (e.g., "Jan 15")
    static func formatDateKeyForDisplay(_ dateKey: String) -> String {
        guard let date = dateFromKey(dateKey) else { return dateKey }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    /// Format date range for display (e.g., "Jan 5 – Jan 15")
    static func formatDateRange(start: String?, end: String?) -> String? {
        guard let start = start, let end = end else { return nil }
        return "\(formatDateKeyForDisplay(start)) – \(formatDateKeyForDisplay(end))"
    }
}

// MARK: - Macro Hit Calculator

enum MacroHitCalculator {
    /// Tolerance for macros (±15%)
    static let tolerance: Double = 0.15
    
    /// Check if all macros are within target range
    static func isHit(logged: MacroTotals, target: MacroTotals) -> Bool {
        guard target.calories > 0 else { return false }
        
        let caloriesHit = isWithinRange(logged.calories, target: target.calories)
        let proteinHit = isWithinRange(logged.protein, target: target.protein)
        let carbsHit = isWithinRange(logged.carbs, target: target.carbs)
        let fatsHit = isWithinRange(logged.fats, target: target.fats)
        
        return caloriesHit && proteinHit && carbsHit && fatsHit
    }
    
    /// Check if value is within ±15% of target
    static func isWithinRange(_ value: Double, target: Double) -> Bool {
        guard target > 0 else { return true }
        let lowerBound = target * (1 - tolerance)
        let upperBound = target * (1 + tolerance)
        return value >= lowerBound && value <= upperBound
    }
    
    /// Get detailed breakdown for UI
    static func breakdown(logged: MacroTotals, target: MacroTotals) -> MacroBreakdown {
        MacroBreakdown(
            calories: MacroStatus(
                logged: logged.calories,
                target: target.calories,
                isHit: isWithinRange(logged.calories, target: target.calories)
            ),
            protein: MacroStatus(
                logged: logged.protein,
                target: target.protein,
                isHit: isWithinRange(logged.protein, target: target.protein)
            ),
            carbs: MacroStatus(
                logged: logged.carbs,
                target: target.carbs,
                isHit: isWithinRange(logged.carbs, target: target.carbs)
            ),
            fats: MacroStatus(
                logged: logged.fats,
                target: target.fats,
                isHit: isWithinRange(logged.fats, target: target.fats)
            )
        )
    }
    
    /// Get percentage of target hit
    static func percentageHit(_ value: Double, target: Double) -> Int {
        guard target > 0 else { return 0 }
        return Int((value / target) * 100)
    }
}


