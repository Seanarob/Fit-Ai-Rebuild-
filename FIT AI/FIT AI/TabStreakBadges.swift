import SwiftUI
import Combine

// MARK: - Workout Tab Streak Badge

struct WorkoutStreakBadge: View {
    var goalOverride: Int? = nil
    var goalLabel: String = "workout"
    @ObservedObject var streakStore = StreakStore.shared
    @State private var showDetail = false
    @State private var isAnimating = false
    
    private var workoutsThisWeek: Int { streakStore.workoutsThisWeek }
    private var weeklyGoal: Int { max(goalOverride ?? streakStore.weeklyWin.weeklyGoal, 1) }
    private var isGoalMet: Bool { workoutsThisWeek >= weeklyGoal }
    
    // Vibrant streak gradient for standout appearance
    private var streakBackground: LinearGradient {
        if isGoalMet {
            return LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.68, blue: 0.38).opacity(0.15),
                    Color(red: 0.10, green: 0.55, blue: 0.30).opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.32, green: 0.22, blue: 0.95).opacity(0.12),
                    Color(red: 0.45, green: 0.32, blue: 0.98).opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var accentColor: Color {
        isGoalMet ? Color(red: 0.15, green: 0.68, blue: 0.38) : FitTheme.cardStreakAccent
    }

    private func pluralizedGoalLabel(for count: Int) -> String {
        count == 1 ? goalLabel : "\(goalLabel)s"
    }
    
    var body: some View {
        Button(action: { showDetail = true }) {
            HStack(spacing: 14) {
                // Trophy icon with progress ring
                ZStack {
                    // Outer glow ring
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accentColor.opacity(0.25), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 35
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    // Progress ring background
                    Circle()
                        .stroke(accentColor.opacity(0.2), lineWidth: 5)
                        .frame(width: 50, height: 50)
                    
                    // Progress ring fill
                    Circle()
                        .trim(from: 0, to: min(CGFloat(workoutsThisWeek) / CGFloat(max(weeklyGoal, 1)), 1.0))
                        .stroke(
                            accentColor,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: accentColor.opacity(0.5), radius: 4, x: 0, y: 0)
                    
                    // Center icon
                    Image(systemName: isGoalMet ? "checkmark.circle.fill" : "trophy.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(accentColor)
                        .scaleEffect(isAnimating && isGoalMet ? 1.1 : 1.0)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Weekly Win")
                            .font(FitFont.heading(size: 18))
                            .foregroundColor(FitTheme.textPrimary)
                        
                        if streakStore.weeklyWin.currentWinStreak > 0 {
                            HStack(spacing: 3) {
                                Text("🔥")
                                    .font(.system(size: 12))
                                Text("\(streakStore.weeklyWin.currentWinStreak)")
                                    .font(FitFont.body(size: 12, weight: .bold))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Text("\(workoutsThisWeek) of \(weeklyGoal) \(pluralizedGoalLabel(for: weeklyGoal)) completed")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(isGoalMet ? accentColor : FitTheme.textSecondary)
                        
                        if isGoalMet {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(accentColor)
                        }
                    }
                }
                
                Spacer()
                
                // Win count badge
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(streakStore.weeklyWin.weeklyWinCount)")
                        .font(FitFont.heading(size: 26))
                        .fontWeight(.bold)
                        .foregroundColor(accentColor)
                    Text("wins")
                        .font(FitFont.body(size: 11))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accentColor.opacity(0.6))
            }
            .padding(18)
            .background(
                ZStack {
                    // Base color
                    FitTheme.cardStreak
                    
                    // Gradient overlay for depth
                    streakBackground
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accentColor.opacity(0.5), accentColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: accentColor.opacity(0.25), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .onAppear {
            if isGoalMet {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
        .sheet(isPresented: $showDetail) {
            WorkoutStreakDetailSheet(goalOverride: goalOverride, goalLabel: goalLabel)
        }
    }
}

// MARK: - Workout Streak Detail Sheet

struct WorkoutStreakDetailSheet: View {
    let goalOverride: Int?
    let goalLabel: String
    @ObservedObject var streakStore = StreakStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingGoalPicker = false
    @State private var goalChangeMessage: String?

    init(goalOverride: Int? = nil, goalLabel: String = "workout") {
        self.goalOverride = goalOverride
        self.goalLabel = goalLabel
    }

    private var weeklyGoal: Int {
        max(goalOverride ?? streakStore.weeklyWin.weeklyGoal, 1)
    }

    private func pluralizedGoalLabel(for count: Int) -> String {
        count == 1 ? goalLabel : "\(goalLabel)s"
    }
    
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    header
                    
                    // Main Weekly Win card
                    mainWeeklyWinCard
                    
                    // This week progress
                    thisWeekProgressCard
                    
                    // Stats grid
                    statsGrid
                    
                    // Tips
                    workoutTipsCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showingGoalPicker) {
            WeeklyGoalPickerSheet(
                currentGoal: weeklyGoal,
                onSelect: { newGoal in
                    if let message = streakStore.setWeeklyGoal(newGoal) {
                        goalChangeMessage = message
                    }
                }
            )
        }
        .alert("Goal Updated", isPresented: .constant(goalChangeMessage != nil)) {
            Button("Got it") { goalChangeMessage = nil }
        } message: {
            Text(goalChangeMessage ?? "")
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly Win")
                    .font(FitFont.heading(size: 28))
                    .foregroundColor(FitTheme.textPrimary)
                Text("Hit your weekly workout goal")
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
    
    private var mainWeeklyWinCard: some View {
        VStack(spacing: 20) {
            // Big trophy with progress
            ZStack {
                Circle()
                    .stroke(FitTheme.cardWorkoutAccent.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: min(CGFloat(streakStore.workoutsThisWeek) / CGFloat(max(weeklyGoal, 1)), 1.0))
                    .stroke(
                        streakStore.workoutsThisWeek >= weeklyGoal ? Color.green : FitTheme.cardWorkoutAccent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 32))
                        .foregroundColor(FitTheme.cardWorkoutAccent)
                    
                    Text("\(streakStore.workoutsThisWeek)/\(weeklyGoal)")
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                }
            }
            
            // Win stats
            HStack(spacing: 32) {
                VStack(spacing: 4) {
                    Text("\(streakStore.weeklyWin.weeklyWinCount)")
                        .font(FitFont.heading(size: 32))
                        .foregroundColor(FitTheme.cardWorkoutAccent)
                    Text("Total Wins")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                VStack(spacing: 4) {
                    Text("\(streakStore.weeklyWin.currentWinStreak)")
                        .font(FitFont.heading(size: 32))
                        .foregroundColor(.orange)
                    Text("Win Streak")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                VStack(spacing: 4) {
                    Text("\(streakStore.weeklyWin.longestWinStreak)")
                        .font(FitFont.heading(size: 32))
                        .foregroundColor(.yellow)
                    Text("Best Streak")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(FitTheme.cardWorkout)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(FitTheme.cardWorkoutAccent.opacity(0.2), lineWidth: 1.5)
        )
    }
    
    private var thisWeekProgressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This Week")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
                
                Spacer()
                
                if goalOverride == nil {
                    Button(action: { showingGoalPicker = true }) {
                        HStack(spacing: 4) {
                            Text("Goal: \(weeklyGoal)")
                                .font(FitFont.body(size: 13))
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(FitTheme.accent)
                    }
                } else {
                    Text("Goal: \(weeklyGoal) \(pluralizedGoalLabel(for: weeklyGoal))")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            
            // Visual week progress
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { dayIndex in
                    let isWorkoutDay = dayIndex < streakStore.weeklyWin.workoutsThisWindow.count
                    
                    VStack(spacing: 6) {
                        Circle()
                            .fill(isWorkoutDay ? FitTheme.cardWorkoutAccent : FitTheme.cardHighlight)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: isWorkoutDay ? "checkmark" : "")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        
                        Text(dayLabel(for: dayIndex))
                            .font(FitFont.body(size: 10))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
            }
            
            // Status message
            let remaining = max(weeklyGoal - streakStore.workoutsThisWeek, 0)
            if remaining > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(FitTheme.cardWorkoutAccent)
                    Text("\(remaining) more \(pluralizedGoalLabel(for: remaining)) to hit your weekly goal")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Weekly goal achieved! 🎉")
                        .font(FitFont.body(size: 13, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            
            // Pending goal change
            if goalOverride == nil, let pendingGoal = streakStore.weeklyWin.pendingGoalChange {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.yellow)
                    Text("Goal changing to \(pendingGoal) \(pluralizedGoalLabel(for: pendingGoal)) next week")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                .padding(10)
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(18)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(title: "Total Workouts", value: "\(totalWorkouts)", icon: "figure.run", color: FitTheme.cardWorkoutAccent)
            statCard(title: "Longest Win Streak", value: "\(streakStore.weeklyWin.longestWinStreak) weeks", icon: "star.fill", color: .yellow)
        }
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            
            Text(value)
                .font(FitFont.heading(size: 22))
                .foregroundColor(FitTheme.textPrimary)
            
            Text(title)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var workoutTipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips")
                .font(FitFont.heading(size: 16))
                .foregroundColor(FitTheme.textPrimary)
            
            VStack(spacing: 8) {
                tipRow(icon: "calendar.badge.plus", text: "Schedule workouts at the start of each week")
                tipRow(icon: "bell.badge.fill", text: "Set reminders for your workout days")
                tipRow(icon: "figure.walk", text: "Even a light workout counts toward your goal")
            }
        }
        .padding(16)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    
    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(FitTheme.cardWorkoutAccent)
                .frame(width: 20)
            Text(text)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)
            Spacer()
        }
    }
    
    private func dayLabel(for index: Int) -> String {
        let days = ["M", "T", "W", "T", "F", "S", "S"]
        return days[index]
    }
    
    private var totalWorkouts: Int {
        // Estimate based on wins
        streakStore.weeklyWin.weeklyWinCount * streakStore.weeklyWin.weeklyGoal + streakStore.workoutsThisWeek
    }
}

// MARK: - Weekly Goal Picker Sheet

struct WeeklyGoalPickerSheet: View {
    let currentGoal: Int
    let onSelect: (Int) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGoal: Int
    
    init(currentGoal: Int, onSelect: @escaping (Int) -> Void) {
        self.currentGoal = currentGoal
        self.onSelect = onSelect
        _selectedGoal = State(initialValue: currentGoal)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("How many workouts per week?")
                        .font(FitFont.heading(size: 20))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(.top, 20)
                    
                    // Goal options
                    VStack(spacing: 12) {
                        ForEach(1...7, id: \.self) { goal in
                            GoalOptionRow(
                                goal: goal,
                                isSelected: selectedGoal == goal,
                                onTap: { selectedGoal = goal }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Confirm button
                    Button(action: {
                        onSelect(selectedGoal)
                        dismiss()
                    }) {
                        Text("Set Goal")
                            .font(FitFont.heading(size: 16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(FitTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .disabled(selectedGoal == currentGoal)
                    .opacity(selectedGoal == currentGoal ? 0.5 : 1)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct GoalOptionRow: View {
    let goal: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("\(goal)")
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(isSelected ? .white : FitTheme.textPrimary)
                
                Text(goal == 1 ? "workout" : "workouts")
                    .font(FitFont.body(size: 16))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : FitTheme.textSecondary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                isSelected
                    ? FitTheme.cardWorkoutAccent
                    : FitTheme.cardBackground
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.clear : FitTheme.cardStroke,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Nutrition Tab Streak Badge

struct NutritionStreakBadge: View {
    @ObservedObject var streakStore = StreakStore.shared
    @State private var showDetail = false
    @State private var isAnimating = false
    
    private var isAtRisk: Bool {
        streakStore.nutritionStreakStatus.isAtRisk
    }
    
    private var isSafe: Bool {
        streakStore.nutritionStreakStatus.isSafe && streakStore.hasHitMacrosToday
    }
    
    // Vibrant streak gradient for standout appearance
    private var streakBackground: LinearGradient {
        if isSafe {
            return LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.68, blue: 0.38).opacity(0.15),
                    Color(red: 0.10, green: 0.55, blue: 0.30).opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isAtRisk {
            return LinearGradient(
                colors: [
                    Color.red.opacity(0.12),
                    Color.red.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    FitTheme.cardNutritionAccent.opacity(0.12),
                    FitTheme.cardNutritionAccent.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var accentColor: Color {
        if isSafe {
            return Color(red: 0.15, green: 0.68, blue: 0.38)
        } else if isAtRisk {
            return Color.red
        } else {
            return FitTheme.cardNutritionAccent
        }
    }
    
    var body: some View {
        Button(action: { showDetail = true }) {
            HStack(spacing: 14) {
                // Nutrition icon with glow
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accentColor.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 18,
                                endRadius: 35
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    // Icon background
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(accentColor.opacity(0.3), lineWidth: 2)
                        )
                    
                    Image(systemName: isSafe ? "checkmark.circle.fill" : "fork.knife")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(accentColor)
                        .scaleEffect(isAnimating && isSafe ? 1.1 : 1.0)
                        .shadow(color: accentColor.opacity(0.4), radius: 4, x: 0, y: 0)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Nutrition Streak")
                            .font(FitFont.heading(size: 18))
                            .foregroundColor(FitTheme.textPrimary)
                        
                        if streakStore.nutritionStreak.currentStreak > 0 {
                            HStack(spacing: 3) {
                                Text("🔥")
                                    .font(.system(size: 12))
                                Text("\(streakStore.nutritionStreak.currentStreak)")
                                    .font(FitFont.body(size: 12, weight: .bold))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                        }
                    }
                    
                    if isSafe {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("Macros hit today!")
                                .font(FitFont.body(size: 13, weight: .medium))
                        }
                        .foregroundColor(accentColor)
                    } else if isAtRisk {
                        if case .atRisk(let time) = streakStore.nutritionStreakStatus {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 11))
                                Text(StreakCalculations.formatCountdown(time))
                                    .font(FitFont.body(size: 13, weight: .medium))
                            }
                            .foregroundColor(.red)
                        }
                    } else {
                        Text("Hit macros within ±15% to streak")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                
                Spacer()
                
                // Streak count
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(streakStore.nutritionStreak.currentStreak)")
                        .font(FitFont.heading(size: 26))
                        .fontWeight(.bold)
                        .foregroundColor(accentColor)
                    Text("days")
                        .font(FitFont.body(size: 11))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accentColor.opacity(0.6))
            }
            .padding(18)
            .background(
                ZStack {
                    // Base color
                    FitTheme.cardNutrition
                    
                    // Gradient overlay for depth
                    streakBackground
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accentColor.opacity(0.5), accentColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: accentColor.opacity(0.25), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .onAppear {
            if isSafe {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
        .sheet(isPresented: $showDetail) {
            NutritionStreakDetailSheet()
        }
    }
}

// MARK: - Nutrition Streak Detail Sheet

struct NutritionStreakDetailSheet: View {
    @ObservedObject var streakStore = StreakStore.shared
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
                    
                    // How it works
                    howItWorksCard
                    
                    // Stats
                    statsSection
                    
                    // Tips
                    nutritionTipsCard
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
                Text("Nutrition Streak")
                    .font(FitFont.heading(size: 28))
                    .foregroundColor(FitTheme.textPrimary)
                Text("Hit your macros consistently")
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
        VStack(spacing: 20) {
            // Big nutrition icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [FitTheme.cardNutritionAccent.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(FitTheme.cardNutritionAccent)
                    .frame(width: 80, height: 80)
                    .shadow(color: FitTheme.cardNutritionAccent.opacity(0.4), radius: 12)
                
                Image(systemName: "fork.knife")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Current streak
            VStack(spacing: 4) {
                Text("\(streakStore.nutritionStreak.currentStreak)")
                    .font(FitFont.heading(size: 48))
                    .foregroundColor(FitTheme.textPrimary)
                Text("Day Streak")
                    .font(FitFont.body(size: 16))
                    .foregroundColor(FitTheme.textSecondary)
                
                if let startDate = streakStore.nutritionStreak.streakStartDate {
                    Text("Since \(StreakCalculations.formatDateKeyForDisplay(startDate))")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            
            // Longest streak
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.yellow)
                Text("Longest: \(streakStore.nutritionStreak.longestStreak) days")
                    .font(FitFont.body(size: 14, weight: .medium))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.1))
            .clipShape(Capsule())
            
            // Today's status
            if streakStore.hasHitMacrosToday {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Macros hit today!")
                        .font(FitFont.body(size: 15, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.1))
                .clipShape(Capsule())
            } else if streakStore.nutritionStreak.currentStreak > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Log food to save your streak!")
                        .font(FitFont.body(size: 15, weight: .medium))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(FitTheme.cardNutrition)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(FitTheme.cardNutritionAccent.opacity(0.2), lineWidth: 1.5)
        )
    }
    
    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How It Works")
                .font(FitFont.heading(size: 18))
                .foregroundColor(FitTheme.textPrimary)
            
            VStack(spacing: 12) {
                ruleRow(number: 1, text: "Log all your meals for the day")
                ruleRow(number: 2, text: "Hit each macro within ±15% of target")
                ruleRow(number: 3, text: "Streak increments at end of day")
                ruleRow(number: 4, text: "Miss a day? Streak resets to zero")
            }
        }
        .padding(18)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private func ruleRow(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(FitFont.body(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(FitTheme.cardNutritionAccent)
                .clipShape(Circle())
            
            Text(text)
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
            
            Spacer()
        }
    }
    
    private var statsSection: some View {
        HStack(spacing: 12) {
            statCard(title: "Current", value: "\(streakStore.nutritionStreak.currentStreak)", subtitle: "days", color: FitTheme.cardNutritionAccent)
            statCard(title: "Longest", value: "\(streakStore.nutritionStreak.longestStreak)", subtitle: "days", color: .yellow)
        }
    }
    
    private func statCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
            
            Text(value)
                .font(FitFont.heading(size: 32))
                .foregroundColor(color)
            
            Text(subtitle)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    
    private var nutritionTipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips to Hit Your Macros")
                .font(FitFont.heading(size: 16))
                .foregroundColor(FitTheme.textPrimary)
            
            VStack(spacing: 8) {
                tipRow(icon: "clock.fill", text: "Log meals right after eating")
                tipRow(icon: "scalemass.fill", text: "Use a food scale for accuracy")
                tipRow(icon: "calendar", text: "Plan meals ahead of time")
                tipRow(icon: "fork.knife", text: "Prep protein-rich snacks")
            }
        }
        .padding(16)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    
    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(FitTheme.cardNutritionAccent)
                .frame(width: 20)
            Text(text)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)
            Spacer()
        }
    }
}

// MARK: - Previews

#Preview("Workout Badge") {
    VStack {
        WorkoutStreakBadge()
    }
    .padding()
    .background(FitTheme.backgroundGradient)
}

#Preview("Nutrition Badge") {
    VStack {
        NutritionStreakBadge()
    }
    .padding()
    .background(FitTheme.backgroundGradient)
}
