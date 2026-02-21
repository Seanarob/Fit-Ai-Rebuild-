import SwiftUI
import PostHog

struct ContentView: View {
    @AppStorage("fitai.auth.userId") private var userId = ""
    @StateObject private var guidedTour = GuidedTourCoordinator()
    @State private var previousUserId = ""

    var body: some View {
        NavigationStack {
            if userId.isEmpty {
                OnboardingReplicaView()
            } else {
                MainTabView(userId: userId)
                    .environmentObject(guidedTour)
            }
        }
        .dismissKeyboardOnTap()
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .task(id: userId) {
            guidedTour.setActiveUserId(userId)

            if userId.isEmpty {
                PostHogSDK.shared.reset()
            } else {
                PostHogSDK.shared.identify(userId)
            }

            await syncOnboardingStateIfNeeded(userId: userId)
            EngagementNotificationsCoordinator.shared.configure(userId: userId)
        }
        .onAppear {
            if previousUserId.isEmpty {
                previousUserId = userId
            }
            guidedTour.setActiveUserId(userId)
        }
        .onChange(of: userId) { newValue in
            let oldValue = previousUserId
            previousUserId = newValue
            guidedTour.setActiveUserId(newValue)

            if newValue.isEmpty {
                PostHogSDK.shared.reset()
            } else if oldValue != newValue {
                if oldValue.isEmpty {
                    // Link pre-login events to the logged-in user.
                    PostHogSDK.shared.alias(newValue)
                } else {
                    // Account switch: clear old identity and start fresh.
                    PostHogSDK.shared.reset()
                    PostHogSDK.shared.alias(newValue)
                }
                PostHogSDK.shared.identify(newValue)
            }

            if oldValue.isEmpty && !newValue.isEmpty {
                guidedTour.queueOnboardingTourIfNeeded(for: newValue)
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "fitai" else { return }

        let host = (url.host ?? "").lowercased()
        if host == "login-callback" {
            Task {
                do {
                    let session = try await SupabaseService.shared.handleAuthCallback(url: url)
                    let resolvedUserId = SupabaseService.shared.getUserId(from: session)
                    if !resolvedUserId.isEmpty {
                        userId = resolvedUserId
                    }
                } catch {
                    // Ignore auth callback failures here; onboarding views also handle callbacks.
                }
            }
            return
        }

        let destination: FitDeepLinkDestination?
        switch host {
        case "home":
            destination = .home
        case "coach":
            destination = .coach
        case "workout":
            destination = .workout
        case "nutrition":
            destination = .nutrition
        case "progress":
            destination = .progress
        case "checkin":
            destination = .checkin
        default:
            destination = nil
        }

        guard let destination else { return }
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

    private func syncOnboardingStateIfNeeded(userId: String) async {
        guard !userId.isEmpty else { return }
        if let data = UserDefaults.standard.data(forKey: "fitai.onboarding.form"),
           let existing = try? JSONDecoder().decode(OnboardingForm.self, from: data),
           existing.userId == userId {
            return
        }
        do {
            guard var fetched = try await OnboardingAPIService.shared.fetchState(userId: userId) else { return }
            if fetched.userId == nil {
                fetched.userId = userId
            }
            guard let encoded = try? JSONEncoder().encode(fetched) else { return }
            UserDefaults.standard.set(encoded, forKey: "fitai.onboarding.form")
            NotificationCenter.default.post(name: .fitAIMacrosUpdated, object: nil)
            NotificationCenter.default.post(name: .fitAIProfileUpdated, object: nil)
        } catch {
            // Ignore onboarding sync failures on launch.
        }
    }
}

#Preview {
    ContentView()
}
