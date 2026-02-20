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
    private func configureAppearance() {
        let chrome = UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1.0)
            }
            return UIColor(red: 0.98, green: 0.96, blue: 0.94, alpha: 1.0)
        }
        let selected = UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(red: 0.22, green: 0.50, blue: 1.0, alpha: 1.0)
            }
            return UIColor(red: 0.29, green: 0.18, blue: 1.0, alpha: 1.0)
        }
        let normal = UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(red: 0.56, green: 0.60, blue: 0.68, alpha: 1.0)
            }
            return UIColor(red: 0.45, green: 0.40, blue: 0.37, alpha: 1.0)
        }
        let titleText = UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(red: 0.96, green: 0.97, blue: 1.0, alpha: 1.0)
            }
            return UIColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 1.0)
        }
        let separator = UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.06)
            }
            return UIColor.black.withAlphaComponent(0.12)
        }

        let tabItemAppearance = UITabBarItemAppearance(style: .stacked)
        tabItemAppearance.normal.iconColor = normal
        tabItemAppearance.normal.titleTextAttributes = [.foregroundColor: normal]
        tabItemAppearance.selected.iconColor = selected
        tabItemAppearance.selected.titleTextAttributes = [.foregroundColor: selected]

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = chrome
        tabBarAppearance.shadowColor = separator
        tabBarAppearance.stackedLayoutAppearance = tabItemAppearance
        tabBarAppearance.inlineLayoutAppearance = tabItemAppearance
        tabBarAppearance.compactInlineLayoutAppearance = tabItemAppearance
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        UITabBar.appearance().unselectedItemTintColor = normal
        UITabBar.appearance().tintColor = selected

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = chrome
        navAppearance.shadowColor = UIColor.clear
        navAppearance.titleTextAttributes = [.foregroundColor: titleText]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: titleText]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = selected

        UISegmentedControl.appearance().selectedSegmentTintColor = selected
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: normal], for: .normal)
    }

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
        configureAppearance()
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
        // Handle notification actions + deep links
        let actionId = response.actionIdentifier
        
        switch actionId {
        case "CHECK_IN_ACTION":
            DeepLinkStore.setDestination(.checkin)
            NotificationCenter.default.post(name: .fitAIOpenCheckIn, object: nil)
        case "LOG_FOOD_ACTION":
            DeepLinkStore.setDestination(.nutrition)
            NotificationCenter.default.post(name: .fitAIOpenNutrition, object: nil)
        case "START_WORKOUT_ACTION":
            DeepLinkStore.setDestination(.workout)
            NotificationCenter.default.post(name: .fitAIOpenWorkout, object: nil)
        case "fitai.rest.skip":
            NotificationCenter.default.post(name: .fitAIRestTimerSkip, object: nil)
        case "fitai.rest.add30":
            NotificationCenter.default.post(name: .fitAIRestTimerAdd30, object: nil)
        default:
            if actionId == UNNotificationDefaultActionIdentifier {
                handleDeepLink(userInfo: response.notification.request.content.userInfo)
            }
            break
        }
        
        completionHandler()
    }

    private func handleDeepLink(userInfo: [AnyHashable: Any]) {
        guard let destinationRaw = userInfo["destination"] as? String,
              let destination = FitDeepLinkDestination(rawValue: destinationRaw) else {
            return
        }
        DeepLinkStore.setDestination(destination)
        switch destination {
        case .home:
            NotificationCenter.default.post(name: .fitAIOpenHome, object: nil)
        case .coach:
            NotificationCenter.default.post(name: .fitAIOpenCoach, object: nil)
        case .workout:
            NotificationCenter.default.post(name: .fitAIOpenWorkout, object: nil)
        case .nutrition:
            NotificationCenter.default.post(name: .fitAIOpenNutrition, object: nil)
        case .progress:
            NotificationCenter.default.post(name: .fitAIOpenProgress, object: nil)
        case .checkin:
            NotificationCenter.default.post(name: .fitAIOpenCheckIn, object: nil)
        }
    }
}

// MARK: - App Navigation Notifications

extension Notification.Name {
    static let fitAIOpenHome = Notification.Name("fitai.open.home")
    static let fitAIOpenCheckIn = Notification.Name("fitai.open.checkin")
    static let fitAIOpenNutrition = Notification.Name("fitai.open.nutrition")
    static let fitAIOpenWorkout = Notification.Name("fitai.open.workout")
    static let fitAIOpenCoach = Notification.Name("fitai.open.coach")
    static let fitAIOpenProgress = Notification.Name("fitai.open.progress")
    static let fitAIRestTimerSkip = Notification.Name("fitai.rest.timer.skip")
    static let fitAIRestTimerAdd30 = Notification.Name("fitai.rest.timer.add30")
}

@main
struct FIT_AIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system
    
    // Initialize StreakStore singleton early
    private let streakStore = StreakStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appAppearance.colorScheme)
                .onAppear {
                    // Schedule streak notifications on app launch
                    streakStore.scheduleStreakNotifications()
                }
        }
    }
}
