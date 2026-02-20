import Foundation

enum TodayTrainingSource: String, Codable {
    case coach
    case generated
    case saved
    case custom
}

struct TodayTrainingSnapshot: Codable {
    let dateKey: String
    let title: String
    let exercises: [String]
    let source: TodayTrainingSource
    let templateId: String?
    let createdAt: Date
}

enum TodayTrainingStore {
    private static let storeKey = "fitai.training.today.snapshot"

    static func save(
        date: Date = Date(),
        title: String,
        exercises: [String],
        source: TodayTrainingSource,
        templateId: String? = nil,
        createdAt: Date = Date()
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? "Today's Training" : trimmedTitle
        let normalizedExercises = exercises
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let snapshot = TodayTrainingSnapshot(
            dateKey: dayKey(for: date),
            title: resolvedTitle,
            exercises: normalizedExercises,
            source: source,
            templateId: templateId,
            createdAt: createdAt
        )

        if let existing = todaysTraining(date: date), existing.createdAt >= createdAt {
            return
        }

        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }

        NotificationCenter.default.post(
            name: .fitAITodayTrainingUpdated,
            object: nil,
            userInfo: ["snapshot": snapshot]
        )
    }

    static func todaysTraining(date: Date = Date()) -> TodayTrainingSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let snapshot = try? JSONDecoder().decode(TodayTrainingSnapshot.self, from: data) else {
            return nil
        }
        return snapshot.dateKey == dayKey(for: date) ? snapshot : nil
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: value)
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

extension Notification.Name {
    static let fitAITodayTrainingUpdated = Notification.Name("fitai.training.today.updated")
}
