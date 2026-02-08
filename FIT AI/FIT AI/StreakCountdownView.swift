import SwiftUI

// MARK: - Streak Countdown View

struct StreakCountdownView: View {
    let timeRemaining: TimeInterval
    let streakType: StreakType
    let action: () -> Void
    
    @State private var pulseAnimation = false
    
    private var urgency: UrgencyLevel {
        StreakCalculations.urgencyLevel(seconds: timeRemaining)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Pulsing warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(urgency.color)
                .scaleEffect(pulseAnimation && urgency.shouldPulse ? 1.2 : 1.0)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(StreakCalculations.formatCountdown(timeRemaining))
                    .font(FitFont.heading(size: 16))
                    .foregroundColor(urgency.color)
                
                Text("to save your \(streakType.displayName) streak")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
            
            Spacer()
            
            Button(action: action) {
                Text("Save")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(urgency.color)
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(urgency.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(urgency.color.opacity(0.3), lineWidth: 1.5)
        )
        .onAppear {
            if urgency.shouldPulse {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
        }
    }
}

// MARK: - Multiple Streaks at Risk Banner

struct MultipleStreaksAtRiskBanner: View {
    let atRiskStreaks: [(StreakType, TimeInterval)]
    let onSaveStreak: (StreakType) -> Void
    
    private var mostUrgentTime: TimeInterval {
        atRiskStreaks.min(by: { $0.1 < $1.1 })?.1 ?? 0
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header warning
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
                
                Text("You have \(atRiskStreaks.count) streaks at risk!")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                
                Spacer()
                
                Text(StreakCalculations.formatCountdown(mostUrgentTime))
                    .font(FitFont.body(size: 12, weight: .bold))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Quick action buttons
            HStack(spacing: 8) {
                ForEach(atRiskStreaks.prefix(3), id: \.0) { streakType, _ in
                    Button(action: { onSaveStreak(streakType) }) {
                        HStack(spacing: 6) {
                            Image(systemName: streakType.icon)
                                .font(.system(size: 12))
                            Text(actionTitle(for: streakType))
                                .font(FitFont.body(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(streakType.color)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
    
    private func actionTitle(for type: StreakType) -> String {
        switch type {
        case .app: return "Check In"
        case .nutrition: return "Log Food"
        case .weeklyWin: return "Workout"
        }
    }
}

// MARK: - Compact Countdown Badge

struct CompactCountdownBadge: View {
    let timeRemaining: TimeInterval
    let streakType: StreakType
    
    private var urgency: UrgencyLevel {
        StreakCalculations.urgencyLevel(seconds: timeRemaining)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 10))
            
            Text(StreakCalculations.formatCountdown(timeRemaining))
                .font(FitFont.body(size: 11, weight: .semibold))
        }
        .foregroundColor(urgency.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(urgency.color.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Inline Streak Warning

struct InlineStreakWarning: View {
    let streakType: StreakType
    let timeRemaining: TimeInterval
    let currentStreak: Int
    let onAction: () -> Void
    
    @State private var isAnimating = false
    
    private var urgency: UrgencyLevel {
        StreakCalculations.urgencyLevel(seconds: timeRemaining)
    }
    
    var body: some View {
        Button(action: onAction) {
            HStack(spacing: 12) {
                // Animated icon
                ZStack {
                    Circle()
                        .fill(urgency.color.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .scaleEffect(isAnimating && urgency.shouldPulse ? 1.15 : 1.0)
                    
                    Image(systemName: streakType.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(urgency.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(currentStreak) day streak at risk!")
                            .font(FitFont.body(size: 15, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                    }
                    
                    Text(StreakCalculations.formatCountdown(timeRemaining))
                        .font(FitFont.body(size: 13))
                        .foregroundColor(urgency.color)
                }
                
                Spacer()
                
                Text(actionTitle)
                    .font(FitFont.body(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(urgency.color)
                    .clipShape(Capsule())
            }
            .padding(14)
            .background(urgency.color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(urgency.color.opacity(0.25), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            if urgency.shouldPulse {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
    }
    
    private var actionTitle: String {
        switch streakType {
        case .app: return "Check In"
        case .nutrition: return "Log Food"
        case .weeklyWin: return "Start"
        }
    }
}

// MARK: - Countdown Timer Display

struct CountdownTimerDisplay: View {
    let timeRemaining: TimeInterval
    
    private var hours: Int { Int(timeRemaining) / 3600 }
    private var minutes: Int { (Int(timeRemaining) % 3600) / 60 }
    private var seconds: Int { Int(timeRemaining) % 60 }
    
    private var urgency: UrgencyLevel {
        StreakCalculations.urgencyLevel(seconds: timeRemaining)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if hours > 0 {
                timeUnit(value: hours, label: "h")
            }
            timeUnit(value: minutes, label: "m")
            if hours == 0 {
                timeUnit(value: seconds, label: "s")
            }
        }
    }
    
    private func timeUnit(value: Int, label: String) -> some View {
        HStack(spacing: 2) {
            Text("\(value)")
                .font(FitFont.heading(size: 20))
                .foregroundColor(urgency.color)
                .monospacedDigit()
            
            Text(label)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        StreakCountdownView(
            timeRemaining: 3600 * 2,
            streakType: .app,
            action: {}
        )
        
        StreakCountdownView(
            timeRemaining: 1800,
            streakType: .nutrition,
            action: {}
        )
        
        MultipleStreaksAtRiskBanner(
            atRiskStreaks: [(.app, 3600), (.nutrition, 5400)],
            onSaveStreak: { _ in }
        )
        
        InlineStreakWarning(
            streakType: .app,
            timeRemaining: 1800,
            currentStreak: 7,
            onAction: {}
        )
    }
    .padding()
    .background(FitTheme.backgroundGradient)
}


