import Foundation
import Combine
import HealthKit

final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    @Published private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private init() {
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        guard isHealthDataAvailable else {
            authorizationStatus = .notDetermined
            return
        }
        authorizationStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
    }

    @MainActor
    func requestAuthorization() async -> Bool {
        guard isHealthDataAvailable else { return false }
        return await withCheckedContinuation { continuation in
            let readTypes: Set<HKObjectType> = [HKObjectType.workoutType()]
            healthStore.requestAuthorization(toShare: Set<HKSampleType>(), read: readTypes) { success, _ in
                DispatchQueue.main.async { [weak self] in
                    self?.refreshAuthorizationStatus()
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func syncWorkoutsIfEnabled() async -> [HealthWorkout] {
        guard HealthSyncState.shared.isEnabled else { return [] }
        guard isHealthDataAvailable else { return [] }
        await MainActor.run {
            self.refreshAuthorizationStatus()
        }
        guard authorizationStatus == .sharingAuthorized else { return [] }

        let since = HealthSyncState.shared.lastSyncDate
            ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())

        do {
            let workouts = try await fetchWorkouts(since: since)
            let newWorkouts = HealthWorkoutStore.merge(workouts)
            await MainActor.run {
                HealthSyncState.shared.lastSyncDate = Date()
            }
            Task { @MainActor in
                self.applyWorkoutsToStreak(newWorkouts)
            }
            return newWorkouts
        } catch {
            return []
        }
    }

    func fetchWorkouts(since: Date?) async throws -> [HealthWorkout] {
        guard isHealthDataAvailable else { return [] }
        let workoutType = HKObjectType.workoutType()
        let predicate = since.map { HKQuery.predicateForSamples(withStart: $0, end: nil, options: .strictStartDate) }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: 200, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                let mapped = workouts.map { workout in
                    HealthWorkout(
                        id: workout.uuid.uuidString,
                        activityType: workout.workoutActivityType.displayName,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        durationSeconds: Int(workout.duration),
                        energyBurned: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        sourceName: workout.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: mapped)
            }
            healthStore.execute(query)
        }
    }

    @MainActor
    private func applyWorkoutsToStreak(_ workouts: [HealthWorkout]) {
        guard !workouts.isEmpty else { return }
        let streakStore = StreakStore.shared
        workouts.forEach { workout in
            streakStore.recordWorkout(date: workout.startDate)
        }

        let hasToday = workouts.contains { Calendar.current.isDateInToday($0.startDate) }
        guard hasToday, WorkoutCompletionStore.todaysCompletion() == nil else { return }

        let exercises = workouts
            .filter { Calendar.current.isDateInToday($0.startDate) }
            .map { $0.activityType }

        WorkoutCompletionStore.markCompleted(exercises: exercises, date: Date())
        let updatedStreak = WorkoutStreakStore.update(for: Date())
        NotificationCenter.default.post(
            name: .fitAIWorkoutStreakUpdated,
            object: nil,
            userInfo: ["streak": updatedStreak]
        )
    }
}

private extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining: return "Functional Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "Yoga"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        case .coreTraining: return "Core Training"
        case .flexibility: return "Flexibility"
        case .mindAndBody: return "Mind & Body"
        default: return "Workout"
        }
    }
}
