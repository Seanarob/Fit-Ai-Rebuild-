import Foundation
import SwiftUI

// MARK: - Codable Wrappers for Workout Session Persistence

/// Codable version of WorkoutSetEntry for persistence
struct PersistedSetEntry: Codable, Identifiable {
    let id: UUID
    var reps: String
    var weight: String
    var isComplete: Bool
    var isWarmup: Bool
    var isDropSet: Bool
    
    init(from entry: WorkoutSetEntry) {
        self.id = entry.id
        self.reps = entry.reps
        self.weight = entry.weight
        self.isComplete = entry.isComplete
        self.isWarmup = entry.isWarmup
        self.isDropSet = entry.isDropSet
    }
    
    func toWorkoutSetEntry() -> WorkoutSetEntry {
        WorkoutSetEntry(
            reps: reps,
            weight: weight,
            isComplete: isComplete,
            isWarmup: isWarmup,
            isDropSet: isDropSet
        )
    }
}

/// Codable version of WorkoutExerciseSession for persistence
struct PersistedExerciseSession: Codable, Identifiable {
    let id: UUID
    var name: String
    var sets: [PersistedSetEntry]
    var restSeconds: Int
    var warmupRestSeconds: Int?
    var notes: String
    var unit: String // WeightUnit rawValue
    var recommendationPreference: String // ExerciseRecommendationPreference rawValue
    
    init(from session: WorkoutExerciseSession) {
        self.id = session.id
        self.name = session.name
        self.sets = session.sets.map { PersistedSetEntry(from: $0) }
        self.restSeconds = session.restSeconds
        self.warmupRestSeconds = session.warmupRestSeconds
        self.notes = session.notes
        self.unit = session.unit.rawValue
        self.recommendationPreference = session.recommendationPreference.rawValue
    }
    
    func toWorkoutExerciseSession() -> WorkoutExerciseSession {
        var session = WorkoutExerciseSession(
            name: name,
            sets: sets.map { $0.toWorkoutSetEntry() },
            restSeconds: restSeconds,
            notes: notes,
            unit: WeightUnit(rawValue: unit) ?? .lb,
            recommendationPreference: ExerciseRecommendationPreference(rawValue: recommendationPreference) ?? .none
        )
        session.warmupRestSeconds = warmupRestSeconds ?? min(60, restSeconds)
        return session
    }
}

/// Full persisted workout session state
struct PersistedWorkoutSession: Codable {
    let sessionId: String?
    let title: String
    let exercises: [PersistedExerciseSession]
    let workoutElapsed: Int
    let isPaused: Bool
    let restRemaining: Int
    let restActive: Bool
    let startedAt: Date
    let lastSavedAt: Date
    
    init(
        sessionId: String?,
        title: String,
        exercises: [WorkoutExerciseSession],
        workoutElapsed: Int,
        isPaused: Bool,
        restRemaining: Int,
        restActive: Bool,
        startedAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.title = title
        self.exercises = exercises.map { PersistedExerciseSession(from: $0) }
        self.workoutElapsed = workoutElapsed
        self.isPaused = isPaused
        self.restRemaining = restRemaining
        self.restActive = restActive
        self.startedAt = startedAt
        self.lastSavedAt = Date()
    }
}

// MARK: - Workout Session Store

/// Manages persistence of active workout sessions to prevent data loss
enum WorkoutSessionStore {
    private static let storageKey = "fitai.activeWorkoutSession"
    private static let backupKey = "fitai.activeWorkoutSession.backup"
    
    // MARK: - Save
    
    /// Save current workout session state
    static func save(
        sessionId: String?,
        title: String,
        exercises: [WorkoutExerciseSession],
        workoutElapsed: Int,
        isPaused: Bool,
        restRemaining: Int,
        restActive: Bool
    ) {
        let session = PersistedWorkoutSession(
            sessionId: sessionId,
            title: title,
            exercises: exercises,
            workoutElapsed: workoutElapsed,
            isPaused: isPaused,
            restRemaining: restRemaining,
            restActive: restActive
        )
        
        guard let data = try? JSONEncoder().encode(session) else {
            debugLog("Failed to encode workout session for save")
            return
        }
        
        // Save to primary and backup
        UserDefaults.standard.set(data, forKey: storageKey)
        UserDefaults.standard.set(data, forKey: backupKey)
        debugLog("Saved workout session: \(title), \(exercises.count) exercises, \(workoutElapsed)s elapsed")
    }
    
    // MARK: - Load
    
    /// Load saved workout session if exists
    static func load() -> PersistedWorkoutSession? {
        // Try primary first
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let session = try? JSONDecoder().decode(PersistedWorkoutSession.self, from: data) {
            debugLog("Loaded workout session from primary: \(session.title)")
            return session
        }
        
        // Fall back to backup
        if let data = UserDefaults.standard.data(forKey: backupKey),
           let session = try? JSONDecoder().decode(PersistedWorkoutSession.self, from: data) {
            debugLog("Loaded workout session from backup: \(session.title)")
            return session
        }
        
        debugLog("No saved workout session found")
        return nil
    }
    
    /// Check if there's a saved session available
    static func hasSavedSession() -> Bool {
        return UserDefaults.standard.data(forKey: storageKey) != nil ||
               UserDefaults.standard.data(forKey: backupKey) != nil
    }
    
    // MARK: - Clear
    
    /// Clear saved workout session (call when workout is completed or discarded)
    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: backupKey)
        debugLog("Cleared saved workout session")
    }
    
    // MARK: - Recovery Check
    
    /// Check if the saved session is recent enough to recover (within 24 hours)
    static func hasRecoverableSession() -> Bool {
        guard let session = load() else { return false }
        let timeSinceSave = Date().timeIntervalSince(session.lastSavedAt)
        let maxRecoveryWindow: TimeInterval = 24 * 60 * 60 // 24 hours
        return timeSinceSave < maxRecoveryWindow
    }
    
    /// Get info about recoverable session for display
    static func getRecoveryInfo() -> (title: String, exerciseCount: Int, elapsed: Int, savedAt: Date)? {
        guard let session = load() else { return nil }
        return (
            title: session.title,
            exerciseCount: session.exercises.count,
            elapsed: session.workoutElapsed,
            savedAt: session.lastSavedAt
        )
    }
    
    // MARK: - Debug
    
    private static func debugLog(_ message: String) {
        #if DEBUG
        let stamp = ISO8601DateFormatter().string(from: Date())
        print("[WorkoutSessionStore] \(stamp) \(message)")
        #endif
    }
}

// MARK: - Notification for Session Recovery

extension Notification.Name {
    static let fitAIWorkoutSessionRecoveryAvailable = Notification.Name("fitai.workout.session.recoveryAvailable")
}
