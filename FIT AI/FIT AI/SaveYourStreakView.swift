import SwiftUI

// MARK: - Save Your Streak View

struct SaveYourStreakView: View {
    let atRiskStreaks: [(StreakType, TimeInterval)]
    let onActionComplete: (StreakType) -> Void
    let onDismiss: () -> Void
    
    @State private var showingCheckIn = false
    @State private var showingQuickLog = false
    @State private var showingQuickWorkout = false
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Dimmed background with urgency gradient
            LinearGradient(
                colors: [
                    Color.red.opacity(0.12),
                    Color.orange.opacity(0.08),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Background pattern
            GeometryReader { geometry in
                ZStack {
                    ForEach(0..<20, id: \.self) { i in
                        Image(systemName: "flame.fill")
                            .font(.system(size: CGFloat.random(in: 20...40)))
                            .foregroundColor(.orange.opacity(0.05))
                            .position(
                                x: CGFloat.random(in: 0...geometry.size.width),
                                y: CGFloat.random(in: 0...geometry.size.height)
                            )
                    }
                }
            }
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Skip button
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(FitTheme.cardBackground.opacity(0.8))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Dramatic header
                VStack(spacing: 16) {
                    // Animated flame
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.orange.opacity(0.4), Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 160, height: 160)
                            .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                        
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: .orange.opacity(0.6), radius: 30)
                        
                        Image(systemName: "flame.fill")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(pulseAnimation ? 1.05 : 1.0)
                    }
                    
                    Text("SAVE YOUR STREAK")
                        .font(FitFont.heading(size: 28))
                        .foregroundColor(FitTheme.textPrimary)
                        .tracking(2)
                    
                    if atRiskStreaks.count > 1 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("\(atRiskStreaks.count) streaks at risk of being lost!")
                                .font(FitFont.body(size: 16))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
                
                // Action buttons for each at-risk streak
                VStack(spacing: 14) {
                    ForEach(atRiskStreaks, id: \.0) { streakType, timeRemaining in
                        SaveStreakActionButton(
                            streakType: streakType,
                            timeRemaining: timeRemaining,
                            currentStreak: currentStreak(for: streakType),
                            onTap: {
                                handleAction(for: streakType)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Skip option (de-emphasized)
                Button(action: onDismiss) {
                    Text("I'll do it later")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textSecondary)
                        .underline()
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .sheet(isPresented: $showingCheckIn) {
            DailyCheckInView(onComplete: {
                onActionComplete(.app)
            })
        }
        .sheet(isPresented: $showingQuickLog) {
            QuickLogMealSheet(onComplete: {
                onActionComplete(.nutrition)
            })
        }
        .sheet(isPresented: $showingQuickWorkout) {
            QuickStartWorkoutSheet(onComplete: {
                onActionComplete(.weeklyWin)
            })
        }
    }
    
    private func currentStreak(for type: StreakType) -> Int {
        switch type {
        case .app: return StreakStore.shared.appStreak.currentStreak
        case .nutrition: return StreakStore.shared.nutritionStreak.currentStreak
        case .weeklyWin: return StreakStore.shared.weeklyWin.currentWinStreak
        }
    }
    
    private func handleAction(for streakType: StreakType) {
        Haptics.selection()
        switch streakType {
        case .app:
            showingCheckIn = true
        case .nutrition:
            showingQuickLog = true
        case .weeklyWin:
            showingQuickWorkout = true
        }
    }
}

// MARK: - Save Streak Action Button

struct SaveStreakActionButton: View {
    let streakType: StreakType
    let timeRemaining: TimeInterval
    let currentStreak: Int
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    private var actionTitle: String {
        switch streakType {
        case .app: return "Complete Check-In"
        case .nutrition: return "Log Food to Hit Macros"
        case .weeklyWin: return "Start Workout"
        }
    }
    
    private var urgency: UrgencyLevel {
        StreakCalculations.urgencyLevel(seconds: timeRemaining)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon with glow
                ZStack {
                    Circle()
                        .fill(streakType.color.opacity(0.2))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: streakType.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(streakType.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(actionTitle)
                        .font(FitFont.heading(size: 17))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    HStack(spacing: 8) {
                        // Current streak
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text("\(currentStreak) days")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        
                        Text("•")
                            .foregroundColor(FitTheme.textSecondary)
                        
                        // Time remaining
                        Text(StreakCalculations.formatCountdown(timeRemaining))
                            .font(FitFont.body(size: 13, weight: .semibold))
                            .foregroundColor(urgency.color)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(streakType.color)
            }
            .padding(16)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(streakType.color.opacity(0.3), lineWidth: 2)
            )
            .shadow(color: streakType.color.opacity(0.15), radius: 15, y: 8)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Quick Log Meal Sheet (Placeholder)

struct QuickLogMealSheet: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 60))
                        .foregroundColor(FitTheme.cardNutritionAccent)
                    
                    Text("Log Your Meal")
                        .font(FitFont.heading(size: 24))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    Text("Log food to hit your macro targets and save your nutrition streak!")
                        .font(FitFont.body(size: 16))
                        .foregroundColor(FitTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button(action: {
                        onComplete()
                        dismiss()
                    }) {
                        Text("Open Nutrition Tab")
                            .font(FitFont.body(size: 17, weight: .semibold))
                            .foregroundColor(FitTheme.buttonText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(FitTheme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Quick Start Workout Sheet (Placeholder)

struct QuickStartWorkoutSheet: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 60))
                        .foregroundColor(FitTheme.cardWorkoutAccent)
                    
                    Text("Start Your Workout")
                        .font(FitFont.heading(size: 24))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    Text("Complete a workout to make progress on your weekly goal!")
                        .font(FitFont.body(size: 16))
                        .foregroundColor(FitTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    // Progress
                    let store = StreakStore.shared
                    HStack(spacing: 8) {
                        ForEach(0..<store.weeklyWin.weeklyGoal, id: \.self) { index in
                            Circle()
                                .fill(index < store.workoutsThisWeek ? FitTheme.cardWorkoutAccent : FitTheme.cardHighlight)
                                .frame(width: 12, height: 12)
                        }
                    }
                    
                    Text("\(store.workoutsThisWeek) / \(store.weeklyWin.weeklyGoal) workouts this week")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Button(action: {
                        onComplete()
                        dismiss()
                    }) {
                        Text("Open Workout Tab")
                            .font(FitFont.body(size: 17, weight: .semibold))
                            .foregroundColor(FitTheme.buttonText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(FitTheme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SaveYourStreakView(
        atRiskStreaks: [
            (.app, 5400),
            (.nutrition, 7200)
        ],
        onActionComplete: { _ in },
        onDismiss: {}
    )
}


