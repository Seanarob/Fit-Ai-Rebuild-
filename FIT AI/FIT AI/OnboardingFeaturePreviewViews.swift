import SwiftUI

struct MealPlanPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var calorieProgress: CGFloat = 0.18
    @State private var autoAdjust = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            PreviewPalette.screenBackground(colorScheme)

            VStack(alignment: .leading, spacing: 12) {
                previewHeader(title: "Meal Plan", badge: "Auto-built")

                HStack(spacing: 12) {
                    PreviewProgressRing(
                        progress: calorieProgress,
                        title: "Calories",
                        value: "1,860",
                        tint: .blue
                    )

                    VStack(spacing: 10) {
                        PreviewMacroBar(title: "Protein", value: "156g", progress: 0.82, tint: .blue)
                        PreviewMacroBar(title: "Carbs", value: "210g", progress: 0.68, tint: .blue)
                        PreviewMacroBar(title: "Fats", value: "58g", progress: 0.55, tint: .blue)
                    }
                }

                PreviewCard {
                    VStack(spacing: 10) {
                        PreviewMealRow(name: "Breakfast", time: "7:30 AM", calories: "420 kcal")
                        PreviewDivider()
                        PreviewMealRow(name: "Lunch", time: "12:15 PM", calories: "610 kcal")
                        PreviewDivider()
                        PreviewMealRow(name: "Dinner", time: "7:00 PM", calories: "830 kcal")
                    }
                }

                PreviewCard {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-adjust after workouts")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(PreviewPalette.primaryText(colorScheme))
                            Text("Macros rebalance nightly")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(PreviewPalette.secondaryText(colorScheme))
                        }

                        Spacer()

                        Toggle("", isOn: $autoAdjust)
                            .labelsHidden()
                            .tint(.blue)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            let target: CGFloat = 0.74
            if reduceMotion {
                calorieProgress = target
            } else {
                withAnimation(MotionTokens.easeOut) {
                    calorieProgress = target
                }
            }
        }
    }

    @ViewBuilder
    private func previewHeader(title: String, badge: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(PreviewPalette.primaryText(colorScheme))

            PreviewChip(text: badge, icon: "sparkles", tint: .blue)

            Spacer()
        }
    }
}

struct WorkoutPlanPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var intensity: CGFloat = 0.18
    @State private var selectedDayIndex: Int = 2

    private let workoutDays: Set<Int> = [0, 2, 4, 5]

    var body: some View {
        ZStack(alignment: .topLeading) {
            PreviewPalette.screenBackground(colorScheme)

            VStack(alignment: .leading, spacing: 12) {
                previewHeader(title: "Workout Plan", badge: "Week 2")

                PreviewCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("This Week")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(PreviewPalette.primaryText(colorScheme))
                            Spacer()
                            Text("4 workouts")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(PreviewPalette.secondaryText(colorScheme))
                        }

                        PreviewWeekStrip(selectedIndex: $selectedDayIndex, workoutDays: workoutDays)
                    }
                }

                PreviewCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Today")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(PreviewPalette.secondaryText(colorScheme))
                            Spacer()
                            PreviewChip(text: "45 min", icon: "clock", tint: .blue)
                        }

                        Text("Upper Body Strength")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(PreviewPalette.primaryText(colorScheme))

                        VStack(alignment: .leading, spacing: 6) {
                            PreviewWorkoutRow(name: "Bench Press", detail: "4 x 8")
                            PreviewWorkoutRow(name: "Lat Pulldown", detail: "3 x 10")
                            PreviewWorkoutRow(name: "Incline DB Press", detail: "3 x 12")
                        }

                        PreviewProgressBar(progress: 0.46, tint: .blue)
                    }
                }

                PreviewCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Auto-adjusted intensity")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(PreviewPalette.primaryText(colorScheme))
                            Spacer()
                            Text("\(Int(intensity * 100))%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(PreviewPalette.secondaryText(colorScheme))
                        }

                        PreviewSlider(value: intensity, tint: .blue)
                    }
                }

                Spacer(minLength: 6)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            let target: CGFloat = 0.72
            if reduceMotion {
                intensity = target
            } else {
                withAnimation(MotionTokens.easeOut) {
                    intensity = target
                }
            }
        }
    }

    @ViewBuilder
    private func previewHeader(title: String, badge: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(PreviewPalette.primaryText(colorScheme))

            PreviewChip(text: badge, icon: "calendar", tint: .blue)

            Spacer()
        }
    }
}

struct CheckInPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanProgress: CGFloat = 0.12

    var body: some View {
        ZStack(alignment: .topLeading) {
            PreviewPalette.screenBackground(colorScheme)

            VStack(alignment: .leading, spacing: 12) {
                previewHeader(title: "AI Check-In", badge: "Weekly")

                PreviewCard {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Body Scan")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(PreviewPalette.primaryText(colorScheme))
                            Spacer()
                            PreviewProgressRing(progress: scanProgress, title: "Complete", value: "86%", tint: .blue)
                        }

                        BodyScanGraphic()
                            .frame(height: 120)
                    }
                }

                PreviewCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Coach Insights")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(PreviewPalette.primaryText(colorScheme))

                        PreviewInsightRow(icon: "arrow.up.right", title: "Lean mass", value: "+1.3 lb")
                        PreviewInsightRow(icon: "bolt.heart", title: "Recovery", value: "87%")
                        PreviewInsightRow(icon: "figure.walk", title: "Daily steps", value: "10.4k avg")
                    }
                }

                PreviewCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Next check-in")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(PreviewPalette.secondaryText(colorScheme))
                            Text("Sunday, 7:00 PM")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(PreviewPalette.primaryText(colorScheme))
                        }

                        Spacer()

                        PreviewChip(text: "Schedule", icon: "bell", tint: .blue)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            let target: CGFloat = 0.86
            if reduceMotion {
                scanProgress = target
            } else {
                withAnimation(MotionTokens.easeOut) {
                    scanProgress = target
                }
            }
        }
    }

    @ViewBuilder
    private func previewHeader(title: String, badge: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(PreviewPalette.primaryText(colorScheme))

            PreviewChip(text: badge, icon: "waveform.path.ecg", tint: .blue)

            Spacer()
        }
    }
}

private enum PreviewPalette {
    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.58)
    }

    static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    static func cardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    static func screenBackground(_ scheme: ColorScheme) -> LinearGradient {
        let top = scheme == .dark ? Color(white: 0.10) : Color(white: 0.98)
        let mid = scheme == .dark ? Color(white: 0.07) : Color(white: 0.95)
        let bottom = scheme == .dark ? Color(white: 0.05) : Color(white: 0.92)
        return LinearGradient(
            colors: [top, mid, bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct PreviewCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PreviewPalette.cardBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PreviewPalette.cardStroke(colorScheme), lineWidth: 1)
            )
    }
}

private struct PreviewChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let icon: String
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tint.opacity(colorScheme == .dark ? 0.25 : 0.16))
        .clipShape(Capsule())
    }
}

private struct PreviewProgressRing: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: CGFloat
    let title: String
    let value: String
    var tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(PreviewPalette.cardStroke(colorScheme), lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(PreviewPalette.primaryText(colorScheme))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(PreviewPalette.secondaryText(colorScheme))
            }
        }
        .frame(width: 78, height: 78)
    }
}

private struct PreviewMacroBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let progress: CGFloat
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PreviewPalette.secondaryText(colorScheme))
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PreviewPalette.primaryText(colorScheme))
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let clamped = max(0, min(progress, 1))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PreviewPalette.cardStroke(colorScheme).opacity(0.7))
                    Capsule()
                        .fill(tint)
                        .frame(width: width * clamped)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct PreviewMealRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    let time: String
    let calories: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PreviewPalette.primaryText(colorScheme))
                Text(time)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(PreviewPalette.secondaryText(colorScheme))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(calories)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PreviewPalette.primaryText(colorScheme))
                PreviewChip(text: "Swap", icon: "arrow.2.circlepath", tint: .blue)
            }
        }
    }
}

private struct PreviewWeekStrip: View {
    @Binding var selectedIndex: Int
    let workoutDays: Set<Int>
    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(labels.indices, id: \.self) { index in
                PreviewDayChip(
                    label: labels[index],
                    isWorkout: workoutDays.contains(index),
                    isSelected: selectedIndex == index
                )
                .onTapGesture {
                    selectedIndex = index
                }
            }
        }
    }
}

private struct PreviewDayChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let isWorkout: Bool
    let isSelected: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(textColor)
            .frame(width: 28, height: 28)
            .background(backgroundColor)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(PreviewPalette.cardStroke(colorScheme), lineWidth: isSelected ? 0 : 1)
            )
    }

    private var backgroundColor: Color {
        if isSelected {
            return .blue
        }
        if isWorkout {
            return .blue.opacity(colorScheme == .dark ? 0.24 : 0.16)
        }
        return PreviewPalette.cardBackground(colorScheme)
    }

    private var textColor: Color {
        if isSelected {
            return .white
        }
        return isWorkout ? PreviewPalette.primaryText(colorScheme) : PreviewPalette.secondaryText(colorScheme)
    }
}

private struct PreviewWorkoutRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    let detail: String

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PreviewPalette.primaryText(colorScheme))
            Spacer()
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PreviewPalette.secondaryText(colorScheme))
        }
    }
}

private struct PreviewProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: CGFloat
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clamped = max(0, min(progress, 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PreviewPalette.cardStroke(colorScheme).opacity(0.7))
                Capsule()
                    .fill(tint)
                    .frame(width: width * clamped)
            }
        }
        .frame(height: 6)
    }
}

private struct PreviewSlider: View {
    @Environment(\.colorScheme) private var colorScheme
    let value: CGFloat
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clamped = max(0, min(value, 1))
            let knobOffset = max(6, width * clamped)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PreviewPalette.cardStroke(colorScheme).opacity(0.7))
                    .frame(height: 6)
                Capsule()
                    .fill(tint)
                    .frame(width: width * clamped, height: 6)
                Circle()
                    .fill(tint)
                    .frame(width: 12, height: 12)
                    .offset(x: knobOffset - 6)
            }
        }
        .frame(height: 12)
    }
}

private struct BodyScanGraphic: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanPhase = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PreviewPalette.cardBackground(colorScheme))

            Image(systemName: "figure.stand")
                .resizable()
                .scaledToFit()
                .foregroundColor(.blue.opacity(0.85))
                .padding(20)

            ScanLineView(animate: scanPhase)
                .padding(.horizontal, 14)
        }
        .onAppear {
            if reduceMotion {
                scanPhase = true
            } else {
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: true)) {
                    scanPhase = true
                }
            }
        }
    }
}

private struct ScanLineView: View {
    let animate: Bool

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let start = -height * 0.3
            let end = height * 0.3

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.0), Color.blue.opacity(0.55), Color.blue.opacity(0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 6)
                .offset(y: animate ? end : start)
        }
    }
}

private struct PreviewInsightRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.24 : 0.16))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                )

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PreviewPalette.primaryText(colorScheme))

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PreviewPalette.secondaryText(colorScheme))
        }
    }
}

private struct PreviewDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(PreviewPalette.cardStroke(colorScheme))
            .frame(height: 1)
    }
}
