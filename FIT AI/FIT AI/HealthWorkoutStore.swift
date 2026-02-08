import Foundation

struct HealthWorkout: Codable, Identifiable {
    let id: String
    let activityType: String
    let startDate: Date
    let endDate: Date
    let durationSeconds: Int
    let energyBurned: Double?
    let sourceName: String?
}

enum HealthWorkoutStore {
    private static let storeKey = "fitai.health.workouts"
    private static let maxStoredWorkouts = 200

    static func allWorkouts() -> [HealthWorkout] {
        load()
    }

    @discardableResult
    static func merge(_ workouts: [HealthWorkout]) -> [HealthWorkout] {
        guard !workouts.isEmpty else { return [] }
        var existing = load()
        let existingIds = Set(existing.map { $0.id })
        let newWorkouts = workouts.filter { !existingIds.contains($0.id) }
        guard !newWorkouts.isEmpty else { return [] }

        existing.append(contentsOf: newWorkouts)
        let cutoff = Calendar.current.date(byAdding: .day, value: -120, to: Date()) ?? Date.distantPast
        existing = existing.filter { $0.startDate >= cutoff }
        existing.sort { $0.startDate > $1.startDate }
        if existing.count > maxStoredWorkouts {
            existing = Array(existing.prefix(maxStoredWorkouts))
        }
        save(existing)
        return newWorkouts
    }

    private static func load() -> [HealthWorkout] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([HealthWorkout].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.startDate > $1.startDate }
    }

    private static func save(_ workouts: [HealthWorkout]) {
        guard let data = try? JSONEncoder().encode(workouts) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }
}
