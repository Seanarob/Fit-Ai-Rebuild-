import ActivityKit
import SwiftUI
import WidgetKit

private enum RestTimerTheme {
    static let textPrimary = Color(red: 0.98, green: 0.95, blue: 0.92)
}

struct RestTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            RestTimerActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Rest")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .font(.title2)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.workoutName)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Next set soon")
                        .font(.caption)
                }
            } compactLeading: {
                Text("REST")
                    .font(.caption2)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                    .font(.caption2)
                    .monospacedDigit()
            } minimal: {
                Text("⏱")
            }
            .foregroundStyle(RestTimerTheme.textPrimary)
            .widgetURL(URL(string: "fitai://workout"))
        }
    }
}

private struct RestTimerActivityView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.attributes.workoutName)
                .font(.headline)
            Text("Rest Timer")
                .font(.caption)
            Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding()
        .foregroundStyle(RestTimerTheme.textPrimary)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(RestTimerTheme.textPrimary)
    }
}
