import AVKit
import SwiftUI
import Combine
import UIKit

private enum ReplicaOnboardingStep: Int, CaseIterable {
    case hero
    case featureWorkoutPlans
    case featureMealPlans
    case featureCheckins
    case featureCoach
    case featureTraining
    case featureChallenges
    case featureNutrition
    case featureProgress
    case featureList
    case rating
    case questionExperience
    case questionGoal
    case questionFrequency
    case questionEnvironment
    case questionFocus
    case questionName
    case questionAge
    case questionSex
    case questionHeight
    case questionWeight
    case questionActivity
    case questionDuration
    case questionDiet
    case building
    case potential
    case personalizedGoals
    case projection
    case personalizing
    case claim
    case paywallReveal
    case paywall

    static let questionSteps: [ReplicaOnboardingStep] = [
        .questionExperience,
        .questionGoal,
        .questionFrequency,
        .questionEnvironment,
        .questionFocus,
        .questionName,
        .questionAge,
        .questionSex,
        .questionHeight,
        .questionWeight,
        .questionActivity,
        .questionDuration,
        .questionDiet,
    ]

    static let featureSteps: [ReplicaOnboardingStep] = [
        .featureWorkoutPlans,
        .featureMealPlans,
        .featureCheckins,
        .featureCoach,
        .featureTraining,
        .featureChallenges,
        .featureNutrition,
        .featureProgress,
    ]

    var isFeatureSlide: Bool {
        Self.featureSteps.contains(self)
    }

    var isLastFeatureSlide: Bool {
        self == Self.featureSteps.last
    }

    var isQuestionStep: Bool {
        Self.questionSteps.contains(self)
    }

    var questionIndex: Int? {
        guard let position = Self.questionSteps.firstIndex(of: self) else { return nil }
        return position + 1
    }

    var questionCount: Int {
        Self.questionSteps.count
    }

    var hidesPrimaryButton: Bool {
        self == .building || self == .personalizing
    }
}

private enum ReplicaExperienceOption: String, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced
    case competitive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner:
            return "Beginner (0-2 years)"
        case .intermediate:
            return "Intermediate (3-5 years)"
        case .advanced:
            return "Advanced (6+ years)"
        case .competitive:
            return "Elite/Competitive"
        }
    }

    var icon: String {
        switch self {
        case .beginner:
            return "leaf.fill"
        case .intermediate:
            return "bolt.fill"
        case .advanced:
            return "flame.fill"
        case .competitive:
            return "crown.fill"
        }
    }

    var mappedLevel: OnboardingForm.TrainingLevel {
        switch self {
        case .beginner:
            return .beginner
        case .intermediate:
            return .intermediate
        case .advanced, .competitive:
            return .advanced
        }
    }
}

private enum ReplicaDurationOption: Int, CaseIterable, Identifiable {
    case min30 = 30
    case min45 = 45
    case min60 = 60
    case min75 = 75

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) min"
    }
}

private enum ReplicaDietOption: String, CaseIterable, Identifiable {
    case balanced
    case highProtein
    case lowCarb
    case vegetarian
    case flexible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .highProtein:
            return "High Protein"
        case .lowCarb:
            return "Lower Carb"
        case .vegetarian:
            return "Vegetarian"
        case .flexible:
            return "No Preference"
        }
    }
}

private enum ReplicaPlan: String, CaseIterable, Identifiable {
    case monthly
    case yearly

    var id: String { rawValue }

    var name: String {
        switch self {
        case .monthly:
            return "FIT AI Monthly"
        case .yearly:
            return "FIT AI Annual"
        }
    }

    var price: String {
        switch self {
        case .monthly:
            return "$8.99/month"
        case .yearly:
            return "$86/year"
        }
    }

    var detail: String {
        switch self {
        case .monthly:
            return "7-day free trial, then monthly billing"
        case .yearly:
            return "Save 20% vs monthly billing"
        }
    }

    var badge: String? {
        switch self {
        case .monthly:
            return nil
        case .yearly:
            return "MOST POPULAR"
        }
    }
}

private enum ReplicaFeatureMedia {
    case image(name: String)
    case video(assetName: String, range: ReplicaVideoClipRange, fallbackImageName: String?)
    case swapImages(primary: String, secondary: String, delay: TimeInterval)

    var id: String {
        switch self {
        case .image(let name):
            return "image-\(name)"
        case .video(let assetName, let range, _):
            return "video-\(assetName)-\(range.id)"
        case .swapImages(let primary, let secondary, _):
            return "swap-\(primary)-\(secondary)"
        }
    }
}

private enum ReplicaVideoClipRange {
    case full
    case range(start: TimeInterval, end: TimeInterval)
    case last(seconds: TimeInterval)

    var id: String {
        switch self {
        case .full:
            return "full"
        case .range(let start, let end):
            return "range-\(start)-\(end)"
        case .last(let seconds):
            return "last-\(seconds)"
        }
    }
}

private struct ReplicaFeatureSlide {
    let title: String
    let subtitle: String
    let media: ReplicaFeatureMedia
    let buttonGradient: [Color]
    let dotColor: Color
}

private struct BenefitItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

struct OnboardingReplicaView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel = OnboardingViewModel()

    @State private var step: ReplicaOnboardingStep = .hero
    @State private var selectedRating = 0
    @State private var selectedExperience: ReplicaExperienceOption?
    @State private var selectedGoal: MainGoalOption?
    @State private var selectedFrequency: Int?
    @State private var selectedEnvironment: TrainingEnvironmentOption?
    @State private var selectedFocus: FocusAreaOption?

    @State private var fullName: String = ""
    @State private var age: String = ""
    @State private var heightFeet: String = ""
    @State private var heightInches: String = ""
    @State private var currentWeight: String = ""
    @State private var targetWeight: String = ""
    @State private var foodNotes: String = ""
    @State private var selectedSex: OnboardingForm.Sex?
    @State private var selectedActivity: OnboardingForm.ActivityLevel?
    @State private var selectedDuration: ReplicaDurationOption?
    @State private var selectedDiet: ReplicaDietOption?

    @State private var selectedPlan: ReplicaPlan = .yearly
    @State private var editedCalories: String = ""
    @State private var editedProtein: String = ""
    @State private var editedCarbs: String = ""
    @State private var editedFats: String = ""
    @State private var goalsMacrosInitialized = false
    @State private var shouldApplyPersonalizedMacros = true
    @State private var buildingStage = 0
    @State private var buildingProgress = 0.0
    @State private var personalizingProgress = 0.0
    @State private var autoTask: Task<Void, Never>?
    @State private var claimDeadline = Date().addingTimeInterval(24 * 60 * 60)
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var onboardingBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var onboardingPrimaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var onboardingSurfaceTint: Color {
        colorScheme == .dark ? .white : .black
    }

    private var stepTransitionID: String {
        step.isFeatureSlide ? "feature" : "\(step.rawValue)"
    }

    private var pageChangeAnimation: Animation {
        reduceMotion ? MotionTokens.easeInOut : MotionTokens.springBase
    }

    private var demoAnimation: Animation {
        reduceMotion ? MotionTokens.easeInOut : MotionTokens.springQuick
    }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.985))
    }

    private var featureDemoTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .fadeSlide(y: 18).combined(with: .scale(scale: 0.985)),
                removal: .fadeSlide(y: -18).combined(with: .scale(scale: 0.995))
            )
    }

    var body: some View {
        ZStack {
            onboardingBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        ZStack {
                            stepBody
                                .id(stepTransitionID)
                                .transition(stepTransition)
                        }
                        .animation(pageChangeAnimation, value: stepTransitionID)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }

                if !step.hidesPrimaryButton {
                    primaryActionButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $viewModel.showLogin) {
            LoginView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showEmailSignup) {
            EmailSignupView(viewModel: viewModel)
        }
        .onOpenURL { url in
            Task {
                await viewModel.handleAuthCallback(url: url)
            }
        }
        .onReceive(clock) { date in
            now = date
        }
        .onAppear {
            syncSelectionsFromModel()
            startAutoStepIfNeeded()
        }
        .onChange(of: step) { _ in
            startAutoStepIfNeeded()
        }
        .onDisappear {
            autoTask?.cancel()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                if showsBackButton {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(onboardingPrimaryText)
                            .frame(width: 40, height: 40)
                            .background(onboardingSurfaceTint.opacity(0.11))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }

                Spacer()

                if step.isFeatureSlide {
                    Button("Skip") {
                        step = .questionExperience
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(onboardingPrimaryText.opacity(0.88))
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            if step.isQuestionStep, let questionIndex = step.questionIndex {
                VStack(spacing: 7) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(onboardingSurfaceTint.opacity(0.16))
                                .frame(height: 4)
                            Capsule()
                                .fill(questionAccent)
                                .frame(
                                    width: proxy.size.width * CGFloat(questionIndex) / CGFloat(max(step.questionCount, 1)),
                                    height: 4
                                )
                        }
                    }
                    .frame(height: 4)

                    Text("\(questionIndex) of \(step.questionCount)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(onboardingPrimaryText.opacity(0.78))
                }
                .padding(.horizontal, 62)
            }
        }
    }

    private var questionAccent: Color {
        step == .questionGoal
            ? Color(red: 0.93, green: 0.39, blue: 0.66)
            : Color(red: 0.39, green: 0.52, blue: 0.94)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .hero:
            heroStep
        case .featureWorkoutPlans, .featureMealPlans, .featureCheckins, .featureCoach, .featureTraining, .featureChallenges, .featureNutrition, .featureProgress:
            featureStep
        case .featureList:
            featuresListStep
        case .rating:
            ratingStep
        case .questionExperience:
            questionExperienceStep
        case .questionGoal:
            questionGoalStep
        case .questionFrequency:
            questionFrequencyStep
        case .questionEnvironment:
            questionEnvironmentStep
        case .questionFocus:
            questionFocusStep
        case .questionName:
            questionNameStep
        case .questionAge:
            questionAgeStep
        case .questionSex:
            questionSexStep
        case .questionHeight:
            questionHeightStep
        case .questionWeight:
            questionWeightStep
        case .questionActivity:
            questionActivityStep
        case .questionDuration:
            questionDurationStep
        case .questionDiet:
            questionDietStep
        case .building:
            buildingStep
        case .potential:
            potentialStep
        case .personalizedGoals:
            personalizedGoalsStep
        case .projection:
            projectionStep
        case .personalizing:
            personalizingStep
        case .claim:
            claimStep
        case .paywallReveal:
            paywallRevealStep
        case .paywall:
            paywallStep
        }
    }

    private var primaryActionButton: some View {
        Button {
            handlePrimaryAction()
        } label: {
            HStack(spacing: 8) {
                Text(primaryTitle)
                    .font(.system(size: 21, weight: .semibold))
                if step != .claim && step != .paywall {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: primaryGradient,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isPrimaryDisabled)
        .opacity(isPrimaryDisabled ? 0.45 : 1)
    }

    private var heroStep: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            CoachCharacterView(size: 128, showBackground: true, pose: .celebration)
                .padding(.top, 8)

            VStack(spacing: 2) {
                Text("Train Smarter")
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundColor(onboardingPrimaryText)
                Text("Win More")
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundColor(Color(red: 0.09, green: 0.49, blue: 0.98))
            }
            .multilineTextAlignment(.center)

            Text("AI-POWERED FITNESS COACH")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.4)
                .foregroundColor(onboardingPrimaryText.opacity(0.48))

            VStack(alignment: .leading, spacing: 15) {
                heroBullet(icon: "photo.fill", text: "Real-time physique analysis")
                heroBullet(icon: "figure.strengthtraining.traditional", text: "Personalized training plans")
                heroBullet(icon: "fork.knife", text: "Adaptive meal plans")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func heroBullet(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                )
            Text(text)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(onboardingPrimaryText.opacity(0.92))
        }
    }

    private var featureStep: some View {
        let slide = currentSlide
        let demoID = featureDemoID

        return VStack(spacing: 0) {
            GeometryReader { proxy in
                let horizontalInset: CGFloat = 16
                let availableWidth = max(proxy.size.width - (horizontalInset * 2), 0)
                let phoneAspect: CGFloat = 9 / 19.5
                let targetHeight = min(proxy.size.height, 620)
                let widthFromHeight = targetHeight * phoneAspect
                let demoWidth = min(availableWidth, widthFromHeight)

                ZStack {
                    featureDemoView
                        .id(demoID)
                        .transition(featureDemoTransition)
                        .frame(width: demoWidth, height: demoWidth / phoneAspect)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 12)
                }
            }
            .animation(demoAnimation, value: demoID)
            .frame(height: min(max(UIScreen.main.bounds.height * 0.56, 420), 620))
            .frame(maxWidth: .infinity)
            .padding(.top, 10)

            // Text content at bottom
            VStack(spacing: 10) {
                Text(slide.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(onboardingPrimaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(slide.subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(onboardingPrimaryText.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            HStack(spacing: 22) {
                ForEach(featureTags, id: \.self) { tag in
                    featureTag(text: tag, tint: slide.dotColor)
                }
            }
            .padding(.top, 16)
        }
    }

    private var featureDemoView: some View {
        PhoneMockupContainerView(cornerRadius: 54, bezelWidth: 12, showNotch: true, shadow: true) {
            ReplicaFeatureMediaView(media: currentSlide.media)
        }
    }

    private var featureDemoID: String {
        currentSlide.media.id
    }

    private var featureTags: [String] {
        switch step {
        case .featureWorkoutPlans, .featureTraining:
            return ["Split", "Schedule", "AI Fit"]
        case .featureMealPlans:
            return ["Meals", "Macros", "Swaps"]
        case .featureCheckins, .featureChallenges:
            return ["Weekly", "Recap", "Adjust"]
        case .featureCoach:
            return ["Chat", "Guidance", "24/7"]
        case .featureProgress:
            return ["Sessions", "Sets", "Streaks"]
        case .featureNutrition:
            return ["Scan", "Photo", "Voice"]
        default:
            return ["Personalized", "AI-Powered", "Real-time"]
        }
    }

    private func featureTag(text: String, tint: Color) -> some View {
        VStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(onboardingPrimaryText.opacity(0.76))
        }
    }

    private struct ReplicaFeatureMediaView: View {
        let media: ReplicaFeatureMedia

        var body: some View {
            Group {
                switch media {
                case .image(let name):
                    Image(name)
                        .resizable()
                        .scaledToFill()
                case .video(let assetName, let range, let fallbackImageName):
                    ReplicaVideoClipView(assetName: assetName, range: range, fallbackImageName: fallbackImageName)
                case .swapImages(let primary, let secondary, let delay):
                    ReplicaTimedSwapView(primary: primary, secondary: secondary, delay: delay)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    private struct ReplicaTimedSwapView: View {
        let primary: String
        let secondary: String
        let delay: TimeInterval

        @State private var showSecondary = false
        @State private var swapTask: Task<Void, Never>?

        var body: some View {
            ZStack {
                Image(primary)
                    .resizable()
                    .scaledToFill()
                    .opacity(showSecondary ? 0 : 1)

                Image(secondary)
                    .resizable()
                    .scaledToFill()
                    .opacity(showSecondary ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.6), value: showSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onAppear {
                showSecondary = false
                swapTask?.cancel()
                swapTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    showSecondary = true
                }
            }
            .onDisappear {
                swapTask?.cancel()
            }
        }
    }

    private struct ReplicaVideoClipView: View {
        let assetName: String
        let range: ReplicaVideoClipRange
        let fallbackImageName: String?

        @State private var player: AVPlayer?
        @State private var timeObserver: Any?

        var body: some View {
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(contentMode: .fill)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            cleanupPlayer()
                        }
                        .allowsHitTesting(false)
                } else if let fallbackImageName {
                    Image(fallbackImageName)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onAppear {
                preparePlayerIfNeeded()
            }
        }

        private func preparePlayerIfNeeded() {
            guard player == nil, let url = ReplicaVideoCache.url(for: assetName) else { return }
            let asset = AVAsset(url: url)
            let duration = asset.duration.seconds
            let clip = resolvedClipRange(duration: duration)
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.actionAtItemEnd = .pause
            self.player = player

            let startTime = CMTime(seconds: clip.start, preferredTimescale: 600)
            player.seek(to: startTime) { _ in
                player.play()
            }

            if clip.end > clip.start + 0.05 {
                let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
                timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                    if time.seconds >= clip.end {
                        player.seek(to: startTime) { _ in
                            player.play()
                        }
                    }
                }
            }
        }

        private func resolvedClipRange(duration: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
            let safeDuration = duration.isFinite ? duration : 0
            switch range {
            case .full:
                return (0, safeDuration)
            case .range(let start, let end):
                return (max(0, start), min(end, safeDuration))
            case .last(let seconds):
                let end = safeDuration
                let start = max(end - seconds, 0)
                return (start, end)
            }
        }

        private func cleanupPlayer() {
            if let observer = timeObserver, let player {
                player.removeTimeObserver(observer)
            }
            timeObserver = nil
            player?.pause()
            player = nil
        }
    }

    private enum ReplicaVideoCache {
        static var cachedURLs: [String: URL] = [:]

        static func url(for assetName: String) -> URL? {
            if let cached = cachedURLs[assetName] { return cached }
            guard let dataAsset = NSDataAsset(name: assetName) else { return nil }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(assetName).mp4")
            if !FileManager.default.fileExists(atPath: url.path) {
                do {
                    try dataAsset.data.write(to: url, options: .atomic)
                } catch {
                    return nil
                }
            }
            cachedURLs[assetName] = url
            return url
        }
    }

    private var featuresListStep: some View {
        VStack(spacing: 14) {
            Text("What makes FIT AI\nspecial?")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(onboardingPrimaryText)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ForEach(featureBenefits) { item in
                    featureBenefitCard(item)
                }
            }
        }
    }

    private func featureBenefitCard(_ item: BenefitItem) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(onboardingSurfaceTint.opacity(0.06))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(onboardingPrimaryText)
                Text(item.detail)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(onboardingPrimaryText.opacity(0.66))
            }

            Spacer()
        }
        .padding(14)
        .background(onboardingSurfaceTint.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(onboardingSurfaceTint.opacity(0.1), lineWidth: 1)
        )
    }

    private var ratingStep: some View {
        VStack(spacing: 16) {
            Circle()
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.blue)
                )

            Text("Love FIT AI?")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(onboardingPrimaryText)

            Text("Help us reach more users by rating us 5 stars")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(onboardingPrimaryText.opacity(0.72))
                .multilineTextAlignment(.center)

            Text("Rate your experience")
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(onboardingPrimaryText)
                .padding(.top, 4)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        selectedRating = value
                    } label: {
                        Image(systemName: value <= selectedRating ? "star.fill" : "star")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 12) {
                Text("What makes FIT AI special?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(onboardingPrimaryText)
                    .padding(.top, 4)
                featureBenefitCard(featureBenefits[0])
                featureBenefitCard(featureBenefits[1])
            }
            .padding(.top, 6)
        }
    }

    private var questionExperienceStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "target",
                title: "What's your training\nexperience?",
                subtitle: "Every champion started somewhere"
            )

            VStack(spacing: 10) {
                ForEach(ReplicaExperienceOption.allCases) { option in
                    questionChoiceRow(
                        title: option.title,
                        icon: option.icon,
                        isSelected: selectedExperience == option
                    ) {
                        selectedExperience = option
                        viewModel.setTrainingLevel(option.mappedLevel)
                    }
                }
            }
        }
    }

    private var questionGoalStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "trophy.fill",
                title: "What's your primary goal?",
                subtitle: "Define your path to greatness"
            )

            VStack(spacing: 10) {
                ForEach(MainGoalOption.allCases) { option in
                    questionChoiceRow(
                        title: option.title,
                        icon: symbolForGoal(option),
                        isSelected: selectedGoal == option,
                        selectedGradient: [Color(red: 0.84, green: 0.44, blue: 0.92), Color(red: 0.95, green: 0.33, blue: 0.43)]
                    ) {
                        selectedGoal = option
                        viewModel.setMainGoal(option)
                    }
                }
            }
        }
    }

    private var questionFrequencyStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "calendar",
                title: "How many days can\nyou train per week?",
                subtitle: "Pick what you can sustain"
            )

            VStack(spacing: 10) {
                ForEach([2, 3, 4, 5, 6], id: \.self) { value in
                    questionChoiceRow(
                        title: value == 6 ? "6+ days per week" : "\(value) days per week",
                        icon: "calendar",
                        isSelected: selectedFrequency == value
                    ) {
                        selectedFrequency = value
                        viewModel.setTrainingFrequency(value)
                    }
                }
            }
        }
    }

    private var questionEnvironmentStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "house.fill",
                title: "Where do you train\nmost often?",
                subtitle: "We'll tailor your plan to your setup"
            )

            VStack(spacing: 10) {
                ForEach(TrainingEnvironmentOption.allCases) { option in
                    questionChoiceRow(
                        title: option.title,
                        icon: symbolForEnvironment(option),
                        isSelected: selectedEnvironment == option
                    ) {
                        selectedEnvironment = option
                        viewModel.setTrainingEnvironment(option)
                    }
                }
            }
        }
    }

    private var questionFocusStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "bolt.fill",
                title: "What should we focus\non first?",
                subtitle: "We'll prioritize this in your split"
            )

            VStack(spacing: 10) {
                ForEach(FocusAreaOption.allCases) { option in
                    questionChoiceRow(
                        title: option.title,
                        icon: symbolForFocus(option),
                        isSelected: selectedFocus == option
                    ) {
                        selectedFocus = option
                        viewModel.setFocusArea(option)
                    }
                }
            }
        }
    }

    private var questionNameStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "person.fill",
                title: "What should your coach\ncall you?",
                subtitle: "We'll personalize your plan and recaps"
            )

            inputCard(
                title: "Your name",
                placeholder: "Enter your first name",
                text: Binding(
                    get: { fullName },
                    set: { newValue in
                        fullName = newValue
                        viewModel.form.fullName = newValue
                        viewModel.save()
                    }
                ),
                keyboardType: .default
            )
        }
    }

    private var questionAgeStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "number.circle.fill",
                title: "How old are you?",
                subtitle: "Age helps us set safer progress pace"
            )

            inputCard(
                title: "Age",
                placeholder: "Enter age",
                text: Binding(
                    get: { age },
                    set: { newValue in
                        let filtered = newValue.filter { "0123456789".contains($0) }
                        age = String(filtered.prefix(3))
                        viewModel.form.age = age
                        viewModel.save()
                    }
                ),
                keyboardType: .numberPad
            )
        }
    }

    private var questionSexStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "person.2.fill",
                title: "What sex should we use\nfor calculation?",
                subtitle: "Used for macro and energy estimation"
            )

            VStack(spacing: 10) {
                ForEach(OnboardingForm.Sex.allCases) { option in
                    questionChoiceRow(
                        title: option.title,
                        icon: symbolForSex(option),
                        isSelected: selectedSex == option
                    ) {
                        selectedSex = option
                        viewModel.setSex(option)
                    }
                }
            }
        }
    }

    private var questionHeightStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "ruler.fill",
                title: "What's your height?",
                subtitle: "We'll use ft/in like your existing app"
            )

            HStack(spacing: 10) {
                inputCard(
                    title: "Feet",
                    placeholder: "5",
                    text: Binding(
                        get: { heightFeet },
                        set: { newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            heightFeet = String(filtered.prefix(1))
                            viewModel.form.heightFeet = heightFeet
                            viewModel.form.heightUnit = "ft/in"
                            viewModel.save()
                        }
                    ),
                    keyboardType: .numberPad
                )

                inputCard(
                    title: "Inches",
                    placeholder: "9",
                    text: Binding(
                        get: { heightInches },
                        set: { newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            heightInches = String(filtered.prefix(2))
                            viewModel.form.heightInches = heightInches
                            viewModel.form.heightUnit = "ft/in"
                            viewModel.save()
                        }
                    ),
                    keyboardType: .numberPad
                )
            }

            Text("Example: 5 ft 9 in")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(onboardingPrimaryText.opacity(0.62))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var questionWeightStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "scalemass.fill",
                title: "Current and target\nbody weight",
                subtitle: "This helps build macro and progression targets"
            )

            HStack(spacing: 10) {
                inputCard(
                    title: "Current (lb)",
                    placeholder: "180",
                    text: Binding(
                        get: { currentWeight },
                        set: { newValue in
                            let filtered = newValue.filter { "0123456789.".contains($0) }
                            currentWeight = String(filtered.prefix(6))
                            viewModel.form.weightLbs = currentWeight
                            viewModel.save()
                        }
                    ),
                    keyboardType: .decimalPad
                )

                inputCard(
                    title: "Target (lb)",
                    placeholder: "170",
                    text: Binding(
                        get: { targetWeight },
                        set: { newValue in
                            let filtered = newValue.filter { "0123456789.".contains($0) }
                            targetWeight = String(filtered.prefix(6))
                            viewModel.form.goalWeightLbs = targetWeight
                            viewModel.save()
                        }
                    ),
                    keyboardType: .decimalPad
                )
            }
        }
    }

    private var questionActivityStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "figure.run",
                title: "How active are you\noutside training?",
                subtitle: "We'll use this for calorie baseline"
            )

            VStack(spacing: 10) {
                ForEach(OnboardingForm.ActivityLevel.allCases) { option in
                    questionChoiceRow(
                        title: option.title,
                        subtitle: option.description,
                        icon: "chart.line.uptrend.xyaxis",
                        isSelected: selectedActivity == option
                    ) {
                        selectedActivity = option
                        viewModel.setActivityLevel(option)
                    }
                }
            }
        }
    }

    private var questionDurationStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "clock.fill",
                title: "How long should each\nworkout be?",
                subtitle: "We'll tune your split and exercise volume"
            )

            VStack(spacing: 10) {
                ForEach(ReplicaDurationOption.allCases) { option in
                    questionChoiceRow(
                        title: option.title,
                        icon: "clock.fill",
                        isSelected: selectedDuration == option
                    ) {
                        selectedDuration = option
                        viewModel.form.workoutDurationMinutes = option.rawValue
                        viewModel.save()
                    }
                }
            }
        }
    }

    private var questionDietStep: some View {
        VStack(spacing: 16) {
            questionHeader(
                icon: "fork.knife",
                title: "Any diet preference?",
                subtitle: "We'll tailor nutrition recommendations"
            )

            VStack(spacing: 10) {
                ForEach(ReplicaDietOption.allCases) { option in
                    questionChoiceRow(
                        title: option.title,
                        icon: "fork.knife",
                        isSelected: selectedDiet == option
                    ) {
                        selectedDiet = option
                        viewModel.form.dietStyle = option.title
                        viewModel.save()
                    }
                }
            }

            inputCard(
                title: "Allergies or dislikes (optional)",
                placeholder: "e.g. peanuts, shellfish",
                text: Binding(
                    get: { foodNotes },
                    set: { newValue in
                        foodNotes = newValue
                        viewModel.form.foodAllergies = newValue
                        viewModel.save()
                    }
                ),
                keyboardType: .default
            )
        }
    }

    private func questionHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(questionAccent.opacity(0.95))
                .frame(width: 62, height: 62)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                )

            if let index = step.questionIndex {
                Text("QUESTION \(index)")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(onboardingPrimaryText.opacity(0.5))
            }

            Text(title)
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(onboardingPrimaryText)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(onboardingPrimaryText.opacity(0.68))
                .multilineTextAlignment(.center)
        }
    }

    private func questionChoiceRow(
        title: String,
        subtitle: String? = nil,
        icon: String,
        isSelected: Bool,
        selectedGradient: [Color] = [Color(red: 0.39, green: 0.52, blue: 0.94), Color(red: 0.34, green: 0.32, blue: 0.93)],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .white : onboardingPrimaryText.opacity(0.95))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(isSelected ? .white : onboardingPrimaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(isSelected ? .white.opacity(0.82) : onboardingPrimaryText.opacity(0.66))
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                        ? LinearGradient(colors: selectedGradient, startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [onboardingSurfaceTint.opacity(0.08), onboardingSurfaceTint.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(onboardingSurfaceTint.opacity(isSelected ? 0.0 : 0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func inputCard(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(onboardingPrimaryText.opacity(0.65))

            TextField(placeholder, text: text)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(onboardingPrimaryText)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(onboardingSurfaceTint.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(onboardingSurfaceTint.opacity(0.12), lineWidth: 1)
        )
    }

    private var buildingStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.yellow)

            Text("Building Your Program")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(onboardingPrimaryText)

            Text("This will only take a moment")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(onboardingPrimaryText.opacity(0.7))

            VStack(alignment: .leading, spacing: 14) {
                statusRow(index: 1, title: "Analyzing your responses", isComplete: buildingStage > 1, isActive: buildingStage == 1)
                statusRow(index: 2, title: "Creating personalized plan", isComplete: buildingStage > 2, isActive: buildingStage == 2)
                statusRow(index: 3, title: "Optimizing AI models", isComplete: buildingStage > 3, isActive: buildingStage == 3)
            }
            .padding(.top, 10)

            ProgressView(value: buildingProgress, total: 1.0)
                .tint(.blue)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)
                .padding(.top, 8)

            Text("\(Int(buildingProgress * 100))% Complete")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(onboardingPrimaryText.opacity(0.74))
        }
        .padding(.horizontal, 2)
    }

    private func statusRow(index: Int, title: String, isComplete: Bool, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : (isActive ? Color.blue : onboardingSurfaceTint.opacity(0.18)))
                    .frame(width: 24, height: 24)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else if isActive {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                } else {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(onboardingPrimaryText.opacity(0.68))
                }
            }

            Text(title)
                .font(.system(size: 21, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? onboardingPrimaryText : onboardingPrimaryText.opacity(0.58))
        }
    }

    private var potentialStep: some View {
        let goalTitle = selectedGoal?.title ?? "Build muscle"
        let daysValue = selectedFrequency ?? 3
        let focusTitle = selectedFocus?.title ?? "Strength"
        let durationValue = selectedDuration?.rawValue ?? 45

        return VStack(spacing: 12) {
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.green)
                )
                .padding(.top, 4)

            Text("Your Progress Potential")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(onboardingPrimaryText)
                .multilineTextAlignment(.center)

            Text("See how FIT AI can accelerate your fitness journey")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(onboardingPrimaryText.opacity(0.7))
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    potentialStatCard(icon: "trophy.fill", title: "Goal", value: goalTitle)
                    potentialStatCard(icon: "calendar", title: "Days / Week", value: "\(daysValue)")
                }

                HStack(spacing: 10) {
                    potentialStatCard(icon: "bolt.fill", title: "Focus", value: focusTitle)
                    potentialStatCard(icon: "clock.fill", title: "Session", value: "\(durationValue) min")
                }
            }
            .padding(.top, 4)

            momentumBar()
                .padding(.top, 2)

            Text(potentialNarrative)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(16)
                .background(Color(red: 0.0, green: 0.18, blue: 0.45).opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.blue.opacity(0.32), lineWidth: 1)
                )
        }
    }

    private func potentialStatCard(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(onboardingPrimaryText.opacity(0.65))
            }

            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(onboardingPrimaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(onboardingSurfaceTint.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(onboardingSurfaceTint.opacity(0.12), lineWidth: 1)
        )
    }

    private func momentumBar() -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Momentum Forecast")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(onboardingPrimaryText.opacity(0.78))
                Spacer()
                Text("Steady climb")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.green)
            }

            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(index < 4 ? Color.green.opacity(0.8) : onboardingSurfaceTint.opacity(0.2))
                        .frame(height: 8)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .background(onboardingSurfaceTint.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(onboardingSurfaceTint.opacity(0.1), lineWidth: 1)
        )
    }

    private var personalizedGoalsStep: some View {
        let startWeightValue = parseWeight(currentWeight, fallback: parseWeight(viewModel.form.weightLbs, fallback: 190))
        let isMaintainGoal = viewModel.form.goal == .maintain
        let fallbackGoalWeight = isMaintainGoal ? startWeightValue : max(startWeightValue - 8, 120)
        let targetWeightValue = isMaintainGoal
            ? startWeightValue
            : parseWeight(targetWeight, fallback: parseWeight(viewModel.form.goalWeightLbs, fallback: fallbackGoalWeight))
        let estimatedGoalDate = suggestedTargetDate(
            currentWeight: startWeightValue,
            goalWeight: targetWeightValue,
            goal: viewModel.form.goal
        )
        let daysToGoal = max(
            0,
            Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: estimatedGoalDate)
            ).day ?? 0
        )
        let weeksToGoal = max(1, daysToGoal / 7)
        let delta = targetWeightValue - startWeightValue
        let deltaText = formatDelta(delta)
        let deltaColor = delta < 0 ? Color.green : (delta > 0 ? Color.blue : onboardingPrimaryText.opacity(0.5))
        let ageValue = resolvedAge()
        let heightFeetValue = Int(heightFeet) ?? Int(viewModel.form.heightFeet) ?? 5
        let heightInchesValue = Int(heightInches) ?? Int(viewModel.form.heightInches) ?? 9
        let macroDefaults = roundedMacros(
            calculateMacroTargets(
                weightLbs: startWeightValue,
                heightFeet: heightFeetValue,
                heightInches: heightInchesValue,
                age: ageValue,
                sex: viewModel.form.sex,
                trainingDaysPerWeek: viewModel.form.workoutDaysPerWeek,
                goal: viewModel.form.goal,
                goalWeightLbs: targetWeightValue
            )
        )
        let weeklyRate = healthyWeeklyRate(for: viewModel.form.goal)
        let paceText = String(format: "%.1f", weeklyRate)
        let goalsAccent = Color(red: 0.30, green: 0.33, blue: 0.95)

        return VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Your Personalized Goals")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(onboardingPrimaryText)
                    .multilineTextAlignment(.center)
                Text("Based on your profile, training schedule, and selected goal.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(onboardingPrimaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(onboardingPrimaryText.opacity(0.62))
                        Text("Today")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(onboardingPrimaryText)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(formatWeight(startWeightValue))
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(onboardingPrimaryText)
                            Text("lbs")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(onboardingPrimaryText.opacity(0.58))
                        }
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(onboardingPrimaryText.opacity(0.42))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(isMaintainGoal ? "Maintenance" : "Estimated Goal")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(onboardingPrimaryText.opacity(0.62))
                        Text(isMaintainGoal ? "On your plan" : estimatedGoalDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(onboardingPrimaryText)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(formatWeight(targetWeightValue))
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(goalsAccent)
                            Text("lbs")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(onboardingPrimaryText.opacity(0.58))
                            if !isMaintainGoal {
                                Text("(\(deltaText))")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(deltaColor)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(goalsAccent)
                    if isMaintainGoal {
                        Text("Maintaining your current range with adaptive nutrition.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(onboardingPrimaryText.opacity(0.9))
                    } else {
                        Text("~\(weeksToGoal) weeks at your \(paceText) lb/week pace")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(onboardingPrimaryText.opacity(0.9))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(goalsAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                PersonalizedGoalsChartView(
                    startWeight: startWeightValue,
                    targetWeight: targetWeightValue,
                    startDate: Date(),
                    targetDate: estimatedGoalDate,
                    accent: goalsAccent,
                    primaryText: onboardingPrimaryText,
                    gridTint: onboardingSurfaceTint
                )
                .frame(height: 220)
            }
            .padding(16)
            .background(onboardingSurfaceTint.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(onboardingSurfaceTint.opacity(0.12), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 11) {
                Text("Tap to edit your targets")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(onboardingPrimaryText.opacity(0.68))

                personalizedMacroRow(
                    icon: "flame.fill",
                    iconColor: .orange,
                    label: "Daily Calories",
                    value: Binding(
                        get: { editedCalories },
                        set: { editedCalories = sanitizeMacroInput($0, maxLength: 4) }
                    ),
                    suffix: "cal"
                )
                personalizedMacroRow(
                    icon: "fish.fill",
                    iconColor: .yellow,
                    label: "Protein Target",
                    value: Binding(
                        get: { editedProtein },
                        set: { editedProtein = sanitizeMacroInput($0, maxLength: 3) }
                    ),
                    suffix: "g"
                )
                personalizedMacroRow(
                    icon: "leaf.fill",
                    iconColor: .red,
                    label: "Carbs Target",
                    value: Binding(
                        get: { editedCarbs },
                        set: { editedCarbs = sanitizeMacroInput($0, maxLength: 4) }
                    ),
                    suffix: "g"
                )
                personalizedMacroRow(
                    icon: "drop.fill",
                    iconColor: goalsAccent,
                    label: "Fat Target",
                    value: Binding(
                        get: { editedFats },
                        set: { editedFats = sanitizeMacroInput($0, maxLength: 3) }
                    ),
                    suffix: "g"
                )
            }
            .padding(16)
            .background(onboardingSurfaceTint.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(onboardingSurfaceTint.opacity(0.12), lineWidth: 1)
            )

            Button {
                shouldApplyPersonalizedMacros.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: shouldApplyPersonalizedMacros ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(goalsAccent)

                    Text("Use these macros")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(goalsAccent)

                    Spacer()
                }
                .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)

            if let message = viewModel.macroStatusMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red.opacity(0.86))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            initializeGoalMacroInputs(defaults: macroDefaults)
        }
    }

    private func personalizedMacroRow(
        icon: String,
        iconColor: Color,
        label: String,
        value: Binding<String>,
        suffix: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 21, weight: .medium))
                .foregroundColor(onboardingPrimaryText)

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0", text: value)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(onboardingPrimaryText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 70)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(onboardingSurfaceTint.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(onboardingSurfaceTint.opacity(0.14), lineWidth: 1)
                    )

                Text(suffix)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(onboardingPrimaryText.opacity(0.58))
            }
        }
    }

    private func initializeGoalMacroInputs(defaults: MacroTotals) {
        guard !goalsMacrosInitialized else { return }

        let savedCalories = Int(viewModel.form.macroCalories)
        let savedProtein = Int(viewModel.form.macroProtein)
        let savedCarbs = Int(viewModel.form.macroCarbs)
        let savedFats = Int(viewModel.form.macroFats)

        editedCalories = "\(max(savedCalories ?? Int(defaults.calories), 0))"
        editedProtein = "\(max(savedProtein ?? Int(defaults.protein), 0))"
        editedCarbs = "\(max(savedCarbs ?? Int(defaults.carbs), 0))"
        editedFats = "\(max(savedFats ?? Int(defaults.fats), 0))"
        goalsMacrosInitialized = true
    }

    private var projectionStep: some View {
        VStack(spacing: 14) {
            Text("6-Month Progress Projection")
                .font(.system(size: 29, weight: .bold))
                .foregroundColor(onboardingPrimaryText)

            ProjectionChartView()
                .frame(height: 220)
                .padding(14)
                .background(onboardingSurfaceTint.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(onboardingSurfaceTint.opacity(0.1), lineWidth: 1)
                )

            HStack(spacing: 10) {
                metricCard(value: "80%", title: "With FIT AI", color: .green)
                metricCard(value: "35%", title: "Traditional", color: .red)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Key Benefits for Your Goals")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(onboardingPrimaryText)

                benefitRow("Personalized feedback on technique and strategy")
                benefitRow("Data-driven insight to accelerate development")
                benefitRow("Consistency through simple check-ins and streaks")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricCard(value: String, title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 31, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(onboardingPrimaryText.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(onboardingSurfaceTint.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(onboardingSurfaceTint.opacity(0.1), lineWidth: 1)
        )
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.green)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(onboardingPrimaryText.opacity(0.86))
        }
    }

    private var personalizingStep: some View {
        VStack(spacing: 14) {
            Text("Personalizing FIT AI")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(onboardingPrimaryText)
                .multilineTextAlignment(.center)

            Text("Tailoring every feature to your training journey")
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(onboardingPrimaryText.opacity(0.72))
                .multilineTextAlignment(.center)

            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.24), lineWidth: 12)
                    .frame(width: 112, height: 112)
                Circle()
                    .trim(from: 0, to: CGFloat(personalizingProgress))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 112, height: 112)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(.top, 6)

            Text("\(Int(personalizingProgress * 100))%")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.blue)

            ProgressView(value: personalizingProgress, total: 1.0)
                .tint(.blue)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)

            VStack(spacing: 10) {
                personalizingCard(title: "Analyzing your profile", subtitle: "Processing goals and baseline")
                personalizingCard(title: "Calibrating macro targets", subtitle: "Balancing intake for your goal")
                personalizingCard(title: "Syncing your first training week", subtitle: "Preparing your day-one plan")
            }
            .padding(.top, 6)
        }
    }

    private func personalizingCard(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.green.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.green)
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(onboardingPrimaryText.opacity(0.62))
            }

            Spacer()
        }
        .padding(14)
        .background(onboardingSurfaceTint.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(onboardingSurfaceTint.opacity(0.1), lineWidth: 1)
        )
    }

    private var claimStep: some View {
        VStack(spacing: 14) {
            Text("Claim Your Plan")
                .font(.system(size: 46, weight: .bold))
                .foregroundColor(onboardingPrimaryText)
                .multilineTextAlignment(.center)

            Text("Sign in to claim plan")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 10) {
                Text("Data Reset Notice")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundColor(.blue)

                Text("Your training data will be automatically reset in:")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(onboardingPrimaryText.opacity(0.8))

                HStack(spacing: 8) {
                    timerCell(value: claimTime.hours, unit: "hours")
                    Text(":")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.blue)
                    timerCell(value: claimTime.minutes, unit: "minutes")
                    Text(":")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.blue)
                    timerCell(value: claimTime.seconds, unit: "seconds")
                }

                Text("Sign in now to preserve your progress and personalized data.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(14)
            .background(Color.blue.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.blue.opacity(0.34), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("What You'll Get")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(onboardingPrimaryText)

                featureBenefitCard(.init(icon: "photo.fill", title: "AI Photo Analysis", detail: "Photo-based physique feedback, muscle focus, and body fat insights."))
                featureBenefitCard(.init(icon: "figure.strengthtraining.traditional", title: "Personalized Training Plans", detail: "Adaptive workouts built around your week."))
                featureBenefitCard(.init(icon: "chart.line.uptrend.xyaxis", title: "Progress Tracking", detail: "Track trends and improve with coach recaps."))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
    }

    private func timerCell(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.blue)
            Text(unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(onboardingPrimaryText.opacity(0.66))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(onboardingSurfaceTint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var paywallRevealStep: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("Unlock Your Potential")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(onboardingPrimaryText.opacity(0.72))

                Text("FIT AI")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(onboardingPrimaryText)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.blue)
                    .frame(height: 150)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)

                            Text("Dominate the Plan")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundColor(.white)

                            Text("Join athletes using AI to sharpen consistency")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.92))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    )

                Text("Premium Features")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(onboardingPrimaryText)

                featureBenefitCard(.init(icon: "photo.fill", title: "AI Photo Analysis", detail: "Track physique changes with photo insights and clear next steps."))

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(width: 338, height: 560)
            .background(onboardingSurfaceTint.opacity(colorScheme == .dark ? 0.95 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(onboardingSurfaceTint.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.top, 10)
    }

    private var paywallStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unlock Your Potential")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(onboardingPrimaryText.opacity(0.72))

                    Text("FIT AI")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundColor(onboardingPrimaryText)
                }

                Spacer()

                Text("PRO")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(Capsule())
            }

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.blue)
                .frame(height: 178)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)

                        Text("Dominate the Plan")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)

                        Text("Use AI to improve faster and train with clear direction")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                )

            Text("Premium Features")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(onboardingPrimaryText)

            featureBenefitCard(.init(icon: "photo.fill", title: "AI Photo Analysis", detail: "Upload photos to get physique feedback and body fat estimates."))
            featureBenefitCard(.init(icon: "brain.head.profile", title: "24/7 AI Coach", detail: "Get guided responses for training and nutrition."))
            featureBenefitCard(.init(icon: "chart.bar.xaxis", title: "Progress Insights", detail: "Track trends and adjust your plan with clarity."))

            Text("Trusted by Athletes")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(onboardingPrimaryText)
                .padding(.top, 4)

            HStack(spacing: 8) {
                trustPill(value: "15K+", label: "Active Users")
                trustPill(value: "98%", label: "See Progress")
                trustPill(value: "4.9", label: "Rating")
            }

            Text("Start Your Journey")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(onboardingPrimaryText)
                .padding(.top, 4)

            VStack(spacing: 10) {
                ForEach(ReplicaPlan.allCases) { plan in
                    planCard(for: plan)
                }
            }

            Text("No commitment required, cancel anytime")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(onboardingPrimaryText.opacity(0.62))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)
        }
    }

    private func trustPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.blue)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(onboardingPrimaryText.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(onboardingSurfaceTint.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func planCard(for plan: ReplicaPlan) -> some View {
        let selected = selectedPlan == plan

        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(onboardingPrimaryText)

                        if let badge = plan.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.16))
                                .clipShape(Capsule())
                        }
                    }

                    Text(plan.price)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.blue)

                    Text(plan.detail)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(onboardingPrimaryText.opacity(0.72))
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(selected ? .blue : onboardingPrimaryText.opacity(0.35))
            }
            .padding(14)
            .background(onboardingSurfaceTint.opacity(selected ? 0.1 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.blue : onboardingSurfaceTint.opacity(0.1), lineWidth: selected ? 1.7 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var featureBenefits: [BenefitItem] {
        [
            .init(icon: "brain.head.profile", title: "Personal AI Coach", detail: "Ask questions and get guidance anytime."),
            .init(icon: "figure.strengthtraining.traditional", title: "Workout Splits", detail: "AI picks the split that fits your week."),
            .init(icon: "calendar.badge.clock", title: "Weekly Check-Ins", detail: "Recaps keep you accountable and on track."),
            .init(icon: "fork.knife", title: "Custom Meal Plans", detail: "Meals and macros built around your goals."),
            .init(icon: "chart.bar.xaxis", title: "Workout Tracker", detail: "Track every session in one place."),
            .init(icon: "camera.viewfinder", title: "AI Nutrition Logging", detail: "Log meals fast with photo, scan, or voice."),
        ]
    }

    private var currentSlide: ReplicaFeatureSlide {
        switch step {
        case .featureWorkoutPlans:
            return .init(
                title: "Personalized workout splits",
                subtitle: "AI matches your split to your training days.",
                media: .video(assetName: "OnboardingWorkoutVideo", range: .range(start: 10, end: 23), fallbackImageName: "OnboardingFeatureTraining"),
                buttonGradient: [Color(red: 0.33, green: 0.66, blue: 0.95), Color(red: 0.08, green: 0.83, blue: 0.90)],
                dotColor: Color(red: 0.33, green: 0.66, blue: 0.95)
            )
        case .featureMealPlans:
            return .init(
                title: "Custom meal plans based on your goals",
                subtitle: "Meals and macros built around your targets.",
                media: .swapImages(primary: "OnboardingFeatureNutrition", secondary: "OnboardingMealDetail", delay: 7),
                buttonGradient: [Color(red: 0.60, green: 0.84, blue: 0.86), Color(red: 0.92, green: 0.82, blue: 0.85)],
                dotColor: Color(red: 0.60, green: 0.84, blue: 0.86)
            )
        case .featureCheckins:
            return .init(
                title: "Weekly AI coach check-ins",
                subtitle: "Weekly recaps keep you accountable.",
                media: .video(assetName: "OnboardingCoachRecapVideo", range: .full, fallbackImageName: "OnboardingFeatureCheckin"),
                buttonGradient: [Color(red: 0.95, green: 0.40, blue: 0.64), Color(red: 0.95, green: 0.84, blue: 0.26)],
                dotColor: Color(red: 0.95, green: 0.40, blue: 0.64)
            )
        case .featureCoach:
            return .init(
                title: "Personal AI coach",
                subtitle: "Ask questions and get guidance anytime.",
                media: .video(assetName: "OnboardingChatVideo", range: .last(seconds: 10), fallbackImageName: "OnboardingFeatureCoach"),
                buttonGradient: [Color(red: 0.38, green: 0.50, blue: 0.93), Color(red: 0.44, green: 0.31, blue: 0.75)],
                dotColor: Color(red: 0.35, green: 0.52, blue: 1.0)
            )
        case .featureTraining:
            return .init(
                title: "Personalized workout splits",
                subtitle: "Choose the split that fits your week.",
                media: .image(name: "OnboardingFeatureTraining"),
                buttonGradient: [Color(red: 0.33, green: 0.66, blue: 0.95), Color(red: 0.08, green: 0.83, blue: 0.90)],
                dotColor: Color(red: 0.33, green: 0.66, blue: 0.95)
            )
        case .featureChallenges:
            return .init(
                title: "Weekly AI coach check-ins",
                subtitle: "Stay consistent with weekly nudges.",
                media: .image(name: "OnboardingFeatureCheckin"),
                buttonGradient: [Color(red: 0.95, green: 0.40, blue: 0.64), Color(red: 0.95, green: 0.84, blue: 0.26)],
                dotColor: Color(red: 0.95, green: 0.40, blue: 0.64)
            )
        case .featureNutrition:
            return .init(
                title: "AI nutrition logging",
                subtitle: "Log meals fast with photo, scan, or voice.",
                media: .image(name: "OnboardingFeatureInsights"),
                buttonGradient: [Color(red: 0.60, green: 0.84, blue: 0.86), Color(red: 0.92, green: 0.82, blue: 0.85)],
                dotColor: Color(red: 0.60, green: 0.84, blue: 0.86)
            )
        case .featureProgress:
            return .init(
                title: "Full built-in workout tracker",
                subtitle: "See every workout in one place.",
                media: .video(assetName: "OnboardingWorkoutVideo", range: .range(start: 26, end: 35), fallbackImageName: "OnboardingFeatureProgress"),
                buttonGradient: [Color(red: 0.93, green: 0.88, blue: 0.80), Color(red: 0.93, green: 0.67, blue: 0.58)],
                dotColor: Color(red: 0.94, green: 0.84, blue: 0.76)
            )
        default:
            return .init(
                title: "",
                subtitle: "",
                media: .image(name: "OnboardingFeatureCoach"),
                buttonGradient: [Color.blue, Color.blue],
                dotColor: .blue
            )
        }
    }

    private var primaryTitle: String {
        switch step {
        case .hero:
            return "Get Started"
        case .featureWorkoutPlans,
             .featureMealPlans,
             .featureCheckins,
             .featureCoach,
             .featureTraining,
             .featureChallenges,
             .featureNutrition,
             .featureProgress:
            return step.isLastFeatureSlide ? "Continue Journey" : "Next Feature"
        case .featureList, .rating:
            return "Continue"
        case .questionExperience:
            return "Forge My Path"
        case .questionGoal:
            return "Lock In My Destiny"
        case .questionDiet:
            return "Build My Program"
        case .questionFrequency, .questionEnvironment, .questionFocus, .questionName, .questionAge, .questionSex, .questionHeight, .questionWeight, .questionActivity, .questionDuration:
            return "Next"
        case .potential, .projection:
            return "Continue Your Journey"
        case .personalizedGoals:
            return viewModel.isApplyingMacros ? "Applying..." : "Continue Your Journey"
        case .claim:
            return "Sign In to Claim Plan"
        case .paywallReveal:
            return "Continue"
        case .paywall:
            return "Start 7-Day Free Trial"
        case .building, .personalizing:
            return ""
        }
    }

    private var primaryGradient: [Color] {
        if step.isFeatureSlide {
            return currentSlide.buttonGradient
        }

        switch step {
        case .questionGoal:
            return [Color(red: 0.84, green: 0.44, blue: 0.92), Color(red: 0.95, green: 0.33, blue: 0.43)]
        case .questionExperience, .questionFrequency, .questionEnvironment, .questionFocus, .questionName, .questionAge, .questionSex, .questionHeight, .questionWeight, .questionActivity, .questionDuration, .questionDiet:
            return [Color(red: 0.39, green: 0.52, blue: 0.94), Color(red: 0.33, green: 0.32, blue: 0.93)]
        default:
            return [Color(red: 0.09, green: 0.49, blue: 0.98), Color(red: 0.09, green: 0.49, blue: 0.98)]
        }
    }

    private var isPrimaryDisabled: Bool {
        if viewModel.isSubmitting {
            return true
        }

        if step == .personalizedGoals, viewModel.isApplyingMacros {
            return true
        }

        switch step {
        case .questionExperience:
            return selectedExperience == nil
        case .questionGoal:
            return selectedGoal == nil
        case .questionFrequency:
            return selectedFrequency == nil
        case .questionEnvironment:
            return selectedEnvironment == nil
        case .questionFocus:
            return selectedFocus == nil
        case .questionName:
            return fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .questionAge:
            return !isValidAge
        case .questionSex:
            return selectedSex == nil
        case .questionHeight:
            return !isValidHeight
        case .questionWeight:
            return !isValidWeight
        case .questionActivity:
            return selectedActivity == nil
        case .questionDuration:
            return selectedDuration == nil
        case .questionDiet:
            return selectedDiet == nil
        default:
            return false
        }
    }

    private var isValidAge: Bool {
        guard let value = Int(age) else { return false }
        return value >= 13 && value <= 100
    }

    private var isValidHeight: Bool {
        guard let feet = Int(heightFeet),
              let inches = Int(heightInches) else { return false }
        return (3...8).contains(feet) && (0...11).contains(inches)
    }

    private var isValidWeight: Bool {
        guard let current = Double(currentWeight),
              let goal = Double(targetWeight) else { return false }
        return current > 40 && goal > 40
    }

    private var showsBackButton: Bool {
        switch step {
        case .hero, .building, .personalizing:
            return false
        case _ where step.isFeatureSlide:
            return false
        default:
            return true
        }
    }

    private var claimTime: (hours: String, minutes: String, seconds: String) {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: now, to: claimDeadline)
        let hours = String(format: "%02d", max(components.hour ?? 0, 0))
        let minutes = String(format: "%02d", max(components.minute ?? 0, 0))
        let seconds = String(format: "%02d", max(components.second ?? 0, 0))
        return (hours, minutes, seconds)
    }

    private var potentialNarrative: String {
        let namePart = fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "You" : fullName
        let verb = namePart == "You" ? "are" : "is"
        let goalText = selectedGoal?.previewText ?? "building muscle"
        let daysText = selectedFrequency ?? 3
        let focusText = selectedFocus?.title.lowercased() ?? "strength"
        let durationText = selectedDuration?.rawValue ?? 45

        return "\(namePart) \(verb) set on \(goalText), training \(daysText) days each week with \(focusText) as the priority. FIT AI will build \(durationText)-minute sessions and adaptive nutrition targets so you improve with consistency and clear direction."
    }

    private func applyPersonalizedMacrosIfEnabled() async {
        guard shouldApplyPersonalizedMacros else { return }
        let defaults = personalizedMacroDefaults()
        let edited = MacroTotals(
            calories: max(Double(editedCalories) ?? defaults.calories, 0),
            protein: max(Double(editedProtein) ?? defaults.protein, 0),
            carbs: max(Double(editedCarbs) ?? defaults.carbs, 0),
            fats: max(Double(editedFats) ?? defaults.fats, 0)
        )
        await viewModel.applyMacros(roundedMacros(edited))
    }

    private func personalizedMacroDefaults() -> MacroTotals {
        let startWeightValue = parseWeight(currentWeight, fallback: parseWeight(viewModel.form.weightLbs, fallback: 190))
        let ageValue = resolvedAge()
        let heightFeetValue = Int(heightFeet) ?? Int(viewModel.form.heightFeet) ?? 5
        let heightInchesValue = Int(heightInches) ?? Int(viewModel.form.heightInches) ?? 9

        return roundedMacros(
            calculateMacroTargets(
                weightLbs: startWeightValue,
                heightFeet: heightFeetValue,
                heightInches: heightInchesValue,
                age: ageValue,
                sex: viewModel.form.sex,
                trainingDaysPerWeek: viewModel.form.workoutDaysPerWeek,
                goal: viewModel.form.goal,
                goalWeightLbs: parseWeight(targetWeight, fallback: parseWeight(viewModel.form.goalWeightLbs, fallback: startWeightValue))
            )
        )
    }

    private func parseWeight(_ text: String, fallback: Double) -> Double {
        let sanitized = text.filter { "0123456789.".contains($0) }
        guard let value = Double(sanitized), value > 0 else {
            return fallback
        }
        return value
    }

    private func formatWeight(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }

    private func formatDelta(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let sign = rounded > 0 ? "+" : (rounded < 0 ? "-" : "")
        return "\(sign)\(formatWeight(abs(rounded)))"
    }

    private func sanitizeMacroInput(_ value: String, maxLength: Int) -> String {
        String(value.filter { "0123456789".contains($0) }.prefix(maxLength))
    }

    private func resolvedAge() -> Int {
        if let parsedAge = Int(age), (13...100).contains(parsedAge) {
            return parsedAge
        }
        if let parsedAge = Int(viewModel.form.age), (13...100).contains(parsedAge) {
            return parsedAge
        }
        if let birthday = viewModel.form.birthday {
            return max(13, min(100, Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 25))
        }
        return 25
    }

    private func clampWeightPaceRate(_ value: Double) -> Double {
        min(max(value, 0.5), 2.0)
    }

    private func healthyWeeklyRate(for goal: OnboardingForm.Goal) -> Double {
        switch goal {
        case .loseWeight:
            return clampWeightPaceRate(viewModel.form.weeklyWeightLossLbs)
        case .loseWeightFast:
            return max(1.5, clampWeightPaceRate(viewModel.form.weeklyWeightLossLbs))
        case .gainWeight:
            return clampWeightPaceRate(viewModel.form.weeklyWeightLossLbs)
        case .maintain:
            return 0
        }
    }

    private func suggestedTargetDate(currentWeight: Double, goalWeight: Double, goal: OnboardingForm.Goal) -> Date {
        let delta = abs(goalWeight - currentWeight)
        let weeklyRate = healthyWeeklyRate(for: goal)

        guard weeklyRate > 0 else {
            return Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date()) ?? Date()
        }

        let weeksNeeded = delta / weeklyRate
        let daysNeeded = Int(ceil(weeksNeeded * 7))
        let clampedDays = max(14, min(daysNeeded, 730))
        return Calendar.current.date(byAdding: .day, value: clampedDays, to: Date()) ?? Date()
    }

    private func calculateMacroTargets(
        weightLbs: Double,
        heightFeet: Int,
        heightInches: Int,
        age: Int,
        sex: OnboardingForm.Sex,
        trainingDaysPerWeek: Int,
        goal: OnboardingForm.Goal,
        goalWeightLbs: Double? = nil
    ) -> MacroTotals {
        let weightKg = weightLbs * 0.453592
        let heightCm = (Double(heightFeet) * 30.48) + (Double(heightInches) * 2.54)

        let bmr: Double
        switch sex {
        case .male:
            bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) + 5
        case .female:
            bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) - 161
        case .other, .preferNotToSay:
            bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) - 78
        }

        let activityMultiplier: Double
        switch trainingDaysPerWeek {
        case ..<3:
            activityMultiplier = 1.375
        case 3...4:
            activityMultiplier = 1.55
        case 5...6:
            activityMultiplier = 1.725
        default:
            activityMultiplier = 1.9
        }

        let maintenanceCalories = bmr * activityMultiplier

        let calories: Double
        switch goal {
        case .maintain:
            calories = maintenanceCalories
        case .loseWeight, .loseWeightFast:
            calories = maintenanceCalories * 0.8
        case .gainWeight:
            calories = maintenanceCalories * 1.15
        }

        let macroWeightLbs: Double
        if goal == .gainWeight, let goalWeightLbs, goalWeightLbs > 0 {
            macroWeightLbs = goalWeightLbs
        } else {
            macroWeightLbs = weightLbs
        }

        let fats = weightLbs * 0.3
        let protein = macroWeightLbs * 1.0
        let carbs = macroWeightLbs * 1.0

        return MacroTotals(calories: calories, protein: protein, carbs: carbs, fats: fats)
    }

    private func roundedMacros(_ macros: MacroTotals) -> MacroTotals {
        MacroTotals(
            calories: macros.calories.rounded(),
            protein: macros.protein.rounded(),
            carbs: macros.carbs.rounded(),
            fats: macros.fats.rounded()
        )
    }

    private func symbolForGoal(_ option: MainGoalOption) -> String {
        switch option {
        case .buildMuscle:
            return "dumbbell.fill"
        case .loseFat:
            return "flame.fill"
        case .maintain:
            return "equal.circle.fill"
        }
    }

    private func symbolForEnvironment(_ option: TrainingEnvironmentOption) -> String {
        switch option {
        case .gym:
            return "figure.strengthtraining.traditional"
        case .home:
            return "house.fill"
        case .both:
            return "square.grid.2x2.fill"
        }
    }

    private func symbolForFocus(_ option: FocusAreaOption) -> String {
        switch option {
        case .strength:
            return "bolt.fill"
        case .endurance:
            return "figure.run"
        case .physique:
            return "person.fill"
        case .athleticism:
            return "target"
        }
    }

    private func symbolForSex(_ option: OnboardingForm.Sex) -> String {
        switch option {
        case .male:
            return "person.fill"
        case .female:
            return "person.fill"
        case .other:
            return "person.2.fill"
        case .preferNotToSay:
            return "eye.slash.fill"
        }
    }

    private func handlePrimaryAction() {
        switch step {
        case .claim, .paywall:
            viewModel.showEmailSignup = true
        case .personalizedGoals:
            Task {
                await applyPersonalizedMacrosIfEnabled()
                if Task.isCancelled { return }
                goNext()
            }
        default:
            goNext()
        }
    }

    private func goNext() {
        guard let next = ReplicaOnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func goBack() {
        guard let previous = ReplicaOnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func syncSelectionsFromModel() {
        selectedGoal = viewModel.mainGoalSelection
        selectedFrequency = viewModel.splitDaysPerWeek
        selectedEnvironment = viewModel.trainingEnvironmentSelection
        selectedFocus = viewModel.focusAreaSelection
        selectedSex = viewModel.form.sex
        selectedActivity = viewModel.form.activityLevel

        fullName = viewModel.form.fullName
        age = viewModel.form.age
        heightFeet = viewModel.form.heightFeet
        heightInches = viewModel.form.heightInches
        currentWeight = viewModel.form.weightLbs
        targetWeight = viewModel.form.goalWeightLbs
        foodNotes = viewModel.form.foodAllergies

        let savedCalories = Int(viewModel.form.macroCalories)
        let savedProtein = Int(viewModel.form.macroProtein)
        let savedCarbs = Int(viewModel.form.macroCarbs)
        let savedFats = Int(viewModel.form.macroFats)
        let hasSavedMacros = (savedCalories ?? 0) > 0 || (savedProtein ?? 0) > 0 || (savedCarbs ?? 0) > 0 || (savedFats ?? 0) > 0
        if hasSavedMacros {
            editedCalories = "\(max(savedCalories ?? 0, 0))"
            editedProtein = "\(max(savedProtein ?? 0, 0))"
            editedCarbs = "\(max(savedCarbs ?? 0, 0))"
            editedFats = "\(max(savedFats ?? 0, 0))"
            goalsMacrosInitialized = true
        } else {
            editedCalories = ""
            editedProtein = ""
            editedCarbs = ""
            editedFats = ""
            goalsMacrosInitialized = false
        }

        if let duration = ReplicaDurationOption(rawValue: viewModel.form.workoutDurationMinutes) {
            selectedDuration = duration
        }

        if let style = ReplicaDietOption.allCases.first(where: { $0.title.caseInsensitiveCompare(viewModel.form.dietStyle) == .orderedSame }) {
            selectedDiet = style
        }

        switch viewModel.form.trainingLevel {
        case .beginner:
            selectedExperience = .beginner
        case .intermediate:
            selectedExperience = .intermediate
        case .advanced:
            selectedExperience = .advanced
        }
    }

    private func startAutoStepIfNeeded() {
        autoTask?.cancel()

        if step == .building {
            buildingStage = 0
            buildingProgress = 0
            autoTask = Task {
                await runBuildingProgress()
            }
        }

        if step == .personalizing {
            personalizingProgress = 0
            autoTask = Task {
                await runPersonalizingProgress()
            }
        }
    }

    @MainActor
    private func runBuildingProgress() async {
        let checkpoints: [(Int, Double)] = [(1, 0.35), (2, 0.67), (3, 1.0)]

        for checkpoint in checkpoints {
            try? await Task.sleep(nanoseconds: 720_000_000)
            if Task.isCancelled { return }
            buildingStage = checkpoint.0
            buildingProgress = checkpoint.1
        }

        try? await Task.sleep(nanoseconds: 380_000_000)
        if Task.isCancelled { return }
        step = .potential
    }

    @MainActor
    private func runPersonalizingProgress() async {
        for value in stride(from: 0.1, through: 1.0, by: 0.1) {
            try? await Task.sleep(nanoseconds: 260_000_000)
            if Task.isCancelled { return }
            personalizingProgress = min(value, 1.0)
        }

        try? await Task.sleep(nanoseconds: 280_000_000)
        if Task.isCancelled { return }
        step = .claim
    }
}

private struct PersonalizedGoalsChartView: View {
    let startWeight: Double
    let targetWeight: Double
    let startDate: Date
    let targetDate: Date
    let accent: Color
    let primaryText: Color
    let gridTint: Color

    private let chartInsets = EdgeInsets(top: 12, leading: 38, bottom: 24, trailing: 12)
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let chartRect = CGRect(
                x: chartInsets.leading,
                y: chartInsets.top,
                width: size.width - chartInsets.leading - chartInsets.trailing,
                height: size.height - chartInsets.top - chartInsets.bottom
            )
            let weights = projectionWeights()
            let scale = weightScale(for: weights)
            let points = projectionPoints(weights: weights, scale: scale, in: chartRect)
            let yLabels = axisLabels(min: scale.min, max: scale.max)
            let monthLabels = monthMarkers()
            let xFractions: [CGFloat] = [0.25, 0.5, 0.75]

            ZStack {
                Path { path in
                    for index in 0...3 {
                        let y = chartRect.minY + chartRect.height * CGFloat(index) / 3
                        path.move(to: CGPoint(x: chartRect.minX, y: y))
                        path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                    }
                    for fraction in xFractions {
                        let x = chartRect.minX + chartRect.width * fraction
                        path.move(to: CGPoint(x: x, y: chartRect.minY))
                        path.addLine(to: CGPoint(x: x, y: chartRect.maxY))
                    }
                }
                .stroke(gridTint.opacity(0.16), lineWidth: 1)

                if points.count > 1 {
                    areaPath(points: points, in: chartRect)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.26),
                                    accent.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    curvePath(points: points)
                        .stroke(
                            accent,
                            style: StrokeStyle(
                                lineWidth: 3,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    ForEach(points.indices, id: \.self) { index in
                        Circle()
                            .fill(Color.white)
                            .frame(width: index == points.count - 1 ? 14 : 12, height: index == points.count - 1 ? 14 : 12)
                            .overlay(
                                Circle()
                                    .stroke(accent, lineWidth: 3)
                            )
                            .position(points[index])
                    }
                }

                ForEach(yLabels.indices, id: \.self) { index in
                    let y = chartRect.minY + chartRect.height * CGFloat(index) / 3
                    Text(yLabels[index])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(primaryText.opacity(0.58))
                        .position(x: chartRect.minX - 14, y: y)
                }

                ForEach(monthLabels.indices, id: \.self) { index in
                    let x = chartRect.minX + chartRect.width * xFractions[index]
                    Text(monthLabels[index])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(primaryText.opacity(0.58))
                        .position(x: x, y: chartRect.maxY + 14)
                }
            }
        }
    }

    private func projectionWeights() -> [Double] {
        let steps: [Double] = [0, 0.22, 0.5, 0.78, 1]
        let delta = targetWeight - startWeight
        return steps.map { step in
            let eased: Double
            if delta < 0 {
                eased = 1 - pow(1 - step, 2.2)
            } else if delta > 0 {
                eased = pow(step, 1.6)
            } else {
                eased = step
            }
            return startWeight + delta * eased
        }
    }

    private func weightScale(for weights: [Double]) -> (min: Double, max: Double) {
        let minValue = min(weights.min() ?? startWeight, startWeight, targetWeight)
        let maxValue = max(weights.max() ?? startWeight, startWeight, targetWeight)
        let padding = max(2.0, abs(maxValue - minValue) * 0.15)
        return (minValue - padding, maxValue + padding)
    }

    private func projectionPoints(weights: [Double], scale: (min: Double, max: Double), in rect: CGRect) -> [CGPoint] {
        guard weights.count > 1 else { return [] }
        let range = max(scale.max - scale.min, 1)
        let stepX = rect.width / CGFloat(weights.count - 1)
        return weights.enumerated().map { index, weight in
            let normalized = (weight - scale.min) / range
            let x = rect.minX + CGFloat(index) * stepX
            let y = rect.maxY - CGFloat(normalized) * rect.height
            return CGPoint(x: x, y: y)
        }
    }

    private func axisLabels(min: Double, max: Double) -> [String] {
        let steps = 3
        let stepValue = (max - min) / Double(steps)
        return (0...steps).map { index in
            formatWeight(max - stepValue * Double(index))
        }
    }

    private func monthMarkers() -> [String] {
        let calendar = Calendar.current
        let totalDays = max(1, calendar.dateComponents([.day], from: startDate, to: targetDate).day ?? 0)
        let offsets = [totalDays / 3, (totalDays * 2) / 3, totalDays].map { max(1, $0) }
        return offsets.compactMap { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: startDate) ?? startDate
            return Self.monthFormatter.string(from: date)
        }
    }

    private func curvePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        path.move(to: points[0])
        for index in 0..<(points.count - 1) {
            let p0 = index == 0 ? points[index] : points[index - 1]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : points[index + 1]
            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }

    private func areaPath(points: [CGPoint], in rect: CGRect) -> Path {
        var path = curvePath(points: points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private func formatWeight(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}

private struct ProjectionChartView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let withAI: [CGFloat] = [0.18, 0.42, 0.62, 0.73, 0.80, 0.84]
    private let traditional: [CGFloat] = [0.18, 0.18, 0.20, 0.24, 0.30, 0.38]

    private var onboardingPrimaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var onboardingSurfaceTint: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                legend(color: .green, text: "With FIT AI")
                legend(color: .red, text: "Traditional")
                Spacer()
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height

                ZStack(alignment: .bottomLeading) {
                    Path { path in
                        let baselineY = height
                        path.move(to: CGPoint(x: 0, y: baselineY))
                        path.addLine(to: CGPoint(x: width, y: baselineY))
                    }
                    .stroke(onboardingSurfaceTint.opacity(0.15), lineWidth: 1)

                    linePath(points: withAI, width: width, height: height)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    linePath(points: traditional, width: width, height: height)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    pointsOverlay(points: withAI, width: width, height: height, color: .green)
                    pointsOverlay(points: traditional, width: width, height: height, color: .red)
                }
            }
            .frame(height: 145)

            HStack {
                ForEach(1...6, id: \.self) { month in
                    Text("M\(month)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(onboardingPrimaryText.opacity(0.6))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(onboardingPrimaryText.opacity(0.85))
        }
    }

    private func linePath(points: [CGFloat], width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * width
                let y = height - (point * height)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func pointsOverlay(points: [CGFloat], width: CGFloat, height: CGFloat, color: Color) -> some View {
        ZStack {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * width
                let y = height - (point * height)
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .position(x: x, y: y)
            }
        }
    }
}

private struct FadeSlideModifier: ViewModifier {
    let y: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: y)
    }
}

private extension AnyTransition {
    static func fadeSlide(y: CGFloat) -> AnyTransition {
        .modifier(
            active: FadeSlideModifier(y: y, opacity: 0),
            identity: FadeSlideModifier(y: 0, opacity: 1)
        )
    }
}
