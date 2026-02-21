import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPaused {
                        Text("Paused")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.yellow)
                    } else if let restEndDate = context.state.restEndDate {
                        Text(restEndDate, style: .timer)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    } else {
                        Text(context.attributes.workoutStartDate, style: .timer)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.sessionTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)

                        if context.state.restEndDate != nil {
                            Text("Resting…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.75))
                        } else if context.state.isPaused {
                            Text("Workout paused")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.75))
                        } else {
                            Text("Workout running")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
            } compactTrailing: {
                if let restEndDate = context.state.restEndDate {
                    Text(restEndDate, style: .timer)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                } else if context.state.isPaused {
                    Text("II")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.yellow)
                } else {
                    Text(context.attributes.workoutStartDate, style: .timer)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .widgetURL(URL(string: "fitai://workout"))
            .keylineTint(Color(red: 0.20, green: 0.55, blue: 1.0))
        }
    }
}

private struct WorkoutLiveActivityLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.sessionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                if context.state.isPaused {
                    Text("Paused")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.yellow)
                } else if let restEndDate = context.state.restEndDate {
                    HStack(spacing: 6) {
                        Text("Rest")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                        Text(restEndDate, style: .timer)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text("Elapsed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                        Text(context.attributes.workoutStartDate, style: .timer)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .activityBackgroundTint(Color(red: 0.06, green: 0.07, blue: 0.12))
        .activitySystemActionForegroundColor(Color.white)
    }
}
