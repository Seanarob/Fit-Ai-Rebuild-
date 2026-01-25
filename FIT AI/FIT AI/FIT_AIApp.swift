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
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct FIT_AIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        FitFont.registerFonts()
        let normalText = UIColor(FitTheme.textSecondary)
        let selectedText = UIColor(FitTheme.textPrimary)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: normalText], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: selectedText], for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Handle OAuth callback from Google sign-in
                    if url.scheme == "fitai" && url.host == "login-callback" {
                        Task { @MainActor in
                            if let viewModel = OnboardingViewModel.shared {
                                await viewModel.handleAuthCallback(url: url)
                            }
                        }
                    }
                }
        }
    }
}
