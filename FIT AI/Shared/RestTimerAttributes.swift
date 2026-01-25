import ActivityKit
import Foundation

struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endDate: Date
        let remainingSeconds: Int
    }

    let workoutName: String
}
