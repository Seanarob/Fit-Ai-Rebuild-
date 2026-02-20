import SwiftUI

// MARK: - Enhanced Streak Detail View

struct EnhancedStreakDetailView: View {
    @ObservedObject var streakStore = StreakStore.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingGoalPicker = false
    @State private var goalChangeMessage: String?
    @State private var selectedBadge: StreakBadgeDefinition?

    private let badgeColumns = [GridItem(.adaptive(minimum: 70), spacing: 12)]
    
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    header
                    
                    // App Streak Card
                    StreakDetailCard(
                        title: "App Streak",
                        subtitle: "Daily Check-Ins",
                        icon: "flame.fill",
                        currentStreak: streakStore.appStreak.currentStreak,
                        longestStreak: streakStore.appStreak.longestStreak,
                        streakStartDate: streakStore.appStreak.streakStartDate,
                        longestStartDate: streakStore.appStreak.longestStreakStartDate,
                        longestEndDate: streakStore.appStreak.longestStreakEndDate,
                        status: streakStore.appStreakStatus,
                        color: .orange
                    )
                    
                    // Nutrition Streak Card
                    StreakDetailCard(
                        title: "Nutrition Streak",
                        subtitle: "Macros Hit (±15%)",
                        icon: "fork.knife",
                        currentStreak: streakStore.nutritionStreak.currentStreak,
                        longestStreak: streakStore.nutritionStreak.longestStreak,
                        streakStartDate: streakStore.nutritionStreak.streakStartDate,
                        longestStartDate: streakStore.nutritionStreak.longestStreakStartDate,
                        longestEndDate: streakStore.nutritionStreak.longestStreakEndDate,
                        status: streakStore.nutritionStreakStatus,
                        color: FitTheme.cardNutritionAccent
                    )
                    
                    // Weekly Win Card
                    WeeklyWinDetailCard(
                        weeklyWinCount: streakStore.weeklyWin.weeklyWinCount,
                        currentWinStreak: streakStore.weeklyWin.currentWinStreak,
                        longestWinStreak: streakStore.weeklyWin.longestWinStreak,
                        weeklyGoal: streakStore.weeklyWin.weeklyGoal,
                        workoutsThisWeek: streakStore.workoutsThisWeek,
                        pendingGoalChange: streakStore.weeklyWin.pendingGoalChange,
                        status: streakStore.weeklyWinStatus,
                        onChangeGoal: { showingGoalPicker = true }
                    )

                    streakBadgesSection
                    
                    // Motivational section
                    StreakMilestoneView(
                        appStreak: streakStore.appStreak.currentStreak,
                        nutritionStreak: streakStore.nutritionStreak.currentStreak,
                        weeklyWins: streakStore.weeklyWin.weeklyWinCount
                    )
                    
                    // Tips section
                    tipsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showingGoalPicker) {
            WeeklyGoalPickerSheet(
                currentGoal: streakStore.weeklyWin.weeklyGoal,
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
        .sheet(item: $selectedBadge) { badge in
            StreakBadgeDetailSheet(
                badge: badge,
                isEarned: badgeEarned(badge),
                longestStreak: streakStore.appStreak.longestStreak
            )
            .presentationDetents([.medium])
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Streaks")
                    .font(FitFont.heading(size: 28))
                    .foregroundColor(FitTheme.textPrimary)
                Text("Consistency is key 🔑")
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
    
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips to Keep Streaks")
                .font(FitFont.heading(size: 18))
                .foregroundColor(FitTheme.textPrimary)
            
            VStack(spacing: 10) {
                StreakTipRow(icon: "bell.badge.fill", text: "Enable notifications for daily reminders")
                StreakTipRow(icon: "clock.fill", text: "Set a consistent time to log meals")
                StreakTipRow(icon: "calendar.badge.plus", text: "Plan workouts at the start of each week")
                StreakTipRow(icon: "moon.fill", text: "Check in before bed to never miss a day")
            }
        }
        .padding(18)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func badgeEarned(_ badge: StreakBadgeDefinition) -> Bool {
        streakStore.appStreak.longestStreak >= badge.requiredDays
    }

    private var streakBadgesSection: some View {
        let earnedCount = StreakBadgeCatalog.all.filter { badgeEarned($0) }.count

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Streak Badges")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)

                Spacer()

                Text("\(earnedCount)/\(StreakBadgeCatalog.all.count)")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(FitTheme.cardHighlight)
                    .clipShape(Capsule())
            }

            Text("Tap a badge to see rarity, requirements, and character nickname.")
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)

            LazyVGrid(columns: badgeColumns, spacing: 12) {
                ForEach(StreakBadgeCatalog.all) { badge in
                    let earned = badgeEarned(badge)
                    Button {
                        selectedBadge = badge
                    } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                HoloBadgeView(
                                    image: Image(badge.imageName),
                                    cornerRadius: 16,
                                    isEarned: earned
                                )
                                .frame(height: 78)
                                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 5)

                                if !earned {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                        .padding(6)
                                }
                            }

                            Text(badge.title)
                                .font(FitFont.body(size: 11, weight: .semibold))
                                .foregroundColor(FitTheme.textPrimary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FitTheme.cardStroke.opacity(0.5), lineWidth: 1)
        )
    }
}

// MARK: - Streak Detail Card

struct StreakDetailCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let currentStreak: Int
    let longestStreak: Int
    let streakStartDate: String?
    let longestStartDate: String?
    let longestEndDate: String?
    let status: StreakStatus
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(color)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(subtitle)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                Spacer()
                
                // Status indicator
                if case .atRisk(let time) = status {
                    CompactCountdownBadge(timeRemaining: time, streakType: .app)
                } else if status.isSafe && currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Safe")
                            .font(FitFont.body(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            
            Divider()
            
            // Stats grid
            HStack(spacing: 20) {
                // Current streak
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(currentStreak)")
                            .font(FitFont.heading(size: 32))
                            .foregroundColor(color)
                        Text("days")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    if let startDate = streakStartDate, currentStreak > 0 {
                        Text("Since \(StreakCalculations.formatDateKeyForDisplay(startDate))")
                            .font(FitFont.body(size: 11))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                
                Divider()
                    .frame(height: 50)
                
                // Longest streak
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text("Longest")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(longestStreak)")
                            .font(FitFont.heading(size: 32))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("days")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    if let range = StreakCalculations.formatDateRange(start: longestStartDate, end: longestEndDate) {
                        Text(range)
                            .font(FitFont.body(size: 11))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(18)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(color.opacity(0.2), lineWidth: 1.5)
        )
    }
}

// MARK: - Weekly Win Detail Card

struct WeeklyWinDetailCard: View {
    let weeklyWinCount: Int
    let currentWinStreak: Int
    let longestWinStreak: Int
    let weeklyGoal: Int
    let workoutsThisWeek: Int
    let pendingGoalChange: Int?
    let status: StreakStatus
    let onChangeGoal: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(FitTheme.cardWorkoutAccent)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Win")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("\(weeklyGoal) workouts per week")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                Spacer()
                
                Button(action: onChangeGoal) {
                    Text("Change")
                        .font(FitFont.body(size: 12, weight: .medium))
                        .foregroundColor(FitTheme.accent)
                }
            }
            
            // Progress this week
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("This Week")
                        .font(FitFont.body(size: 14, weight: .medium))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    Spacer()
                    
                    Text("\(workoutsThisWeek) / \(weeklyGoal)")
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(workoutsThisWeek >= weeklyGoal ? .green : FitTheme.cardWorkoutAccent)
                }
                
                // Visual progress
                HStack(spacing: 6) {
                    ForEach(0..<weeklyGoal, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(index < workoutsThisWeek ? FitTheme.cardWorkoutAccent : FitTheme.cardHighlight)
                            .frame(height: 8)
                    }
                }
                
                if workoutsThisWeek >= weeklyGoal {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Goal reached! 🎉")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(.green)
                    }
                } else {
                    Text("\(weeklyGoal - workoutsThisWeek) more to hit your goal")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            .padding(14)
            .background(FitTheme.cardWorkout.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            Divider()
            
            // Stats
            HStack(spacing: 0) {
                winStat(value: weeklyWinCount, label: "Total Wins", icon: "trophy.fill")
                
                Divider()
                    .frame(height: 40)
                    .padding(.horizontal, 12)
                
                winStat(value: currentWinStreak, label: "Win Streak", icon: "flame.fill")
                
                Divider()
                    .frame(height: 40)
                    .padding(.horizontal, 12)
                
                winStat(value: longestWinStreak, label: "Best Streak", icon: "star.fill")
            }
            
            // Pending goal change notice
            if let pendingGoal = pendingGoalChange {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(FitTheme.accent)
                    Text("Goal changing to \(pendingGoal) workouts next week")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                .padding(10)
                .background(FitTheme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(18)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(FitTheme.cardWorkoutAccent.opacity(0.2), lineWidth: 1.5)
        )
    }
    
    private func winStat(value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                Text("\(value)")
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(FitTheme.textPrimary)
            }
            Text(label)
                .font(FitFont.body(size: 11))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Streak Milestone View

struct StreakMilestoneView: View {
    let appStreak: Int
    let nutritionStreak: Int
    let weeklyWins: Int
    
    private var nextMilestone: (name: String, current: Int, target: Int)? {
        let milestones = [7, 14, 30, 60, 90, 180, 365]
        
        // Check app streak
        if let target = milestones.first(where: { $0 > appStreak }) {
            return ("App Streak", appStreak, target)
        }
        
        // Check nutrition streak
        if let target = milestones.first(where: { $0 > nutritionStreak }) {
            return ("Nutrition Streak", nutritionStreak, target)
        }
        
        return nil
    }
    
    var body: some View {
        if let milestone = nextMilestone {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Next Milestone")
                        .font(FitFont.heading(size: 16))
                        .foregroundColor(FitTheme.textPrimary)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(milestone.target) Day \(milestone.name)")
                            .font(FitFont.body(size: 15, weight: .medium))
                            .foregroundColor(FitTheme.textPrimary)
                        
                        Text("\(milestone.target - milestone.current) days to go")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(FitTheme.cardHighlight, lineWidth: 6)
                            .frame(width: 50, height: 50)
                        
                        Circle()
                            .trim(from: 0, to: Double(milestone.current) / Double(milestone.target))
                            .stroke(FitTheme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 50, height: 50)
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(Int(Double(milestone.current) / Double(milestone.target) * 100))%")
                            .font(FitFont.body(size: 11, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                    }
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color.yellow.opacity(0.1), Color.orange.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Streak Badge Detail Sheet

struct StreakBadgeDetailSheet: View {
    let badge: StreakBadgeDefinition
    let isEarned: Bool
    let longestStreak: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(badge.title)
                            .font(FitFont.heading(size: 22))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Nickname: \(badge.nickname)")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    Spacer()
                    RarityPill(rarity: badge.rarity)
                }

                HoloBadgeView(
                    image: Image(badge.imageName),
                    cornerRadius: 24,
                    isEarned: isEarned
                )
                .frame(width: 160, height: 160)
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 10) {
                    detailRow(label: "Requirement", value: badge.requirementText)
                    if isEarned {
                        detailRow(label: "Status", value: "Unlocked")
                    } else {
                        detailRow(label: "Status", value: "Locked")
                        detailRow(label: "Current Best", value: "\(max(longestStreak, 0)) days")
                    }
                }
                .padding(14)
                .background(FitTheme.cardHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
        }
        .background(FitTheme.backgroundGradient.ignoresSafeArea())
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)
                .frame(width: 95, alignment: .leading)
            Text(value)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textPrimary)
            Spacer()
        }
    }
}

struct RarityPill: View {
    let rarity: StreakBadgeRarity

    var body: some View {
        Text(rarity.rawValue)
            .font(FitFont.body(size: 12, weight: .semibold))
            .foregroundColor(rarity.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(rarity.color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Streak Tip Row

struct StreakTipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(FitTheme.accent)
                .frame(width: 24)
            Text(text)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    EnhancedStreakDetailView()
}
