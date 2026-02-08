import Foundation

extension WorkoutSession {
    var isHealthWorkout: Bool {
        id.hasPrefix("health-")
    }
}
