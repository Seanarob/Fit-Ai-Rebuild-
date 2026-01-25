import SwiftUI

struct AccountHomeView: View {
    let userId: String
    @AppStorage("fitai.auth.userId") private var storedUserId = ""

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome back")
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(FitTheme.textSecondary)

                Text("Your FitAI account")
                    .font(FitFont.heading(size: 34, weight: .bold))
                    .foregroundColor(FitTheme.textPrimary)

                Text("User ID: \(userId)")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)

                Spacer()

                Button("Log out") {
                    storedUserId = ""
                }
                .font(FitFont.body(size: 17, weight: .semibold))
                .foregroundColor(FitTheme.buttonText)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(FitTheme.primaryGradient)
                .clipShape(Capsule())
                .shadow(color: FitTheme.buttonShadow, radius: 12, x: 0, y: 8)
            }
            .padding(24)
        }
    }
}

#Preview {
    AccountHomeView(userId: "demo-user")
}
