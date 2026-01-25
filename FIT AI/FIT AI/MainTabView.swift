import SwiftUI

enum MainTab: Hashable {
    case home
    case coach
    case workout
    case nutrition
    case progress
}

enum WorkoutTabIntent: Equatable {
    case startRecommended
    case swapSaved
}

enum NutritionTabIntent: Equatable {
    case logMeal
}

struct MainTabView: View {
    let userId: String
    @State private var selectedTab: MainTab = .home
    @State private var workoutIntent: WorkoutTabIntent?
    @State private var nutritionIntent: NutritionTabIntent?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                userId: userId,
                selectedTab: $selectedTab,
                workoutIntent: $workoutIntent,
                nutritionIntent: $nutritionIntent
            )
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(MainTab.home)

            CoachChatView(
                userId: userId,
                showsCloseButton: true,
                onClose: { selectedTab = .home }
            )
                .tabItem {
                    Label("Coach", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(MainTab.coach)

            WorkoutView(userId: userId, intent: $workoutIntent)
                .tabItem {
                    Label("Workout", systemImage: "dumbbell")
                }
                .tag(MainTab.workout)

            NutritionView(userId: userId, intent: $nutritionIntent)
                .tabItem {
                    Label("Nutrition", systemImage: "leaf")
                }
                .tag(MainTab.nutrition)

            ProgressTabView(userId: userId)
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(MainTab.progress)
        }
        .tint(FitTheme.accent)
    }
}

private struct TabPlaceholderView: View {
    let title: String

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            Text("\(title)\nComing soon")
                .font(FitFont.heading(size: 22))
                .multilineTextAlignment(.center)
                .foregroundColor(FitTheme.textPrimary)
        }
    }
}

#Preview {
    MainTabView(userId: "demo-user")
}
