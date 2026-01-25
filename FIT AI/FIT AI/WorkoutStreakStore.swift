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
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func dateFromKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: key)
    }
}

extension Notification.Name {
    static let fitAIWorkoutStreakUpdated = Notification.Name("fitai.workout.streak.updated")
    static let fitAIWorkoutCompleted = Notification.Name("fitai.workout.completed")
}

struct WorkoutCompletion: Codable {
    let dateKey: String
    let exercises: [String]
}

enum WorkoutCompletionStore {
    private static let storeKey = "fitai.workout.completion"

    static func markCompleted(exercises: [String], date: Date = Date()) {
        let completion = WorkoutCompletion(dateKey: dayKey(for: date), exercises: exercises)
        if let data = try? JSONEncoder().encode(completion) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
        NotificationCenter.default.post(
            name: .fitAIWorkoutCompleted,
            object: nil,
            userInfo: ["completion": completion]
        )
    }

    static func todaysCompletion(date: Date = Date()) -> WorkoutCompletion? {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let completion = try? JSONDecoder().decode(WorkoutCompletion.self, from: data) else {
            return nil
        }
        return completion.dateKey == dayKey(for: date) ? completion : nil
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
