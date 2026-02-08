import SwiftUI

enum MainTab: Hashable, CaseIterable {
    case home
    case coach
    case workout
    case nutrition
    case progress

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .coach:
            return "Coach"
        case .workout:
            return "Workout"
        case .nutrition:
            return "Nutrition"
        case .progress:
            return "Progress"
        }
    }

    var icon: String {
        switch self {
        case .home:
            return "house"
        case .coach:
            return "bubble.left.and.bubble.right"
        case .workout:
            return "dumbbell"
        case .nutrition:
            return "leaf"
        case .progress:
            return "chart.line.uptrend.xyaxis"
        }
    }

    var activeIcon: String {
        switch self {
        case .home:
            return "house.fill"
        case .coach:
            return "bubble.left.and.bubble.right.fill"
        case .workout:
            return "dumbbell.fill"
        case .nutrition:
            return "leaf.fill"
        case .progress:
            return "chart.line.uptrend.xyaxis"
        }
    }
}

enum WorkoutTabIntent: Equatable {
    case startRecommended
    case swapSaved
    case startCoachPick(templateId: String)
}

enum NutritionTabIntent: Equatable {
    case logMeal
}

enum ProgressTabIntent: Equatable {
    case startCheckin
}

struct MainTabView: View {
    let userId: String
    @State private var selectedTab: MainTab = .home
    @State private var workoutIntent: WorkoutTabIntent?
    @State private var nutritionIntent: NutritionTabIntent?
    @State private var progressIntent: ProgressTabIntent?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                userId: userId,
                selectedTab: $selectedTab,
                workoutIntent: $workoutIntent,
                nutritionIntent: $nutritionIntent,
                progressIntent: $progressIntent
            )
            .tabItem {
                tabItemView(for: .home)
            }
            .tag(MainTab.home)

            CoachChatView(
                userId: userId,
                showsCloseButton: false,
                onClose: { selectedTab = .home }
            )
            .tabItem {
                tabItemView(for: .coach)
            }
            .tag(MainTab.coach)

            WorkoutView(userId: userId, intent: $workoutIntent)
                .tabItem {
                    tabItemView(for: .workout)
                }
                .tag(MainTab.workout)

            NutritionView(userId: userId, intent: $nutritionIntent)
                .tabItem {
                    tabItemView(for: .nutrition)
                }
                .tag(MainTab.nutrition)

            ProgressTabView(userId: userId, intent: $progressIntent)
                .tabItem {
                    tabItemView(for: .progress)
                }
                .tag(MainTab.progress)
        }
        .tint(FitTheme.accent)
        .animation(MotionTokens.springSoft, value: selectedTab)
        .onChange(of: selectedTab) { _ in
            Haptics.heavy()
        }
        .task {
            _ = await HealthKitManager.shared.syncWorkoutsIfEnabled()
        }
    }

    private func tabItemView(for tab: MainTab) -> some View {
        let isActive = selectedTab == tab
        let iconName = isActive ? tab.activeIcon : tab.icon
        let weight: Font.Weight = isActive ? .semibold : .regular
        return VStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: weight))
            Text(tab.title)
                .font(.system(size: 11, weight: weight))
        }
        .scaleEffect(isActive ? 1.08 : 0.98)
        .opacity(isActive ? 1.0 : 0.85)
    }
}

#Preview {
    MainTabView(userId: "demo-user")
}
