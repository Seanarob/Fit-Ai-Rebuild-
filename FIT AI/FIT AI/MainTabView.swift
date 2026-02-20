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
    @EnvironmentObject private var guidedTour: GuidedTourCoordinator
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
        .onChange(of: selectedTab) { tab in
            Haptics.heavy()
            guidedTour.presentIntroIfNeeded(for: guidedTourScreen(for: tab))
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIOpenWorkout)) { _ in
            selectedTab = .workout
            workoutIntent = .startRecommended
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIOpenHome)) { _ in
            selectedTab = .home
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIOpenNutrition)) { _ in
            selectedTab = .nutrition
            nutritionIntent = .logMeal
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIOpenCheckIn)) { _ in
            selectedTab = .progress
            progressIntent = .startCheckin
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIOpenCoach)) { _ in
            selectedTab = .coach
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIOpenProgress)) { _ in
            selectedTab = .progress
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIWalkthroughReplayRequested)) { _ in
            selectedTab = .home
            workoutIntent = nil
            nutritionIntent = nil
            progressIntent = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guidedTour.startFullTour(source: .settingsReplay)
            }
        }
        .onAppear {
            guidedTour.configureActionHandler(handleGuidedTourAction)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guidedTour.presentIntroIfNeeded(for: guidedTourScreen(for: selectedTab))
            }
        }
        .task {
            _ = await HealthKitManager.shared.syncWorkoutsIfEnabled()
            if let destination = DeepLinkStore.consumeDestination() {
                switch destination {
                case .home:
                    selectedTab = .home
                case .coach:
                    selectedTab = .coach
                case .workout:
                    selectedTab = .workout
                    workoutIntent = .startRecommended
                case .nutrition:
                    selectedTab = .nutrition
                    nutritionIntent = .logMeal
                case .progress:
                    selectedTab = .progress
                case .checkin:
                    selectedTab = .progress
                    progressIntent = .startCheckin
                }
            }
        }
        .guidedTourOverlay(using: guidedTour)
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

    private func handleGuidedTourAction(_ action: GuidedTourAction) {
        switch action {
        case .openScreen(let screen):
            selectedTab = mainTab(for: screen)
        case .openNutritionLogging:
            selectedTab = .nutrition
            nutritionIntent = .logMeal
        case .startProgressCheckin:
            selectedTab = .progress
            progressIntent = .startCheckin
        }
    }

    private func mainTab(for screen: GuidedTourScreen) -> MainTab {
        switch screen {
        case .home:
            return .home
        case .coach:
            return .coach
        case .workout:
            return .workout
        case .nutrition:
            return .nutrition
        case .progress:
            return .progress
        }
    }

    private func guidedTourScreen(for tab: MainTab) -> GuidedTourScreen {
        switch tab {
        case .home:
            return .home
        case .coach:
            return .coach
        case .workout:
            return .workout
        case .nutrition:
            return .nutrition
        case .progress:
            return .progress
        }
    }
}

#Preview {
    MainTabView(userId: "demo-user")
        .environmentObject(GuidedTourCoordinator())
}
