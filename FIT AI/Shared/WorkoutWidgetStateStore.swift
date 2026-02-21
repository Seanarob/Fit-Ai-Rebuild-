import Foundation

struct WorkoutWidgetState: Codable, Hashable {
    var sessionTitle: String
    var startDate: Date
    var isPaused: Bool
    var restEndDate: Date?
    var lastUpdated: Date
    var isActive: Bool
}

enum WorkoutWidgetStateStore {
    private static let storageKey = "fitai.widget.workout.state.v1"

    static func load() -> WorkoutWidgetState? {
        if let groupDefaults = FitAppGroup.userDefaults,
           let data = groupDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(WorkoutWidgetState.self, from: data) {
            return decoded
        }

        if Bundle.main.bundleURL.pathExtension == "appex" {
            return nil
        }

        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(WorkoutWidgetState.self, from: data) else {
            return nil
        }

        return decoded
    }

    static func save(_ state: WorkoutWidgetState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        FitAppGroup.userDefaults?.set(data, forKey: storageKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        FitAppGroup.userDefaults?.removeObject(forKey: storageKey)
    }
}

