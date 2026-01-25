import SwiftUI

struct ContentView: View {
    @AppStorage("fitai.auth.userId") private var userId = ""

    var body: some View {
        NavigationStack {
            if userId.isEmpty {
                OnboardingView()
            } else {
                MainTabView(userId: userId)
            }
        }
        .dismissKeyboardOnTap()
    }
}

#Preview {
    ContentView()
}
