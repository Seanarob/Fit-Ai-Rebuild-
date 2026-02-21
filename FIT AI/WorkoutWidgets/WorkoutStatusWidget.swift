import SwiftUI
import WidgetKit

struct WorkoutStatusEntry: TimelineEntry {
    let date: Date
    let state: WorkoutWidgetState?
}

struct WorkoutStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutStatusEntry {
        WorkoutStatusEntry(date: Date(), state: placeholderState())
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutStatusEntry) -> Void) {
        let entry = WorkoutStatusEntry(date: Date(), state: WorkoutWidgetStateStore.load() ?? placeholderState())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutStatusEntry>) -> Void) {
        let now = Date()
        let state = WorkoutWidgetStateStore.load()
        let entry = WorkoutStatusEntry(date: now, state: state)

        let nextRefresh: Date
        if let state, state.isActive, let restEndDate = state.restEndDate, restEndDate > now {
            nextRefresh = restEndDate
        } else {
            nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(30 * 60)
        }

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func placeholderState() -> WorkoutWidgetState? {
        WorkoutWidgetState(
            sessionTitle: "Upper Body",
            startDate: Date().addingTimeInterval(-8 * 60),
            isPaused: false,
            restEndDate: Date().addingTimeInterval(42),
            lastUpdated: Date(),
            isActive: true
        )
    }
}

struct WorkoutStatusWidget: Widget {
    let kind = "WorkoutStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutStatusProvider()) { entry in
            WorkoutStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Workout")
        .description("Quick access to your active workout and rest timer.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct WorkoutStatusWidgetView: View {
    let entry: WorkoutStatusEntry

    private var workoutURL: URL? {
        URL(string: "fitai://workout")
    }

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.12, blue: 0.18),
                            Color(red: 0.06, green: 0.07, blue: 0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            content
                .padding(14)
        }
        .widgetURL(workoutURL)
    }

    @ViewBuilder
    private var content: some View {
        if let state = entry.state, state.isActive {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Active workout")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    if state.isPaused {
                        Text("Paused")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.yellow)
                    }
                }

                Text(state.sessionTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let restEndDate = state.restEndDate {
                    HStack(spacing: 8) {
                        Text("Rest")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(restEndDate, style: .timer)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text("Elapsed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(state.startDate, style: .timer)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }

                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Workout")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()
                }

                Text("Start your next session")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text("Tap to open FIT AI")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer(minLength: 0)
            }
        }
    }
}

