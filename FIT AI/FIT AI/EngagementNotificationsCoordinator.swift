import Combine
import Foundation

@MainActor
final class EngagementNotificationsCoordinator {
    static let shared = EngagementNotificationsCoordinator()

    private var cancellables = Set<AnyCancellable>()
    private var currentUserId = ""
    private var hasStarted = false

    private init() {}

    func configure(userId: String) {
        currentUserId = userId
        guard !hasStarted else {
            Task { await EngagementNotifications.refreshSchedule(userId: userId) }
            return
        }
        hasStarted = true
        startObservers()
        Task { await EngagementNotifications.refreshSchedule(userId: userId) }
    }

    private func startObservers() {
        NotificationCenter.default.publisher(for: .fitAINutritionLogged)
            .sink { [weak self] notification in
                guard let self else { return }
                Task { @MainActor in
                    self.handleNutritionLogged(notification)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .fitAIMacrosUpdated)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await EngagementNotifications.handleMacrosUpdated()
                    await EngagementNotifications.refreshSchedule(userId: self.currentUserId)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .fitAISplitUpdated)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await EngagementNotifications.handleProgressUpdate()
                    await EngagementNotifications.refreshSchedule(userId: self.currentUserId)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .fitAIDailyCheckInCompleted)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await EngagementNotifications.handleProgressUpdate()
                    await EngagementNotifications.refreshSchedule(userId: self.currentUserId)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .fitAIWorkoutCompleted)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await EngagementNotifications.handleNiceWorkToday()
                    await EngagementNotifications.refreshSchedule(userId: self.currentUserId)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .fitAINewPR)
            .sink { _ in
                Task { @MainActor in
                    await EngagementNotifications.handleStrengthClimbing()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .fitAINutritionStreakHit)
            .sink { _ in
                Task { @MainActor in
                    await EngagementNotifications.handleRecapReady()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .fitAITodayTrainingUpdated)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await EngagementNotifications.refreshSchedule(userId: self.currentUserId)
                }
            }
            .store(in: &cancellables)
    }

    private func handleNutritionLogged(_ notification: Notification) {
        let logDateKey = (notification.userInfo?["logDate"] as? String) ?? StreakCalculations.localDateKey()
        EngagementNotifications.updateLastNutritionLog(dateKey: logDateKey)
        Task { @MainActor in
            await EngagementNotifications.rescheduleNutritionNudges(userId: currentUserId)
        }
    }
}

