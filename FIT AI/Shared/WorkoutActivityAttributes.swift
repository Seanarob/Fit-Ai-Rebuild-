import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var sessionTitle: String
        var isPaused: Bool
        var restEndDate: Date?
        var restTotalSeconds: Int?
    }

    var workoutStartDate: Date
}

