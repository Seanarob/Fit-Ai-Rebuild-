# FIT AI Streak System Implementation Plan

## Overview

Build a Snapchat-style streak system with three core streaks: **App Streak** (Daily Check-In), **Nutrition Streak** (Macros Hit), and **Weekly Win** (Workout Goals). The system emphasizes urgency, habit formation, and real loss when streaks break.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Data Models](#data-models)
3. [Phase 1: Core Streak Infrastructure](#phase-1-core-streak-infrastructure)
4. [Phase 2: Daily Check-In System](#phase-2-daily-check-in-system)
5. [Phase 3: Nutrition Streak](#phase-3-nutrition-streak)
6. [Phase 4: Weekly Win System](#phase-4-weekly-win-system)
7. [Phase 5: Countdown Timers & Urgency UI](#phase-5-countdown-timers--urgency-ui)
8. [Phase 6: "Save Your Streak" Mode](#phase-6-save-your-streak-mode)
9. [Phase 7: Local Push Notifications](#phase-7-local-push-notifications)
10. [Phase 8: Longest Streaks & History](#phase-8-longest-streaks--history)
11. [UI/UX Components](#uiux-components)
12. [Backend Changes](#backend-changes)
13. [Migration Strategy](#migration-strategy)
14. [Testing Plan](#testing-plan)

---

## Architecture Overview

### Storage Strategy
All streak data stored **on-device** using `UserDefaults` / `@AppStorage` for:
- Speed and offline reliability
- Privacy (no server-side tracking)
- Simplicity (no sync conflicts)

### Timezone Handling
- Auto-detect device timezone via `TimeZone.current`
- All streak calculations use **local calendar day** (midnight to midnight)
- Store timezone identifier for consistency checks

### Key Principles
1. **Streaks increment only on completion** (not app opens)
2. **Miss = Reset to zero** (no recovery/freeze options)
3. **Real-time countdown urgency** (Snapchat-style timers)
4. **Gen Z UX** (loss aversion, instant gratification, social proof)

---

## Data Models

### 1. StreakStore.swift (New Unified Store)

```swift
import Foundation

// MARK: - Streak Types

enum StreakType: String, CaseIterable {
    case app = "app"           // Daily Check-In
    case nutrition = "nutrition" // Macros Hit
    case weeklyWin = "weekly_win" // Workout Goal
}

// MARK: - App Streak Data

struct AppStreakData: Codable {
    var currentStreak: Int
    var longestStreak: Int
    var lastCompletedDate: String?      // "yyyy-MM-dd" in local timezone
    var longestStreakStartDate: String?
    var longestStreakEndDate: String?
    var streakStartDate: String?        // Current streak start
    
    static let empty = AppStreakData(
        currentStreak: 0,
        longestStreak: 0,
        lastCompletedDate: nil,
        longestStreakStartDate: nil,
        longestStreakEndDate: nil,
        streakStartDate: nil
    )
}

// MARK: - Nutrition Streak Data

struct NutritionStreakData: Codable {
    var currentStreak: Int
    var longestStreak: Int
    var lastHitDate: String?            // "yyyy-MM-dd" in local timezone
    var longestStreakStartDate: String?
    var longestStreakEndDate: String?
    var streakStartDate: String?
    
    static let empty = NutritionStreakData(
        currentStreak: 0,
        longestStreak: 0,
        lastHitDate: nil,
        longestStreakStartDate: nil,
        longestStreakEndDate: nil,
        streakStartDate: nil
    )
}

// MARK: - Weekly Win Data

struct WeeklyWinData: Codable {
    var weeklyWinCount: Int             // Total weeks won
    var longestWinStreak: Int           // Consecutive weeks won
    var currentWinStreak: Int           // Current consecutive weeks
    var weeklyGoal: Int                 // Target workouts per week (default 5)
    var pendingGoalChange: Int?         // Goal to apply next week
    var workoutsThisWindow: [String]    // Dates of workouts in rolling 7 days
    var lastWinDate: String?            // Last week that was won
    var longestWinStreakStartDate: String?
    var longestWinStreakEndDate: String?
    
    static let empty = WeeklyWinData(
        weeklyWinCount: 0,
        longestWinStreak: 0,
        currentWinStreak: 0,
        weeklyGoal: 5,
        pendingGoalChange: nil,
        workoutsThisWindow: [],
        lastWinDate: nil,
        longestWinStreakStartDate: nil,
        longestWinStreakEndDate: nil
    )
}

// MARK: - Daily Check-In Data

struct DailyCheckInData: Codable {
    var hitMacros: Bool?                // Did you hit macros yesterday?
    var trainingStatus: TrainingStatus? // Trained / Off day
    var sleepQuality: SleepQuality?     // Good / Okay / Poor
    var completedAt: Date?
    var coachResponse: String?
    
    enum TrainingStatus: String, Codable, CaseIterable {
        case trained = "trained"
        case offDay = "off_day"
        
        var title: String {
            switch self {
            case .trained: return "I trained"
            case .offDay: return "Off day"
            }
        }
    }
    
    enum SleepQuality: String, Codable, CaseIterable {
        case good = "good"
        case okay = "okay"
        case poor = "poor"
        
        var title: String {
            switch self {
            case .good: return "Good"
            case .okay: return "Okay"
            case .poor: return "Poor"
            }
        }
        
        var emoji: String {
            switch self {
            case .good: return "😴"
            case .okay: return "😐"
            case .poor: return "😫"
            }
        }
    }
}

// MARK: - Streak Status (for UI)

enum StreakStatus {
    case safe                           // Completed today, no action needed
    case atRisk(timeRemaining: TimeInterval) // Not completed, countdown active
    case lost                           // Missed deadline, streak reset
    
    var isAtRisk: Bool {
        if case .atRisk = self { return true }
        return false
    }
}
```

### 2. StreakStore Manager

```swift
// MARK: - StreakStore (Singleton)

@MainActor
final class StreakStore: ObservableObject {
    static let shared = StreakStore()
    
    // Published state
    @Published private(set) var appStreak: AppStreakData = .empty
    @Published private(set) var nutritionStreak: NutritionStreakData = .empty
    @Published private(set) var weeklyWin: WeeklyWinData = .empty
    @Published private(set) var todaysCheckIn: DailyCheckInData?
    
    // Computed
    @Published private(set) var appStreakStatus: StreakStatus = .safe
    @Published private(set) var nutritionStreakStatus: StreakStatus = .safe
    @Published private(set) var weeklyWinStatus: StreakStatus = .safe
    
    // Timer for real-time updates
    private var countdownTimer: Timer?
    
    // UserDefaults keys
    private enum Keys {
        static let appStreak = "fitai.streak.app.data"
        static let nutritionStreak = "fitai.streak.nutrition.data"
        static let weeklyWin = "fitai.streak.weeklywin.data"
        static let todaysCheckIn = "fitai.checkin.today"
        static let deviceTimezone = "fitai.device.timezone"
    }
    
    private init() {
        load()
        startCountdownTimer()
        checkForMissedDeadlines()
    }
    
    // ... implementation methods
}
```

---

## Phase 1: Core Streak Infrastructure

### Files to Create

| File | Purpose |
|------|---------|
| `StreakModels.swift` | Data models for all streak types |
| `StreakStore.swift` | Central manager for streak state |
| `StreakCalculations.swift` | Date/time calculations, timezone handling |
| `StreakNotifications.swift` | Local notification scheduling |

### Files to Modify

| File | Changes |
|------|---------|
| `WorkoutStreakStore.swift` | Deprecate, migrate to new system |
| `HomeView.swift` | Remove old streak logic, integrate new StreakStore |
| `FIT_AIApp.swift` | Initialize StreakStore on launch |

### Implementation Steps

1. **Create `StreakModels.swift`**
   - Define all Codable structs
   - Define enums for check-in options
   - Define StreakStatus enum

2. **Create `StreakStore.swift`**
   - Singleton pattern with `@MainActor`
   - UserDefaults persistence
   - Timer for real-time countdown updates
   - Methods for each streak action

3. **Create `StreakCalculations.swift`**
   - `localDateKey(for:)` - Get "yyyy-MM-dd" in device timezone
   - `timeUntilMidnight()` - Seconds until local midnight
   - `isWithinWindow(date:windowDays:)` - Rolling window check
   - `macrosWithinTarget(logged:target:tolerance:)` - ±15% check

4. **Create `StreakNotifications.swift`**
   - Request notification permissions
   - Schedule/cancel notifications
   - Handle notification responses

---

## Phase 2: Daily Check-In System

### User Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    DAILY CHECK-IN                           │
│                                                             │
│  "Quick check-in to save your streak"                      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Did you hit your macros yesterday?                 │   │
│  │  ┌──────────┐  ┌──────────┐                        │   │
│  │  │   Yes    │  │    No    │                        │   │
│  │  └──────────┘  └──────────┘                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Did you train or was it an off day?                │   │
│  │  ┌──────────┐  ┌──────────┐                        │   │
│  │  │ I trained │  │ Off day  │                        │   │
│  │  └──────────┘  └──────────┘                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  How was your sleep?                                │   │
│  │  ┌──────┐  ┌──────┐  ┌──────┐                      │   │
│  │  │ Good │  │ Okay │  │ Poor │                      │   │
│  │  │  😴  │  │  😐  │  │  😫  │                      │   │
│  │  └──────┘  └──────┘  └──────┘                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Complete Check-In                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘

                           ↓ Submit

┌─────────────────────────────────────────────────────────────┐
│                   COACH RESPONSE                            │
│                                                             │
│         ┌──────────────────────────┐                       │
│         │      🏋️ Coach           │                       │
│         │    [Animated Avatar]     │                       │
│         └──────────────────────────┘                       │
│                                                             │
│  "Great work on hitting your macros! Rest up tonight       │
│   and let's crush tomorrow's workout."                     │
│                                                             │
│               🔥 4 Day Streak! 🔥                          │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Continue                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Files to Create

| File | Purpose |
|------|---------|
| `DailyCheckInView.swift` | Check-in form UI |
| `DailyCheckInViewModel.swift` | Form state and submission logic |

### Implementation Steps

1. **Create `DailyCheckInView.swift`**
   - Three-question form (macros, training, sleep)
   - Binary/ternary selection buttons
   - Progress indicator (1/3, 2/3, 3/3)
   - Submit button (disabled until all answered)
   - Coach response modal after submission

2. **Create `DailyCheckInViewModel.swift`**
   - Form state management
   - Validation
   - Submit to StreakStore
   - AI coach response generation

3. **Add Backend Endpoint** (optional enhancement)
   ```python
   # routers/daily_checkin.py
   @router.post("/daily-checkin")
   async def submit_daily_checkin(
       user_id: str,
       hit_macros: bool,
       training_status: str,
       sleep_quality: str
   ):
       # Generate AI coach response
       prompt = f"""
       User check-in:
       - Hit macros yesterday: {hit_macros}
       - Training: {training_status}
       - Sleep: {sleep_quality}
       
       Respond with ONE short motivational sentence (under 20 words).
       Be encouraging but acknowledge their honest answers.
       """
       # Return coach response
   ```

4. **Integrate with HomeView**
   - Replace current greeting flow with check-in trigger
   - Show check-in card if not completed today
   - Animate streak celebration after completion

### Streak Logic

```swift
extension StreakStore {
    func completeCheckIn(_ checkIn: DailyCheckInData) {
        let today = localDateKey(for: Date())
        
        // Check if already completed today
        guard appStreak.lastCompletedDate != today else { return }
        
        // Check if streak continues or resets
        let yesterday = localDateKey(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        
        if appStreak.lastCompletedDate == yesterday {
            // Consecutive - increment
            appStreak.currentStreak += 1
        } else {
            // Streak broken - reset to 1
            appStreak.currentStreak = 1
            appStreak.streakStartDate = today
        }
        
        // Update longest if needed
        if appStreak.currentStreak > appStreak.longestStreak {
            appStreak.longestStreak = appStreak.currentStreak
            appStreak.longestStreakEndDate = today
            appStreak.longestStreakStartDate = appStreak.streakStartDate
        }
        
        appStreak.lastCompletedDate = today
        todaysCheckIn = checkIn
        save()
        
        // Cancel any pending notifications
        StreakNotifications.cancelAppStreakReminders()
    }
}
```

---

## Phase 3: Nutrition Streak

### Macro Hit Calculation

```swift
struct MacroHitCalculator {
    /// Tolerance for macros (±15%)
    static let tolerance: Double = 0.15
    
    /// Check if all macros are within target range
    static func isHit(logged: MacroTotals, target: MacroTotals) -> Bool {
        guard target.calories > 0 else { return false }
        
        let caloriesHit = isWithinRange(logged.calories, target: target.calories)
        let proteinHit = isWithinRange(logged.protein, target: target.protein)
        let carbsHit = isWithinRange(logged.carbs, target: target.carbs)
        let fatsHit = isWithinRange(logged.fats, target: target.fats)
        
        return caloriesHit && proteinHit && carbsHit && fatsHit
    }
    
    /// Check if value is within ±15% of target
    private static func isWithinRange(_ value: Double, target: Double) -> Bool {
        guard target > 0 else { return true } // Skip if no target set
        let lowerBound = target * (1 - tolerance)
        let upperBound = target * (1 + tolerance)
        return value >= lowerBound && value <= upperBound
    }
    
    /// Get detailed breakdown for UI
    static func breakdown(logged: MacroTotals, target: MacroTotals) -> MacroBreakdown {
        MacroBreakdown(
            calories: MacroStatus(
                logged: logged.calories,
                target: target.calories,
                isHit: isWithinRange(logged.calories, target: target.calories)
            ),
            protein: MacroStatus(
                logged: logged.protein,
                target: target.protein,
                isHit: isWithinRange(logged.protein, target: target.protein)
            ),
            carbs: MacroStatus(
                logged: logged.carbs,
                target: target.carbs,
                isHit: isWithinRange(logged.carbs, target: target.carbs)
            ),
            fats: MacroStatus(
                logged: logged.fats,
                target: target.fats,
                isHit: isWithinRange(logged.fats, target: target.fats)
            )
        )
    }
}

struct MacroBreakdown {
    let calories: MacroStatus
    let protein: MacroStatus
    let carbs: MacroStatus
    let fats: MacroStatus
    
    var allHit: Bool {
        calories.isHit && protein.isHit && carbs.isHit && fats.isHit
    }
}

struct MacroStatus {
    let logged: Double
    let target: Double
    let isHit: Bool
    
    var percentage: Double {
        guard target > 0 else { return 0 }
        return (logged / target) * 100
    }
    
    var rangeText: String {
        let lower = Int(target * 0.85)
        let upper = Int(target * 1.15)
        return "\(lower)–\(upper)"
    }
}
```

### Auto-Detection Logic

```swift
extension StreakStore {
    /// Called whenever nutrition logs are updated
    func checkNutritionStreak(logged: MacroTotals, target: MacroTotals) {
        let today = localDateKey(for: Date())
        
        // Skip if already credited for today
        guard nutritionStreak.lastHitDate != today else { return }
        
        // Check if macros are hit
        guard MacroHitCalculator.isHit(logged: logged, target: target) else { return }
        
        // Check if streak continues or resets
        let yesterday = localDateKey(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        
        if nutritionStreak.lastHitDate == yesterday {
            nutritionStreak.currentStreak += 1
        } else {
            nutritionStreak.currentStreak = 1
            nutritionStreak.streakStartDate = today
        }
        
        // Update longest
        if nutritionStreak.currentStreak > nutritionStreak.longestStreak {
            nutritionStreak.longestStreak = nutritionStreak.currentStreak
            nutritionStreak.longestStreakEndDate = today
            nutritionStreak.longestStreakStartDate = nutritionStreak.streakStartDate
        }
        
        nutritionStreak.lastHitDate = today
        save()
        
        // Trigger celebration
        NotificationCenter.default.post(name: .fitAINutritionStreakHit, object: nil)
    }
}
```

### Integration Points

1. **NutritionViewModel.swift** - Call `StreakStore.shared.checkNutritionStreak()` after each food log
2. **HomeView.swift** - Observe nutrition totals and update streak status
3. **NutritionSnapshotCard** - Show macro hit status with visual feedback

---

## Phase 4: Weekly Win System

### Rolling 7-Day Window Logic

```swift
extension StreakStore {
    /// Record a completed workout
    func recordWorkout(date: Date = Date()) {
        let dateKey = localDateKey(for: date)
        
        // Add to window if not already recorded
        if !weeklyWin.workoutsThisWindow.contains(dateKey) {
            weeklyWin.workoutsThisWindow.append(dateKey)
        }
        
        // Clean old entries (keep only last 7 days)
        pruneWorkoutWindow()
        
        // Check if goal is met
        checkWeeklyWinStatus()
        
        save()
    }
    
    /// Remove workouts older than 7 days
    private func pruneWorkoutWindow() {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let cutoffKey = localDateKey(for: sevenDaysAgo)
        
        weeklyWin.workoutsThisWindow = weeklyWin.workoutsThisWindow.filter { dateKey in
            dateKey >= cutoffKey
        }
    }
    
    /// Check if weekly goal is achieved
    private func checkWeeklyWinStatus() {
        let workoutsInWindow = weeklyWin.workoutsThisWindow.count
        
        if workoutsInWindow >= weeklyWin.weeklyGoal {
            // Goal achieved!
            let today = localDateKey(for: Date())
            
            // Only credit once per achievement window
            if weeklyWin.lastWinDate != today {
                weeklyWin.weeklyWinCount += 1
                weeklyWin.currentWinStreak += 1
                weeklyWin.lastWinDate = today
                
                if weeklyWin.currentWinStreak > weeklyWin.longestWinStreak {
                    weeklyWin.longestWinStreak = weeklyWin.currentWinStreak
                    weeklyWin.longestWinStreakEndDate = today
                }
                
                // Trigger celebration
                NotificationCenter.default.post(name: .fitAIWeeklyWinAchieved, object: nil)
            }
        }
    }
    
    /// Called at start of each day to check for win streak reset
    func checkWeeklyWinReset() {
        // If 7 days have passed since last win and goal not met, reset win streak
        guard let lastWinKey = weeklyWin.lastWinDate,
              let lastWinDate = dateFromKey(lastWinKey) else { return }
        
        let daysSinceWin = Calendar.current.dateComponents([.day], from: lastWinDate, to: Date()).day ?? 0
        
        if daysSinceWin > 7 && weeklyWin.workoutsThisWindow.count < weeklyWin.weeklyGoal {
            // Failed to maintain - reset win streak (but keep total count)
            weeklyWin.currentWinStreak = 0
            save()
        }
        
        // Apply pending goal change if it's a new week
        applyPendingGoalChangeIfNeeded()
    }
    
    /// Change weekly workout goal (applies next week)
    func setWeeklyGoal(_ newGoal: Int) -> String? {
        guard newGoal >= 1 && newGoal <= 7 else { return nil }
        
        if newGoal == weeklyWin.weeklyGoal {
            return nil // No change
        }
        
        weeklyWin.pendingGoalChange = newGoal
        save()
        
        return "Goal will change to \(newGoal) workouts starting next week. Keep crushing your current goal of \(weeklyWin.weeklyGoal)!"
    }
    
    private func applyPendingGoalChangeIfNeeded() {
        guard let pendingGoal = weeklyWin.pendingGoalChange else { return }
        
        // Apply at the start of a new week (Sunday)
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        
        if weekday == 1 { // Sunday
            weeklyWin.weeklyGoal = pendingGoal
            weeklyWin.pendingGoalChange = nil
            save()
        }
    }
}
```

### Weekly Win UI Display

```
┌────────────────────────────────────────────────────┐
│  Weekly Win 🏆                                     │
│                                                    │
│  ┌──┬──┬──┬──┬──┬──┬──┐                          │
│  │✓ │✓ │✓ │○ │○ │  │  │  3 / 5 this week        │
│  │M │T │W │T │F │S │S │                          │
│  └──┴──┴──┴──┴──┴──┴──┘                          │
│                                                    │
│  🔥 Win Streak: 4 weeks                           │
│                                                    │
└────────────────────────────────────────────────────┘
```

---

## Phase 5: Countdown Timers & Urgency UI

### Countdown Timer Logic

```swift
struct StreakCountdown {
    /// Time remaining until local midnight
    static func timeUntilMidnight() -> TimeInterval {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
        return tomorrow.timeIntervalSince(now)
    }
    
    /// Format countdown for display
    static func format(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        } else if minutes > 0 {
            return "\(minutes)m left"
        } else {
            return "< 1m left"
        }
    }
    
    /// Urgency level for UI styling
    static func urgencyLevel(seconds: TimeInterval) -> UrgencyLevel {
        let hours = seconds / 3600
        if hours <= 0.5 { return .critical }   // < 30 min
        if hours <= 2 { return .high }          // < 2 hours
        if hours <= 6 { return .medium }        // < 6 hours
        return .low
    }
}

enum UrgencyLevel {
    case low, medium, high, critical
    
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
    
    var shouldPulse: Bool {
        self == .critical
    }
}
```

### Countdown Timer View

```swift
struct StreakCountdownView: View {
    let timeRemaining: TimeInterval
    let streakType: StreakType
    let action: () -> Void
    
    @State private var pulseAnimation = false
    
    private var urgency: UrgencyLevel {
        StreakCountdown.urgencyLevel(seconds: timeRemaining)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Pulsing warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(urgency.color)
                .scaleEffect(pulseAnimation && urgency.shouldPulse ? 1.2 : 1.0)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(StreakCountdown.format(timeRemaining))
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
```

### Multiple Streaks at Risk

```swift
struct MultipleStreaksAtRiskView: View {
    let atRiskStreaks: [(StreakType, TimeInterval)]
    let onSaveStreak: (StreakType) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header warning
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("You have \(atRiskStreaks.count) streaks at risk!")
                    .font(FitFont.heading(size: 16))
                    .foregroundColor(FitTheme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.1))
            .clipShape(Capsule())
            
            // Individual streak warnings
            ForEach(atRiskStreaks, id: \.0) { streakType, timeRemaining in
                StreakCountdownView(
                    timeRemaining: timeRemaining,
                    streakType: streakType,
                    action: { onSaveStreak(streakType) }
                )
            }
        }
    }
}
```

---

## Phase 6: "Save Your Streak" Mode

### Trigger Conditions

- Time remaining < 6 hours AND streak not yet saved for the day
- Activated for any streak that meets this criteria

### Save Your Streak View

```swift
struct SaveYourStreakView: View {
    let atRiskStreaks: [(StreakType, TimeInterval)]
    let onActionComplete: (StreakType) -> Void
    let onDismiss: () -> Void
    
    @State private var showingAction: StreakType?
    
    var body: some View {
        ZStack {
            // Dimmed background with urgency gradient
            LinearGradient(
                colors: [
                    Color.red.opacity(0.15),
                    FitTheme.backgroundGradient.colors.first ?? Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Dramatic header
                VStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                        .shadow(color: .orange.opacity(0.5), radius: 20)
                    
                    Text("SAVE YOUR STREAK")
                        .font(FitFont.heading(size: 28))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    if atRiskStreaks.count > 1 {
                        Text("\(atRiskStreaks.count) streaks at risk of being lost!")
                            .font(FitFont.body(size: 16))
                            .foregroundColor(.red)
                    }
                }
                .padding(.top, 40)
                
                // Action buttons for each at-risk streak
                VStack(spacing: 16) {
                    ForEach(atRiskStreaks, id: \.0) { streakType, timeRemaining in
                        SaveStreakActionButton(
                            streakType: streakType,
                            timeRemaining: timeRemaining,
                            onTap: {
                                showingAction = streakType
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
                }
                .padding(.bottom, 32)
            }
        }
        .sheet(item: $showingAction) { streakType in
            switch streakType {
            case .app:
                DailyCheckInView(onComplete: {
                    onActionComplete(.app)
                    showingAction = nil
                })
            case .nutrition:
                QuickLogMealSheet(onComplete: {
                    onActionComplete(.nutrition)
                    showingAction = nil
                })
            case .weeklyWin:
                QuickStartWorkoutSheet(onComplete: {
                    onActionComplete(.weeklyWin)
                    showingAction = nil
                })
            }
        }
    }
}

struct SaveStreakActionButton: View {
    let streakType: StreakType
    let timeRemaining: TimeInterval
    let onTap: () -> Void
    
    private var actionTitle: String {
        switch streakType {
        case .app: return "Complete Check-In"
        case .nutrition: return "Log Food to Hit Macros"
        case .weeklyWin: return "Start Workout"
        }
    }
    
    private var icon: String {
        switch streakType {
        case .app: return "checkmark.circle.fill"
        case .nutrition: return "fork.knife"
        case .weeklyWin: return "figure.run"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(streakType.color)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(actionTitle)
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    Text(StreakCountdown.format(timeRemaining))
                        .font(FitFont.body(size: 14))
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(16)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: streakType.color.opacity(0.2), radius: 10)
        }
        .buttonStyle(.plain)
    }
}
```

---

## Phase 7: Local Push Notifications

### Notification Schedule

| Streak Type | Condition | Notification Times |
|-------------|-----------|-------------------|
| **App Streak** | Not completed, streak > 3 days | 6 PM, 10 PM, 11:30 PM |
| **App Streak** | Not completed, streak ≤ 3 days | 10 PM, 11:30 PM |
| **Nutrition** | Macros not hit by evening | 6 PM, 8 PM |
| **Weekly Win** | Behind pace (workouts < expected) | 10 AM daily |

### Implementation (Similar to Rest Timer)

```swift
import UserNotifications

enum StreakNotifications {
    private static let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Notification IDs
    
    private enum NotificationID {
        static let appStreak6pm = "fitai.streak.app.6pm"
        static let appStreak10pm = "fitai.streak.app.10pm"
        static let appStreak1130pm = "fitai.streak.app.1130pm"
        static let nutrition6pm = "fitai.streak.nutrition.6pm"
        static let nutrition8pm = "fitai.streak.nutrition.8pm"
        static let weeklyWin = "fitai.streak.weeklywin"
    }
    
    // MARK: - Request Permissions
    
    static func requestPermissions() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted
        } catch {
            return false
        }
    }
    
    // MARK: - Schedule App Streak Reminders
    
    static func scheduleAppStreakReminders(currentStreak: Int) {
        cancelAppStreakReminders()
        
        let today = Calendar.current.startOfDay(for: Date())
        
        // 6 PM reminder (only for streaks > 3)
        if currentStreak > 3 {
            scheduleNotification(
                id: NotificationID.appStreak6pm,
                title: "Don't lose your \(currentStreak) day streak! 🔥",
                body: "Quick check-in takes 10 seconds. Keep the momentum going!",
                date: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: today)!
            )
        }
        
        // 10 PM reminder (2 hours before midnight)
        scheduleNotification(
            id: NotificationID.appStreak10pm,
            title: "⚠️ Streak at risk!",
            body: "2 hours left to save your \(currentStreak) day streak. Tap to check in.",
            date: Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: today)!
        )
        
        // 11:30 PM reminder (30 min before midnight, streaks > 3)
        if currentStreak > 3 {
            scheduleNotification(
                id: NotificationID.appStreak1130pm,
                title: "🚨 LAST CHANCE!",
                body: "30 minutes to save your \(currentStreak) day streak! Don't let it reset!",
                date: Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: today)!
            )
        }
    }
    
    static func cancelAppStreakReminders() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            NotificationID.appStreak6pm,
            NotificationID.appStreak10pm,
            NotificationID.appStreak1130pm
        ])
    }
    
    // MARK: - Schedule Nutrition Reminders
    
    static func scheduleNutritionReminders(macrosHit: Bool) {
        cancelNutritionReminders()
        
        guard !macrosHit else { return }
        
        let today = Calendar.current.startOfDay(for: Date())
        
        // 6 PM reminder
        scheduleNotification(
            id: NotificationID.nutrition6pm,
            title: "Hit your macros today! 🥗",
            body: "Log your remaining meals to keep your nutrition streak alive.",
            date: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: today)!
        )
        
        // 8 PM reminder
        scheduleNotification(
            id: NotificationID.nutrition8pm,
            title: "⚠️ Macros at risk!",
            body: "Still time to hit your targets. Tap to log food.",
            date: Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: today)!
        )
    }
    
    static func cancelNutritionReminders() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            NotificationID.nutrition6pm,
            NotificationID.nutrition8pm
        ])
    }
    
    // MARK: - Schedule Weekly Win Reminders
    
    static func scheduleWeeklyWinReminder(workoutsDone: Int, goal: Int, daysLeftInWindow: Int) {
        cancelWeeklyWinReminders()
        
        // Calculate if behind pace
        let workoutsNeeded = goal - workoutsDone
        let expectedPace = Double(goal) / 7.0
        let currentPace = Double(workoutsDone) / Double(7 - daysLeftInWindow)
        
        guard currentPace < expectedPace && workoutsNeeded > 0 else { return }
        
        // Schedule for 10 AM tomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let notificationDate = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow)!
        
        scheduleNotification(
            id: NotificationID.weeklyWin,
            title: "Time to train! 💪",
            body: "You need \(workoutsNeeded) more workout\(workoutsNeeded > 1 ? "s" : "") to hit your weekly goal.",
            date: notificationDate
        )
    }
    
    static func cancelWeeklyWinReminders() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            NotificationID.weeklyWin
        ])
    }
    
    // MARK: - Helper
    
    private static func scheduleNotification(id: String, title: String, body: String, date: Date) {
        // Don't schedule if date is in the past
        guard date > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "STREAK_REMINDER"
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
}
```

---

## Phase 8: Longest Streaks & History

### Display in Streak Detail View

```swift
struct EnhancedStreakDetailView: View {
    @ObservedObject var streakStore = StreakStore.shared
    @Environment(\.dismiss) private var dismiss
    
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
                        workoutsThisWeek: streakStore.weeklyWin.workoutsThisWindow.count,
                        pendingGoalChange: streakStore.weeklyWin.pendingGoalChange,
                        status: streakStore.weeklyWinStatus
                    )
                    
                    // Motivational section
                    StreakMilestoneView(
                        appStreak: streakStore.appStreak.currentStreak,
                        nutritionStreak: streakStore.nutritionStreak.currentStreak,
                        weeklyWins: streakStore.weeklyWin.weeklyWinCount
                    )
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
}

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
                    Text(StreakCountdown.format(time))
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            
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
                    if let startDate = streakStartDate {
                        Text("Since \(formatDate(startDate))")
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
                    if let start = longestStartDate, let end = longestEndDate {
                        Text("\(formatDate(start)) – \(formatDate(end))")
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
    
    private func formatDate(_ dateKey: String) -> String {
        // Convert "yyyy-MM-dd" to "Jan 15"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateKey) else { return dateKey }
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
```

---

## UI/UX Components

### Updated StreakBadge (Home Screen)

Replace the existing `StreakBadge` with an enhanced version that shows:

1. **Primary**: App Streak (most important)
2. **Mini indicators**: Nutrition streak + Weekly Win progress
3. **Countdown**: If any streak is at risk
4. **Tap to expand**: Full streak detail sheet

```swift
struct EnhancedStreakBadge: View {
    @ObservedObject var streakStore = StreakStore.shared
    let onTap: () -> Void
    
    @State private var isAnimating = false
    
    private var atRiskCount: Int {
        var count = 0
        if streakStore.appStreakStatus.isAtRisk { count += 1 }
        if streakStore.nutritionStreakStatus.isAtRisk { count += 1 }
        if streakStore.weeklyWinStatus.isAtRisk { count += 1 }
        return count
    }
    
    private var mostUrgentCountdown: TimeInterval? {
        var times: [TimeInterval] = []
        if case .atRisk(let t) = streakStore.appStreakStatus { times.append(t) }
        if case .atRisk(let t) = streakStore.nutritionStreakStatus { times.append(t) }
        if case .atRisk(let t) = streakStore.weeklyWinStatus { times.append(t) }
        return times.min()
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Main streak display
                HStack(spacing: 12) {
                    // Flame icon
                    ZStack {
                        Circle()
                            .fill(FitTheme.streakGradient)
                            .frame(width: 44, height: 44)
                            .shadow(color: .orange.opacity(0.4), radius: 8)
                        
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
                        MiniStreakIndicator(
                            icon: "trophy.fill",
                            count: streakStore.weeklyWin.weeklyWinCount,
                            color: FitTheme.cardWorkoutAccent,
                            isAtRisk: streakStore.weeklyWinStatus.isAtRisk,
                            showProgress: true,
                            progress: "\(streakStore.weeklyWin.workoutsThisWindow.count)/\(streakStore.weeklyWin.weeklyGoal)"
                        )
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                // Countdown warning if at risk
                if atRiskCount > 0, let countdown = mostUrgentCountdown {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                        
                        if atRiskCount > 1 {
                            Text("\(atRiskCount) streaks at risk • \(StreakCountdown.format(countdown))")
                        } else {
                            Text("\(StreakCountdown.format(countdown)) to save your streak")
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
                        ? [Color.red.opacity(0.05), Color(red: 1.0, green: 0.96, blue: 0.88)]
                        : [Color(red: 1.0, green: 0.98, blue: 0.92), Color(red: 1.0, green: 0.96, blue: 0.88)],
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
```

---

## Backend Changes

### New API Endpoints (Optional)

For AI coach response on daily check-in:

```python
# routers/daily_checkin.py

from fastapi import APIRouter
from pydantic import BaseModel
from ..prompts import run_simple_prompt

router = APIRouter()

class DailyCheckInRequest(BaseModel):
    user_id: str
    hit_macros: bool
    training_status: str  # "trained" or "off_day"
    sleep_quality: str    # "good", "okay", "poor"

class DailyCheckInResponse(BaseModel):
    coach_response: str
    streak_saved: bool

DAILY_CHECKIN_PROMPT = """
You are FitAI Coach. A user just completed their daily check-in.

Check-in data:
- Hit macros yesterday: {hit_macros}
- Training: {training_status}
- Sleep quality: {sleep_quality}

Respond with ONE short motivational sentence (15-20 words max).
Be encouraging and acknowledge their honest answers.
If they didn't hit macros or had poor sleep, be supportive not critical.
Use a casual, friendly tone like a gym buddy.
"""

@router.post("/daily-checkin", response_model=DailyCheckInResponse)
async def submit_daily_checkin(request: DailyCheckInRequest):
    prompt = DAILY_CHECKIN_PROMPT.format(
        hit_macros="Yes" if request.hit_macros else "No",
        training_status=request.training_status.replace("_", " "),
        sleep_quality=request.sleep_quality
    )
    
    coach_response = run_simple_prompt(prompt)
    
    return DailyCheckInResponse(
        coach_response=coach_response,
        streak_saved=True
    )
```

---

## Migration Strategy

### From Existing Streak System

1. **Keep backward compatibility** - Don't delete old `WorkoutStreakStore` immediately
2. **Migrate data on first launch**:
   ```swift
   func migrateFromLegacyStreaks() {
       // Migrate old workout streak to Weekly Win initial count
       let oldWorkoutStreak = WorkoutStreakStore.current()
       if oldWorkoutStreak > 0 {
           weeklyWin.weeklyWinCount = oldWorkoutStreak / 7 // Rough conversion
       }
       
       // Migrate old app open streak to App Streak
       if let oldAppStreak = UserDefaults.standard.integer(forKey: "fitai.appOpen.streak") as Int?, oldAppStreak > 0 {
           appStreak.currentStreak = oldAppStreak
           appStreak.longestStreak = oldAppStreak
       }
       
       // Mark migration complete
       UserDefaults.standard.set(true, forKey: "fitai.streak.migrated.v2")
   }
   ```

3. **Historical data**: Start fresh from implementation date (simplest approach)

---

## Testing Plan

### Unit Tests

1. **Streak Calculations**
   - Test midnight boundary detection
   - Test timezone handling (simulate different timezones)
   - Test macro hit calculation (edge cases at ±15%)
   - Test rolling 7-day window pruning

2. **Streak State Transitions**
   - Streak increment on consecutive days
   - Streak reset on missed day
   - Longest streak update
   - Weekly goal change queue

### Integration Tests

1. **Daily Check-In Flow**
   - Complete check-in saves streak
   - AI response returns correctly
   - Notification canceled after completion

2. **Nutrition Streak Auto-Detection**
   - Logging food triggers streak check
   - Hitting macros credits streak
   - Missing target doesn't credit

3. **Weekly Win Logic**
   - Workout logged adds to window
   - Goal met triggers win celebration
   - Goal not met resets win streak

### UI Tests

1. **Countdown Timer**
   - Timer updates in real-time
   - Urgency colors change correctly
   - Pulse animation at critical level

2. **Save Your Streak Mode**
   - Triggers at <6 hours remaining
   - Shows correct actions for each streak type
   - Dismisses after action complete

3. **Notifications**
   - Scheduled at correct times
   - Canceled when streak saved
   - Correct content for each streak type

---

## File Summary

### New Files to Create

| File | Location | Purpose |
|------|----------|---------|
| `StreakModels.swift` | `FIT AI/` | All streak data models |
| `StreakStore.swift` | `FIT AI/` | Central streak manager |
| `StreakCalculations.swift` | `FIT AI/` | Date/time utilities |
| `StreakNotifications.swift` | `FIT AI/` | Local notification handling |
| `DailyCheckInView.swift` | `FIT AI/` | Check-in form UI |
| `DailyCheckInViewModel.swift` | `FIT AI/` | Check-in logic |
| `SaveYourStreakView.swift` | `FIT AI/` | Urgency mode UI |
| `StreakCountdownView.swift` | `FIT AI/` | Countdown timer component |
| `EnhancedStreakDetailView.swift` | `FIT AI/` | Full streak details sheet |
| `WeeklyWinDetailCard.swift` | `FIT AI/` | Weekly win UI component |
| `daily_checkin.py` | `backend/app/routers/` | AI coach response endpoint |

### Files to Modify

| File | Changes |
|------|---------|
| `HomeView.swift` | Integrate new StreakStore, add Save Your Streak mode trigger |
| `WorkoutStreakStore.swift` | Deprecate, keep for migration |
| `NutritionViewModel.swift` | Call streak check on food log |
| `WorkoutFlows.swift` | Call streak store on workout complete |
| `FIT_AIApp.swift` | Initialize StreakStore, request notifications |
| `main.py` | Register daily_checkin router |

---

## Estimated Timeline

| Phase | Duration | Dependency |
|-------|----------|------------|
| Phase 1: Core Infrastructure | 2-3 days | None |
| Phase 2: Daily Check-In | 2-3 days | Phase 1 |
| Phase 3: Nutrition Streak | 1-2 days | Phase 1 |
| Phase 4: Weekly Win | 2-3 days | Phase 1 |
| Phase 5: Countdown UI | 1-2 days | Phases 2-4 |
| Phase 6: Save Your Streak | 1-2 days | Phase 5 |
| Phase 7: Notifications | 1-2 days | Phases 2-4 |
| Phase 8: History/Longest | 1 day | Phases 2-4 |

**Total: ~12-18 days**

---

## Questions for Review

Before implementation, confirm:

1. ✅ Daily Check-In is separate from Weekly Check-In (confirmed)
2. ✅ Macro tolerance is ±15% for all macros (confirmed)
3. ✅ Rolling 7-day window, resets on miss (confirmed)
4. ✅ Goal changes apply next week with notification (confirmed)
5. ✅ Auto-detect device timezone (confirmed)
6. ✅ Multiple streaks at risk shows combined message (confirmed)
7. ✅ Local notifications only (confirmed)
8. ✅ On-device storage (confirmed)
9. ✅ Start fresh from implementation date (recommended)

---

Ready to proceed with implementation when you give the go-ahead! 🚀


