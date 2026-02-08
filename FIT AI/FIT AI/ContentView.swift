import SwiftUI

struct ContentView: View {
    @AppStorage("fitai.auth.userId") private var userId = ""

    var body: some View {
        NavigationStack {
            if userId.isEmpty {
                OnboardingReplicaView()
            } else {
                MainTabView(userId: userId)
            }
        }
        .dismissKeyboardOnTap()
        .task(id: userId) {
            await syncOnboardingStateIfNeeded(userId: userId)
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


