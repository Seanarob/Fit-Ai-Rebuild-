import Foundation
import SwiftUI

// MARK: - Streak Types

enum StreakType: String, CaseIterable, Identifiable {
    case app = "app"
    case nutrition = "nutrition"
    case weeklyWin = "weekly_win"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .app: return "App"
        case .nutrition: return "Nutrition"
        case .weeklyWin: return "Weekly Win"
        }
    }
    
    var icon: String {
        switch self {
        case .app: return "flame.fill"
        case .nutrition: return "fork.knife"
        case .weeklyWin: return "trophy.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .app: return Color.orange
        case .nutrition: return Color(red: 0.98, green: 0.55, blue: 0.48)
        case .weeklyWin: return Color(red: 0.35, green: 0.48, blue: 0.95)
        }
    }
}

// MARK: - App Streak Data

struct AppStreakData: Codable, Equatable {
    var currentStreak: Int
    var longestStreak: Int
    var lastCompletedDate: String?
    var longestStreakStartDate: String?
    var longestStreakEndDate: String?
    var streakStartDate: String?
    
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

struct NutritionStreakData: Codable, Equatable {
    var currentStreak: Int
    var longestStreak: Int
    var lastHitDate: String?
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

struct WeeklyWinData: Codable, Equatable {
    var weeklyWinCount: Int
    var longestWinStreak: Int
    var currentWinStreak: Int
    var weeklyGoal: Int
    var pendingGoalChange: Int?
    var workoutsThisWindow: [String]
    var lastWinDate: String?
    var longestWinStreakStartDate: String?
    var longestWinStreakEndDate: String?
    var winStreakStartDate: String?
    
    static let empty = WeeklyWinData(
        weeklyWinCount: 0,
        longestWinStreak: 0,
        currentWinStreak: 0,
        weeklyGoal: 5,
        pendingGoalChange: nil,
        workoutsThisWindow: [],
        lastWinDate: nil,
        longestWinStreakStartDate: nil,
        longestWinStreakEndDate: nil,
        winStreakStartDate: nil
    )
}

// MARK: - Daily Check-In Data

struct DailyCheckInData: Codable, Equatable {
    var hitMacros: Bool?
    var trainingStatus: TrainingStatus?
    var sleepQuality: SleepQuality?
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
        
        var icon: String {
            switch self {
            case .trained: return "figure.run"
            case .offDay: return "bed.double.fill"
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
    
    var isComplete: Bool {
        hitMacros != nil && trainingStatus != nil && sleepQuality != nil
    }
    
    static let empty = DailyCheckInData(
        hitMacros: nil,
        trainingStatus: nil,
        sleepQuality: nil,
        completedAt: nil,
        coachResponse: nil
    )
}

// MARK: - Streak Status

enum StreakStatus: Equatable {
    case safe
    case atRisk(timeRemaining: TimeInterval)
    case lost
    
    var isAtRisk: Bool {
        if case .atRisk = self { return true }
        return false
    }
    
    var isSafe: Bool {
        if case .safe = self { return true }
        return false
    }
}

// MARK: - Macro Status

struct MacroStatus: Equatable {
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

struct MacroBreakdown: Equatable {
    let calories: MacroStatus
    let protein: MacroStatus
    let carbs: MacroStatus
    let fats: MacroStatus
    
    var allHit: Bool {
        calories.isHit && protein.isHit && carbs.isHit && fats.isHit
    }
}

// MARK: - Urgency Level

enum UrgencyLevel {
    case low
    case medium
    case high
    case critical
    
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

// MARK: - Notification Names

extension Notification.Name {
    static let fitAIAppStreakUpdated = Notification.Name("fitai.streak.app.updated")
    static let fitAINutritionStreakHit = Notification.Name("fitai.streak.nutrition.hit")
    static let fitAIWeeklyWinAchieved = Notification.Name("fitai.streak.weeklywin.achieved")
    static let fitAIStreakAtRisk = Notification.Name("fitai.streak.atrisk")
    static let fitAIStreakLost = Notification.Name("fitai.streak.lost")
    static let fitAIDailyCheckInCompleted = Notification.Name("fitai.checkin.completed")
}


