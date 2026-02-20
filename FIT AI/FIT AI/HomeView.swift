import SwiftUI
import Combine
import UIKit

struct HomeView: View {
    let userId: String
    @Binding var selectedTab: MainTab
    @Binding var workoutIntent: WorkoutTabIntent?
    @Binding var nutritionIntent: NutritionTabIntent?
    @Binding var progressIntent: ProgressTabIntent?
    @EnvironmentObject private var guidedTour: GuidedTourCoordinator
    @StateObject private var viewModel: HomeViewModel
    @ObservedObject private var streakStore = StreakStore.shared
    @AppStorage("fitai.home.lastGreetingDate") private var lastGreetingDate = ""
    @AppStorage("fitai.home.lastDailyCheckInPromptDate") private var lastDailyCheckInPromptDate = ""
    @AppStorage("fitai.home.lastWeeklyCheckInPromptDate") private var lastWeeklyCheckInPromptDate = ""
    @State private var showGreeting = false
    @State private var showStreakCelebration = false
    @State private var previousStreak = 0
    @State private var showSettings = false
    @State private var showProfileEdit = false
    @State private var showStreakDetail = false
    @State private var showDailyCheckIn = false
    @State private var showSaveStreakMode = false
    @State private var showWeeklyCheckInPrompt = false
    @State private var hasLoadedHomeData = false
    @State private var todaysWorkout: WorkoutCompletion?
    @State private var todaysTrainingSnapshot: TodayTrainingSnapshot?
    @State private var splitRefreshToken = UUID()
    @State private var hasActivatedPendingOnboardingTour = false
    @State private var homeActiveSession: HomeSessionDraft?
    @State private var showHomeActiveSession = false

    private let trainingPreview = [
        "Bench Press · 4 x 8",
        "Incline DB Press · 3 x 10"
    ]

    init(
        userId: String,
        selectedTab: Binding<MainTab>,
        workoutIntent: Binding<WorkoutTabIntent?>,
        nutritionIntent: Binding<NutritionTabIntent?>,
        progressIntent: Binding<ProgressTabIntent?>
    ) {
        self.userId = userId
        _selectedTab = selectedTab
        _workoutIntent = workoutIntent
        _nutritionIntent = nutritionIntent
        _progressIntent = progressIntent
        _viewModel = StateObject(wrappedValue: HomeViewModel(userId: userId))
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Enhanced Streak Badge with new StreakStore
                        EnhancedStreakBadge(onTap: {
                            showStreakDetail = true
                        })
                        
                        // Daily Check-In Card (if not completed today)
                        if !streakStore.hasCompletedCheckInToday {
                            DailyCheckInCard(
                                currentStreak: streakStore.appStreak.currentStreak,
                                timeRemaining: streakStore.timeUntilMidnight,
                                onCheckIn: { showDailyCheckIn = true }
                            )
                        }

                        HomeHeaderView(
                            name: viewModel.displayName,
                            onHelpTap: {
                                guidedTour.startScreenTour(.home)
                            }
                        ) {
                            showSettings = true
                        }
                        .tourTarget(.homeHeader)
                        .id(GuidedTourTargetID.homeHeader)

                        Group {
                            let schedule = SplitSchedule.loadSnapshot()
                            let splitLabel = SplitSchedule.splitLabel(for: Date(), snapshot: schedule.snapshot)
                            let isTrainingDay = splitLabel != nil
                            let nextTraining = SplitSchedule.nextTrainingDayDetail(after: Date(), snapshot: schedule.snapshot)
                            let coachPickForToday = viewModel.coachPickWorkout?.isCreatedToday == true ? viewModel.coachPickWorkout : nil
                            let hasOverrideTraining = (todaysTrainingSnapshot != nil) || (coachPickForToday != nil)

                            if schedule.hasPreferences && !isTrainingDay && !hasOverrideTraining {
                                NoTrainingTodayCard(nextDetail: nextTraining)
                                    .tourTarget(.homeTrainingCard)
                                    .id(GuidedTourTargetID.homeTrainingCard)
                            } else {
                                let title = coachPickForToday?.title ?? todaysTrainingSnapshot?.title ?? "Today's Training"
                                let snapshotExercises = (todaysTrainingSnapshot?.exercises ?? []).isEmpty ? nil : todaysTrainingSnapshot?.exercises
                                let exercises = coachPickForToday?.exercises ?? snapshotExercises ?? trainingPreview
                                let subtitle = splitLabel ?? "Today's Training"

                                TodayTrainingCard(
                                    title: title,
                                    subtitle: subtitle,
                                    exercises: exercises,
                                    completedExercises: todaysWorkout?.exercises ?? [],
                                    isCompleted: todaysWorkout != nil,
                                    coachPick: coachPickForToday,
                                    onStartWorkout: {
                                        Task {
                                            await startWorkoutFromHome(coachPick: coachPickForToday)
                                        }
                                    },
                                    onSwap: {
                                        workoutIntent = .swapSaved
                                        selectedTab = .workout
                                    }
                                )
                                .tourTarget(.homeTrainingCard)
                                .id(GuidedTourTargetID.homeTrainingCard)
                            }
                        }

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
                        .tourTarget(.homeNutritionCard)
                        .id(GuidedTourTargetID.homeNutritionCard)

                        CheckInReminderCard(
                            daysUntilCheckin: viewModel.daysUntilCheckin,
                            isOverdue: viewModel.isCheckinOverdue,
                            statusText: viewModel.checkinStatusText,
                            checkinDayName: viewModel.checkinDayName,
                            onCheckinTap: {
                                progressIntent = .startCheckin
                                selectedTab = .progress
                            }
                        )
                        .tourTarget(.homeCheckinCard, shape: .roundedRect(cornerRadius: 24), padding: 0)
                        .id(GuidedTourTargetID.homeCheckinCard)
                        
                        ProgressSummaryCard(weight: viewModel.latestWeight, lastPr: viewModel.lastPr)
                        GoalCard(
                            name: viewModel.displayName,
                            goal: viewModel.goal,
                            height: viewModel.heightText,
                            gender: viewModel.genderText,
                            weight: viewModel.latestWeight,
                            age: viewModel.age,
                            onTap: { showProfileEdit = true }
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .onAppear {
                    scrollToGuidedTourTarget(using: proxy)
                }
                .onChange(of: guidedTour.currentStep?.id) { _ in
                    scrollToGuidedTourTarget(using: proxy)
                }
            }
            // Save Your Streak Mode (when <6 hours remaining and streaks at risk)
            if showSaveStreakMode {
                SaveYourStreakView(
                    atRiskStreaks: streakStore.atRiskStreaks,
                    onActionComplete: { streakType in
                        handleStreakActionComplete(streakType)
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showSaveStreakMode = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
            
            if showWeeklyCheckInPrompt {
                WeeklyCheckInDuePromptView(
                    isOverdue: viewModel.isCheckinOverdue,
                    statusText: viewModel.checkinStatusText,
                    onStartCheckIn: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showWeeklyCheckInPrompt = false
                        }
                        progressIntent = .startCheckin
                        selectedTab = .progress
                    },
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showWeeklyCheckInPrompt = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(2)
            }
            
            if showGreeting && !showSaveStreakMode && !showWeeklyCheckInPrompt {
                DailyCoachGreetingView(
                    name: viewModel.displayName,
                    streakDays: streakStore.appStreak.currentStreak,
                    onDismiss: {
                        onGreetingDismissed()
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
            
            if showStreakCelebration {
                StreakCelebrationView(
                    streakDays: streakStore.appStreak.currentStreak,
                    onDismiss: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showStreakCelebration = false
                        }
                    }
                )
                .transition(.scale.combined(with: .opacity))
                .zIndex(3)
            }
        }
        .sheet(isPresented: $showSettings) {
            MoreView(userId: userId)
        }
        .sheet(isPresented: $showProfileEdit) {
            ProfileEditSheet(
                userId: userId,
                name: viewModel.displayName,
                goal: viewModel.goal,
                height: viewModel.heightText,
                gender: viewModel.genderText,
                weight: viewModel.latestWeight,
                age: viewModel.age,
                onSave: {
                    Task { await viewModel.load() }
                }
            )
        }
        .sheet(isPresented: $showStreakDetail) {
            EnhancedStreakDetailView()
        }
        .sheet(isPresented: $showDailyCheckIn) {
            DailyCheckInView(onComplete: {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    showStreakCelebration = true
                }
            })
        }
        .fullScreenCover(isPresented: $showHomeActiveSession, onDismiss: {
            homeActiveSession = nil
        }) {
            Group {
                if let session = homeActiveSession, !session.exercises.isEmpty {
                    WorkoutSessionView(
                        userId: userId,
                        title: session.title,
                        sessionId: session.sessionId,
                        exercises: session.exercises
                    )
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("Unable to load workout")
                            .font(FitFont.heading(size: 20))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Please try again")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                        Button("Dismiss") {
                            showHomeActiveSession = false
                            homeActiveSession = nil
                        }
                        .foregroundColor(FitTheme.accent)
                        .padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FitTheme.backgroundGradient.ignoresSafeArea())
                }
            }
        }
        .task {
            await viewModel.load()
            hasLoadedHomeData = true
            promptWeeklyCheckInIfNeeded()
            promptDailyCheckInIfNeeded()
            updateGreetingIfNeeded()
            todaysWorkout = WorkoutCompletionStore.todaysCompletion()
            todaysTrainingSnapshot = TodayTrainingStore.todaysTraining()
            tryActivatePendingOnboardingTourIfNeeded()
        }
        .onAppear {
            promptDailyCheckInIfNeeded()
            updateGreetingIfNeeded()
            tryActivatePendingOnboardingTourIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIMacrosUpdated)) { _ in
            Task { await viewModel.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAISplitUpdated)) { _ in
            splitRefreshToken = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIWalkthroughReplayRequested)) { _ in
            showSettings = false
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
        .onReceive(NotificationCenter.default.publisher(for: .fitAITodayTrainingUpdated)) { _ in
            todaysTrainingSnapshot = TodayTrainingStore.todaysTraining()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAINutritionLogged)) { notification in
            // Update macro totals immediately for responsive UI
            Task { @MainActor in
                let logDate = notification.userInfo?["logDate"] as? String
                let isTodayLog = (logDate == nil) || (logDate == NutritionLocalStore.todayKey)
                if isTodayLog, let macros = notification.userInfo?["macros"] as? [String: Any] {
                    viewModel.macroTotals = MacroTotals.fromDictionary(macros)
                }
                if isTodayLog {
                    // Also reload full data to ensure sync
                    await viewModel.load()
                }
            }
        }
        .onChange(of: selectedTab) { tab in
            if tab == .home {
                Task { await viewModel.load() }
                todaysTrainingSnapshot = TodayTrainingStore.todaysTraining()
                tryActivatePendingOnboardingTourIfNeeded()
            }
        }
        .onChange(of: showGreeting) { _ in
            tryActivatePendingOnboardingTourIfNeeded()
        }
        .onChange(of: showSaveStreakMode) { _ in
            tryActivatePendingOnboardingTourIfNeeded()
        }
        .onChange(of: showWeeklyCheckInPrompt) { _ in
            tryActivatePendingOnboardingTourIfNeeded()
        }
        .onChange(of: showDailyCheckIn) { _ in
            tryActivatePendingOnboardingTourIfNeeded()
        }
    }

    private func updateGreetingIfNeeded() {
        let today = greetingDateKey()
        guard lastGreetingDate != today else { return }
        
        // Store previous streak for animation
        previousStreak = streakStore.appStreak.currentStreak
        
        lastGreetingDate = today
        
        // Check if we should show Save Your Streak mode instead
        if shouldPromptWeeklyCheckIn() || showWeeklyCheckInPrompt {
            showSaveStreakMode = false
            markWeeklyCheckInPrompted()
            withAnimation(.easeInOut(duration: 0.2)) {
                showWeeklyCheckInPrompt = true
            }
        } else if streakStore.shouldShowSaveStreakMode && !streakStore.hasCompletedCheckInToday {
            withAnimation(.easeInOut(duration: 0.3)) {
                showSaveStreakMode = true
            }
        } else if shouldPromptDailyCheckIn() || showDailyCheckIn {
            return
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                showGreeting = true
            }
        }
    }
    
    private func onGreetingDismissed() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showGreeting = false
        }
        
        // If check-in not completed, prompt once per day
        if shouldPromptDailyCheckIn() {
            markDailyCheckInPrompted()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showDailyCheckIn = true
            }
        }
    }

    private func tryActivatePendingOnboardingTourIfNeeded() {
        guard !hasActivatedPendingOnboardingTour else { return }
        guard selectedTab == .home else { return }
        guard !showGreeting else { return }
        guard !showSaveStreakMode else { return }
        guard !showWeeklyCheckInPrompt else { return }
        guard !showDailyCheckIn else { return }
        hasActivatedPendingOnboardingTour = true
        guidedTour.activatePendingOnboardingTourIfNeeded()
    }

    private func scrollToGuidedTourTarget(using proxy: ScrollViewProxy) {
        guard let step = guidedTour.currentStep else { return }
        guard step.screen == .home else { return }
        guard let target = step.target else { return }

        let anchor: UnitPoint
        switch target {
        case .homeHeader:
            anchor = .top
        case .homeTrainingCard, .homeNutritionCard, .homeCheckinCard:
            anchor = .center
        default:
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(target, anchor: anchor)
            }
        }
    }
    
    private func handleStreakActionComplete(_ streakType: StreakType) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSaveStreakMode = false
        }
        
        // Navigate to appropriate tab based on action
        switch streakType {
        case .app:
            // Check-in completed, show celebration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    showStreakCelebration = true
                }
            }
        case .nutrition:
            nutritionIntent = .logMeal
            selectedTab = .nutrition
        case .weeklyWin:
            let coachPickForToday = viewModel.coachPickWorkout?.isCreatedToday == true ? viewModel.coachPickWorkout : nil
            Task {
                await startWorkoutFromHome(coachPick: coachPickForToday)
            }
        }
    }

    private func startWorkoutFromHome(coachPick: CoachPickWorkout?) async {
        let launchPlan = workoutLaunchPlan(coachPick: coachPick)

        await MainActor.run {
            homeActiveSession = HomeSessionDraft(
                sessionId: nil,
                title: launchPlan.title,
                exercises: launchPlan.exercises
            )
            showHomeActiveSession = true
        }

        TodayTrainingStore.save(
            title: launchPlan.title,
            exercises: launchPlan.exercises.map(\.name),
            source: launchPlan.source,
            templateId: launchPlan.templateId
        )

        guard !userId.isEmpty else { return }

        do {
            let sessionId = try await WorkoutAPIService.shared.startSession(
                userId: userId,
                templateId: launchPlan.templateId
            )
            await MainActor.run {
                guard showHomeActiveSession else { return }
                homeActiveSession = HomeSessionDraft(
                    sessionId: sessionId,
                    title: launchPlan.title,
                    exercises: launchPlan.exercises
                )
            }
        } catch {
            // Keep the local session running even if backend session creation fails.
        }
    }

    private func workoutLaunchPlan(coachPick: CoachPickWorkout?) -> HomeWorkoutLaunchPlan {
        if let coachPick {
            let exercises = coachPick.exerciseDetails.map { detail in
                makeSessionExercise(
                    name: detail.name,
                    sets: max(1, detail.sets),
                    reps: detail.reps,
                    restSeconds: 60
                )
            }
            return HomeWorkoutLaunchPlan(
                title: coachPick.title,
                templateId: coachPick.id,
                source: .coach,
                exercises: exercises.isEmpty ? defaultHomeRecommendedExercises : exercises
            )
        }

        let snapshotTitle = todaysTrainingSnapshot?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = snapshotTitle.isEmpty ? "Today's Training" : snapshotTitle
        let snapshotExerciseNames = (todaysTrainingSnapshot?.exercises ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let exercises = snapshotExerciseNames.isEmpty
            ? defaultHomeRecommendedExercises
            : snapshotExerciseNames.map { makeSessionExercise(name: $0, sets: 3, reps: "10", restSeconds: 90) }

        return HomeWorkoutLaunchPlan(
            title: title,
            templateId: nil,
            source: .custom,
            exercises: exercises
        )
    }

    private var defaultHomeRecommendedExercises: [WorkoutExerciseSession] {
        [
            makeSessionExercise(name: "Bench Press", sets: 3, reps: "8", restSeconds: 90),
            makeSessionExercise(name: "Incline Dumbbell Press", sets: 3, reps: "10", restSeconds: 75),
            makeSessionExercise(name: "Cable Fly", sets: 3, reps: "12", restSeconds: 60)
        ]
    }

    private func makeSessionExercise(name: String, sets: Int, reps: String, restSeconds: Int) -> WorkoutExerciseSession {
        let repsText = reps.trimmingCharacters(in: .whitespacesAndNewlines)
        var session = WorkoutExerciseSession(
            name: name,
            sets: WorkoutSetEntry.batch(
                reps: repsText.isEmpty ? "10" : repsText,
                count: max(1, sets)
            ),
            restSeconds: max(30, restSeconds)
        )
        session.warmupRestSeconds = min(60, session.restSeconds)
        return session
    }
    
    private func greetingDateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
    
    private func shouldPromptDailyCheckIn() -> Bool {
        guard !streakStore.hasCompletedCheckInToday else { return false }
        guard streakStore.appStreak.currentStreak > 0 else { return false }
        return lastDailyCheckInPromptDate != StreakCalculations.localDateKey()
    }
    
    private func markDailyCheckInPrompted() {
        lastDailyCheckInPromptDate = StreakCalculations.localDateKey()
    }
    
    private func promptDailyCheckInIfNeeded() {
        guard shouldPromptDailyCheckIn() else { return }
        guard !(streakStore.shouldShowSaveStreakMode && !streakStore.hasCompletedCheckInToday) else { return }
        guard !showWeeklyCheckInPrompt else { return }
        markDailyCheckInPrompted()
        showDailyCheckIn = true
    }
    
    private func shouldPromptWeeklyCheckIn() -> Bool {
        guard lastWeeklyCheckInPromptDate != StreakCalculations.localDateKey() else { return false }
        guard hasLoadedHomeData else { return false }
        guard !showDailyCheckIn else { return false }
        return viewModel.isCheckinOverdue || viewModel.daysUntilCheckin == 0
    }
    
    private func markWeeklyCheckInPrompted() {
        lastWeeklyCheckInPromptDate = StreakCalculations.localDateKey()
    }
    
    private func promptWeeklyCheckInIfNeeded() {
        guard shouldPromptWeeklyCheckIn() else { return }
        markWeeklyCheckInPrompted()
        showWeeklyCheckInPrompt = true
    }
    
    private func dateFromKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: key)
    }
}

private struct HomeWorkoutLaunchPlan {
    let title: String
    let templateId: String?
    let source: TodayTrainingSource
    let exercises: [WorkoutExerciseSession]
}

private struct HomeSessionDraft: Identifiable {
    let id = UUID()
    let sessionId: String?
    let title: String
    let exercises: [WorkoutExerciseSession]
}

private struct HomeHeaderView: View {
    let name: String
    let onHelpTap: () -> Void
    let onSettingsTap: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome back, \(name)")
                    .font(FitFont.body(size: 18))
                    .foregroundColor(FitTheme.textSecondary)

                Text("Ready to train?")
                    .font(FitFont.heading(size: 30))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: onHelpTap) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(FitFont.body(size: 18, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(10)
                        .background(FitTheme.cardBackground)
                        .clipShape(Circle())
                }

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
}

private struct DailyCoachGreetingView: View {
    let name: String
    let streakDays: Int
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
        if streakDays > 1 {
            return "🔥 \(streakDays) day streak! Your coach is ready with today's plan."
        }
        return "Your coach is ready with today's plan. Quick check-in and we start."
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

                    Button(action: onDismiss) {
                        Text("Let's go")
                            .font(FitFont.body(size: 17, weight: .semibold))
                            .foregroundColor(FitTheme.buttonText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(FitTheme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
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

// MARK: - Streak Celebration View

private struct StreakCelebrationView: View {
    let streakDays: Int
    let onDismiss: () -> Void
    
    @State private var animateFlame = false
    @State private var animateNumber = false
    @State private var animateRing = false
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            // Celebration card
            VStack(spacing: 24) {
                // Animated flame with rings
                ZStack {
                    // Outer pulsing ring
                    Circle()
                        .stroke(Color.orange.opacity(0.3), lineWidth: 3)
                        .frame(width: 140, height: 140)
                        .scaleEffect(animateRing ? 1.3 : 1.0)
                        .opacity(animateRing ? 0 : 0.6)
                    
                    Circle()
                        .stroke(Color.orange.opacity(0.5), lineWidth: 4)
                        .frame(width: 120, height: 120)
                        .scaleEffect(animateRing ? 1.2 : 1.0)
                        .opacity(animateRing ? 0 : 0.8)
                    
                    // Glow background
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.orange.opacity(0.6), Color.orange.opacity(0)],
                                center: .center,
                                startRadius: 20,
                                endRadius: 70
                            )
                        )
                        .frame(width: 140, height: 140)
                    
                    // Main circle
                    Circle()
                        .fill(FitTheme.streakGradient)
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.orange.opacity(0.5), radius: 20, x: 0, y: 8)
                    
                    // Flame icon
                    Image(systemName: "flame.fill")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(animateFlame ? 1.1 : 1.0)
                }
                
                // Streak number with animation
                VStack(spacing: 8) {
                    Text("\(streakDays)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundColor(FitTheme.textPrimary)
                        .scaleEffect(animateNumber ? 1.0 : 0.5)
                        .opacity(animateNumber ? 1.0 : 0.0)
                    
                    Text("Day Streak! 🎉")
                        .font(FitFont.heading(size: 24))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    Text("You're on fire! Keep showing up.")
                        .font(FitFont.body(size: 16))
                        .foregroundColor(FitTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                // Continue button
                Button(action: onDismiss) {
                    Text("Keep Going!")
                        .font(FitFont.body(size: 17, weight: .semibold))
                        .foregroundColor(FitTheme.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(FitTheme.streakGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 24)
            }
            .padding(32)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.3), radius: 40, x: 0, y: 20)
            .padding(.horizontal, 32)
        }
        .onAppear {
            // Animate flame
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                animateFlame = true
            }
            // Animate number pop
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.2)) {
                animateNumber = true
            }
            // Animate rings
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                animateRing = true
            }
        }
    }
}

private struct TodayTrainingCard: View {
    let title: String
    let subtitle: String
    let exercises: [String]
    let completedExercises: [String]
    let isCompleted: Bool
    let coachPick: CoachPickWorkout?
    let onStartWorkout: () -> Void
    let onSwap: () -> Void
    
    @State private var isExpanded = false
    
    private var isCoachPick: Bool {
        coachPick != nil
    }
    
    private var cardTitle: String {
        if let coachPick = coachPick {
            return coachPick.title
                .replacingOccurrences(of: "Coach's Pick: ", with: "")
                .replacingOccurrences(of: "Coaches Pick: ", with: "")
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Today's Training" : trimmed
    }
    
    private var cardSubtitle: String {
        if isCoachPick {
            return "Coaches Pick"
        }
        let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Today's Training" : trimmed
    }

    private var statusText: String {
        if isCompleted {
            return "Completed"
        }
        return isCoachPick ? "" : cardSubtitle
    }
    
    private var displayList: [String] {
        isCompleted && !completedExercises.isEmpty ? completedExercises : exercises
    }
    
    private var previewList: [String] {
        Array(displayList.prefix(2))
    }

    var body: some View {
        CardContainer(backgroundColor: FitTheme.cardWorkout, accentBorder: FitTheme.cardWorkoutAccent.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: isCoachPick ? "sparkles" : "figure.run")
                                .font(.system(size: 14))
                                .foregroundColor(isCoachPick ? FitTheme.accent : FitTheme.cardWorkoutAccent)
                            Text(cardTitle)
                                .font(FitFont.body(size: 18))
                                .fontWeight(.semibold)
                                .foregroundColor(FitTheme.textPrimary)
                        }
                        
                        HStack(spacing: 8) {
                            if !isCompleted {
                                Text("~45 min")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                                
                                Text("•")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            }

                            if !statusText.isEmpty {
                                Text(statusText)
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(isCompleted ? FitTheme.success : FitTheme.cardWorkoutAccent)
                            }

                            if isCoachPick {
                                CoachPickPill()
                            }
                        }
                    }

                    Spacer()
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                            .padding(8)
                            .background(FitTheme.cardWorkoutAccent.opacity(0.15))
                            .clipShape(Circle())
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    if isExpanded {
                        if let coachPick, !coachPick.exerciseDetails.isEmpty {
                            ForEach(coachPick.exerciseDetails) { exercise in
                                HStack {
                                    Circle()
                                        .fill(FitTheme.cardWorkoutAccent)
                                        .frame(width: 6, height: 6)
                                    
                                    Text(exercise.name)
                                        .font(FitFont.body(size: 14))
                                        .foregroundColor(FitTheme.textPrimary)
                                    
                                    Spacer()
                                    
                                    Text("\(exercise.sets) × \(exercise.reps)")
                                        .font(FitFont.body(size: 13))
                                        .foregroundColor(FitTheme.textSecondary)
                                }
                                .padding(.vertical, 4)
                            }
                        } else {
                            ForEach(displayList, id: \.self) { item in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(FitTheme.cardWorkoutAccent)
                                        .frame(width: 6, height: 6)
                                    Text(item)
                                        .font(FitFont.body(size: 14))
                                        .foregroundColor(FitTheme.textSecondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } else {
                        // Show preview
                        ForEach(previewList, id: \.self) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(FitTheme.cardWorkoutAccent)
                                    .frame(width: 6, height: 6)
                                Text(item)
                                    .font(FitFont.body(size: 14))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                        }
                        
                        if displayList.count > previewList.count {
                            Text("+\(displayList.count - previewList.count) more exercises")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.cardWorkoutAccent)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isExpanded = true
                                    }
                                }
                        }
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

private struct NoTrainingTodayCard: View {
    let nextDetail: (dayName: String, workoutName: String)?

    var body: some View {
        CardContainer(backgroundColor: FitTheme.cardWorkout, accentBorder: FitTheme.cardWorkoutAccent.opacity(0.2)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "zzz")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                    Text("No training today")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                }

                if let nextDetail {
                    Text("Next training: \(nextDetail.dayName) — \(nextDetail.workoutName)")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                } else {
                    Text("Next training scheduled soon.")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
        }
    }
}

private struct CoachPickPill: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text("COACHES PICK")
                .font(FitFont.body(size: 10, weight: .bold))
                .tracking(0.6)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [FitTheme.cardCoachAccent, FitTheme.cardCoachAccent.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: FitTheme.cardCoachAccent.opacity(0.25), radius: 6, x: 0, y: 4)
    }
}

private struct CheckInReminderCard: View {
    let daysUntilCheckin: Int
    let isOverdue: Bool
    let statusText: String
    let checkinDayName: String
    let onCheckinTap: () -> Void
    
    @State private var showLockedSheet = false
    
    /// Check-in is unlocked only on the designated day or if overdue
    private var isUnlocked: Bool {
        isOverdue || daysUntilCheckin == 0
    }
    
    private var accentColor: Color {
        if isOverdue {
            return Color(red: 0.92, green: 0.30, blue: 0.25)  // Urgent red
        }
        if daysUntilCheckin == 0 {
            return FitTheme.cardReminderAccent  // Today - amber
        }
        return FitTheme.cardReminderAccent  // Normal - amber
    }
    
    private var iconName: String {
        if isOverdue {
            return "exclamationmark.triangle.fill"
        }
        if daysUntilCheckin == 0 {
            return "checkmark.circle.fill"
        }
        return "calendar.badge.clock"
    }
    
    private var urgencyBadge: String? {
        if isOverdue {
            return "OVERDUE"
        }
        if daysUntilCheckin == 0 {
            return "TODAY"
        }
        return nil
    }
    
    var body: some View {
        Button(action: {
            if isUnlocked {
                onCheckinTap()
            } else {
                showLockedSheet = true
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // Header with badge
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Weekly Check-in")
                                .font(FitFont.heading(size: 18))
                                .foregroundColor(FitTheme.textPrimary)
                            
                            if let badge = urgencyBadge {
                                Text(badge)
                                    .font(FitFont.body(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Text(statusText)
                            .font(FitFont.body(size: 13))
                            .foregroundColor(isOverdue ? accentColor : FitTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(accentColor)
                }
                
                // Progress indicator - show days until check-in
                if !isOverdue && daysUntilCheckin > 0 {
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { day in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(day < (7 - daysUntilCheckin) ? accentColor : accentColor.opacity(0.2))
                                .frame(height: 4)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FitTheme.cardReminder)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(accentColor.opacity(0.4), lineWidth: isOverdue ? 2 : 1.5)
            )
            .shadow(color: accentColor.opacity(0.2), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLockedSheet) {
            HomeCheckinLockedSheet(checkinDayName: checkinDayName, daysUntilCheckin: daysUntilCheckin)
        }
    }
}

// MARK: - Home Check-In Locked Sheet
private struct HomeCheckinLockedSheet: View {
    let checkinDayName: String
    let daysUntilCheckin: Int
    
    @Environment(\.dismiss) private var dismiss
    @State private var showDayPicker = false
    
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(FitTheme.cardHighlight)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer()
                
                // Lock icon
                ZStack {
                    Circle()
                        .fill(FitTheme.cardReminderAccent.opacity(0.15))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(FitTheme.cardReminderAccent)
                }
                
                // Title
                Text("Check-In Locked")
                    .font(FitFont.heading(size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(FitTheme.textPrimary)
                
                // Message
                VStack(spacing: 8) {
                    Text("Your weekly check-in is available on")
                        .font(FitFont.body(size: 16))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Text(checkinDayName)
                        .font(FitFont.heading(size: 24))
                        .foregroundColor(FitTheme.cardReminderAccent)
                    
                    if daysUntilCheckin == 1 {
                        Text("That's tomorrow!")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                    } else {
                        Text("That's in \(daysUntilCheckin) days")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Change day button
                VStack(spacing: 12) {
                    Text("Want to check in on a different day?")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Button(action: {
                        showDayPicker = true
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Change Check-In Day")
                                .font(FitFont.body(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [FitTheme.cardReminderAccent, FitTheme.cardReminderAccent.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: FitTheme.cardReminderAccent.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showDayPicker) {
            HomeCheckinDayPickerSheet(onDismissParent: { dismiss() })
        }
    }
}

// MARK: - Home Check-In Day Picker Sheet
private struct HomeCheckinDayPickerSheet: View {
    let onDismissParent: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("checkinDay") private var checkinDay: Int = 0
    @State private var selectedDay: Int = 0
    @State private var isSaving = false
    
    private let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(FitTheme.cardHighlight)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("Check-In Day")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    Spacer()
                    
                    Color.clear
                        .frame(width: 32, height: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Hero
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(FitTheme.cardReminderAccent.opacity(0.15))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(FitTheme.cardReminderAccent)
                    }
                    
                    Text("Choose Your Check-In Day")
                        .font(FitFont.heading(size: 22))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    Text("Pick the day that works best for your schedule")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
                
                // Day picker
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { index in
                            Button(action: {
                                selectedDay = index
                                Haptics.light()
                            }) {
                                HStack {
                                    Text(days[index])
                                        .font(FitFont.body(size: 16, weight: selectedDay == index ? .semibold : .regular))
                                        .foregroundColor(selectedDay == index ? .white : FitTheme.textPrimary)
                                    
                                    Spacer()
                                    
                                    if selectedDay == index {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .background(selectedDay == index ? FitTheme.cardReminderAccent : FitTheme.cardHighlight)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                // Save button
                Button(action: saveDay) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Save Changes")
                            .font(FitFont.body(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [FitTheme.cardReminderAccent, FitTheme.cardReminderAccent.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: FitTheme.cardReminderAccent.opacity(0.4), radius: 12, x: 0, y: 6)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            selectedDay = checkinDay
        }
    }
    
    private func saveDay() {
        isSaving = true
        checkinDay = selectedDay
        Haptics.success()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
            onDismissParent()
        }
    }
}

private struct CoachQuickCard: View {
    let onOpen: () -> Void

    var body: some View {
        CardContainer(backgroundColor: FitTheme.cardCoach, accentBorder: FitTheme.cardCoachAccent.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundColor(FitTheme.cardCoachAccent)
                        Text("AI Coach")
                            .font(FitFont.body(size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.textPrimary)
                    }

                    Spacer()

                    Image(systemName: "message.fill")
                        .foregroundColor(FitTheme.cardCoachAccent)
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
    let name: String
    let goal: String
    let height: String
    let gender: String
    let weight: Double?
    let age: Int?
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private let profileColor = Color(red: 0.2, green: 0.6, blue: 0.7)
    private let profileColorLight = Color(red: 0.85, green: 0.95, blue: 0.97)

    private var profileBackground: Color {
        colorScheme == .dark ? FitTheme.cardBackground : profileColorLight
    }

    private var profileStroke: Color {
        profileColor.opacity(colorScheme == .dark ? 0.4 : 0.3)
    }

    private var profileShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : profileColor.opacity(0.15)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    // Avatar circle with initial
                    ZStack {
                        Circle()
                            .fill(profileColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Text(String(name.prefix(1)).uppercased())
                            .font(FitFont.heading(size: 18))
                            .foregroundColor(profileColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(FitFont.heading(size: 18))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Profile Snapshot")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(profileColor)
                }

                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    ProfileStatChip(title: "Goal", value: goal, icon: "target", color: profileColor)
                    ProfileStatChip(title: "Height", value: height, icon: "ruler", color: profileColor)
                    ProfileStatChip(title: "Gender", value: gender, icon: "person", color: profileColor)
                    if let weight = weight {
                        ProfileStatChip(title: "Weight", value: "\(Int(weight)) lbs", icon: "scalemass", color: profileColor)
                    }
                    if let age = age {
                        ProfileStatChip(title: "Age", value: "\(age)", icon: "calendar", color: profileColor)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(profileBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(profileStroke, lineWidth: 1.5)
            )
            .shadow(color: profileShadow, radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileStatChip: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = FitTheme.cardProgressAccent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(title)
                    .font(FitFont.body(size: 10))
                    .foregroundColor(FitTheme.textSecondary)
            }
            Text(value)
                .font(FitFont.body(size: 13, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        let calorieDelta = caloriesTarget - caloriesUsed
        let isOverCalories = calorieDelta < 0
        let calorieAmount = abs(calorieDelta)

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
                    Text("\(calorieAmount)")
                        .font(FitFont.heading(size: 34))
                        .fontWeight(.bold)
                        .foregroundColor(FitTheme.textPrimary)

                    Text(isOverCalories ? "cal over" : "cal left")
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
        CardContainer(
            backgroundColor: FitTheme.cardProgress,
            accentBorder: FitTheme.cardProgressAccent.opacity(0.3)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Encouraging header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Progress")
                            .font(FitFont.body(size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.textPrimary)
                        
                        Text("You're making great strides! 💪")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.cardProgressAccent)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(FitTheme.cardProgressAccent)
                        .padding(12)
                        .background(FitTheme.cardProgressAccent.opacity(0.15))
                        .clipShape(Circle())
                }

                // Stats row
                HStack(spacing: 20) {
                    // Weight stat
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "scalemass.fill")
                                .font(.system(size: 12))
                                .foregroundColor(FitTheme.cardProgressAccent)
                            Text("Current Weight")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        
                        Text(weightText)
                            .font(FitFont.heading(size: 28))
                            .fontWeight(.bold)
                            .foregroundColor(FitTheme.textPrimary)
                    }
                    
                    Spacer()
                    
                    // Mini trend
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Trend")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                        MiniTrendView()
                    }
                }

                // PR highlight
                if !lastPr.isEmpty && lastPr != "—" {
                    HStack(spacing: 12) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.yellow)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Latest PR")
                                .font(FitFont.body(size: 11))
                                .foregroundColor(FitTheme.textSecondary)
                            Text(lastPr)
                                .font(FitFont.body(size: 15, weight: .semibold))
                                .foregroundColor(FitTheme.textPrimary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    .padding(12)
                    .background(FitTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
    let nutritionStreak: Int
    let workoutStreak: Int
    let onTap: () -> Void
    
    @State private var isAnimating = false
    
    // Electric gold gradient for the streak icon
    private let streakGold = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.84, blue: 0.0),  // Bright gold
            Color(red: 1.0, green: 0.65, blue: 0.0)   // Deep gold/amber
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Animated flame icon with new color
                ZStack {
                    // Glow effect - gold
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 28
                            )
                        )
                        .frame(width: 56, height: 56)
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                    
                    // Flame background circle - gold
                    Circle()
                        .fill(streakGold)
                        .frame(width: 44, height: 44)
                        .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: "flame.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(isAnimating ? 1.05 : 1.0)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(days)")
                        .font(FitFont.heading(size: 28))
                        .foregroundColor(FitTheme.textPrimary)
                        .contentTransition(.numericText())
                    
                    Text(days == 1 ? "day streak" : "day streak")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                Spacer()
                
                // Mini streak indicators
                HStack(spacing: 8) {
                    MiniStreakIndicator(icon: "fork.knife", count: nutritionStreak, color: FitTheme.cardNutritionAccent)
                    MiniStreakIndicator(icon: "dumbbell.fill", count: workoutStreak, color: FitTheme.cardWorkoutAccent)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                LinearGradient(
                    colors: [
                        FitTheme.cardStreak,
                        FitTheme.cardHighlight
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(FitTheme.cardStreakAccent.opacity(0.35), lineWidth: 1.5)
            )
            .shadow(color: FitTheme.cardStreakAccent.opacity(0.2), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Daily Check-In Card

private struct DailyCheckInCard: View {
    let currentStreak: Int
    let timeRemaining: TimeInterval
    let onCheckIn: () -> Void
    
    private var urgency: UrgencyLevel {
        StreakCalculations.urgencyLevel(seconds: timeRemaining)
    }
    
    var body: some View {
        Button(action: onCheckIn) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.red.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Daily Check-In")
                                .font(FitFont.heading(size: 18))
                                .foregroundColor(FitTheme.textPrimary)
                            
                            if currentStreak > 0 {
                                Text("🔥 \(currentStreak)")
                                    .font(FitFont.body(size: 12, weight: .bold))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Text("Save your streak in 10 seconds")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                }
                
                // Time remaining indicator
                if currentStreak > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(urgency.color)
                        
                        Text(StreakCalculations.formatCountdown(timeRemaining))
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(urgency.color)
                        
                        Text("to save your streak")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(urgency.color.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        FitTheme.cardReminder.opacity(0.92),
                        FitTheme.cardBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(FitTheme.cardReminderAccent.opacity(0.35), lineWidth: 1.5)
            )
            .shadow(color: FitTheme.cardReminderAccent.opacity(0.15), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Enhanced Streak Badge

private struct EnhancedStreakBadge: View {
    @ObservedObject var streakStore = StreakStore.shared
    let onTap: () -> Void
    
    @State private var isAnimating = false
    
    // Only count streaks as "at risk" if they have less than 6 hours (21600 seconds) remaining
    private let sixHoursInSeconds: TimeInterval = 21600
    
    private var atRiskCount: Int {
        var count = 0
        if case .atRisk(let t) = streakStore.appStreakStatus, t < sixHoursInSeconds { count += 1 }
        if case .atRisk(let t) = streakStore.nutritionStreakStatus, t < sixHoursInSeconds { count += 1 }
        if case .atRisk(let t) = streakStore.weeklyWinStatus, t < sixHoursInSeconds { count += 1 }
        return count
    }
    
    private var mostUrgentCountdown: TimeInterval? {
        var times: [TimeInterval] = []
        // Only include times that are less than 6 hours
        if case .atRisk(let t) = streakStore.appStreakStatus, t < sixHoursInSeconds { times.append(t) }
        if case .atRisk(let t) = streakStore.nutritionStreakStatus, t < sixHoursInSeconds { times.append(t) }
        if case .atRisk(let t) = streakStore.weeklyWinStatus, t < sixHoursInSeconds { times.append(t) }
        return times.min()
    }
    
    private let streakGold = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.84, blue: 0.0),
            Color(red: 1.0, green: 0.65, blue: 0.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Main streak display
                HStack(spacing: 12) {
                    // Flame icon
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5), Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 28
                                )
                            )
                            .frame(width: 56, height: 56)
                            .scaleEffect(isAnimating ? 1.1 : 1.0)
                        
                        Circle()
                            .fill(streakGold)
                            .frame(width: 44, height: 44)
                            .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5), radius: 8, x: 0, y: 4)
                        
                        Image(systemName: "flame.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(isAnimating ? 1.05 : 1.0)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(streakStore.appStreak.currentStreak)")
                            .font(FitFont.heading(size: 28))
                            .foregroundColor(FitTheme.textPrimary)
                            .contentTransition(.numericText())
                        
                        Text("day streak")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Mini streak indicators
                    HStack(spacing: 8) {
                        MiniStreakIndicator(
                            icon: "fork.knife",
                            count: streakStore.nutritionStreak.currentStreak,
                            color: FitTheme.cardNutritionAccent,
                            isAtRisk: streakStore.nutritionStreakStatus.isAtRisk
                        )
                        WeeklyWinMiniIndicator(
                            workoutsThisWeek: streakStore.workoutsThisWeek,
                            weeklyGoal: streakStore.weeklyWin.weeklyGoal,
                            winCount: streakStore.weeklyWin.weeklyWinCount
                        )
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                // Countdown warning if at risk - only shows when less than 6 hours remaining (filtered in atRiskCount)
                if atRiskCount > 0, let countdown = mostUrgentCountdown {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                        
                        if atRiskCount > 1 {
                            Text("\(atRiskCount) streaks at risk • \(StreakCalculations.formatCountdown(countdown))")
                        } else {
                            Text("\(StreakCalculations.formatCountdown(countdown)) to save your streak")
                        }
                    }
                    .font(FitFont.body(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                LinearGradient(
                    colors: atRiskCount > 0
                        ? [Color.red.opacity(0.12), FitTheme.cardStreak]
                        : [FitTheme.cardStreak, FitTheme.cardHighlight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        atRiskCount > 0 ? Color.red.opacity(0.3) : Color.orange.opacity(0.3),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Weekly Win Mini Indicator

private struct WeeklyWinMiniIndicator: View {
    let workoutsThisWeek: Int
    let weeklyGoal: Int
    let winCount: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(FitTheme.cardWorkoutAccent)
            Text("\(workoutsThisWeek)/\(weeklyGoal)")
                .font(FitFont.body(size: 11, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(FitTheme.cardWorkoutAccent.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Mini Streak Indicator (Updated)

private struct MiniStreakIndicator: View {
    let icon: String
    let count: Int
    let color: Color
    var isAtRisk: Bool = false
    var showProgress: Bool = false
    var progress: String = ""
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isAtRisk ? .red : color)
            if showProgress {
                Text(progress)
                    .font(FitFont.body(size: 11, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
            } else {
                Text("\(count)")
                    .font(FitFont.body(size: 11, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isAtRisk ? Color.red : color).opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Streak Detail View (Legacy - replaced by EnhancedStreakDetailView)
struct StreakDetailView: View {
    let appOpenStreak: Int
    let nutritionStreak: Int
    let workoutStreak: Int
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    header
                    
                    // Main streak card
                    mainStreakCard
                    
                    // Individual streaks
                    VStack(spacing: 16) {
                        Text("Your Streaks")
                            .font(FitFont.heading(size: 20))
                            .foregroundColor(FitTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        StreakTypeCard(
                            title: "App Streak",
                            subtitle: "Days opened the app",
                            icon: "flame.fill",
                            count: appOpenStreak,
                            color: Color(red: 1.0, green: 0.84, blue: 0.0),
                            gradient: LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.65, blue: 0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        
                        StreakTypeCard(
                            title: "Nutrition Streak",
                            subtitle: "Days logged food",
                            icon: "fork.knife",
                            count: nutritionStreak,
                            color: FitTheme.cardNutritionAccent,
                            gradient: LinearGradient(
                                colors: [FitTheme.cardNutritionAccent, FitTheme.cardNutritionAccent.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        
                        StreakTypeCard(
                            title: "Workout Streak",
                            subtitle: "Days completed workouts",
                            icon: "dumbbell.fill",
                            count: workoutStreak,
                            color: FitTheme.cardWorkoutAccent,
                            gradient: LinearGradient(
                                colors: [FitTheme.cardWorkoutAccent, FitTheme.cardWorkoutAccent.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    
                    // Tips section
                    tipsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Streaks")
                    .font(FitFont.heading(size: 28))
                    .foregroundColor(FitTheme.textPrimary)
                Text("Keep the momentum going!")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardHighlight)
                    .clipShape(Circle())
            }
        }
    }
    
    private var mainStreakCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.65, blue: 0.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5), radius: 12, x: 0, y: 6)
                
                Image(systemName: "flame.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 4) {
                Text("\(appOpenStreak)")
                    .font(FitFont.heading(size: 48))
                    .foregroundColor(FitTheme.textPrimary)
                Text("Total Streak Days")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            LinearGradient(
                colors: [
                    FitTheme.cardStreak,
                    FitTheme.cardHighlight
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardStreakAccent.opacity(0.35), lineWidth: 1.5)
        )
    }
    
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips to Keep Streaks")
                .font(FitFont.heading(size: 18))
                .foregroundColor(FitTheme.textPrimary)
            
            VStack(spacing: 10) {
                StreakTipRow(icon: "bell.badge.fill", text: "Enable notifications for daily reminders")
                StreakTipRow(icon: "clock.fill", text: "Set a consistent time to log meals")
                StreakTipRow(icon: "calendar.badge.plus", text: "Plan workouts at the start of each week")
            }
        }
        .padding(18)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct StreakTypeCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let count: Int
    let color: Color
    let gradient: LinearGradient
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(gradient)
                    .frame(width: 50, height: 50)
                    .shadow(color: color.opacity(0.3), radius: 6, x: 0, y: 3)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                Text(subtitle)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(count)")
                    .font(FitFont.heading(size: 24))
                    .foregroundColor(color)
                Text("days")
                    .font(FitFont.body(size: 11))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .padding(16)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
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
    var accentColor: Color? = nil

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
        .background(accentColor?.opacity(0.1) ?? FitTheme.cardHighlight)
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
        let delta = progress.target - progress.current
        let amount = abs(delta)
        let label = delta < 0 ? "over" : "left"

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.name)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)

                Spacer()

                Text("\(amount) g \(label)")
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(style == .secondary ? FitTheme.cardStroke : Color.clear, lineWidth: 1)
                )
                .shadow(color: style == .primary ? FitTheme.buttonShadow : .clear, radius: 12, x: 0, y: 6)
        }
    }
}

private struct CardContainer<Content: View>: View {
    var backgroundColor: Color
    var accentBorder: Color?
    @ViewBuilder let content: Content
    
    init(
        backgroundColor: Color = FitTheme.cardBackground,
        accentBorder: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.backgroundColor = backgroundColor
        self.accentBorder = accentBorder
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(accentBorder ?? FitTheme.cardStroke.opacity(0.6), lineWidth: accentBorder != nil ? 2 : 1)
            )
            .shadow(color: FitTheme.shadow, radius: 18, x: 0, y: 10)
    }
}

@MainActor
/// Represents a coach-generated workout ready to start
struct CoachPickWorkout: Identifiable {
    let id: String
    let title: String
    let exercises: [String]
    let exerciseDetails: [CoachPickExerciseDetail]
    let exerciseCount: Int
    let createdAt: Date?

    var isCreatedToday: Bool {
        guard let createdAt else { return false }
        return Calendar.current.isDateInToday(createdAt)
    }
}

struct CoachPickExerciseDetail: Identifiable {
    let id = UUID()
    let name: String
    let sets: Int
    let reps: String
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
    @Published var age: Int?
    @Published var lastPr = "—"
    @Published var streakDays = 0
    @Published var lastCheckinDate: Date?
    @Published var preferredCheckinDay: Int = 1  // 1 = Sunday, 2 = Monday, etc.
    @Published var coachPickWorkout: CoachPickWorkout?

    private let userId: String
    private let localStore = NutritionLocalStore.shared

    init(userId: String) {
        self.userId = userId
        // Sync with AppStorage on init
        syncCheckinDayFromAppStorage()
    }
    
    /// Sync preferredCheckinDay with AppStorage("checkinDay")
    /// AppStorage uses 0-6 (0 = Sunday), preferredCheckinDay uses 1-7 (1 = Sunday)
    func syncCheckinDayFromAppStorage() {
        let appStorageDay = UserDefaults.standard.integer(forKey: "checkinDay")  // 0-6
        preferredCheckinDay = appStorageDay + 1  // Convert to 1-7
    }
    
    /// Calculate days until next check-in based on preferred day (or days overdue if missed)
    var daysUntilCheckin: Int {
        // Re-sync with AppStorage each time this is called to pick up changes
        let appStorageDay = UserDefaults.standard.integer(forKey: "checkinDay")
        let currentPreferredDay = appStorageDay + 1  // Convert 0-6 to 1-7
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentWeekday = calendar.component(.weekday, from: today)  // 1 = Sunday, 7 = Saturday
        
        // Calculate days until the preferred check-in day
        var daysUntilPreferredDay = currentPreferredDay - currentWeekday
        if daysUntilPreferredDay < 0 {
            daysUntilPreferredDay += 7
        }
        
        // If today is the check-in day
        if daysUntilPreferredDay == 0 {
            // If we have a last check-in and it was today, next check-in is in 7 days
            if let lastCheckin = lastCheckinDate {
                let isToday = calendar.isDateInToday(lastCheckin)
                if isToday {
                    return 7
                }
                // If last check-in was more than 7 days ago, they're overdue
                let daysSinceCheckin = calendar.dateComponents([.day], from: lastCheckin, to: today).day ?? 0
                if daysSinceCheckin > 7 {
                    return -(daysSinceCheckin - 7)  // Negative means overdue
                }
            }
            return 0  // Check-in day is today
        }
        
        // If we have a last check-in, check if they're overdue
        if let lastCheckin = lastCheckinDate {
            let daysSinceCheckin = calendar.dateComponents([.day], from: lastCheckin, to: today).day ?? 0
            if daysSinceCheckin > 7 {
                return -(daysSinceCheckin - 7)  // Negative = overdue
            }
        }
        
        return daysUntilPreferredDay
    }
    
    var isCheckinOverdue: Bool {
        daysUntilCheckin < 0
    }
    
    var checkinStatusText: String {
        if isCheckinOverdue {
            return "You missed your check-in! Check in ASAP"
        }
        if daysUntilCheckin == 0 {
            return "Check-in day is today!"
        }
        if daysUntilCheckin == 1 {
            return "Check-in tomorrow"
        }
        return "Check-in in \(daysUntilCheckin) days"
    }
    
    /// Returns the name of the preferred check-in day (e.g., "Sunday", "Monday")
    var checkinDayName: String {
        let weekdaySymbols = Calendar.current.weekdaySymbols  // ["Sunday", "Monday", ...]
        // Read directly from AppStorage to ensure we have latest value
        let appStorageDay = UserDefaults.standard.integer(forKey: "checkinDay")  // 0-6
        guard appStorageDay >= 0, appStorageDay <= 6 else {
            return weekdaySymbols.first ?? "Sunday"
        }
        return weekdaySymbols[appStorageDay]
    }

    func load() async {
        guard !userId.isEmpty else { return }

        let today = Calendar.current.startOfDay(for: Date())

        // Load local targets and today's macros first as immediate fallback.
        loadLocalMacroTargets()
        let localSnapshot = localStore.snapshot(userId: userId, date: today)
        if localSnapshot.isPersisted {
            macroTotals = localSnapshot.totals
        }

        async let profileTask: [String: Any]? = try? await ProfileAPIService.shared.fetchProfile(userId: userId)
        async let checkinsTask: [WeeklyCheckin]? = try? await ProgressAPIService.shared.fetchCheckins(userId: userId, limit: 1)
        async let logsTask: [NutritionLogEntry]? = try? await NutritionAPIService.shared.fetchDailyLogs(userId: userId, date: today)

        if let profile = await profileTask {
            updateFromProfile(profile)
        }
        if let checkins = await checkinsTask {
            updateFromCheckins(checkins)
        }
        if let logs = await logsTask {
            let meals = buildMeals(from: logs)
            let totals = buildTotals(from: logs)
            if !localSnapshot.isPersisted {
                macroTotals = totals
                _ = localStore.replaceDay(userId: userId, date: today, meals: meals)
            }
        }
        
        // Load coach-generated workouts separately (non-blocking)
        await loadCoachPickWorkout()
    }
    
    /// Fetch the latest coach-generated workout template (mode = "coach")
    func loadCoachPickWorkout() async {
        guard !userId.isEmpty else { return }
        
        do {
            let templates = try await WorkoutAPIService.shared.fetchTemplates(userId: userId)
            // Find the most recent coach-generated template
            if let coachTemplate = templates.first(where: { $0.mode == "coach" }) {
                // Fetch exercises for the template
                let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: coachTemplate.id)
                let createdAt = TodayTrainingStore.parseDate(coachTemplate.createdAt)
                let exerciseNames = detail.exercises.prefix(3).map { ex in
                    "\(ex.name) · \(ex.sets ?? 3) x \(ex.reps ?? 10)"
                }
                let exerciseDetails = detail.exercises.map { ex in
                    CoachPickExerciseDetail(
                        name: ex.name,
                        sets: ex.sets ?? 3,
                        reps: "\(ex.reps ?? 10)"
                    )
                }

                if let createdAt, Calendar.current.isDateInToday(createdAt) {
                    let existing = TodayTrainingStore.todaysTraining()
                    let shouldSaveCoachSnapshot = existing == nil || existing?.source == .coach
                    if shouldSaveCoachSnapshot {
                        TodayTrainingStore.save(
                            title: coachTemplate.title,
                            exercises: detail.exercises.map { $0.name },
                            source: .coach,
                            templateId: coachTemplate.id,
                            createdAt: createdAt
                        )
                    }
                }
                
                await MainActor.run {
                    coachPickWorkout = CoachPickWorkout(
                        id: coachTemplate.id,
                        title: coachTemplate.title,
                        exercises: Array(exerciseNames),
                        exerciseDetails: exerciseDetails,
                        exerciseCount: detail.exercises.count,
                        createdAt: createdAt
                    )
                }
            } else {
                await MainActor.run {
                    coachPickWorkout = nil
                }
            }
        } catch {
            // Silently fail - coach pick is optional
            await MainActor.run {
                coachPickWorkout = nil
            }
        }
    }
    
    /// Load macro targets from locally saved onboarding form as fallback
    private func loadLocalMacroTargets() {
        guard let data = UserDefaults.standard.data(forKey: "fitai.onboarding.form"),
              let form = try? JSONDecoder().decode(OnboardingForm.self, from: data) else {
            return
        }
        
        let calories = Double(form.macroCalories) ?? 0
        let protein = Double(form.macroProtein) ?? 0
        let carbs = Double(form.macroCarbs) ?? 0
        let fats = Double(form.macroFats) ?? 0
        
        // Only apply if we have valid values and current targets are empty
        if (calories > 0 || protein > 0 || carbs > 0 || fats > 0) && macroTargets == .zero {
            macroTargets = MacroTotals(
                calories: calories,
                protein: protein,
                carbs: carbs,
                fats: fats
            )
        }
        
        // Also load display name from form if not set
        if displayName == "Athlete" && !form.fullName.isEmpty {
            displayName = form.fullName
        }
        
        // Load preferred check-in day if set during onboarding
        // Only update if AppStorage hasn't been set by user
        let hasUserSetCheckinDay = UserDefaults.standard.object(forKey: "checkinDay") != nil
        if !hasUserSetCheckinDay && !form.checkinDay.isEmpty {
            let weekdaySymbols = Calendar.current.weekdaySymbols  // ["Sunday", "Monday", ...]
            if let index = weekdaySymbols.firstIndex(of: form.checkinDay) {
                preferredCheckinDay = index + 1  // weekdaySymbols is 0-indexed, weekday is 1-indexed (1 = Sunday)
                // Sync to AppStorage (index is already 0-6)
                UserDefaults.standard.set(index, forKey: "checkinDay")
            }
        }
        
        // Load weight from onboarding if not set
        if latestWeight == nil, let weightValue = Double(form.weightLbs), weightValue > 0 {
            latestWeight = weightValue
        }
        
        // Load age from onboarding if available
        if age == nil, let ageValue = Int(form.age), ageValue > 0 {
            age = ageValue
        }
        
        // Load height from onboarding
        if heightText == "—" {
            let feet = Double(form.heightFeet) ?? 0
            let inches = Double(form.heightInches) ?? 0
            let totalInches = feet * 12 + inches
            if totalInches > 0 {
                let heightCm = totalInches * 2.54
                heightText = formatHeight(cm: heightCm)
            }
        }
        
        // Load gender from onboarding
        if genderText == "—" {
            genderText = form.sex.title
        }
        
        // Load goal from onboarding
        if goal == "—" {
            goal = form.goal.title
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

        if let prefs = profile["preferences"] as? [String: Any] {
            if let gender = prefs["gender"] as? String, !gender.isEmpty {
                genderText = gender.capitalized
            } else if let sex = prefs["sex"] as? String, !sex.isEmpty {
                genderText = sex.capitalized
            }
        }
        
        // Load age
        if let ageValue = profile["age"] as? Int {
            age = ageValue
        }
        
        // Load weight from profile if available
        if let weightKg = profile["weight_kg"] as? Double, weightKg > 0 {
            latestWeight = weightKg * 2.20462
        } else if let weightKg = profile["weight_kg"] as? Int, weightKg > 0 {
            latestWeight = Double(weightKg) * 2.20462
        } else if let weightKg = profile["weight_kg"] as? NSNumber, weightKg.doubleValue > 0 {
            latestWeight = weightKg.doubleValue * 2.20462
        } else if let weightLbs = profile["weight_lbs"] as? Double, weightLbs > 0 {
            latestWeight = weightLbs
        } else if let weightLbs = profile["weight_lbs"] as? Int, weightLbs > 0 {
            latestWeight = Double(weightLbs)
        }
        
        // Load preferred check-in day (1 = Sunday through 7 = Saturday)
        // Only update from profile if AppStorage hasn't been set by user
        let hasUserSetCheckinDay = UserDefaults.standard.object(forKey: "checkinDay") != nil
        
        if !hasUserSetCheckinDay {
            var checkinValue: Any? = profile["checkin_day"]
            if checkinValue == nil, let prefs = profile["preferences"] as? [String: Any] {
                checkinValue = prefs["checkin_day"]
            }

            if let checkinDay = checkinValue as? Int, checkinDay >= 1, checkinDay <= 7 {
                preferredCheckinDay = checkinDay
                // Sync to AppStorage (convert 1-7 to 0-6)
                UserDefaults.standard.set(checkinDay - 1, forKey: "checkinDay")
            } else if let checkinDayName = checkinValue as? String, !checkinDayName.isEmpty {
                // Also handle case where check-in day is stored as weekday name
                let weekdaySymbols = Calendar.current.weekdaySymbols
                if let index = weekdaySymbols.firstIndex(of: checkinDayName) {
                    preferredCheckinDay = index + 1
                    // Sync to AppStorage (index is already 0-6)
                    UserDefaults.standard.set(index, forKey: "checkinDay")
                }
            }
        }
    }

    private func updateFromCheckins(_ checkins: [WeeklyCheckin]) {
        latestWeight = checkins.first?.weight
        let workoutStreak = WorkoutStreakStore.current()
        streakDays = workoutStreak > 0 ? workoutStreak : max(checkins.count, 0)
        
        // Track last check-in date for reminder feature
        if let latestCheckin = checkins.first, let dateValue = latestCheckin.dateValue {
            lastCheckinDate = dateValue
        }
    }

    private func buildMeals(from logs: [NutritionLogEntry]) -> [MealType: [LoggedFoodItem]] {
        var result: [MealType: [LoggedFoodItem]] = [:]
        for log in logs {
            guard let meal = normalizedMealType(from: log.mealType) else { continue }
            let items = (log.items ?? []).map(makeLoggedItem(from:))
            if result[meal] != nil {
                result[meal, default: []].append(contentsOf: items)
            } else {
                result[meal] = items
            }
        }
        return result
    }

    private func normalizedMealType(from rawValue: String) -> MealType? {
        let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let meal = MealType(rawValue: cleaned) {
            return meal
        }
        if cleaned.hasPrefix("breakfast") { return .breakfast }
        if cleaned.hasPrefix("lunch") { return .lunch }
        if cleaned.hasPrefix("dinner") { return .dinner }
        if cleaned.hasPrefix("snack") { return .snacks }
        return nil
    }

    private func makeLoggedItem(from item: NutritionLogItem) -> LoggedFoodItem {
        let portionValue = item.portionValue ?? 0
        let portionUnit = PortionUnit(rawValue: item.portionUnit ?? "") ?? .grams
        let macros = MacroTotals(
            calories: item.calories ?? 0,
            protein: item.protein ?? 0,
            carbs: item.carbs ?? 0,
            fats: item.fats ?? 0
        )
        let name = item.name ?? (item.raw == nil ? "Logged item" : "Scan result")
        let detail: String
        if let serving = item.serving, !serving.isEmpty {
            detail = serving
        } else if portionValue > 0 {
            detail = "\(formattedPortionValue(portionValue)) \(portionUnit.title)"
        } else {
            detail = "Logged"
        }
        return LoggedFoodItem(
            name: name,
            portionValue: portionValue,
            portionUnit: portionUnit,
            macros: macros,
            detail: detail,
            brandName: item.brand,
            restaurantName: item.restaurant,
            source: item.source
        )
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

    private func formattedPortionValue(_ value: Double, maxFractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
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
    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { trait in
                trait.userInterfaceStyle == .dark ? dark : light
            }
        )
    }

    private static let backgroundStart = adaptiveColor(
        light: UIColor(red: 0.98, green: 0.96, blue: 0.94, alpha: 1.0),
        dark: UIColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1.0)
    )
    private static let backgroundMiddle = adaptiveColor(
        light: UIColor(red: 0.97, green: 0.93, blue: 0.91, alpha: 1.0),
        dark: UIColor(red: 0.03, green: 0.05, blue: 0.08, alpha: 1.0)
    )
    private static let backgroundEnd = adaptiveColor(
        light: UIColor(red: 0.95, green: 0.90, blue: 0.88, alpha: 1.0),
        dark: UIColor(red: 0.01, green: 0.02, blue: 0.04, alpha: 1.0)
    )

    static let backgroundGradient = LinearGradient(
        colors: [backgroundStart, backgroundMiddle, backgroundEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardBackground = adaptiveColor(
        light: UIColor(red: 1.0, green: 0.98, blue: 0.97, alpha: 1.0),
        dark: UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1.0)
    )
    static let cardHighlight = adaptiveColor(
        light: UIColor(red: 0.95, green: 0.92, blue: 0.90, alpha: 1.0),
        dark: UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1.0)
    )
    static let cardStroke = adaptiveColor(
        light: UIColor(red: 0.90, green: 0.86, blue: 0.84, alpha: 1.0),
        dark: UIColor(red: 0.22, green: 0.24, blue: 0.30, alpha: 1.0)
    )
    static let accent = adaptiveColor(
        light: UIColor(red: 0.29, green: 0.18, blue: 1.0, alpha: 1.0),
        dark: UIColor(red: 0.22, green: 0.50, blue: 1.0, alpha: 1.0)
    )
    static let accentSoft = adaptiveColor(
        light: UIColor(red: 0.86, green: 0.82, blue: 1.0, alpha: 1.0),
        dark: UIColor(red: 0.22, green: 0.50, blue: 1.0, alpha: 0.18)
    )
    static let accentMuted = adaptiveColor(
        light: UIColor(red: 0.74, green: 0.69, blue: 0.98, alpha: 1.0),
        dark: UIColor(red: 0.42, green: 0.64, blue: 1.0, alpha: 1.0)
    )
    static let textPrimary = adaptiveColor(
        light: UIColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 1.0),
        dark: UIColor(red: 0.96, green: 0.97, blue: 1.0, alpha: 1.0)
    )
    static let textSecondary = adaptiveColor(
        light: UIColor(red: 0.45, green: 0.40, blue: 0.37, alpha: 1.0),
        dark: UIColor(red: 0.62, green: 0.66, blue: 0.74, alpha: 1.0)
    )
    static let buttonText = Color.white
    static let shadow = adaptiveColor(
        light: UIColor(red: 0.23, green: 0.17, blue: 0.36, alpha: 0.12),
        dark: UIColor.black.withAlphaComponent(0.45)
    )
    static let buttonShadow = adaptiveColor(
        light: UIColor(red: 0.35, green: 0.22, blue: 0.86, alpha: 0.35),
        dark: UIColor(red: 0.22, green: 0.50, blue: 1.0, alpha: 0.34)
    )
    static let success = adaptiveColor(
        light: UIColor(red: 0.16, green: 0.66, blue: 0.38, alpha: 1.0),
        dark: UIColor(red: 0.19, green: 0.82, blue: 0.51, alpha: 1.0)
    )

    static let textOnAccent = Color.white

    static let primaryGradient = LinearGradient(
        colors: [
            adaptiveColor(
                light: UIColor(red: 0.32, green: 0.20, blue: 1.0, alpha: 1.0),
                dark: UIColor(red: 0.18, green: 0.49, blue: 0.98, alpha: 1.0)
            ),
            adaptiveColor(
                light: UIColor(red: 0.45, green: 0.27, blue: 0.98, alpha: 1.0),
                dark: UIColor(red: 0.26, green: 0.56, blue: 1.0, alpha: 1.0)
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let streakGradient = LinearGradient(
        colors: [
            adaptiveColor(
                light: UIColor(red: 0.30, green: 0.20, blue: 1.0, alpha: 1.0),
                dark: UIColor(red: 0.14, green: 0.34, blue: 0.78, alpha: 1.0)
            ),
            adaptiveColor(
                light: UIColor(red: 0.46, green: 0.28, blue: 0.98, alpha: 1.0),
                dark: UIColor(red: 0.24, green: 0.51, blue: 1.0, alpha: 1.0)
            )
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let proteinColor = adaptiveColor(
        light: UIColor(red: 0.98, green: 0.64, blue: 0.17, alpha: 1.0),
        dark: UIColor(red: 0.95, green: 0.65, blue: 0.27, alpha: 1.0)
    )
    static let carbColor = adaptiveColor(
        light: UIColor(red: 0.98, green: 0.43, blue: 0.55, alpha: 1.0),
        dark: UIColor(red: 0.95, green: 0.34, blue: 0.46, alpha: 1.0)
    )
    static let fatColor = adaptiveColor(
        light: UIColor(red: 0.56, green: 0.33, blue: 0.94, alpha: 1.0),
        dark: UIColor(red: 0.54, green: 0.38, blue: 0.96, alpha: 1.0)
    )

    static func macroColor(for title: String) -> Color {
        let lower = title.lowercased()
        if lower.contains("protein") { return proteinColor }
        if lower.contains("carb") { return carbColor }
        if lower.contains("fat") { return fatColor }
        return accent
    }
    
    // MARK: - Card Surfaces

    static let cardNutrition = adaptiveColor(
        light: UIColor(red: 1.0, green: 0.96, blue: 0.94, alpha: 1.0),
        dark: UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1.0)
    )
    static let cardNutritionAccent = adaptiveColor(
        light: UIColor(red: 0.98, green: 0.55, blue: 0.48, alpha: 1.0),
        dark: UIColor(red: 0.22, green: 0.50, blue: 1.0, alpha: 1.0)
    )

    static let cardWorkout = adaptiveColor(
        light: UIColor(red: 0.94, green: 0.96, blue: 1.0, alpha: 1.0),
        dark: UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)
    )
    static let cardWorkoutAccent = adaptiveColor(
        light: UIColor(red: 0.35, green: 0.48, blue: 0.95, alpha: 1.0),
        dark: UIColor(red: 0.24, green: 0.53, blue: 1.0, alpha: 1.0)
    )

    static let cardProgress = adaptiveColor(
        light: UIColor(red: 0.94, green: 0.99, blue: 0.97, alpha: 1.0),
        dark: UIColor(red: 0.07, green: 0.10, blue: 0.13, alpha: 1.0)
    )
    static let cardProgressAccent = adaptiveColor(
        light: UIColor(red: 0.22, green: 0.72, blue: 0.58, alpha: 1.0),
        dark: UIColor(red: 0.22, green: 0.74, blue: 0.63, alpha: 1.0)
    )

    static let cardCoach = adaptiveColor(
        light: UIColor(red: 0.97, green: 0.95, blue: 1.0, alpha: 1.0),
        dark: UIColor(red: 0.09, green: 0.07, blue: 0.13, alpha: 1.0)
    )
    static let cardCoachAccent = adaptiveColor(
        light: UIColor(red: 0.58, green: 0.42, blue: 0.92, alpha: 1.0),
        dark: UIColor(red: 0.58, green: 0.41, blue: 0.95, alpha: 1.0)
    )

    static let cardReminder = adaptiveColor(
        light: UIColor(red: 1.0, green: 0.98, blue: 0.92, alpha: 1.0),
        dark: UIColor(red: 0.10, green: 0.09, blue: 0.07, alpha: 1.0)
    )
    static let cardReminderAccent = adaptiveColor(
        light: UIColor(red: 0.95, green: 0.68, blue: 0.25, alpha: 1.0),
        dark: UIColor(red: 0.92, green: 0.67, blue: 0.26, alpha: 1.0)
    )

    static let cardStreak = adaptiveColor(
        light: UIColor(red: 0.95, green: 0.94, blue: 1.0, alpha: 1.0),
        dark: UIColor(red: 0.09, green: 0.09, blue: 0.12, alpha: 1.0)
    )
    static let cardStreakAccent = adaptiveColor(
        light: UIColor(red: 0.45, green: 0.32, blue: 0.95, alpha: 1.0),
        dark: UIColor(red: 0.24, green: 0.53, blue: 1.0, alpha: 1.0)
    )
}

// MARK: - Profile Edit Sheet

private struct ProfileEditSheet: View {
    let userId: String
    let name: String
    let goal: String
    let height: String
    let gender: String
    let weight: Double?
    let age: Int?
    let onSave: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var editedName: String = ""
    @State private var editedGoal: String = ""
    @State private var editedHeightFeet: Int = 5
    @State private var editedHeightInches: Int = 10
    @State private var editedGender: String = ""
    @State private var editedWeight: String = ""
    @State private var editedAge: String = ""
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    private let goalOptions = ["Lose weight", "Maintain", "Gain weight"]
    private let genderOptions = ["Male", "Female", "Other"]
    
    var body: some View {
        NavigationView {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissKeyboard()
                    }
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(FitTheme.cardProgressAccent.opacity(0.15))
                                .frame(width: 80, height: 80)
                            Text(String(editedName.prefix(1)).uppercased())
                                .font(FitFont.heading(size: 32))
                                .foregroundColor(FitTheme.cardProgressAccent)
                        }
                        .padding(.top, 20)
                        
                        // Form fields
                        VStack(spacing: 16) {
                            ProfileEditField(title: "Name", text: $editedName, placeholder: "Your name")
                            
                            ProfileEditPicker(title: "Goal", selection: $editedGoal, options: goalOptions)
                            
                            ProfileEditPicker(title: "Gender", selection: $editedGender, options: genderOptions)
                            
                            ProfileEditField(title: "Weight (lbs)", text: $editedWeight, placeholder: "175", keyboardType: .numberPad)
                            
                            ProfileEditField(title: "Age", text: $editedAge, placeholder: "25", keyboardType: .numberPad)
                            
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Height (ft)")
                                        .font(FitFont.body(size: 12))
                                        .foregroundColor(FitTheme.textSecondary)
                                    Picker("Feet", selection: $editedHeightFeet) {
                                        ForEach(4...7, id: \.self) { ft in
                                            Text("\(ft)'").tag(ft)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                .frame(maxWidth: .infinity)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Height (in)")
                                        .font(FitFont.body(size: 12))
                                        .foregroundColor(FitTheme.textSecondary)
                                    Picker("Inches", selection: $editedHeightInches) {
                                        ForEach(0...11, id: \.self) { inch in
                                            Text("\(inch)\"").tag(inch)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(height: 100)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(16)
                            .background(FitTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal, 20)
                        
                        // Save button
                        Button(action: saveProfile) {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Save Changes")
                                    .font(FitFont.body(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundColor(FitTheme.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(FitTheme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                        .disabled(isSaving)
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(FitTheme.accent)
                }
            }
        }
        .onAppear {
            editedName = name
            // Map API goal to display value
            let goalMapped: String
            switch goal.lowercased().replacingOccurrences(of: "_", with: " ") {
            case "lose weight":
                goalMapped = "Lose weight"
            case "lose weight fast", "lose weight faster":
                goalMapped = "Lose weight"
            case "gain weight":
                goalMapped = "Gain weight"
            default:
                goalMapped = "Maintain"
            }
            editedGoal = goalMapped
            editedGender = gender.capitalized
            if let weight = weight {
                editedWeight = "\(Int(weight))"
            }
            if let age = age {
                editedAge = "\(age)"
            }
            parseHeight()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onTapGesture {
            dismissKeyboard()
        }
    }
    
    private func parseHeight() {
        // Parse height string like "5'10\""
        let cleaned = height.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: " ")
        let parts = cleaned.split(separator: " ")
        if parts.count >= 1, let feet = Int(parts[0]) {
            editedHeightFeet = feet
        }
        if parts.count >= 2, let inches = Int(parts[1]) {
            editedHeightInches = inches
        }
    }
    
    private func saveProfile() {
        dismissKeyboard()
        isSaving = true
        
        let heightCm = Double(editedHeightFeet * 12 + editedHeightInches) * 2.54
        let weightLbs = Double(editedWeight) ?? 0
        let ageValue = Int(editedAge) ?? 0
        
        // Map goal display text to API value
        let goalValue: String
        switch editedGoal.lowercased() {
        case "lose weight":
            goalValue = "lose_weight"
        case "gain weight", "build muscle":
            goalValue = "gain_weight"
        default:
            goalValue = "maintain"
        }
        
        Task {
            do {
                let updates: [String: Any] = [
                    "full_name": editedName,
                    "goal": goalValue,
                    "height_cm": heightCm,
                    "weight_lbs": weightLbs,
                    "age": ageValue,
                    "sex": editedGender.lowercased()
                ]
                
                _ = try await ProfileAPIService.shared.updateProfile(userId: userId, payload: updates)
                
                await MainActor.run {
                    isSaving = false
                    Haptics.success()
                    onSave()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save profile. Please try again."
                    showError = true
                    Haptics.error()
                }
            }
        }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct ProfileEditField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
            
            TextField(placeholder, text: $text)
                .font(FitFont.body(size: 16))
                .foregroundColor(FitTheme.textPrimary)
                .padding(14)
                .background(FitTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .keyboardType(keyboardType)
        }
    }
}

private struct ProfileEditPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
            
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button(action: { selection = option }) {
                        Text(option)
                            .font(FitFont.body(size: 13, weight: selection == option ? .semibold : .regular))
                            .foregroundColor(selection == option ? FitTheme.buttonText : FitTheme.textPrimary)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(selection == option ? FitTheme.cardProgressAccent : FitTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    HomeView(
        userId: "demo-user",
        selectedTab: .constant(.home),
        workoutIntent: .constant(nil),
        nutritionIntent: .constant(nil),
        progressIntent: .constant(nil)
    )
    .environmentObject(GuidedTourCoordinator())
}
