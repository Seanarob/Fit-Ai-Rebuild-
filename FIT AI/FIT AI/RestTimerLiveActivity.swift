import ActivityKit
import Foundation

enum RestTimerLiveActivity {
    private static var activity: Activity<RestTimerAttributes>?

    static func start(workoutName: String, durationSeconds: Int) {
        guard durationSeconds > 0 else { return }
        if #available(iOS 16.1, *) {
            let authorization = ActivityAuthorizationInfo()
            guard authorization.areActivitiesEnabled else { return }
            let attributes = RestTimerAttributes(workoutName: workoutName)
            let endDate = Date().addingTimeInterval(TimeInterval(durationSeconds))
            let content = RestTimerAttributes.ContentState(
                endDate: endDate,
                remainingSeconds: durationSeconds
            )
            do {
                if #available(iOS 17.0, *) {
                    let activityContent = ActivityContent(state: content, staleDate: nil)
                    activity = try Activity.request(attributes: attributes, content: activityContent, pushType: nil)
                } else {
                    activity = try Activity.request(attributes: attributes, contentState: content, pushType: nil)
                }
            } catch {
                activity = nil
            }
        }
    }

    static func update(remainingSeconds: Int) {
        if #available(iOS 16.1, *) {
            guard let activity else { return }
            let content = RestTimerAttributes.ContentState(
                endDate: Date().addingTimeInterval(TimeInterval(remainingSeconds)),
                remainingSeconds: remainingSeconds
            )
            Task {
                if #available(iOS 17.0, *) {
                    let activityContent = ActivityContent(state: content, staleDate: nil)
                    await activity.update(activityContent)
                } else {
                    await activity.update(using: content)
                }
            }
        }
    }

    static func stop() {
        if #available(iOS 16.1, *) {
            guard let activity else { return }
            Task {
                if #available(iOS 17.0, *) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                } else {
                    await activity.end(using: nil, dismissalPolicy: .immediate)
                }
            }
            self.activity = nil
        }
    }
}
