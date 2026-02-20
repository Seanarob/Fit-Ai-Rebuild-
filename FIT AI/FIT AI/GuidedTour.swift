import Combine
import Foundation
import SwiftUI

enum GuidedTourScreen: String, CaseIterable {
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

    var symbolName: String {
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

    var accentColor: Color {
        switch self {
        case .home:
            return FitTheme.accent
        case .coach:
            return FitTheme.cardCoachAccent
        case .workout:
            return FitTheme.cardWorkoutAccent
        case .nutrition:
            return FitTheme.cardNutritionAccent
        case .progress:
            return FitTheme.cardProgressAccent
        }
    }
}

enum GuidedTourTargetID: String, Hashable {
    case homeHeader
    case homeTrainingCard
    case homeNutritionCard
    case homeCheckinCard

    case coachTopBar
    case coachInputBar

    case workoutWeeklySplit
    case workoutBuilder

    case nutritionMacroCard
    case nutritionMealPlanCard
    case nutritionAddButton

    case progressCheckinCard
    case progressBodyScanCard
    case progressPhotosCard
}

enum GuidedTourAction: Hashable {
    case openScreen(GuidedTourScreen)
    case openNutritionLogging
    case startProgressCheckin
}

enum GuidedTourStartSource: Hashable {
    case onboarding
    case settingsReplay
    case screenHelp(GuidedTourScreen)
}

struct GuidedTourTryIt: Hashable {
    let label: String
    let action: GuidedTourAction
    let advanceAfterAction: Bool

    init(
        label: String,
        action: GuidedTourAction,
        advanceAfterAction: Bool = false
    ) {
        self.label = label
        self.action = action
        self.advanceAfterAction = advanceAfterAction
    }
}

// Kept for compatibility with existing screen code that still reads currentStep.
struct GuidedTourStep: Identifiable, Hashable {
    let id: String
    let screen: GuidedTourScreen
    let target: GuidedTourTargetID?
    let title: String
    let message: String
    let tryIt: GuidedTourTryIt?

    init(
        id: String,
        screen: GuidedTourScreen,
        target: GuidedTourTargetID?,
        title: String,
        message: String,
        tryIt: GuidedTourTryIt? = nil
    ) {
        self.id = id
        self.screen = screen
        self.target = target
        self.title = title
        self.message = message
        self.tryIt = tryIt
    }
}

struct GuidedTourDefinition: Hashable {
    let id: String
    let source: GuidedTourStartSource
    let steps: [GuidedTourStep]
}

enum GuidedTourSpotlightShapeStyle: Hashable {
    case roundedRect(cornerRadius: CGFloat)
    case capsule
    case circle
}

private struct GuidedTourIntroContent {
    let eyebrow: String
    let title: String
    let message: String
    let highlights: [String]
    let buttonTitle: String
}

private enum GuidedTourIntroCatalog {
    static func intro(for screen: GuidedTourScreen) -> GuidedTourIntroContent {
        switch screen {
        case .home:
            return GuidedTourIntroContent(
                eyebrow: "YOUR COMMAND CENTER",
                title: "Home is your daily launchpad",
                message: "This page keeps your day focused by surfacing training, nutrition, and check-ins in one place.",
                highlights: [
                    "Start or swap today’s workout from the main card.",
                    "Track macro progress without leaving this screen.",
                    "Use reminders to jump straight into weekly check-ins."
                ],
                buttonTitle: "Got it"
            )
        case .coach:
            return GuidedTourIntroContent(
                eyebrow: "PERSONAL COACH",
                title: "Coach gives instant guidance",
                message: "Ask for workouts, nutrition adjustments, recovery strategy, or weekly planning at any time.",
                highlights: [
                    "Start a fresh conversation from the top controls.",
                    "Use the prompt list for fast, high-value asks.",
                    "Type or dictate messages in the bottom input bar."
                ],
                buttonTitle: "Start chatting"
            )
        case .workout:
            return GuidedTourIntroContent(
                eyebrow: "TRAINING HUB",
                title: "Workout manages your full training flow",
                message: "Set your weekly split, generate sessions, and launch workouts from one page.",
                highlights: [
                    "Review today’s split and upcoming sessions.",
                    "Switch between Generate, Saved, and Create modes.",
                    "Launch a workout directly from your selected plan."
                ],
                buttonTitle: "Let’s train"
            )
        case .nutrition:
            return GuidedTourIntroContent(
                eyebrow: "NUTRITION HQ",
                title: "Nutrition keeps macro tracking frictionless",
                message: "Log meals quickly and monitor calories/macros in real time.",
                highlights: [
                    "View daily macro progress at a glance.",
                    "Use the + button for photo, barcode, search, or voice log.",
                    "Generate meals and log directly from your plan."
                ],
                buttonTitle: "Track food"
            )
        case .progress:
            return GuidedTourIntroContent(
                eyebrow: "RESULTS DASHBOARD",
                title: "Progress turns data into trends",
                message: "Weekly check-ins, scans, workouts, and photos are consolidated here.",
                highlights: [
                    "Run your weekly check-in when it unlocks.",
                    "Capture body scans and compare confidence over time.",
                    "Review photos and trend charts in one flow."
                ],
                buttonTitle: "View progress"
            )
        }
    }
}

struct GuidedTourIntro: Identifiable {
    let screen: GuidedTourScreen
    let source: GuidedTourStartSource

    var id: String {
        switch source {
        case .onboarding:
            return "\(screen.rawValue).onboarding"
        case .settingsReplay:
            return "\(screen.rawValue).settingsReplay"
        case .screenHelp(let target):
            return "\(screen.rawValue).help.\(target.rawValue)"
        }
    }
}

@MainActor
final class GuidedTourCoordinator: ObservableObject {
    @Published private(set) var activeIntro: GuidedTourIntro?

    // Compatibility surface used by existing screen code.
    @Published private(set) var activeTour: GuidedTourDefinition?
    @Published private(set) var currentStepIndex: Int = 0

    private var actionHandler: ((GuidedTourAction) -> Void)?
    private var pendingOnboardingTour = false
    private var activeUserId: String = ""
    private let seenPrefix = "fitai.walkthrough.screenIntro.seen.v1"

    var isRunning: Bool {
        activeIntro != nil
    }

    var currentStep: GuidedTourStep? {
        nil
    }

    var canGoBack: Bool {
        false
    }

    var isLastStep: Bool {
        true
    }

    var progressText: String {
        ""
    }

    func setActiveUserId(_ userId: String) {
        activeUserId = userId
    }

    func configureActionHandler(_ handler: @escaping (GuidedTourAction) -> Void) {
        actionHandler = handler
    }

    func queueOnboardingTourIfNeeded(for userId: String) {
        activeUserId = userId
        pendingOnboardingTour = !hasSeenIntro(for: .home, userId: userId)
    }

    func activatePendingOnboardingTourIfNeeded() {
        guard pendingOnboardingTour else { return }
        pendingOnboardingTour = false
        presentIntro(for: .home, source: .onboarding, force: false)
    }

    func startFullTour(source: GuidedTourStartSource) {
        resetSeenScreens(for: activeUserId)
        actionHandler?(.openScreen(.home))
        presentIntro(for: .home, source: source, force: true)
    }

    func startScreenTour(_ screen: GuidedTourScreen) {
        presentIntro(for: screen, source: .screenHelp(screen), force: true)
    }

    func presentIntroIfNeeded(for screen: GuidedTourScreen) {
        presentIntro(for: screen, source: .onboarding, force: false)
    }

    func dismissIntro() {
        guard let intro = activeIntro else { return }
        markSeenIntro(for: intro.screen, userId: activeUserId)
        withAnimation(MotionTokens.easeInOut) {
            activeIntro = nil
        }
    }

    private func presentIntro(for screen: GuidedTourScreen, source: GuidedTourStartSource, force: Bool) {
        if !force && hasSeenIntro(for: screen, userId: activeUserId) {
            return
        }

        if let existing = activeIntro, existing.screen == screen, !force {
            return
        }

        withAnimation(MotionTokens.springSoft) {
            activeIntro = GuidedTourIntro(screen: screen, source: source)
        }
    }

    private func resetSeenScreens(for userId: String) {
        for screen in GuidedTourScreen.allCases {
            UserDefaults.standard.removeObject(forKey: seenKey(for: screen, userId: userId))
        }
    }

    private func hasSeenIntro(for screen: GuidedTourScreen, userId: String) -> Bool {
        UserDefaults.standard.bool(forKey: seenKey(for: screen, userId: userId))
    }

    private func markSeenIntro(for screen: GuidedTourScreen, userId: String) {
        UserDefaults.standard.set(true, forKey: seenKey(for: screen, userId: userId))
    }

    private func seenKey(for screen: GuidedTourScreen, userId: String) -> String {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = trimmed.isEmpty ? "anonymous" : trimmed
        return "\(seenPrefix).\(identity).\(screen.rawValue)"
    }
}

extension View {
    // Kept for compatibility with existing screen markup.
    func tourTarget(
        _ targetID: GuidedTourTargetID,
        shape: GuidedTourSpotlightShapeStyle = .roundedRect(cornerRadius: 16),
        padding: CGFloat = 0
    ) -> some View {
        self
    }

    func guidedTourOverlay(using coordinator: GuidedTourCoordinator) -> some View {
        modifier(GuidedTourIntroOverlayModifier(coordinator: coordinator))
    }
}

private struct GuidedTourIntroOverlayModifier: ViewModifier {
    @ObservedObject var coordinator: GuidedTourCoordinator

    func body(content: Content) -> some View {
        content
            .overlay {
                if let intro = coordinator.activeIntro {
                    GuidedTourIntroCard(
                        intro: intro,
                        onDismiss: coordinator.dismissIntro
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(999)
                }
            }
    }
}

private struct GuidedTourIntroCard: View {
    let intro: GuidedTourIntro
    let onDismiss: () -> Void

    @State private var cardVisible = false
    private let content: GuidedTourIntroContent

    init(intro: GuidedTourIntro, onDismiss: @escaping () -> Void) {
        self.intro = intro
        self.onDismiss = onDismiss
        self.content = GuidedTourIntroCatalog.intro(for: intro.screen)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.64),
                        intro.screen.accentColor.opacity(0.36),
                        Color.black.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .onTapGesture {}

                VStack(spacing: 20) {
                    iconBadge

                    VStack(alignment: .leading, spacing: 10) {
                        Text(content.eyebrow)
                            .font(FitFont.body(size: 11, weight: .semibold))
                            .tracking(1.0)
                            .foregroundColor(intro.screen.accentColor)

                        Text(content.title)
                            .font(FitFont.heading(size: 28))
                            .foregroundColor(FitTheme.textPrimary)

                        Text(content.message)
                            .font(FitFont.body(size: 15, weight: .regular))
                            .foregroundColor(FitTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(content.highlights.enumerated()), id: \.offset) { index, line in
                            highlightRow(text: line)
                                .opacity(cardVisible ? 1 : 0)
                                .offset(y: cardVisible ? 0 : 8)
                                .animation(
                                    .easeOut(duration: 0.24).delay(0.05 * Double(index + 1)),
                                    value: cardVisible
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onDismiss) {
                        Text(content.buttonTitle)
                            .font(FitFont.body(size: 16, weight: .semibold))
                            .foregroundColor(FitTheme.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(intro.screen.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 24)
                .frame(maxWidth: 540)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(FitTheme.cardBackground.opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(FitTheme.cardStroke.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 20)
                .padding(.horizontal, 20)
                .padding(.vertical, max(24, proxy.safeAreaInsets.top + 12))
                .scaleEffect(cardVisible ? 1 : 0.96)
                .opacity(cardVisible ? 1 : 0)
                .onAppear {
                    withAnimation(MotionTokens.springSoft) {
                        cardVisible = true
                    }
                }
                .onDisappear {
                    cardVisible = false
                }
            }
            .allowsHitTesting(true)
            .accessibilityAddTraits(.isModal)
        }
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(intro.screen.accentColor.opacity(0.18))
                .frame(width: 74, height: 74)

            Circle()
                .stroke(intro.screen.accentColor.opacity(0.4), lineWidth: 1)
                .frame(width: 88, height: 88)

            Image(systemName: intro.screen.symbolName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(intro.screen.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func highlightRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(intro.screen.accentColor)
                .padding(.top, 2)

            Text(text)
                .font(FitFont.body(size: 14, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
