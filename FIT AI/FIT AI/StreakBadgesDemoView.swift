import SwiftUI

struct StreakBadgesDemoView: View {
    private struct BadgeItem: Identifiable {
        let id = UUID()
        let imageName: String
        let isEarned: Bool
    }

    private let badges: [BadgeItem] = [
        .init(imageName: "StreakBadge01", isEarned: true),
        .init(imageName: "StreakBadge02", isEarned: true),
        .init(imageName: "StreakBadge03", isEarned: false),
        .init(imageName: "StreakBadge04", isEarned: true),
        .init(imageName: "StreakBadge05", isEarned: false),
        .init(imageName: "StreakBadge06", isEarned: true),
        .init(imageName: "StreakBadge07", isEarned: false),
        .init(imageName: "StreakBadge08", isEarned: true)
    ]

    private let columns: [GridItem] = [
        GridItem(.flexible(minimum: 80), spacing: 16),
        GridItem(.flexible(minimum: 80), spacing: 16),
        GridItem(.flexible(minimum: 80), spacing: 16),
        GridItem(.flexible(minimum: 80), spacing: 16)
    ]

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Streak Badges")
                            .font(FitFont.heading(size: 26))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Drag your finger over earned badges to see the holographic shimmer.")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(badges) { badge in
                            HoloBadgeView(
                                image: Image(badge.imageName),
                                cornerRadius: 20,
                                isEarned: badge.isEarned
                            )
                            .frame(height: 110)
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        StreakBadgesDemoView()
    }
}
