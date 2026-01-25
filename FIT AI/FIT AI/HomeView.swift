import SwiftUI
import Combine

struct HomeView: View {
    let userId: String
    @Binding var selectedTab: MainTab
    @Binding var workoutIntent: WorkoutTabIntent?
    @Binding var nutritionIntent: NutritionTabIntent?
    @StateObject private var viewModel: HomeViewModel
    @AppStorage("fitai.home.lastGreetingDate") private var lastGreetingDate = ""
    @State private var showGreeting = false
    @State private var showSettings = false
    @State private var todaysWorkout: WorkoutCompletion?

    private let trainingPreview = [
        "Bench Press · 4 x 8",
        "Incline DB Press · 3 x 10"
    ]

    init(
        userId: String,
        selectedTab: Binding<MainTab>,
        workoutIntent: Binding<WorkoutTabIntent?>,
        nutritionIntent: Binding<NutritionTabIntent?>
    ) {
        self.userId = userId
        _selectedTab = selectedTab
        _workoutIntent = workoutIntent
        _nutritionIntent = nutritionIntent
        _viewModel = StateObject(wrappedValue: HomeViewModel(userId: userId))
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StreakBadge(days: viewModel.streakDays)

                    HomeHeaderView(name: viewModel.displayName) {
                        showSettings = true
                    }

                    TodayTrainingCard(
                        exercises: trainingPreview,
                        completedExercises: todaysWorkout?.exercises ?? [],
                        isCompleted: todaysWorkout != nil,
                        onStartWorkout: {
                            workoutIntent = .startRecommended
                            selectedTab = .workout
                        },
                        onSwap: {
                            workoutIntent = .swapSaved
                            selectedTab = .workout
                        }
                    )

                    NutritionSnapshotCard(
                        caloriesUsed: Int(viewModel.macroTotals.calories),
                        caloriesTarget: Int(viewModel.macroTargets.calories),
                        protein: MacroProgress(
                            name: "Protein",
                            current: Int(viewModel.macroTotals.protein),
                            target: Int(viewModel.macroTargets.protein)
                        ),
                        carbs: MacroProgress(
                            name: "Carbs",
                            current: Int(viewModel.macroTotals.carbs),
                            target: Int(viewModel.macroTargets.carbs)
                        ),
                        fats: MacroProgress(
                            name: "Fats",
                            current: Int(viewModel.macroTotals.fats),
                            target: Int(viewModel.macroTargets.fats)
                        ),
                        onLogMeal: {
                            nutritionIntent = .logMeal
                            selectedTab = .nutrition
                        },
                        onScanFood: {
                            nutritionIntent = .logMeal
                            selectedTab = .nutrition
                        }
                    )

                    ProgressSummaryCard(weight: viewModel.latestWeight, lastPr: viewModel.lastPr)
                    GoalCard(goal: viewModel.goal, height: viewModel.heightText, gender: viewModel.genderText)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            if showGreeting {
                DailyCoachGreetingView(
                    name: viewModel.displayName,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showGreeting = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .sheet(isPresented: $showSettings) {
            MoreView(userId: userId)
        }
        .task {
            await viewModel.load()
            updateGreetingIfNeeded()
            todaysWorkout = WorkoutCompletionStore.todaysCompletion()
        }
        .onAppear {
            updateGreetingIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIMacrosUpdated)) { _ in
            Task { await viewModel.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIWorkoutStreakUpdated)) { notification in
            if let streak = notification.userInfo?["streak"] as? Int {
                viewModel.streakDays = streak
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIWorkoutCompleted)) { notification in
            if let completion = notification.userInfo?["completion"] as? WorkoutCompletion {
                todaysWorkout = completion
            } else {
                todaysWorkout = WorkoutCompletionStore.todaysCompletion()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAINutritionLogged)) { notification in
            if let macros = notification.userInfo?["macros"] as? [String: Any] {
                viewModel.macroTotals = MacroTotals.fromDictionary(macros)
            }
            Task { await viewModel.load() }
        }
        .onChange(of: selectedTab) { tab in
            if tab == .home {
                Task { await viewModel.load() }
            }
        }
    }

    private func updateGreetingIfNeeded() {
        let today = greetingDateKey()
        guard lastGreetingDate != today else { return }
        lastGreetingDate = today
        withAnimation(.easeInOut(duration: 0.2)) {
            showGreeting = true
        }
    }

    private func greetingDateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}

private struct HomeHeaderView: View {
    let name: String
    let onSettingsTap: () -> Void

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Welcome back"
        }
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(greeting), \(name)")
                    .font(FitFont.body(size: 18))
                    .foregroundColor(FitTheme.textSecondary)

                Text("Ready to train?")
                    .font(FitFont.heading(size: 30))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)
            }

            Spacer()

            Button(action: onSettingsTap) {
                Image(systemName: "gearshape.fill")
                    .font(FitFont.body(size: 18, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(10)
                    .background(FitTheme.cardBackground)
                    .clipShape(Circle())
            }
        }
    }
}

private struct DailyCoachGreetingView: View {
    let name: String
    let onDismiss: () -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base: String
        switch hour {
        case 5..<12: base = "Good morning"
        case 12..<17: base = "Good afternoon"
        case 17..<22: base = "Good evening"
        default: base = "Welcome back"
        }
        guard !trimmedName.isEmpty else { return base }
        return "\(base), \(trimmedName)"
    }

    private var greetingMessage: String {
        "Your coach is ready with today's plan. Quick check-in and we start."
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer(minLength: 8)

                    ZStack {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(FitTheme.cardBackground.opacity(0.96))
                            .shadow(color: FitTheme.shadow, radius: 16, x: 0, y: 10)

                        CoachDotBackground()
                            .opacity(0.5)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

                    CoachArtView(pose: .neutral)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
                    )
                    .frame(height: min(geometry.size.height * 0.48, 360))
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 10) {
                        Text(greetingTitle)
                            .font(FitFont.heading(size: 34, weight: .bold))
                            .foregroundColor(FitTheme.textPrimary)

                        Text(greetingMessage)
                            .font(FitFont.body(size: 16, weight: .regular))
                            .foregroundColor(FitTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Button("Let's go") {
                        onDismiss()
                    }
                    .font(FitFont.body(size: 17, weight: .semibold))
                    .foregroundColor(FitTheme.buttonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: FitTheme.buttonShadow, radius: 16, x: 0, y: 10)

                    Spacer(minLength: 16)
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 12)
            }
        }
    }

    private struct CoachDotBackground: View {
        var body: some View {
            GeometryReader { proxy in
                Canvas { context, size in
                    let dotSize: CGFloat = 2
                    let spacing: CGFloat = 16
                    let color = FitTheme.cardStroke.opacity(0.35)

                    for x in stride(from: 0, through: size.width, by: spacing) {
                        for y in stride(from: 0, through: size.height, by: spacing) {
                            let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                            context.fill(Path(ellipseIn: rect), with: .color(color))
                        }
                    }
                }
            }
        }
    }

}

private struct TodayTrainingCard: View {
    let exercises: [String]
    let completedExercises: [String]
    let isCompleted: Bool
    let onStartWorkout: () -> Void
    let onSwap: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Today's Training")
                        .font(FitFont.body(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Spacer()

                    if isCompleted {
                        Text("Completed")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.success)
                    } else {
                        Text("Push Day")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    let list = isCompleted ? completedExercises : exercises
                    ForEach(list, id: \.self) { item in
                        Text(item)
                            .font(FitFont.body(size: 15))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }

                if !isCompleted {
                    HStack(spacing: 12) {
                        ActionButton(title: "Start Workout", style: .primary, action: onStartWorkout)
                        ActionButton(title: "Swap", style: .secondary, action: onSwap)
                    }
                }
            }
        }
    }
}

private struct CoachQuickCard: View {
    let onOpen: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("AI Coach")
                        .font(FitFont.body(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Spacer()

                    Image(systemName: "sparkles")
                        .foregroundColor(FitTheme.accent)
                }

                Text("Ask about workouts, nutrition, recovery, or your plan.")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)

                ActionButton(title: "Open Coach", style: .primary, action: onOpen)
            }
        }
    }
}

private struct GoalCard: View {
    let goal: String
    let height: String
    let gender: String

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Profile Snapshot")
                    .font(FitFont.body(size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                HStack(spacing: 12) {
                    InfoChip(title: "Goal", value: goal)
                    InfoChip(title: "Height", value: height)
                    InfoChip(title: "Gender", value: gender)
                }
            }
        }
    }
}

private struct NutritionSnapshotCard: View {
    let caloriesUsed: Int
    let caloriesTarget: Int
    let protein: MacroProgress
    let carbs: MacroProgress
    let fats: MacroProgress
    let onLogMeal: () -> Void
    let onScanFood: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Nutrition Snapshot")
                        .font(FitFont.body(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Spacer()

                    Text("Today")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(max(caloriesTarget - caloriesUsed, 0))")
                        .font(FitFont.heading(size: 34))
                        .fontWeight(.bold)
                        .foregroundColor(FitTheme.textPrimary)

                    Text("cal left")
                        .font(FitFont.body(size: 16))
                        .foregroundColor(FitTheme.textSecondary)

                    Spacer()

                    Text("\(caloriesUsed) / \(caloriesTarget) used")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }

                MacroRow(progress: protein)
                MacroRow(progress: carbs)
                MacroRow(progress: fats)

                HStack(spacing: 12) {
                    ActionButton(title: "Log Meal", style: .primary, action: onLogMeal)
                    ActionButton(title: "Scan Food", style: .secondary, action: onScanFood)
                }
            }
        }
    }
}

private struct ProgressSummaryCard: View {
    let weight: Double?
    let lastPr: String

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text("Progress Summary")
                    .font(FitFont.body(size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weight")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)

                        Text(weightText)
                            .font(FitFont.heading(size: 26))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.textPrimary)
                    }

                    Spacer()

                    MiniTrendView()
                }

                HStack(spacing: 16) {
                    InfoChip(title: "Last PR", value: lastPr)
                }
            }
        }
    }

    private var weightText: String {
        guard let weight else { return "—" }
        return String(format: "%.1f lb", weight)
    }
}

private struct StreakBadge: View {
    let days: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundColor(FitTheme.buttonText)
            Text("\(days) day streak")
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.buttonText)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(FitTheme.streakGradient)
        .clipShape(Capsule())
    }
}

private struct MiniTrendView: View {
    private let values: [CGFloat] = [0.3, 0.5, 0.45, 0.6, 0.55, 0.7, 0.65]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(values.indices, id: \.self) { index in
                Capsule()
                    .fill(index == values.indices.last ? FitTheme.accent : FitTheme.cardHighlight)
                    .frame(width: 6, height: 46 * values[index] + 8)
            }
        }
    }
}

private struct InfoChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)

            Text(value)
                .font(FitFont.body(size: 15))
                .foregroundColor(FitTheme.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct MacroProgress {
    let name: String
    let current: Int
    let target: Int

    var ratio: Double {
        guard target > 0 else { return 0 }
        return min(Double(current) / Double(target), 1.0)
    }

    var remaining: Int {
        max(target - current, 0)
    }
}

private struct MacroRow: View {
    let progress: MacroProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.name)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)

                Spacer()

                Text("\(progress.remaining) g left")
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.accent)
            }

            ProgressBar(value: progress.ratio)
        }
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(FitTheme.cardHighlight)

                RoundedRectangle(cornerRadius: 6)
                    .fill(FitTheme.primaryGradient)
                    .frame(width: proxy.size.width * value)
            }
        }
        .frame(height: 8)
    }
}

private enum ActionButtonStyle {
    case primary
    case secondary
}

private struct ActionButton: View {
    let title: String
    let style: ActionButtonStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FitFont.body(size: 14))
                .fontWeight(.semibold)
                .foregroundColor(style == .primary ? FitTheme.buttonText : FitTheme.textPrimary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background {
                    if style == .primary {
                        FitTheme.primaryGradient
                    } else {
                        FitTheme.cardBackground
                    }
                }
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(style == .secondary ? FitTheme.cardStroke : Color.clear, lineWidth: 1)
                )
                .shadow(color: style == .primary ? FitTheme.buttonShadow : .clear, radius: 12, x: 0, y: 6)
        }
    }
}

private struct CardContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: FitTheme.shadow, radius: 18, x: 0, y: 10)
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var displayName = "Athlete"
    @Published var macroTotals = MacroTotals.zero
    @Published var macroTargets = MacroTotals.zero
    @Published var latestWeight: Double?
    @Published var goal = "—"
    @Published var heightText = "—"
    @Published var genderText = "—"
    @Published var lastPr = "—"
    @Published var streakDays = 0

    private let userId: String

    init(userId: String) {
        self.userId = userId
    }

    func load() async {
        guard !userId.isEmpty else { return }
        do {
            async let profileTask = ProfileAPIService.shared.fetchProfile(userId: userId)
            async let checkinsTask = ProgressAPIService.shared.fetchCheckins(userId: userId, limit: 1)
            async let logsTask = NutritionAPIService.shared.fetchDailyLogs(userId: userId)

            let profile = try await profileTask
            let checkins = try await checkinsTask
            let logs = try await logsTask

            updateFromProfile(profile)
            updateFromCheckins(checkins)
            updateFromLogs(logs)
        } catch {
            // Keep existing values if any call fails.
        }
    }

    private func updateFromProfile(_ profile: [String: Any]) {
        if let fullName = profile["full_name"] as? String, !fullName.isEmpty {
            displayName = fullName
        } else if let email = profile["email"] as? String, !email.isEmpty {
            displayName = email
        }

        if let goal = profile["goal"] as? String, !goal.isEmpty {
            self.goal = goal.replacingOccurrences(of: "_", with: " ")
        }

        if let macros = profile["macros"] as? [String: Any] {
            let totals = MacroTotals.fromDictionary(macros)
            if totals != .zero {
                macroTargets = totals
            }
        }

        if let heightCm = profile["height_cm"] as? Double {
            heightText = formatHeight(cm: heightCm)
        } else if let heightCm = profile["height_cm"] as? Int {
            heightText = formatHeight(cm: Double(heightCm))
        }

        if let prefs = profile["preferences"] as? [String: Any],
           let gender = prefs["gender"] as? String,
           !gender.isEmpty {
            genderText = gender.capitalized
        }
    }

    private func updateFromCheckins(_ checkins: [WeeklyCheckin]) {
        latestWeight = checkins.first?.weight
        let workoutStreak = WorkoutStreakStore.current()
        streakDays = workoutStreak > 0 ? workoutStreak : max(checkins.count, 0)
    }

    private func updateFromLogs(_ logs: [NutritionLogEntry]) {
        macroTotals = buildTotals(from: logs)
    }

    private func buildTotals(from logs: [NutritionLogEntry]) -> MacroTotals {
        var total = MacroTotals.zero
        for log in logs {
            let entryTotals = MacroTotals.fromLogTotals(log.totals)
            if entryTotals != .zero {
                total = total.adding(entryTotals)
                continue
            }
            let items = log.items ?? []
            let itemTotals = items.reduce(MacroTotals.zero) { partial, item in
                let macros = MacroTotals(
                    calories: item.calories ?? 0,
                    protein: item.protein ?? 0,
                    carbs: item.carbs ?? 0,
                    fats: item.fats ?? 0
                )
                return partial.adding(macros)
            }
            total = total.adding(itemTotals)
        }
        return total
    }

    private func formatHeight(cm: Double) -> String {
        guard cm > 0 else { return "—" }
        let totalInches = cm / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(round(totalInches.truncatingRemainder(dividingBy: 12)))
        return "\(feet)'\(inches)\""
    }
}

enum FitTheme {
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.96, blue: 0.94),
            Color(red: 0.97, green: 0.93, blue: 0.91),
            Color(red: 0.95, green: 0.90, blue: 0.88)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardBackground = Color(red: 1.0, green: 0.98, blue: 0.97)
    static let cardHighlight = Color(red: 0.95, green: 0.92, blue: 0.90)
    static let cardStroke = Color(red: 0.90, green: 0.86, blue: 0.84)
    static let accent = Color(red: 0.29, green: 0.18, blue: 1.0)
    static let accentSoft = Color(red: 0.86, green: 0.82, blue: 1.0)
    static let accentMuted = Color(red: 0.74, green: 0.69, blue: 0.98)
    static let textPrimary = Color(red: 0.12, green: 0.10, blue: 0.09)
    static let textSecondary = Color(red: 0.45, green: 0.40, blue: 0.37)
    static let buttonText = Color(red: 0.98, green: 0.95, blue: 0.92)
    static let shadow = Color(red: 0.23, green: 0.17, blue: 0.36).opacity(0.12)
    static let buttonShadow = Color(red: 0.35, green: 0.22, blue: 0.86).opacity(0.35)
    static let success = Color(red: 0.16, green: 0.66, blue: 0.38)

    static let primaryGradient = LinearGradient(
        colors: [
            Color(red: 0.32, green: 0.20, blue: 1.0),
            Color(red: 0.45, green: 0.27, blue: 0.98)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let streakGradient = LinearGradient(
        colors: [
            Color(red: 0.30, green: 0.20, blue: 1.0),
            Color(red: 0.46, green: 0.28, blue: 0.98)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let proteinColor = Color(red: 0.98, green: 0.64, blue: 0.17)
    static let carbColor = Color(red: 0.98, green: 0.43, blue: 0.55)
    static let fatColor = Color(red: 0.56, green: 0.33, blue: 0.94)

    static func macroColor(for title: String) -> Color {
        let lower = title.lowercased()
        if lower.contains("protein") { return proteinColor }
        if lower.contains("carb") { return carbColor }
        if lower.contains("fat") { return fatColor }
        return accent
    }
}

#Preview {
    HomeView(
        userId: "demo-user",
        selectedTab: .constant(.home),
        workoutIntent: .constant(nil),
        nutritionIntent: .constant(nil)
    )
}
