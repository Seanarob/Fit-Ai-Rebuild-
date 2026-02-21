import ActivityKit
import Foundation

@MainActor
enum WorkoutLiveActivityManager {
    private static func currentActivity() -> Activity<WorkoutActivityAttributes>? {
        Activity<WorkoutActivityAttributes>.activities.sorted { lhs, rhs in
            lhs.attributes.workoutStartDate > rhs.attributes.workoutStartDate
        }.first
    }

    static func startIfNeeded(
        startDate: Date,
        sessionTitle: String,
        isPaused: Bool,
        restEndDate: Date?,
        restTotalSeconds: Int?
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if currentActivity() != nil {
            await update(
                sessionTitle: sessionTitle,
                isPaused: isPaused,
                restEndDate: restEndDate,
                restTotalSeconds: restTotalSeconds
            )
            return
        }

        let attributes = WorkoutActivityAttributes(workoutStartDate: startDate)
        let state = WorkoutActivityAttributes.ContentState(
            sessionTitle: sessionTitle,
            isPaused: isPaused,
            restEndDate: restEndDate,
            restTotalSeconds: restTotalSeconds
        )

        do {
            _ = try Activity<WorkoutActivityAttributes>.request(
                attributes: attributes,
                contentState: state,
                pushType: nil
            )
        } catch {
            #if DEBUG
            print("[WorkoutLiveActivity] Failed to start:", error.localizedDescription)
            #endif
        }
    }

    static func update(
        sessionTitle: String,
        isPaused: Bool,
        restEndDate: Date?,
        restTotalSeconds: Int?
    ) async {
        guard let activity = currentActivity() else { return }
        let state = WorkoutActivityAttributes.ContentState(
            sessionTitle: sessionTitle,
            isPaused: isPaused,
            restEndDate: restEndDate,
            restTotalSeconds: restTotalSeconds
        )
        await activity.update(using: state)
    }

    static func endAll() async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(dismissalPolicy: .immediate)
        }
    }
}
