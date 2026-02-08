//
//  FIT_AIApp.swift
//  FIT AI
//
//  Created by Sean Robinson on 1/6/26.
//

import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private func shouldSuppressForegroundNotification(_ notification: UNNotification) -> Bool {
        let content = notification.request.content
        var tokens: [String] = [
            content.title,
            content.body,
            content.categoryIdentifier,
            content.threadIdentifier
        ]

        let userInfo = content.userInfo
        let infoKeys = ["type", "event", "kind", "notification_type", "category", "topic"]
        for key in infoKeys {
            if let value = userInfo[key] as? String {
                tokens.append(value)
            }
        }

        let normalized = tokens.joined(separator: " ").lowercased()
        let hasWorkout = normalized.contains("workout")
        let hasCompletion = normalized.contains("complete")
            || normalized.contains("completed")
            || normalized.contains("completion")
            || normalized.contains("finished")
        return hasWorkout && hasCompletion
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        
        // Setup notification categories for streak reminders
        StreakNotifications.setupNotificationCategories()
        
        // Request notification permissions
        Task {
            _ = await StreakNotifications.requestPermissions()
        }
        
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if shouldSuppressForegroundNotification(notification) {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle streak notification actions
        let actionId = response.actionIdentifier
        
        switch actionId {
        case "CHECK_IN_ACTION":
            NotificationCenter.default.post(name: .fitAIOpenCheckIn, object: nil)
        case "LOG_FOOD_ACTION":
            NotificationCenter.default.post(name: .fitAIOpenNutrition, object: nil)
        case "START_WORKOUT_ACTION":
            NotificationCenter.default.post(name: .fitAIOpenWorkout, object: nil)
        default:
            break
        }
        
        completionHandler()
    }
}

// MARK: - App Navigation Notifications

extension Notification.Name {
    static let fitAIOpenCheckIn = Notification.Name("fitai.open.checkin")
    static let fitAIOpenNutrition = Notification.Name("fitai.open.nutrition")
    static let fitAIOpenWorkout = Notification.Name("fitai.open.workout")
}

@main
struct FIT_AIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Initialize StreakStore singleton early
    private let streakStore = StreakStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Schedule streak notifications on app launch
                    streakStore.scheduleStreakNotifications()
                }
        }
    }
}
