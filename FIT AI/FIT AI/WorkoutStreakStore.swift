import Foundation

enum WorkoutStreakStore {
    private static let streakKey = "fitai.workout.streak"
    private static let dateKey = "fitai.workout.streak.date"

    static func current() -> Int {
        UserDefaults.standard.integer(forKey: streakKey)
    }

    @discardableResult
    static func update(for date: Date = Date()) -> Int {
        let defaults = UserDefaults.standard
        let todayKey = dateKey(for: date)
        let lastKey = defaults.string(forKey: dateKey)
        let existing = defaults.integer(forKey: streakKey)

        let newStreak: Int
        if lastKey == todayKey {
            newStreak = existing
        } else if let lastKey,
                  let lastDate = dateFromKey(lastKey),
                  Calendar.current.isDate(lastDate, inSameDayAs: Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date) {
            newStreak = max(existing + 1, 1)
        } else {
            newStreak = 1
        }

        defaults.set(todayKey, forKey: dateKey)
        defaults.set(newStreak, forKey: streakKey)
        return newStreak
    }

    private static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current // Use local timezone for accurate day boundaries
        return formatter.string(from: date)
    }

    private static func dateFromKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current // Use local timezone for accurate day boundaries
        return formatter.date(from: key)
    }
}

extension Notification.Name {
    static let fitAIWorkoutStreakUpdated = Notification.Name("fitai.workout.streak.updated")
    static let fitAIWorkoutCompleted = Notification.Name("fitai.workout.completed")
    static let fitAINewPR = Notification.Name("fitai.workout.newPR")
}

struct WorkoutCompletion: Codable {
    let dateKey: String
    let exercises: [String]
}

enum WorkoutCompletionStore {
    private static let storeKey = "fitai.workout.completion"
    private static let completionsKey = "fitai.workout.completions"

    static func markCompleted(exercises: [String], date: Date = Date()) {
        let completion = WorkoutCompletion(dateKey: dayKey(for: date), exercises: exercises)
        if let data = try? JSONEncoder().encode(completion) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
        var completions = loadCompletions()
        completions[completion.dateKey] = completion
        saveCompletions(completions)
        NotificationCenter.default.post(
            name: .fitAIWorkoutCompleted,
            object: nil,
            userInfo: ["completion": completion]
        )
    }

    static func todaysCompletion(date: Date = Date()) -> WorkoutCompletion? {
        let key = dayKey(for: date)
        if let completion = loadCompletions()[key] {
            return completion
        }
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let completion = try? JSONDecoder().decode(WorkoutCompletion.self, from: data) else {
            return nil
        }
        return completion.dateKey == dayKey(for: date) ? completion : nil
    }

    static func completion(on date: Date) -> WorkoutCompletion? {
        let key = dayKey(for: date)
        if let completion = loadCompletions()[key] {
            return completion
        }
        if Calendar.current.isDateInToday(date) {
            return todaysCompletion(date: date)
        }
        return nil
    }

    static func hasCompletion(on date: Date) -> Bool {
        completion(on: date) != nil
    }

    private static func loadCompletions() -> [String: WorkoutCompletion] {
        guard let data = UserDefaults.standard.data(forKey: completionsKey),
              let decoded = try? JSONDecoder().decode([String: WorkoutCompletion].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveCompletions(_ completions: [String: WorkoutCompletion]) {
        guard let data = try? JSONEncoder().encode(completions) else { return }
        UserDefaults.standard.set(data, forKey: completionsKey)
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current // Use local timezone for accurate day boundaries
        return formatter.string(from: date)
    }
}
