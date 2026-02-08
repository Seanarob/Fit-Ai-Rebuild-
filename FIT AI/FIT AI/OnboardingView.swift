#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
import Combine
import PhotosUI
import SwiftUI
import UIKit

private enum OnboardingStepIndex: Int, CaseIterable {
    case outcome = 0
    case featureCoach
    case featureTraining
    case featureCheckin
    case featureNutrition
    case featureProgress
    case featureInsights
    case goal
    case frequency
    case environment
    case experience
    case focus
    case building
    case comparison
    case reflection
    case claim
    case trial
    case instantWin

    static let featureSlides: [OnboardingStepIndex] = [
        .featureCoach,
        .featureTraining,
        .featureCheckin,
        .featureNutrition,
        .featureProgress,
        .featureInsights,
    ]

    var isFeatureSlide: Bool {
        Self.featureSlides.contains(self)
    }

    var featureImageAsset: String? {
        switch self {
        case .featureCoach:
            return "OnboardingFeatureCoach"
        case .featureTraining:
            return "OnboardingFeatureTraining"
        case .featureCheckin:
            return "OnboardingFeatureCheckin"
        case .featureNutrition:
            return "OnboardingFeatureNutrition"
        case .featureProgress:
            return "OnboardingFeatureProgress"
        case .featureInsights:
            return "OnboardingFeatureInsights"
        default:
            return nil
        }
    }
}

private enum TrialPlan: String, CaseIterable, Identifiable {
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly:
            return "FIT AI Monthly"
        case .yearly:
            return "FIT AI Yearly"
        }
    }

    var price: String {
        switch self {
        case .monthly:
            return "$8.99 / month"
        case .yearly:
            return "$86 / year"
        }
    }

    var detail: String {
        switch self {
        case .monthly:
            return "Billed monthly"
        case .yearly:
            return "Save 20%  •  $7.17/month billed yearly"
        }
    }
}

enum MainGoalOption: String, CaseIterable, Identifiable {
    case buildMuscle
    case loseFat
    case recomp
    case performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buildMuscle: return "Build muscle"
        case .loseFat: return "Lose fat"
        case .recomp: return "Recomp"
        case .performance: return "Performance"
        }
    }

    var icon: String {
        switch self {
        case .buildMuscle: return "dumbbell.fill"
        case .loseFat: return "flame.fill"
        case .recomp: return "arrow.triangle.2.circlepath"
        case .performance: return "bolt.fill"
        }
    }

    var coachText: String {
        switch self {
        case .buildMuscle: return "build muscle"
        case .loseFat: return "lose fat"
        case .recomp: return "recomp your body"
        case .performance: return "boost performance"
        }
    }

    var previewText: String {
        switch self {
        case .buildMuscle: return "building muscle"
        case .loseFat: return "losing fat"
        case .recomp: return "recomping your body"
        case .performance: return "performance"
        }
    }
}

enum TrainingEnvironmentOption: String, CaseIterable, Identifiable {
    case gym
    case home
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gym: return "Gym"
        case .home: return "Home"
        case .both: return "Both"
        }
    }

    var icon: String {
        switch self {
        case .gym: return "dumbbell.fill"
        case .home: return "house.fill"
        case .both: return "square.grid.2x2"
        }
    }
}

enum FocusAreaOption: String, CaseIterable, Identifiable {
    case strength
    case endurance
    case physique
    case athleticism

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: return "Strength"
        case .endurance: return "Endurance"
        case .physique: return "Physique"
        case .athleticism: return "Athleticism"
        }
    }

    var icon: String {
        switch self {
        case .strength: return "bolt.fill"
        case .endurance: return "figure.run"
        case .physique: return "person.fill"
        case .athleticism: return "target"
        }
    }
}

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var healthKitManager = HealthKitManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // Editable macro state
    @State private var editedCalories: String = ""
    @State private var editedProtein: String = ""
    @State private var editedCarbs: String = ""
    @State private var editedFats: String = ""
    @State private var macrosInitialized = false
    @State private var healthKitStatusMessage: String?
    @State private var analysisStage: Int = 0
    @State private var analysisCTAVisible = false
    @State private var analysisStarted = false
    @State private var progressPhotoItem: PhotosPickerItem?
    @State private var progressPhoto: UIImage?
    @State private var progressPhotoError: String?
    @State private var isShowingProgressPhotoCamera = false
    @State private var isShowingPlanPreview = false
    @State private var selectedTrialPlan: TrialPlan = .yearly
    
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                progressHeader
                    .padding(.top, 8)
                    .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 24) {
                        heroIllustration

                        VStack(alignment: .leading, spacing: 12) {
                            Text(stepTitle)
                                .font(FitFont.heading(size: 28, weight: .bold))
                                .foregroundColor(FitTheme.textPrimary)

                            if let subtitle = stepSubtitle {
                                Text(subtitle)
                                    .font(FitFont.body(size: 15, weight: .regular))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)

                        stepContent
                            .padding(.horizontal, 24)

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 20)
                }

                stepActions
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $viewModel.showHeightPicker) {
            HeightPickerView(
                viewModel: viewModel,
                isPresented: $viewModel.showHeightPicker
            )
        }
        .sheet(isPresented: $viewModel.showDatePicker) {
            DatePickerSheet(
                date: $viewModel.selectedDate,
                title: viewModel.datePickerTitle,
                isPresented: $viewModel.showDatePicker,
                onSave: { date in
                    viewModel.updateBirthday(date)
                }
            )
        }
        .sheet(isPresented: $viewModel.showLogin) {
            LoginView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showEmailSignup) {
            EmailSignupView(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingProgressPhotoCamera) {
            OnboardingCameraPicker(isPresented: $isShowingProgressPhotoCamera) { image in
                applyProgressPhoto(image)
            }
        }
        .onOpenURL { url in
            Task {
                await viewModel.handleAuthCallback(url: url)
            }
        }
        .preferredColorScheme(.light)
    }
    
    // MARK: - Welcome Screen
    
    private var welcomeScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                // Coach character
                CoachCharacterView(size: 200, showBackground: true, pose: .talking)
                
                Text("This is not a tracker.")
                    .font(FitFont.heading(size: 34, weight: .bold))
                    .foregroundColor(FitTheme.textPrimary)
                
                VStack(spacing: 8) {
                    Text("It is your coach.")
                    Text("Every day it watches, reacts, and adjusts.")
                }
                .font(FitFont.body(size: 16, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
                .foregroundColor(FitTheme.textSecondary)
                .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    viewModel.startOnboarding()
                } label: {
                    Text("Continue")
                        .font(FitFont.body(size: 17, weight: .semibold))
                        .foregroundColor(FitTheme.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(FitTheme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                
                Button {
                    viewModel.showLogin = true
                } label: {
                    Text("Already have an account? **Sign in**")
                        .font(FitFont.body(size: 15, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Progress Indicators

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                GeometryReader { proxy in
                    let progress = CGFloat(viewModel.progressIndex + 1) / CGFloat(max(viewModel.progressSteps.count, 1))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(FitTheme.cardStroke.opacity(0.55))
                            .frame(height: 4)
                        Capsule()
                            .fill(FitTheme.accent)
                            .frame(width: max(progress * proxy.size.width, 12), height: 4)
                    }
                }
                .frame(height: 4)

                if viewModel.isFeatureSlideActive {
                    Button("Skip") {
                        viewModel.skipFeatureTour()
                    }
                    .font(FitFont.body(size: 13, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                    .buttonStyle(.plain)
                }
            }

            Text(viewModel.progressLabel)
                .font(FitFont.body(size: 12, weight: .medium))
                .foregroundColor(FitTheme.textSecondary)
        }
    }
    
    // MARK: - Hero Illustrations
    
    @ViewBuilder
    private var heroIllustration: some View {
        switch viewModel.currentStepCase {
        case .outcome:
            CoachCharacterView(size: 180, showBackground: true, pose: .talking)
        case .featureCoach:
            OnboardingFeaturePhoneMock(imageName: "OnboardingFeatureCoach")
        case .featureTraining:
            OnboardingFeaturePhoneMock(imageName: "OnboardingFeatureTraining")
        case .featureCheckin:
            OnboardingFeaturePhoneMock(imageName: "OnboardingFeatureCheckin")
        case .featureNutrition:
            OnboardingFeaturePhoneMock(imageName: "OnboardingFeatureNutrition")
        case .featureProgress:
            OnboardingFeaturePhoneMock(imageName: "OnboardingFeatureProgress")
        case .featureInsights:
            OnboardingFeaturePhoneMock(imageName: "OnboardingFeatureInsights")
        case .goal:
            CoachCharacterView(size: 180, showBackground: true, pose: .celebration)
        case .frequency:
            CoachCharacterView(size: 180, showBackground: true, pose: .idle)
        case .environment:
            CoachCharacterView(size: 180, showBackground: true, pose: .neutral)
        case .experience:
            CoachCharacterView(size: 180, showBackground: true, pose: .talking)
        case .focus:
            CoachCharacterView(size: 180, showBackground: true, pose: .thinking)
        case .building:
            CoachCharacterView(size: 180, showBackground: true, pose: .idle)
        case .comparison:
            CoachCharacterView(size: 180, showBackground: true, pose: .neutral)
        case .reflection:
            CoachCharacterView(size: 180, showBackground: true, pose: .talking)
        case .claim:
            CoachCharacterView(size: 180, showBackground: true, pose: .celebration)
        case .trial:
            CoachCharacterView(size: 180, showBackground: true, pose: .talking)
        case .instantWin:
            CoachCharacterView(size: 180, showBackground: true, pose: .celebration)
        default:
            CoachCharacterView(size: 180, showBackground: true, pose: .idle)
        }
    }
    
    // MARK: - Step Content
    
    private var stepTitle: String {
        switch viewModel.currentStepCase {
        case .outcome: return "Train smarter. Stay consistent."
        case .featureCoach: return "AI Fitness Coach"
        case .featureTraining: return "Personalized Training"
        case .featureCheckin: return "Daily Check-Ins"
        case .featureNutrition: return "Nutrition + Macros"
        case .featureProgress: return "Progress Tracking"
        case .featureInsights: return "Coach Insights"
        case .goal: return "What's your main goal right now?"
        case .frequency: return "How many days can you train each week?"
        case .environment: return "Where do you train most?"
        case .experience: return "What's your training experience?"
        case .focus: return "What's the one area you want to improve most?"
        case .building: return "Building your plan"
        case .comparison: return "6-month progress projection"
        case .reflection: return "Your progress potential"
        case .claim: return "Claim your plan"
        case .trial: return "Unlock FIT AI Pro"
        case .instantWin: return "Today is ready"
        default: return ""
        }
    }
    
    private var stepSubtitle: String? {
        switch viewModel.currentStepCase {
        case .outcome: return "AI coaching for workouts and nutrition, built around your life."
        case .featureCoach: return "Daily guidance tuned to your goal, schedule, and progress."
        case .featureTraining: return "Your split and progression are built for your experience and equipment."
        case .featureCheckin: return "Fast accountability prompts keep your streak and momentum alive."
        case .featureNutrition: return "Hit targets you can sustain with simple logging and weekly adjustments."
        case .featureProgress: return "Track trends, check-ins, and consistency so you always know what to improve."
        case .featureInsights: return "Get clear recap notes on what improved and what to do next."
        case .goal: return nil
        case .frequency: return nil
        case .environment: return nil
        case .experience: return nil
        case .focus: return nil
        case .building: return "This will only take a moment."
        case .comparison: return "With FIT AI vs self-guided consistency."
        case .reflection: return "See how FIT AI can accelerate your fitness journey."
        case .claim: return "Sign in now to preserve your progress and personalized training data."
        case .trial: return "7-day free trial, then $8.99/month or $86/year (save 20%)."
        case .instantWin: return nil
        default: return nil
        }
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStepCase {
        case .outcome:
            outcomePromiseStep
        case .featureCoach, .featureTraining, .featureCheckin, .featureNutrition, .featureProgress, .featureInsights:
            featureSlideStep
        case .goal:
            mainGoalStep
        case .frequency:
            trainingFrequencyStep
        case .environment:
            trainingEnvironmentStep
        case .experience:
            trainingExperienceStep
        case .focus:
            focusAreaStep
        case .building:
            buildingPlanStep
        case .comparison:
            futureStateComparisonStep
        case .reflection:
            coachReflectionStep
        case .claim:
            claimPlanStep
        case .trial:
            trialDecisionStep
        case .instantWin:
            instantWinStep
        default:
            EmptyView()
        }
    }
    
    // MARK: - Step Views

    private var outcomePromiseStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                planDetailRow(text: "Adaptive training plans")
                planDetailRow(text: "Macros that adjust weekly")
                planDetailRow(text: "Quick logging + streak accountability")
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )

            Text("One tap to begin your personalized program.")
                .font(FitFont.body(size: 13, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private var featureSlideStep: some View {
        HStack(spacing: 20) {
            featurePill(text: "Personalized")
            featurePill(text: "AI-Powered")
            featurePill(text: "Real-time")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func featurePill(text: String) -> some View {
        Text(text)
            .font(FitFont.body(size: 12, weight: .semibold))
            .foregroundColor(FitTheme.textSecondary)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(FitTheme.cardHighlight)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
    }

    private var mainGoalStep: some View {
        VStack(spacing: 12) {
            ForEach(MainGoalOption.allCases) { option in
                OnboardingOptionRow(
                    title: option.title,
                    systemImage: option.icon,
                    isSelected: viewModel.mainGoalSelection == option,
                    action: { viewModel.setMainGoal(option) }
                )
            }
        }
    }

    private var trainingFrequencyStep: some View {
        let options = [
            TrainingFrequencyOption(label: "2", days: 2),
            TrainingFrequencyOption(label: "3", days: 3),
            TrainingFrequencyOption(label: "4", days: 4),
            TrainingFrequencyOption(label: "5+", days: 5)
        ]
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(options) { option in
                    let isSelected = option.days == 5
                        ? viewModel.splitDaysPerWeek >= 5
                        : viewModel.splitDaysPerWeek == option.days
                    Button {
                        viewModel.setTrainingFrequency(option.days)
                    } label: {
                        Text(option.label)
                            .font(FitFont.body(size: 16, weight: .semibold))
                            .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isSelected ? FitTheme.accent : Color.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.clear : FitTheme.cardStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Choose a schedule you can repeat.")
                .font(FitFont.body(size: 12, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private var trainingEnvironmentStep: some View {
        VStack(spacing: 12) {
            ForEach(TrainingEnvironmentOption.allCases) { option in
                OnboardingOptionRow(
                    title: option.title,
                    systemImage: option.icon,
                    isSelected: viewModel.trainingEnvironmentSelection == option,
                    action: { viewModel.setTrainingEnvironment(option) }
                )
            }
        }
    }

    private var trainingExperienceStep: some View {
        trainingLevelStep
    }

    private var focusAreaStep: some View {
        VStack(spacing: 12) {
            ForEach(FocusAreaOption.allCases) { option in
                OnboardingOptionRow(
                    title: option.title,
                    systemImage: option.icon,
                    isSelected: viewModel.focusAreaSelection == option,
                    action: { viewModel.setFocusArea(option) }
                )
            }
        }
    }

    private var buildingPlanStep: some View {
        PlanBuildStateView(stage: analysisStage)
            .onAppear {
                guard !analysisStarted else { return }
                analysisStarted = true
                analysisStage = 0
                analysisCTAVisible = false
                viewModel.prepareCoachSignalsIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    guard viewModel.currentStepCase == .building else { return }
                    analysisStage = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    guard viewModel.currentStepCase == .building else { return }
                    analysisStage = 2
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    guard viewModel.currentStepCase == .building else { return }
                    analysisStage = 3
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                    guard viewModel.currentStepCase == .building else { return }
                    analysisStage = 4
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    guard viewModel.currentStepCase == .building else { return }
                    viewModel.nextStep()
                }
            }
            .onDisappear {
                analysisStarted = false
            }
    }

    private var futureStateComparisonStep: some View {
        let metrics = comparisonMetrics
        return VStack(spacing: 16) {
            FutureStateComparisonCard(withMetrics: metrics.with, withoutMetrics: metrics.without)
        }
    }

    private var coachReflectionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(coachReflectionText)
                .font(FitFont.body(size: 15, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FitTheme.cardStroke, lineWidth: 1)
                )
        }
    }

    private var claimPlanStep: some View {
        VStack(spacing: 16) {
            ClaimPlanCard()

            Button {
                isShowingPlanPreview.toggle()
            } label: {
                Text(isShowingPlanPreview ? "Hide preview" : "View a preview")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(FitTheme.accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if isShowingPlanPreview {
                PlanPreviewCard(goal: viewModel.mainGoalSelection, daysPerWeek: viewModel.form.workoutDaysPerWeek)
            }
        }
    }

    private var trialDecisionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            BenefitRow(text: "Adaptive workout plans")
            BenefitRow(text: "Macro coaching + nutrition support")
            BenefitRow(text: "Weekly coach adjustments")
            BenefitRow(text: "Progress analytics + recaps")

            VStack(spacing: 10) {
                ForEach(TrialPlan.allCases) { plan in
                    TrialPlanOptionRow(
                        plan: plan,
                        isSelected: selectedTrialPlan == plan,
                        action: { selectedTrialPlan = plan }
                    )
                }
            }
            .padding(.top, 4)

            Text("7-day free trial, then renews at the selected plan unless canceled at least 24 hours before renewal.")
                .font(FitFont.body(size: 11, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }

    private var instantWinStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            planDetailRow(text: "Your first workout is loaded.")
            planDetailRow(text: "Your macro targets are set.")
            planDetailRow(text: "Your coach left you a note.")
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }

    private var comparisonMetrics: (with: [ComparisonMetric], without: [ComparisonMetric]) {
        let days = max(viewModel.form.workoutDaysPerWeek, 2)
        let consistencyWith = days >= 4 ? "82%" : (days == 3 ? "78%" : "72%")
        let consistencyWithout = days >= 4 ? "56%" : (days == 3 ? "52%" : "46%")
        let adherenceWith = days >= 4 ? "80%" : (days == 3 ? "74%" : "70%")
        let adherenceWithout = days >= 4 ? "58%" : (days == 3 ? "54%" : "50%")

        let trendLabel: String
        let trendWith: String
        let trendWithout: String

        switch viewModel.form.goal {
        case .gainWeight:
            trendLabel = "Weight trend"
            trendWith = "+0.7 lb/week"
            trendWithout = "+0.2 lb/week"
        case .loseWeight, .loseWeightFast:
            trendLabel = "Weight trend"
            trendWith = "-0.7 lb/week"
            trendWithout = "-0.2 lb/week"
        case .maintain:
            trendLabel = "Strength trend"
            trendWith = "+6%"
            trendWithout = "+1%"
        }

        let withMetrics = [
            ComparisonMetric(label: "Consistency", value: consistencyWith),
            ComparisonMetric(label: trendLabel, value: trendWith),
            ComparisonMetric(label: "Adherence", value: adherenceWith)
        ]

        let withoutMetrics = [
            ComparisonMetric(label: "Consistency", value: consistencyWithout),
            ComparisonMetric(label: trendLabel, value: trendWithout),
            ComparisonMetric(label: "Adherence", value: adherenceWithout)
        ]

        return (with: withMetrics, without: withoutMetrics)
    }

    private var coachReflectionText: String {
        let goalText = viewModel.mainGoalSelection.coachText
        let days = max(viewModel.form.workoutDaysPerWeek, 2)
        let experience = viewModel.form.trainingLevel.title.lowercased()
        let focus = viewModel.focusAreaSelection.title.lowercased()
        let environment: String
        switch viewModel.trainingEnvironmentSelection {
        case .gym:
            environment = "at the gym"
        case .home:
            environment = "at home"
        case .both:
            environment = "at the gym and at home"
        }
        return "You chose to \(goalText), training \(days) days per week \(environment), with \(experience) experience and a focus on \(focus). FIT AI will guide progressive overload, recovery, and macro adherence so your progress stays consistent."
    }

    private var valueStep: some View {
        VStack(spacing: 16) {
            InfoCard(
                title: "Today",
                subtitle: "Train • Adjust • Recover",
                detail: "A plan that adapts to how you actually feel."
            )

            Text("No guesswork. No wasted sessions.")
                .font(FitFont.body(size: 14, weight: .medium))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private var contrastStep: some View {
        VStack(spacing: 16) {
            FitAIMomentumComparisonCard()
        }
    }

    private var primaryGoalStep: some View {
        VStack(spacing: 12) {
            ForEach(OnboardingForm.PrimaryTrainingGoal.allCases, id: \.self) { goal in
                PrimaryGoalOptionButton(
                    goal: goal,
                    isSelected: viewModel.form.primaryTrainingGoal == goal,
                    action: { viewModel.setPrimaryTrainingGoal(goal) }
                )
            }
        }
    }

    private var physiqueFocusStep: some View {
        let options = ["Chest", "Back", "Shoulders", "Arms", "Legs", "Glutes", "Core"]
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(options, id: \.self) { option in
                    SelectableChip(
                        title: option,
                        isSelected: viewModel.form.physiqueFocus.contains(option),
                        action: { viewModel.togglePhysiqueFocus(option) }
                    )
                }
            }

            Text("Pick 1–3 so the plan does not waste weeks.")
                .font(FitFont.body(size: 12, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private var weakPointsStep: some View {
        let options: [(title: String, icon: String)] = [
            ("Lack of consistency", "arrow.triangle.2.circlepath"),
            ("Unhealthy eating habits", "fork.knife"),
            ("Lack of support", "person.2"),
            ("Busy schedule", "calendar"),
            ("Lack of meal inspiration", "lightbulb")
        ]
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(options, id: \.title) { option in
                OnboardingOptionRow(
                    title: option.title,
                    systemImage: option.icon,
                    isSelected: viewModel.form.pastFailures.contains(option.title),
                    action: { viewModel.togglePastFailure(option.title) }
                )
            }

            TextField(
                "",
                text: Binding(
                    get: { viewModel.form.pastFailuresNote },
                    set: { viewModel.form.pastFailuresNote = $0; viewModel.save() }
                ),
                prompt: Text("Anything else? (optional)")
                    .foregroundColor(FitTheme.textSecondary)
            )
            .font(FitFont.body(size: 15, weight: .regular))
            .foregroundColor(FitTheme.textPrimary)
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
        }
    }

    private var trainingDaysStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Days per week")
                .font(FitFont.body(size: 16, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)

            HStack(spacing: 8) {
                ForEach(2...7, id: \.self) { dayCount in
                    Button {
                        viewModel.setSplitDaysPerWeek(dayCount)
                    } label: {
                        Text("\(dayCount)")
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(viewModel.splitDaysPerWeek == dayCount ? FitTheme.buttonText : FitTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(viewModel.splitDaysPerWeek == dayCount ? FitTheme.accent : Color.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(viewModel.splitDaysPerWeek == dayCount ? Color.clear : FitTheme.cardStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Pick your exact days")
                .font(FitFont.body(size: 16, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
            let shortSymbols = viewModel.shortWeekdaySymbols
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(viewModel.weekdaySymbols.indices, id: \.self) { index in
                    let day = viewModel.weekdaySymbols[index]
                    let shortLabel = index < shortSymbols.count ? shortSymbols[index] : String(day.prefix(3))
                    SplitDayChip(
                        title: shortLabel,
                        isSelected: viewModel.splitTrainingDays.contains(day),
                        action: {
                            viewModel.toggleSplitTrainingDay(day)
                        }
                    )
                }
            }

            Text("Select \(viewModel.splitDaysPerWeek) days. Tap a selected day to free a slot.")
                .font(FitFont.body(size: 12, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private var trainingLevelStep: some View {
        VStack(spacing: 12) {
            ForEach(OnboardingForm.TrainingLevel.allCases, id: \.self) { level in
                TrainingLevelButton(
                    level: level,
                    isSelected: viewModel.form.trainingLevel == level,
                    action: { viewModel.setTrainingLevel(level) }
                )
            }
        }
    }

    private var habitsStep: some View {
        VStack(spacing: 16) {
            HabitRow(
                title: "Sleep",
                selection: Binding(
                    get: { viewModel.form.habitsSleep },
                    set: { viewModel.form.habitsSleep = $0; viewModel.save() }
                )
            )
            HabitRow(
                title: "Nutrition",
                selection: Binding(
                    get: { viewModel.form.habitsNutrition },
                    set: { viewModel.form.habitsNutrition = $0; viewModel.save() }
                )
            )
            HabitRow(
                title: "Stress",
                selection: Binding(
                    get: { viewModel.form.habitsStress },
                    set: { viewModel.form.habitsStress = $0; viewModel.save() }
                )
            )
            HabitRow(
                title: "Recovery",
                selection: Binding(
                    get: { viewModel.form.habitsRecovery },
                    set: { viewModel.form.habitsRecovery = $0; viewModel.save() }
                )
            )
        }
    }

    private var pastFailuresStep: some View {
        let options = ["No structure", "Too much volume", "Not enough recovery", "Inconsistent nutrition", "Lost motivation", "Progress stalled"]
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(options, id: \.self) { option in
                    SelectableChip(
                        title: option,
                        isSelected: viewModel.form.pastFailures.contains(option),
                        action: { viewModel.togglePastFailure(option) }
                    )
                }
            }

            TextField(
                "",
                text: Binding(
                    get: { viewModel.form.pastFailuresNote },
                    set: { viewModel.form.pastFailuresNote = $0; viewModel.save() }
                ),
                prompt: Text("Anything else? (optional)")
                    .foregroundColor(FitTheme.textSecondary)
            )
            .font(FitFont.body(size: 15, weight: .regular))
            .foregroundColor(FitTheme.textPrimary)
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
        }
    }

    private var dietStyleStep: some View {
        let options: [(title: String, icon: String)] = [
            ("Classic", "fork.knife"),
            ("Pescatarian", "fish"),
            ("Vegetarian", "leaf"),
            ("Vegan", "leaf.circle")
        ]

        return VStack(spacing: 12) {
            ForEach(options, id: \.title) { option in
                OnboardingOptionRow(
                    title: option.title,
                    systemImage: option.icon,
                    isSelected: viewModel.form.dietStyle == option.title,
                    action: {
                        viewModel.form.dietStyle = option.title
                        viewModel.save()
                    }
                )
            }
        }
    }

    private var progressPhotoStep: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)

                if let progressPhoto {
                    Image(uiImage: progressPhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(FitTheme.accent)
                        Text("Upload a current photo")
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Front or side view works best.")
                            .font(FitFont.body(size: 12, weight: .regular))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    .padding(12)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )

            HStack(spacing: 12) {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        progressPhotoError = nil
                        isShowingProgressPhotoCamera = true
                    } else {
                        progressPhotoError = "Camera is not available on this device."
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("Take photo")
                    }
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FitTheme.cardStroke, lineWidth: 1)
                    )
                }

                PhotosPicker(selection: $progressPhotoItem, matching: .images) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                        Text(progressPhoto == nil ? "Choose photo" : "Replace")
                    }
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FitTheme.cardStroke, lineWidth: 1)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Your coach will build a 30-day transformation plan:")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    planDetailRow(text: "Macro targets tailored to your body")
                    planDetailRow(text: "Workout split + progression rules")
                    planDetailRow(text: "Meal plan structure and timing")
                    planDetailRow(text: "Weekly check-ins and adjustments")
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )

            if let progressPhotoError {
                Text(progressPhotoError)
                    .font(FitFont.body(size: 12, weight: .regular))
                    .foregroundColor(.red.opacity(0.85))
            } else if progressPhoto == nil {
                Text("Add a photo to continue.")
                    .font(FitFont.body(size: 12, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary)
            } else {
                Text("Photo ready. We’ll analyze this next.")
                    .font(FitFont.body(size: 12, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .onChange(of: progressPhotoItem) { _ in
            Task {
                await loadProgressPhoto()
            }
        }
    }

    private var analysisStep: some View {
        VStack(spacing: 16) {
            AnalysisStateView(
                stage: analysisStage,
                showCTA: analysisCTAVisible,
                onContinue: {
                    viewModel.goToClaim()
                }
            )
        }
        .onAppear {
            guard !analysisStarted else { return }
            analysisStarted = true
            analysisStage = 0
            analysisCTAVisible = false
            viewModel.prepareCoachSignalsIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                analysisStage = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                analysisStage = 2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                analysisStage = 3
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                analysisStage = 4
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                analysisCTAVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.6) {
                viewModel.goToClaim()
            }
        }
    }

    @ViewBuilder
    private func planDetailRow(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FitTheme.accent)
            Text(text)
                .font(FitFont.body(size: 13, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paywallStep: some View {
        VStack(spacing: 18) {
            PaywallPreviewCard(
                signals: viewModel.form.coachSignals,
                gap: viewModel.form.lastSeenGap
            )

            Button {
                viewModel.showEmailSignup = true
            } label: {
                Text("Start free trial")
                    .font(FitFont.body(size: 17, weight: .semibold))
                    .foregroundColor(FitTheme.buttonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Button {
                viewModel.showLogin = true
            } label: {
                Text("Already have an account? **Sign in**")
                    .font(FitFont.body(size: 14, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var nameStep: some View {
        VStack(spacing: 16) {
            TextField("Your name", text: $viewModel.form.fullName)
                .font(FitFont.heading(size: 24, weight: .bold))
                .foregroundColor(FitTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FitTheme.cardStroke, lineWidth: 1)
                )
                .onChange(of: viewModel.form.fullName) { _ in
                    viewModel.save()
                }
            
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(FitTheme.accent)
                Text("We'll use this to personalize your coaching experience")
                    .font(FitFont.body(size: 12, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }
    
    private var genderStep: some View {
        VStack(spacing: 16) {
            ForEach(OnboardingForm.Sex.allCases, id: \.self) { option in
                GenderOptionButton(
                    option: option,
                    isSelected: viewModel.form.sex == option,
                    action: { viewModel.setSex(option) }
                )
            }
        }
    }
    
    private var birthdayStep: some View {
        VStack(spacing: 16) {
            Button {
                viewModel.datePickerTitle = "Select Birthday"
                // Set a default date 18 years ago if no birthday is set
                let defaultDate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
                viewModel.selectedDate = viewModel.form.birthday ?? defaultDate
                viewModel.showDatePicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let birthday = viewModel.form.birthday {
                            Text(birthday, style: .date)
                                .font(FitFont.heading(size: 20, weight: .bold))
                                .foregroundColor(FitTheme.accent)
                            
                            Text("\(Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0) years old")
                                .font(FitFont.body(size: 14, weight: .regular))
                                .foregroundColor(FitTheme.accent.opacity(0.7))
                        } else {
                            let defaultDate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
                            Text(defaultDate, style: .date)
                                .font(FitFont.heading(size: 20, weight: .bold))
                                .foregroundColor(FitTheme.accent.opacity(0.6))
                            
                            Text("Tap to select")
                                .font(FitFont.body(size: 14, weight: .regular))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundColor(FitTheme.textSecondary)
                }
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FitTheme.cardStroke, lineWidth: 1)
                )
            }
            
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(FitTheme.accent)
            Text("Your data is private and secure")
                .font(FitFont.body(size: 12, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
            }
        }
    }
    
    private var heightStep: some View {
        VStack(spacing: 16) {
            Button {
                viewModel.showHeightPicker = true
            } label: {
                VStack(spacing: 8) {
                    Text("\(viewModel.heightFeet)' \(viewModel.heightInches)\"")
                        .font(FitFont.heading(size: 32, weight: .bold))
                        .foregroundColor(FitTheme.accent)
                    
                    HStack(spacing: 4) {
                        Text("Tap to change")
                            .font(FitFont.body(size: 14, weight: .regular))
                            .foregroundColor(FitTheme.textSecondary)
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FitTheme.cardStroke, lineWidth: 1)
                )
            }
        }
    }
    
    private var weightStep: some View {
        VStack(spacing: 16) {
            WeightInputField(
                label: "Current Weight",
                value: $viewModel.weightLbs,
                placeholder: "188 lbs"
            )

            if viewModel.form.goal != .maintain {
                WeightInputField(
                    label: "Goal Weight",
                    value: $viewModel.goalWeightLbs,
                    placeholder: "180 lbs"
                )
                
                // Show estimated time to reach goal
                if !viewModel.goalWeightLbs.isEmpty {
                    let current = parseWeight(viewModel.weightLbs, fallback: 188)
                    let goal = parseWeight(viewModel.goalWeightLbs, fallback: 180)
                    let delta = abs(goal - current)
                    let weeklyRate = healthyWeeklyRate(for: viewModel.form.goal)
                    let weeksNeeded = Int(ceil(delta / weeklyRate))
                    
                    if delta > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 16))
                                .foregroundColor(FitTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Estimated time to goal")
                                    .font(FitFont.body(size: 12, weight: .regular))
                                    .foregroundColor(FitTheme.textSecondary)
                                Text("~\(weeksNeeded) weeks at your selected pace")
                                    .font(FitFont.body(size: 14, weight: .medium))
                                    .foregroundColor(FitTheme.textPrimary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(FitTheme.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private var goalSelectionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(goalOptions, id: \.self) { option in
                GoalOptionButton(
                    goal: option,
                    title: goalTitle(for: option),
                    isSelected: viewModel.form.goal == option,
                    action: { viewModel.setGoal(option) }
                )
            }

            if showsWeightPace {
                weightPaceCard
            }
        }
    }

    private var goalOptions: [OnboardingForm.Goal] {
        [.loseWeight, .maintain, .gainWeight]
    }

    private func goalTitle(for goal: OnboardingForm.Goal) -> String {
        switch goal {
        case .gainWeight: return "Gain muscle"
        case .loseWeight: return "Lose weight"
        case .loseWeightFast: return "Lose weight faster"
        case .maintain: return "Maintain weight"
        }
    }

    private var isLossGoal: Bool {
        viewModel.form.goal == .loseWeight || viewModel.form.goal == .loseWeightFast
    }

    private var showsWeightPace: Bool {
        isLossGoal || viewModel.form.goal == .gainWeight
    }

    private var weightPaceRateBinding: Binding<Double> {
        Binding(
            get: {
                clampWeightPaceRate(viewModel.form.weeklyWeightLossLbs)
            },
            set: { newValue in
                viewModel.form.weeklyWeightLossLbs = clampWeightPaceRate(newValue)
                viewModel.save()
            }
        )
    }

    private func clampWeightPaceRate(_ value: Double) -> Double {
        min(max(value, 0.5), 2.0)
    }

    private var weightPaceCard: some View {
        let rate = weightPaceRateBinding.wrappedValue
        let assessment = lossPaceAssessment(for: rate)
        let title = viewModel.form.goal == .gainWeight ? "Muscle gain pace" : "Weight loss pace"
        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(FitFont.body(size: 15, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)

            HStack {
                Text(String(format: "%.1f lb/week", rate))
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                Spacer()
                Text(assessment.title)
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(assessment.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(assessment.color.opacity(0.12))
                    .clipShape(Capsule())
            }

            Slider(value: weightPaceRateBinding, in: 0.5...2.0, step: 0.25)
                .tint(FitTheme.accent)

            HStack(spacing: 8) {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { value in
                    Button(action: {
                        weightPaceRateBinding.wrappedValue = value
                    }) {
                        Text(String(format: "%.1f", value))
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(rate == value ? FitTheme.buttonText : FitTheme.textPrimary)
                            .frame(minWidth: 48)
                            .padding(.vertical, 6)
                            .background(
                                rate == value
                                    ? FitTheme.primaryGradient
                                    : LinearGradient(
                                        colors: [FitTheme.cardHighlight, FitTheme.cardHighlight],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(assessment.detail)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
        }
        .padding(14)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private struct LossPaceAssessment {
        let title: String
        let detail: String
        let color: Color
    }

    private func lossPaceAssessment(for rate: Double) -> LossPaceAssessment {
        switch rate {
        case ..<0.8:
            return LossPaceAssessment(
                title: "Easy",
                detail: "Very realistic for long-term progress.",
                color: FitTheme.success
            )
        case ..<1.2:
            return LossPaceAssessment(
                title: "Moderate",
                detail: "Realistic for most people with consistent habits.",
                color: FitTheme.accent
            )
        case ..<1.8:
            return LossPaceAssessment(
                title: "Aggressive",
                detail: "Challenging; prioritize sleep, protein, and recovery.",
                color: .orange
            )
        default:
            return LossPaceAssessment(
                title: "Very aggressive",
                detail: "Hard to sustain; best for short-term pushes.",
                color: .red
            )
        }
    }

    private var splitSetupStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ForEach(SplitCreationMode.allCases) { mode in
                    SplitModeCard(
                        mode: mode,
                        isSelected: viewModel.splitCreationMode == mode,
                        action: {
                            viewModel.setSplitCreationMode(mode)
                        }
                    )
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Training days per week")
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)

                HStack(spacing: 8) {
                    ForEach(2...7, id: \.self) { dayCount in
                        Button {
                            viewModel.setSplitDaysPerWeek(dayCount)
                        } label: {
                            Text("\(dayCount)")
                                .font(FitFont.body(size: 14, weight: .semibold))
                                .foregroundColor(viewModel.splitDaysPerWeek == dayCount ? FitTheme.buttonText : FitTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(viewModel.splitDaysPerWeek == dayCount ? FitTheme.accent : Color.white)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(viewModel.splitDaysPerWeek == dayCount ? Color.clear : FitTheme.cardStroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Pick your training days")
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)

                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
                let shortSymbols = viewModel.shortWeekdaySymbols
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(viewModel.weekdaySymbols.indices, id: \.self) { index in
                        let day = viewModel.weekdaySymbols[index]
                        let shortLabel = index < shortSymbols.count ? shortSymbols[index] : String(day.prefix(3))
                        SplitDayChip(
                            title: shortLabel,
                            isSelected: viewModel.splitTrainingDays.contains(day),
                            action: {
                                viewModel.toggleSplitTrainingDay(day)
                            }
                        )
                    }
                }

                Text("Select \(viewModel.splitDaysPerWeek) days. Tap a selected day to free a slot.")
                    .font(FitFont.body(size: 12, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }
    
    private var activityStep: some View {
        VStack(spacing: 12) {
            ForEach(OnboardingForm.ActivityLevel.allCases, id: \.self) { level in
                ActivityLevelButton(
                    level: level,
                    isSelected: viewModel.form.activityLevel == level,
                    action: { viewModel.setActivityLevel(level) }
                )
            }
        }
    }
    
    private var checkinDayStep: some View {
        VStack(spacing: 16) {
            ForEach(OnboardingForm.checkinDays, id: \.self) { day in
                CheckinDayButton(
                    day: day,
                    isSelected: viewModel.form.checkinDay == day,
                    action: {
                        viewModel.form.checkinDay = day
                        viewModel.save()
                    }
                )
            }
            
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 14))
                    .foregroundColor(FitTheme.accent)
                Text("You'll receive a reminder to check in with your AI coach each week")
                    .font(FitFont.body(size: 12, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }
    
    private var specialConsiderationsStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                let considerations = OnboardingForm.SpecialConsideration.allCases
                let chunked = considerations.chunked(into: 2)
                
                ForEach(Array(chunked.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { consideration in
                            SpecialConsiderationButton(
                                consideration: consideration,
                                isSelected: viewModel.form.specialConsiderations.contains(consideration),
                                action: {
                                    if viewModel.form.specialConsiderations.contains(consideration) {
                                        viewModel.form.specialConsiderations.remove(consideration)
                                    } else {
                                        viewModel.form.specialConsiderations.insert(consideration)
                                    }
                                    viewModel.save()
                                }
                            )
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Anything else? (optional)")
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                
                TextField(
                    "",
                    text: $viewModel.additionalNotes,
                    prompt: Text("e.g. 'Wedding in April', 'Recovering from surgery'")
                        .foregroundColor(FitTheme.textSecondary)
                )
                    .font(FitFont.body(size: 15, weight: .regular))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FitTheme.cardStroke, lineWidth: 1)
                    )
            }
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(FitTheme.accent)
                Text("These help personalize your nutrition goals. You can change them anytime in settings.")
                    .font(FitFont.body(size: 12, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }

    private var healthKitStep: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(FitTheme.cardWorkoutAccent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.cardWorkoutAccent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Health workouts")
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("Automatically log workouts and keep your streak accurate.")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                Spacer()
            }

            Toggle(isOn: Binding(
                get: { viewModel.form.healthKitSyncEnabled },
                set: { newValue in
                    updateHealthKitSync(newValue)
                }
            )) {
                Text("Sync Apple Health workouts")
                    .font(FitFont.body(size: 14, weight: .medium))
                    .foregroundColor(FitTheme.textPrimary)
            }
            .toggleStyle(SwitchToggleStyle(tint: FitTheme.accent))
            .disabled(!healthKitManager.isHealthDataAvailable)

            if let healthKitStatusMessage {
                Text(healthKitStatusMessage)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !healthKitManager.isHealthDataAvailable {
                Text("Apple Health isn’t available on this device.")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
        .onAppear {
            healthKitManager.refreshAuthorizationStatus()
            if viewModel.form.healthKitSyncEnabled {
                healthKitStatusMessage = "Apple Health sync is on."
            }
        }
    }

    private func updateHealthKitSync(_ enabled: Bool) {
        if !enabled {
            viewModel.form.healthKitSyncEnabled = false
            HealthSyncState.shared.isEnabled = false
            viewModel.save()
            healthKitStatusMessage = "Apple Health sync is off."
            return
        }

        Task {
            let granted = await healthKitManager.requestAuthorization()
            await MainActor.run {
                viewModel.form.healthKitSyncEnabled = granted
                HealthSyncState.shared.isEnabled = granted
                viewModel.save()
                healthKitStatusMessage = granted
                    ? "Apple Health connected."
                    : "Permission not granted. You can enable it later in Settings."
            }
        }
    }
    
    private var goalsStep: some View {
        let currentWeight = parseWeight(viewModel.weightLbs, fallback: 192)
        let isMaintain = viewModel.form.goal == .maintain
        let goalWeight = isMaintain ? currentWeight : parseWeight(viewModel.goalWeightLbs, fallback: 180)
        
        // Calculate the estimated goal date based on healthy rate of change
        let estimatedGoalDate = suggestedTargetDate(currentWeight: currentWeight, goalWeight: goalWeight, goal: viewModel.form.goal)
        
        let daysToGoal = max(
            0,
            Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: estimatedGoalDate)
            ).day ?? 0
        )
        let weeksToGoal = max(1, daysToGoal / 7)
        
        let delta = goalWeight - currentWeight
        let deltaText = formatDelta(delta)
        let deltaColor = delta < 0 ? FitTheme.success : (delta > 0 ? FitTheme.accent : FitTheme.textSecondary)
        let heightFt = Int(viewModel.form.heightFeet) ?? 5
        let heightIn = Int(viewModel.form.heightInches) ?? 9
        let userAge: Int
        if let birthday = viewModel.form.birthday {
            userAge = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 25
        } else {
            userAge = 25
        }
        
        let macroTargets = roundedMacros(calculateMacroTargets(
            weightLbs: currentWeight,
            heightFeet: heightFt,
            heightInches: heightIn,
            age: userAge,
            sex: viewModel.form.sex,
            trainingDaysPerWeek: viewModel.form.workoutDaysPerWeek,
            goal: viewModel.form.goal
        ))
        
        // Weekly rate description
        let weeklyRate = healthyWeeklyRate(for: viewModel.form.goal)
        let rateDescription = weeklyRate > 0 ? "\(String(format: "%.1f", weeklyRate)) lb/week" : ""
        
        return VStack(spacing: 20) {
            // Weight goal card
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start")
                            .font(FitFont.body(size: 12, weight: .regular))
                            .foregroundColor(FitTheme.textSecondary)
                        Text("Today")
                            .font(FitFont.body(size: 14, weight: .medium))
                            .foregroundColor(FitTheme.textPrimary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatWeight(currentWeight))
                                .font(FitFont.heading(size: 18, weight: .bold))
                                .foregroundColor(FitTheme.textPrimary)
                            Text("lbs")
                                .font(FitFont.body(size: 14, weight: .regular))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    Image(systemName: "arrow.right")
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Spacer(minLength: 8)
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        if isMaintain {
                            Text("Ongoing")
                                .font(FitFont.body(size: 12, weight: .regular))
                                .foregroundColor(FitTheme.textSecondary)
                            Text("Maintain")
                                .font(FitFont.body(size: 14, weight: .medium))
                                .foregroundColor(FitTheme.textPrimary)
                        } else {
                            Text("Estimated Goal")
                                .font(FitFont.body(size: 12, weight: .regular))
                                .foregroundColor(FitTheme.textSecondary)
                            Text("\(estimatedGoalDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(FitFont.body(size: 14, weight: .medium))
                                .foregroundColor(FitTheme.textPrimary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatWeight(goalWeight))
                                .font(FitFont.heading(size: 18, weight: .bold))
                                .foregroundColor(FitTheme.accent)
                            Text("lbs")
                                .font(FitFont.body(size: 14, weight: .regular))
                                .foregroundColor(FitTheme.textSecondary)
                            if !isMaintain {
                                Text("(\(deltaText) lbs)")
                                    .font(FitFont.body(size: 12, weight: .semibold))
                                    .foregroundColor(deltaColor)
                            }
                        }
                    }
                }
                
                // Show timeline info for non-maintain goals
                if !isMaintain {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(FitTheme.accent)
                        Text("~\(weeksToGoal) weeks at your \(rateDescription) pace")
                            .font(FitFont.body(size: 13, weight: .medium))
                            .foregroundColor(FitTheme.textPrimary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FitTheme.accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                
                GoalProjectionChart(
                    startWeight: currentWeight,
                    targetWeight: goalWeight,
                    startDate: Date(),
                    targetDate: estimatedGoalDate
                )
                .frame(height: 150)
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
            
            // Editable Nutrient targets
            VStack(alignment: .leading, spacing: 12) {
                Text("Tap to edit your targets")
                    .font(FitFont.body(size: 12, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary)
                
                EditableNutrientRow(
                    icon: "flame.fill",
                    iconColor: .orange,
                    label: "Daily Calories",
                    value: $editedCalories,
                    suffix: "cal"
                )
                EditableNutrientRow(
                    icon: "fish.fill",
                    iconColor: .yellow,
                    label: "Protein Target",
                    value: $editedProtein,
                    suffix: "g"
                )
                EditableNutrientRow(
                    icon: "apple.fill",
                    iconColor: .red,
                    label: "Carbs Target",
                    value: $editedCarbs,
                    suffix: "g"
                )
                EditableNutrientRow(
                    icon: "drop.fill",
                    iconColor: FitTheme.accent,
                    label: "Fat Target",
                    value: $editedFats,
                    suffix: "g"
                )
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
            .onAppear {
                if !macrosInitialized {
                    editedCalories = "\(Int(macroTargets.calories.rounded()))"
                    editedProtein = "\(Int(macroTargets.protein.rounded()))"
                    editedCarbs = "\(Int(macroTargets.carbs.rounded()))"
                    editedFats = "\(Int(macroTargets.fats.rounded()))"
                    macrosInitialized = true
                }
            }
            
            Button {
                Task {
                    let editedMacros = MacroTotals(
                        calories: Double(editedCalories) ?? macroTargets.calories,
                        protein: Double(editedProtein) ?? macroTargets.protein,
                        carbs: Double(editedCarbs) ?? macroTargets.carbs,
                        fats: Double(editedFats) ?? macroTargets.fats
                    )
                    await viewModel.applyMacros(editedMacros)
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(FitTheme.accent)
                    Text(viewModel.isApplyingMacros ? "Applying..." : "Use these macros")
                        .font(FitFont.body(size: 15, weight: .medium))
                        .foregroundColor(FitTheme.accent)
                }
            }
            .disabled(viewModel.isApplyingMacros)
        }
    }

    private func parseWeight(_ text: String, fallback: Double) -> Double {
        let sanitized = text.filter { "0123456789.".contains($0) }
        if let value = Double(sanitized), value > 0 {
            return value
        }
        return fallback
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
        let magnitude = formatWeight(abs(rounded))
        return "\(sign)\(magnitude)"
    }
    
    // MARK: - Realistic Weight Change Calculations
    
    /// Healthy rate of weight change per week (in lbs)
    private func healthyWeeklyRate(for goal: OnboardingForm.Goal) -> Double {
        switch goal {
        case .loseWeight:
            return clampWeightPaceRate(viewModel.form.weeklyWeightLossLbs)
        case .loseWeightFast:
            return max(1.5, clampWeightPaceRate(viewModel.form.weeklyWeightLossLbs))
        case .gainWeight:
            return clampWeightPaceRate(viewModel.form.weeklyWeightLossLbs)
        case .maintain:
            return 0.0
        }
    }
    
    /// Calculate the suggested target date based on weight change and healthy rate
    private func suggestedTargetDate(currentWeight: Double, goalWeight: Double, goal: OnboardingForm.Goal) -> Date {
        let delta = abs(goalWeight - currentWeight)
        let weeklyRate = healthyWeeklyRate(for: goal)
        
        guard weeklyRate > 0 else {
            // Maintain goal - default to 12 weeks
            return Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date()) ?? Date()
        }
        
        let weeksNeeded = delta / weeklyRate
        let daysNeeded = Int(ceil(weeksNeeded * 7))
        
        // Minimum 2 weeks, maximum 2 years
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
        goal: OnboardingForm.Goal
    ) -> MacroTotals {
        // Convert to metric
        let weightKg = weightLbs * 0.453592
        let heightCm = (Double(heightFeet) * 30.48) + (Double(heightInches) * 2.54)
        
        // Mifflin-St Jeor BMR calculation
        let bmr: Double
        switch sex {
        case .male:
            bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) + 5
        case .female:
            bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) - 161
        case .other, .preferNotToSay:
            // Use average of male/female formulas
            bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) - 78
        }
        
        // Activity multiplier based on training days
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

        // Adjust for goal (percentage-based)
        let calories: Double
        let proteinMultiplier: Double

        switch goal {
        case .maintain:
            calories = maintenanceCalories
            proteinMultiplier = 0.8
        case .loseWeight, .loseWeightFast:
            calories = maintenanceCalories * 0.8
            proteinMultiplier = 0.8
        case .gainWeight:
            calories = maintenanceCalories * 1.15
            proteinMultiplier = 1.0
        }

        let fat = weightLbs * 0.3
        let protein = weightLbs * proteinMultiplier
        let carbCalories = max(calories - (protein * 4) - (fat * 9), 0)
        let carbs = carbCalories / 4
        
        return MacroTotals(calories: calories, protein: protein, carbs: carbs, fats: fat)
    }

    private func roundedMacros(_ macros: MacroTotals) -> MacroTotals {
        MacroTotals(
            calories: macros.calories.rounded(),
            protein: macros.protein.rounded(),
            carbs: macros.carbs.rounded(),
            fats: macros.fats.rounded()
        )
    }
    
    private var accountStep: some View {
        VStack(spacing: 16) {
            Button {
                Task {
                    await viewModel.signInWithGoogle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Google logo placeholder
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text("G")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.blue)
                        )
                    Text("Continue with Google")
                        .font(FitFont.body(size: 17, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FitTheme.cardStroke, lineWidth: 1)
                )
            }

            if let message = viewModel.submissionMessage, !message.isEmpty {
                Text(message)
                    .font(FitFont.body(size: 14, weight: .regular))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            HStack {
                Rectangle()
                    .fill(FitTheme.cardStroke)
                    .frame(height: 1)
                Text("or")
                    .font(FitFont.body(size: 14, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary)
                    .padding(.horizontal, 12)
                Rectangle()
                    .fill(FitTheme.cardStroke)
                    .frame(height: 1)
            }
            
            Button {
                viewModel.showEmailSignup = true
            } label: {
                Text("Use email instead")
                    .font(FitFont.body(size: 17, weight: .semibold))
                    .foregroundColor(FitTheme.buttonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    
    // MARK: - Step Actions
    
    @ViewBuilder
    private var stepActions: some View {
        if viewModel.isActionBarHidden {
            EmptyView()
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    if viewModel.currentStep > 0 {
                        Button {
                            viewModel.previousStep()
                        } label: {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(FitTheme.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.white)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(FitTheme.cardStroke, lineWidth: 1)
                                )
                        }
                    }

                    Spacer()

                    Button {
                        Task {
                            await handlePrimaryAction()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(viewModel.primaryActionTitle)
                                .font(FitFont.body(size: 17, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(FitTheme.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(FitTheme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .disabled(isPrimaryActionDisabled)
                }
            }
        }
    }

    private func handlePrimaryAction() async {
        switch viewModel.currentStepCase {
        case .instantWin:
            viewModel.showEmailSignup = true
        case .trial:
            viewModel.showEmailSignup = true
        default:
            await viewModel.advanceStep()
        }
    }

    private var isPrimaryActionDisabled: Bool {
        if viewModel.isSubmitting {
            return true
        }
        return false
    }

    private func loadProgressPhoto() async {
        guard let item = progressPhotoItem else { return }
        progressPhotoError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                progressPhotoError = "Unable to load photo data."
                return
            }
            applyProgressPhoto(image)
        } catch {
            progressPhotoError = error.localizedDescription
        }
        progressPhotoItem = nil
    }

    private func applyProgressPhoto(_ image: UIImage) {
        progressPhotoError = nil
        progressPhoto = image
        viewModel.form.photosPending = false
        viewModel.save()
    }
}

// MARK: - Supporting Views

private struct TrainingFrequencyOption: Identifiable {
    let label: String
    let days: Int
    var id: String { label }
}

private struct ComparisonMetric: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

private struct OnboardingFeaturePhoneMock: View {
    let imageName: String

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 270)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: FitTheme.shadow.opacity(0.35), radius: 16, x: 0, y: 10)
    }
}

private struct PlanBuildStateView: View {
    let stage: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your plan is taking shape")
                    .font(FitFont.body(size: 13, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                Text("This is your coach at work")
                    .font(FitFont.heading(size: 20, weight: .bold))
                    .foregroundColor(FitTheme.textPrimary)
            }

            ProgressView(value: Double(min(stage, 4)), total: 4)
                .tint(FitTheme.accent)

            VStack(alignment: .leading, spacing: 10) {
                PlanBuildRow(title: "Analyzing your responses", isActive: stage >= 1)
                PlanBuildRow(title: "Creating personalized plan", isActive: stage >= 2)
                PlanBuildRow(title: "Dialing in macro targets", isActive: stage >= 3)
                PlanBuildRow(title: "Syncing your coach", isActive: stage >= 4)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}

private struct PlanBuildRow: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isActive ? FitTheme.accent : FitTheme.cardStroke)
            Text(title)
                .font(FitFont.body(size: 13, weight: .medium))
                .foregroundColor(isActive ? FitTheme.textPrimary : FitTheme.textSecondary)
        }
    }
}

private struct FutureStateComparisonCard: View {
    let withMetrics: [ComparisonMetric]
    let withoutMetrics: [ComparisonMetric]

    var body: some View {
        HStack(spacing: 12) {
            ComparisonColumn(title: "Self-guided", metrics: withoutMetrics, accent: FitTheme.cardStroke)
            ComparisonColumn(title: "With FIT AI", metrics: withMetrics, accent: FitTheme.accent)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}

private struct ComparisonColumn: View {
    let title: String
    let metrics: [ComparisonMetric]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(FitFont.body(size: 13, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)

            ForEach(metrics) { metric in
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(metric.label)
                        .font(FitFont.body(size: 12, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                    Spacer()
                    Text(metric.value)
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ClaimPlanCard: View {
    private var resetCountdown: (String, String, String) {
        let resetDate = Date().addingTimeInterval(24 * 60 * 60)
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: Date(), to: resetDate)
        let hours = String(format: "%02d", max(components.hour ?? 0, 0))
        let minutes = String(format: "%02d", max(components.minute ?? 0, 0))
        let seconds = String(format: "%02d", max(components.second ?? 0, 0))
        return (hours, minutes, seconds)
    }

    var body: some View {
        let countdown = resetCountdown
        return VStack(alignment: .leading, spacing: 12) {
            Text("Data Reset Notice")
                .font(FitFont.body(size: 14, weight: .semibold))
                .foregroundColor(FitTheme.accent)

            Text("Your personalized plan will reset in:")
                .font(FitFont.body(size: 13, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)

            HStack(spacing: 8) {
                countdownCell(value: countdown.0, unit: "hours")
                countdownCell(value: countdown.1, unit: "minutes")
                countdownCell(value: countdown.2, unit: "seconds")
            }

            Text("Sign in now to preserve your progress and personalized training data.")
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }

    private func countdownCell(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(FitFont.heading(size: 20, weight: .bold))
                .foregroundColor(FitTheme.accent)
            Text(unit)
                .font(FitFont.body(size: 10, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FitFont.body(size: 12, weight: .semibold))
            .foregroundColor(FitTheme.textPrimary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(FitTheme.cardHighlight)
            .clipShape(Capsule())
    }
}

private struct PlanPreviewCard: View {
    let goal: MainGoalOption
    let daysPerWeek: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan preview")
                .font(FitFont.body(size: 13, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)

            Text("\(daysPerWeek)-day split focused on \(goal.previewText)")
                .font(FitFont.body(size: 14, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)

            Text("Weekly adjustments and recovery built in.")
                .font(FitFont.body(size: 12, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}

private struct BenefitRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FitTheme.accent)
            Text(text)
                .font(FitFont.body(size: 14, weight: .regular))
                .foregroundColor(FitTheme.textPrimary)
        }
    }
}

private struct TrialPlanOptionRow: View {
    let plan: TrialPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                        if plan == .yearly {
                            Text("Save 20%")
                                .font(FitFont.body(size: 10, weight: .bold))
                                .foregroundColor(FitTheme.accent)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 8)
                                .background(FitTheme.accent.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    Text(plan.price)
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(plan.detail)
                        .font(FitFont.body(size: 11, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? FitTheme.accent : FitTheme.cardStroke)
            }
            .padding(12)
            .background(isSelected ? FitTheme.accent.opacity(0.08) : FitTheme.cardHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? FitTheme.accent : FitTheme.cardStroke, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct InfoCard: View {
    let title: String
    let subtitle: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FitFont.body(size: 13, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)
            Text(subtitle)
                .font(FitFont.heading(size: 22, weight: .bold))
                .foregroundColor(FitTheme.textPrimary)
            Text(detail)
                .font(FitFont.body(size: 13, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}

private struct FitAIMomentumComparisonCard: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Goal momentum")
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)

                    Text("2x more likely\nto finish strong")
                        .font(FitFont.heading(size: 22, weight: .bold))
                        .foregroundColor(FitTheme.textPrimary)
                }

                Spacer()

                MomentumRing()
            }

            VStack(spacing: 12) {
                ComparisonTrackRow(
                    title: "On your own",
                    subtitle: "Starts hot, stalls when life hits.",
                    tag: "1x",
                    barHeights: [0.65, 0.55, 0.4, 0.3, 0.25],
                    barColor: FitTheme.cardStroke,
                    isAccent: false
                )

                ComparisonTrackRow(
                    title: "With FitAI",
                    subtitle: "Daily check-ins keep momentum up.",
                    tag: "2x",
                    barHeights: [0.35, 0.5, 0.65, 0.8, 0.9],
                    barColor: FitTheme.accent,
                    isAccent: true
                )
            }

            Text("FitAI adapts your workouts and nutrition so progress does not stall.")
                .font(FitFont.body(size: 14, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}

private struct MomentumRing: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(FitTheme.cardStroke, lineWidth: 6)

            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(
                    FitTheme.primaryGradient,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("2x")
                    .font(FitFont.body(size: 16, weight: .bold))
                    .foregroundColor(FitTheme.textPrimary)
                Text("lift")
                    .font(FitFont.body(size: 10, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .frame(width: 64, height: 64)
    }
}

private struct ComparisonTrackRow: View {
    let title: String
    let subtitle: String
    let tag: String
    let barHeights: [CGFloat]
    let barColor: Color
    let isAccent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(FitFont.body(size: 15, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(subtitle)
                        .font(FitFont.body(size: 12, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                }

                Spacer()

                Text(tag)
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(isAccent ? FitTheme.textOnAccent : FitTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(isAccent ? FitTheme.accent : FitTheme.cardHighlight)
                    .clipShape(Capsule())
            }

            MomentumBarRow(heights: barHeights, color: barColor)
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}

private struct MomentumBarRow: View {
    let heights: [CGFloat]
    let color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(heights.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(index == heights.count - 1 ? 1.0 : 0.5))
                    .frame(width: 12, height: 14 + (heights[index] * 28))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingOptionRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(FitTheme.cardStroke, lineWidth: 1)
                        )
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                }

                Text(title)
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(isSelected ? FitTheme.accent.opacity(0.08) : FitTheme.cardHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? FitTheme.accent.opacity(0.35) : FitTheme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PrimaryGoalOptionButton: View {
    let goal: OnboardingForm.PrimaryTrainingGoal
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FitTheme.accent)
                Text(goal.title)
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(FitTheme.accent)
                }
            }
            .padding(14)
            .background(isSelected ? FitTheme.accent.opacity(0.1) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? FitTheme.accent : FitTheme.cardStroke, lineWidth: isSelected ? 2 : 1)
            )
        }
    }

    private var iconName: String {
        switch goal {
        case .strength: return "bolt.fill"
        case .hypertrophy: return "dumbbell.fill"
        case .fatLoss: return "flame.fill"
        }
    }
}

private struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FitFont.body(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? FitTheme.accent : Color.white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : FitTheme.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct TrainingLevelButton: View {
    let level: OnboardingForm.TrainingLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundColor(FitTheme.accent)

                Text(level.title)
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(FitTheme.accent)
                }
            }
            .padding(16)
            .background(isSelected ? FitTheme.accent.opacity(0.1) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? FitTheme.accent : FitTheme.cardStroke, lineWidth: isSelected ? 2 : 1)
            )
        }
    }

    private var iconName: String {
        switch level {
        case .beginner: return "figure.walk"
        case .intermediate: return "figure.run"
        case .advanced: return "trophy.fill"
        }
    }
}

private struct HabitRow: View {
    let title: String
    @Binding var selection: String

    private let options = ["Low", "Okay", "Strong"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FitFont.body(size: 14, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)

            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(option)
                            .font(FitFont.body(size: 13, weight: .semibold))
                            .foregroundColor(selection == option ? FitTheme.buttonText : FitTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selection == option ? FitTheme.accent : Color.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selection == option ? Color.clear : FitTheme.cardStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}

private struct CheckinRatingRow: View {
    let title: String
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FitFont.body(size: 14, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        Text("\(value)")
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(selection == value ? FitTheme.buttonText : FitTheme.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(selection == value ? FitTheme.accent : Color.white)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(selection == value ? Color.clear : FitTheme.cardStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct AnalysisStateView: View {
    let stage: Int
    let showCTA: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Analyzing your photo")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                Text("30-day plan forming")
                    .font(FitFont.heading(size: 22, weight: .bold))
                    .foregroundColor(FitTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 10) {
                AnalysisChip(title: "Reading body composition markers", isVisible: stage >= 1)
                AnalysisChip(title: "Estimating metabolism + macros", isVisible: stage >= 2)
                AnalysisChip(title: "Building a 30-day workout split", isVisible: stage >= 3)
                AnalysisChip(title: "Structuring meal plan strategy", isVisible: stage >= 4, blurred: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showCTA {
                Button(action: onContinue) {
                    Text("Unlock the full readout")
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(FitTheme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}

private struct AnalysisChip: View {
    let title: String
    let isVisible: Bool
    var blurred: Bool = false

    var body: some View {
        Text(title)
            .font(FitFont.body(size: 13, weight: .medium))
            .foregroundColor(FitTheme.textPrimary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(FitTheme.cardHighlight)
            .clipShape(Capsule())
            .opacity(isVisible ? 1 : 0)
            .blur(radius: blurred ? 6 : 0)
            .animation(.easeInOut(duration: 0.3), value: isVisible)
    }
}

private struct OnboardingCameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: OnboardingCameraPicker

        init(parent: OnboardingCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.onImage(uiImage)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

private struct PaywallPreviewCard: View {
    let signals: [String]
    let gap: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your signals are in.")
                .font(FitFont.body(size: 14, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)
            Text("Your adjustments are ready.")
                .font(FitFont.heading(size: 22, weight: .bold))
                .foregroundColor(FitTheme.textPrimary)

            if !gap.isEmpty {
                Text(gap)
                    .font(FitFont.body(size: 13, weight: .medium))
                    .foregroundColor(FitTheme.textSecondary)
            }

            HStack(spacing: 8) {
                ForEach(signals.prefix(3), id: \.self) { signal in
                    Text(signal)
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(FitTheme.cardHighlight)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}

struct GenderOptionButton: View {
    let option: OnboardingForm.Sex
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: genderIcon)
                    .font(.system(size: 20))
                    .foregroundColor(FitTheme.accent)
                
                Text(option.title)
                    .font(FitFont.body(size: 17, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(FitTheme.accent)
                }
            }
            .padding(16)
            .background(isSelected ? FitTheme.accent.opacity(0.1) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? FitTheme.accent : FitTheme.cardStroke, lineWidth: isSelected ? 2 : 1)
            )
        }
    }
    
    private var genderIcon: String {
        switch option {
        case .male: return "person"
        case .female: return "person.fill"
        case .other: return "person.2"
        case .preferNotToSay: return "questionmark.circle"
        }
    }
}

struct GoalOptionButton: View {
    let goal: OnboardingForm.Goal
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: goalIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FitTheme.accent)

                Text(title)
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(FitTheme.accent)
                }
            }
            .padding(14)
            .background(isSelected ? FitTheme.accent.opacity(0.1) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? FitTheme.accent : FitTheme.cardStroke, lineWidth: isSelected ? 2 : 1)
            )
        }
    }

    private var goalIcon: String {
        switch goal {
        case .gainWeight: return "arrow.up.right"
        case .loseWeight: return "arrow.down.right"
        case .loseWeightFast: return "bolt.fill"
        case .maintain: return "minus"
        }
    }
}

struct SplitModeCard: View {
    let mode: SplitCreationMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FitTheme.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(mode.subtitle)
                        .font(FitFont.body(size: 12, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(FitTheme.accent)
                }
            }
            .padding(16)
            .background(isSelected ? FitTheme.accent.opacity(0.1) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? FitTheme.accent : FitTheme.cardStroke, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SplitDayChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FitFont.body(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? FitTheme.accent : Color.white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : FitTheme.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct ActivityLevelButton: View {
    let level: OnboardingForm.ActivityLevel
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: activityIcon)
                    .font(.system(size: 18))
                    .foregroundColor(FitTheme.accent)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.title)
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(level.description)
                        .font(FitFont.body(size: 13, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(FitTheme.accent)
                }
            }
            .padding(16)
            .background(isSelected ? FitTheme.accent.opacity(0.1) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? FitTheme.accent : FitTheme.cardStroke, lineWidth: isSelected ? 2 : 1)
            )
        }
    }
    
    private var activityIcon: String {
        switch level {
        case .sedentary: return "chair"
        case .lightlyActive: return "figure.walk"
        case .moderatelyActive: return "figure.run"
        case .veryActive: return "figure.run.circle"
        case .extremelyActive: return "figure.strengthtraining"
        }
    }
}

struct SpecialConsiderationButton: View {
    let consideration: OnboardingForm.SpecialConsideration
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: considerationIcon)
                    .font(.system(size: 14))
                Text(consideration.title)
                    .font(FitFont.body(size: 14, weight: .medium))
            }
            .foregroundColor(isSelected ? FitTheme.textPrimary : FitTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? FitTheme.accent : Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(FitTheme.cardStroke, lineWidth: isSelected ? 0 : 1)
            )
        }
    }
    
    private var considerationIcon: String {
        switch consideration {
        case .highProtein: return "fish.fill"
        case .lowCarb: return "leaf.fill"
        case .athlete: return "figure.run"
        case .strengthTraining: return "dumbbell.fill"
        case .enduranceTraining: return "bicycle"
        case .vegetarianVegan: return "carrot.fill"
        }
    }
}

struct CheckinDayButton: View {
    let day: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(FitTheme.accent)
                
                Text(day)
                    .font(FitFont.body(size: 17, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(FitTheme.accent)
                }
            }
            .padding(16)
            .background(isSelected ? FitTheme.accent.opacity(0.1) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? FitTheme.accent : FitTheme.cardStroke, lineWidth: isSelected ? 2 : 1)
            )
        }
    }
}

struct WeightInputField: View {
    let label: String
    @Binding var value: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(FitFont.body(size: 14, weight: .medium))
                .foregroundColor(FitTheme.textSecondary)
            
            HStack {
                TextField(placeholder, text: $value)
                    .font(FitFont.heading(size: 20, weight: .bold))
                    .foregroundColor(value.isEmpty ? FitTheme.accent.opacity(0.5) : FitTheme.accent)
                    .keyboardType(.decimalPad)
                Spacer()
                Image(systemName: "pencil")
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
        }
    }
}

struct NutrientTargetRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
            
            Text(label)
                .font(FitFont.body(size: 15, weight: .medium))
                .foregroundColor(FitTheme.textPrimary)
            
            Spacer()
            
            Text(value)
                .font(FitFont.body(size: 15, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)
        }
    }
}

private struct EditableNutrientRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    @Binding var value: String
    let suffix: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
            
            Text(label)
                .font(FitFont.body(size: 15, weight: .medium))
                .foregroundColor(FitTheme.textPrimary)
            
            Spacer()
            
            HStack(spacing: 4) {
                TextField("0", text: $value)
                    .font(FitFont.body(size: 15, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(FitTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(FitTheme.cardStroke, lineWidth: 1)
                    )
                
                Text(suffix)
                    .font(FitFont.body(size: 14, weight: .medium))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }
}

private struct GoalProjectionChart: View {
    let startWeight: Double
    let targetWeight: Double
    let startDate: Date
    let targetDate: Date

    private let chartInsets = EdgeInsets(top: 12, leading: 36, bottom: 24, trailing: 12)
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
                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)

                if points.count > 1 {
                    areaPath(points: points, in: chartRect)
                        .fill(
                            LinearGradient(
                                colors: [
                                    FitTheme.accent.opacity(0.22),
                                    FitTheme.accent.opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    curvePath(points: points)
                        .stroke(FitTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    ForEach(points.indices, id: \.self) { index in
                        let point = points[index]
                        Circle()
                            .fill(Color.white)
                            .frame(width: index == points.count - 1 ? 12 : 10, height: index == points.count - 1 ? 12 : 10)
                            .overlay(
                                Circle()
                                    .stroke(FitTheme.accent, lineWidth: 3)
                            )
                            .position(point)
                    }
                }

                ForEach(yLabels.indices, id: \.self) { index in
                    let y = chartRect.minY + chartRect.height * CGFloat(index) / 3
                    Text(yLabels[index])
                        .font(FitFont.body(size: 11, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                        .position(x: chartRect.minX - 12, y: y)
                }

                ForEach(monthLabels.indices, id: \.self) { index in
                    let x = chartRect.minX + chartRect.width * xFractions[index]
                    Text(monthLabels[index])
                        .font(FitFont.body(size: 12, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                        .position(x: x, y: chartRect.maxY + 14)
                }
            }
        }
    }

    private func projectionWeights() -> [Double] {
        let steps: [Double] = [0.0, 0.22, 0.5, 0.78, 1.0]
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
            let value = max - stepValue * Double(index)
            return formatWeight(value)
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


// MARK: - Picker Views

struct HeightPickerView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Binding var isPresented: Bool
    
    @State private var selectedFeet: Int
    @State private var selectedInches: Int
    @State private var selectedUnit: String
    
    init(viewModel: OnboardingViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        _selectedFeet = State(initialValue: Int(viewModel.heightFeet) ?? 5)
        _selectedInches = State(initialValue: Int(viewModel.heightInches) ?? 9)
        _selectedUnit = State(initialValue: viewModel.heightUnit)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your height")
                    .font(FitFont.heading(size: 20, weight: .bold))
                Spacer()
                Text("\(selectedFeet)' \(selectedInches)\"")
                    .font(FitFont.heading(size: 24, weight: .bold))
                    .foregroundColor(FitTheme.accent)
                
                Picker("Unit", selection: $selectedUnit) {
                    Text("cm").tag("cm")
                    Text("ft/in").tag("ft/in")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .padding(20)
            
            if selectedUnit == "ft/in" {
                HStack(spacing: 0) {
                    Picker("Feet", selection: $selectedFeet) {
                        ForEach(3...8, id: \.self) { ft in
                            Text("\(ft)'").tag(ft)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    
                    Picker("Inches", selection: $selectedInches) {
                        ForEach(0...11, id: \.self) { inch in
                            Text("\(inch)\"").tag(inch)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
            } else {
                // CM picker would go here
                Text("CM picker - to be implemented")
                    .padding()
            }
            
            Button {
                viewModel.heightFeet = "\(selectedFeet)"
                viewModel.heightInches = "\(selectedInches)"
                viewModel.heightUnit = selectedUnit
                isPresented = false
            } label: {
                Text("Done")
                    .font(FitFont.body(size: 17, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(20)
        }
        .background(Color(white: 0.96))
        .presentationDetents([.medium])
        .preferredColorScheme(.light)
    }
}

struct DatePickerSheet: View {
    @Binding var date: Date
    let title: String
    @Binding var isPresented: Bool
    let onSave: ((Date) -> Void)?
    
    init(date: Binding<Date>, title: String, isPresented: Binding<Bool>, onSave: ((Date) -> Void)? = nil) {
        self._date = date
        self.title = title
        self._isPresented = isPresented
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(FitFont.heading(size: 18, weight: .bold))
                    .foregroundColor(FitTheme.textPrimary)
                
                Spacer()
                
                Button("Done") {
                    onSave?(date)
                    isPresented = false
                }
                .font(FitFont.body(size: 16, weight: .semibold))
                .foregroundColor(FitTheme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(FitTheme.cardHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(20)
            
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxHeight: .infinity)
        }
        .background(
            Color(white: 0.96)
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .preferredColorScheme(.light)
    }
}

// MARK: - Login and Email Signup Views

struct LoginView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Sign In")
                    .font(FitFont.heading(size: 28, weight: .bold))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(.top, 40)

                if let message = viewModel.submissionMessage, !message.isEmpty {
                    Text(message)
                        .font(FitFont.body(size: 14, weight: .regular))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        await viewModel.signInWithGoogle()
                        if viewModel.isComplete {
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text("G")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.blue)
                            )
                        Text("Continue with Google")
                            .font(FitFont.body(size: 17, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FitTheme.cardStroke, lineWidth: 1)
                    )
                }

                HStack {
                    Rectangle()
                        .fill(FitTheme.cardStroke)
                        .frame(height: 1)
                    Text("or")
                        .font(FitFont.body(size: 14, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                        .padding(.horizontal, 12)
                    Rectangle()
                        .fill(FitTheme.cardStroke)
                        .frame(height: 1)
                }
                
                VStack(spacing: 16) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FitTheme.cardStroke, lineWidth: 1)
                        )
                    
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FitTheme.cardStroke, lineWidth: 1)
                        )
                }
                
                Button {
                    Task {
                        await viewModel.login()
                        if viewModel.isComplete {
                            dismiss()
                        }
                    }
                } label: {
                    Text("Sign In")
                        .font(FitFont.body(size: 17, weight: .semibold))
                        .foregroundColor(FitTheme.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(FitTheme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(viewModel.isSubmitting)
                
                Spacer()
            }
            .padding(24)
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: viewModel.isComplete) { isComplete in
                if isComplete {
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

struct EmailSignupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Create Account")
                    .font(FitFont.heading(size: 28, weight: .bold))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(.top, 40)

                if let message = viewModel.submissionMessage, !message.isEmpty {
                    Text(message)
                        .font(FitFont.body(size: 14, weight: .regular))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        await viewModel.signInWithGoogle()
                        if viewModel.isComplete {
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text("G")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.blue)
                            )
                        Text("Continue with Google")
                            .font(FitFont.body(size: 17, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FitTheme.cardStroke, lineWidth: 1)
                    )
                }

                HStack {
                    Rectangle()
                        .fill(FitTheme.cardStroke)
                        .frame(height: 1)
                    Text("or")
                        .font(FitFont.body(size: 14, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                        .padding(.horizontal, 12)
                    Rectangle()
                        .fill(FitTheme.cardStroke)
                        .frame(height: 1)
                }
                
                VStack(spacing: 16) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FitTheme.cardStroke, lineWidth: 1)
                        )
                    
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.newPassword)
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FitTheme.cardStroke, lineWidth: 1)
                        )
                    
                    SecureField("Confirm Password", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FitTheme.cardStroke, lineWidth: 1)
                        )
                }
                
                Button {
                    Task {
                        await viewModel.registerAndComplete()
                        if viewModel.isComplete {
                            dismiss()
                        }
                    }
                } label: {
                    Text("Create Account")
                        .font(FitFont.body(size: 17, weight: .semibold))
                        .foregroundColor(FitTheme.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(FitTheme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(viewModel.isSubmitting)
                
                Spacer()
            }
            .padding(24)
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - ViewModel

@MainActor
final class OnboardingViewModel: NSObject, ObservableObject {
    static var shared: OnboardingViewModel?
    
    @Published var form = OnboardingForm()
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var currentStep = 0
    @Published var isComplete = false
    @Published var isSubmitting = false
    @Published var submissionMessage: String?
    
    @Published var showLogin = false
    @Published var showEmailSignup = false
    @Published var showHeightPicker = false
    @Published var showDatePicker = false
    @Published var datePickerTitle = ""
    @Published var selectedDate = Date()
    @Published var selectedFeet = 5
    @Published var selectedInches = 9
    @Published var isApplyingMacros = false
    @Published var macroStatusMessage: String?
    @Published var splitCreationMode: SplitCreationMode = .ai
    @Published var splitDaysPerWeek: Int = 3
    @Published var splitTrainingDays: [String] = []
    @Published var mainGoalSelection: MainGoalOption = .buildMuscle
    @Published var trainingEnvironmentSelection: TrainingEnvironmentOption = .gym
    @Published var focusAreaSelection: FocusAreaOption = .strength

    private var authSession: ASWebAuthenticationSession?
    
    var heightFeet: String {
        get { form.heightFeet }
        set { form.heightFeet = newValue; save() }
    }
    
    var heightInches: String {
        get { form.heightInches }
        set { form.heightInches = newValue; save() }
    }
    
    var heightUnit: String {
        get { form.heightUnit }
        set { form.heightUnit = newValue; save() }
    }
    
    var weightLbs: String {
        get { form.weightLbs }
        set { form.weightLbs = newValue; save() }
    }
    
    var goalWeightLbs: String {
        get { form.goalWeightLbs }
        set { form.goalWeightLbs = newValue; save() }
    }
    
    var additionalNotes: String {
        get { form.additionalNotes }
        set { form.additionalNotes = newValue; save() }
    }
    
    private let persistenceKey = "fitai.onboarding.form"
    private let splitPreferencesKey = "fitai.onboarding.split.preferences"
    private let mainGoalKey = "fitai.onboarding.mainGoal"
    private let trainingEnvironmentKey = "fitai.onboarding.environment"
    private let focusAreaKey = "fitai.onboarding.focusArea"
    let totalSteps = OnboardingStepIndex.allCases.count

    fileprivate var currentStepCase: OnboardingStepIndex? {
        OnboardingStepIndex(rawValue: currentStep)
    }

    fileprivate var progressSteps: [OnboardingStepIndex] {
        OnboardingStepIndex.allCases.filter { !shouldSkipStep($0) }
    }

    fileprivate var progressIndex: Int {
        guard let current = currentStepCase else { return 0 }
        return progressSteps.firstIndex(of: current) ?? 0
    }

    fileprivate var progressLabel: String {
        "Step \(progressIndex + 1) of \(progressSteps.count)"
    }

    fileprivate var isFeatureSlideActive: Bool {
        currentStepCase?.isFeatureSlide ?? false
    }

    fileprivate var isActionBarHidden: Bool {
        guard let current = currentStepCase else { return false }
        return current == .building
    }
    
    var primaryActionTitle: String {
        switch currentStepCase {
        case .outcome:
            return "Get Started"
        case .featureCoach, .featureTraining, .featureCheckin, .featureNutrition, .featureProgress:
            return "Next Feature"
        case .featureInsights:
            return "Continue"
        case .claim:
            return "Claim My Plan"
        case .trial:
            return "Start 7-Day Free Trial"
        case .instantWin:
            return "Start Today"
        default:
            return "Next"
        }
    }
    
    override init() {
        super.init()
        load()
        loadMainGoalSelection()
        loadTrainingEnvironmentSelection()
        loadFocusAreaSelection()
        loadSplitPreferences()
        OnboardingViewModel.shared = self
    }
    
    func startOnboarding() {
        currentStep = OnboardingStepIndex.outcome.rawValue
        save()
    }
    
    func nextStep() {
        guard let current = currentStepCase else { return }
        guard let next = nextStepIndex(from: current) else { return }
        currentStep = next
        save()
    }

    func skipFeatureTour() {
        currentStep = OnboardingStepIndex.goal.rawValue
        save()
    }
    
    func previousStep() {
        guard let current = currentStepCase else { return }
        guard let previous = previousStepIndex(from: current) else { return }
        currentStep = previous
        save()
    }
    
    func advanceStep() async {
        guard !isSubmitting else { return }
        
        if validateCurrentStep() {
            nextStep()
        }
    }
    
    private func validateCurrentStep() -> Bool {
        switch currentStepCase {
        case .focus:
            return !form.physiqueFocus.isEmpty
        default:
            return true
        }
    }

    private func nextStepIndex(from step: OnboardingStepIndex) -> Int? {
        var index = step.rawValue + 1
        while index < totalSteps {
            if let candidate = OnboardingStepIndex(rawValue: index), !shouldSkipStep(candidate) {
                return index
            }
            index += 1
        }
        return nil
    }

    private func previousStepIndex(from step: OnboardingStepIndex) -> Int? {
        var index = step.rawValue - 1
        while index >= 0 {
            if let candidate = OnboardingStepIndex(rawValue: index), !shouldSkipStep(candidate) {
                return index
            }
            index -= 1
        }
        return nil
    }

    private func shouldSkipStep(_ step: OnboardingStepIndex) -> Bool {
        false
    }
    
    func setSex(_ sex: OnboardingForm.Sex) {
        form.sex = sex
        save()
    }

    func setPrimaryTrainingGoal(_ goal: OnboardingForm.PrimaryTrainingGoal) {
        form.primaryTrainingGoal = goal
        switch goal {
        case .strength:
            form.goal = .maintain
        case .hypertrophy:
            form.goal = .gainWeight
        case .fatLoss:
            form.goal = .loseWeight
        }
        save()
    }

    func setMainGoal(_ goal: MainGoalOption) {
        mainGoalSelection = goal
        switch goal {
        case .buildMuscle:
            form.primaryTrainingGoal = .hypertrophy
            form.goal = .gainWeight
        case .loseFat:
            form.primaryTrainingGoal = .fatLoss
            form.goal = .loseWeight
        case .recomp:
            form.primaryTrainingGoal = .strength
            form.goal = .maintain
        case .performance:
            form.primaryTrainingGoal = .strength
            form.goal = .maintain
        }
        saveMainGoalSelection()
        save()
    }

    func setTrainingFrequency(_ days: Int) {
        let clamped = min(max(days, 2), 7)
        splitDaysPerWeek = clamped
        let normalized = normalizedTrainingDays([], targetCount: clamped)
        splitTrainingDays = normalized
        form.workoutDaysPerWeek = clamped
        form.trainingDaysOfWeek = normalized
        save()
        saveSplitPreferences()
    }

    func setTrainingEnvironment(_ environment: TrainingEnvironmentOption) {
        trainingEnvironmentSelection = environment
        switch environment {
        case .gym:
            form.equipment = .gym
        case .home:
            form.equipment = .home
        case .both:
            form.equipment = .gym
            appendAdditionalNote("Trains at gym and home")
        }
        saveTrainingEnvironmentSelection()
        save()
    }

    func setFocusArea(_ focus: FocusAreaOption) {
        focusAreaSelection = focus
        form.physiqueFocus = [focus.title]
        saveFocusAreaSelection()
        save()
    }

    func setGoal(_ goal: OnboardingForm.Goal) {
        form.goal = goal
        switch goal {
        case .gainWeight:
            form.primaryTrainingGoal = .hypertrophy
        case .loseWeight, .loseWeightFast:
            form.primaryTrainingGoal = .fatLoss
        case .maintain:
            form.primaryTrainingGoal = .strength
        }
        if goal == .loseWeightFast, form.weeklyWeightLossLbs < 1.5 {
            form.weeklyWeightLossLbs = 1.5
        }
        form.weeklyWeightLossLbs = min(max(form.weeklyWeightLossLbs, 0.5), 2.0)
        save()
    }
    
    func setActivityLevel(_ level: OnboardingForm.ActivityLevel) {
        form.activityLevel = level
        save()
    }

    func setTrainingLevel(_ level: OnboardingForm.TrainingLevel) {
        form.trainingLevel = level
        save()
    }

    func togglePhysiqueFocus(_ option: String) {
        var selected = Set(form.physiqueFocus)
        if selected.contains(option) {
            selected.remove(option)
        } else {
            if selected.count < 3 {
                selected.insert(option)
            }
        }
        form.physiqueFocus = selected.sorted()
        save()
    }

    func toggleWeakPoint(_ option: String) {
        var selected = Set(form.weakPoints)
        if selected.contains(option) {
            selected.remove(option)
        } else {
            selected.insert(option)
        }
        form.weakPoints = selected.sorted()
        save()
    }

    func togglePastFailure(_ option: String) {
        var selected = Set(form.pastFailures)
        if selected.contains(option) {
            selected.remove(option)
        } else {
            selected.insert(option)
        }
        form.pastFailures = selected.sorted()
        save()
    }

    func prepareCoachSignalsIfNeeded() {
        if form.coachSignals.isEmpty {
            form.coachSignals = ["Workout split", "Macro targets", "Coach check-ins"]
        }
        if form.lastSeenGap.isEmpty {
            form.lastSeenGap = "Consistency will drive your next 8 weeks."
        }
        save()
    }

    func goToClaim() {
        currentStep = OnboardingStepIndex.claim.rawValue
        save()
    }

    var weekdaySymbols: [String] {
        Calendar.current.weekdaySymbols
    }

    var shortWeekdaySymbols: [String] {
        Calendar.current.shortWeekdaySymbols
    }

    func setSplitCreationMode(_ mode: SplitCreationMode) {
        splitCreationMode = mode
        saveSplitPreferences()
    }

    func setSplitDaysPerWeek(_ days: Int) {
        let clamped = min(max(days, 2), 7)
        var updatedDays = splitTrainingDays
        if updatedDays.count > clamped {
            updatedDays = Array(updatedDays.prefix(clamped))
        }
        splitDaysPerWeek = clamped
        splitTrainingDays = updatedDays
        form.workoutDaysPerWeek = clamped
        form.trainingDaysOfWeek = updatedDays
        save()
        saveSplitPreferences()
    }

    func toggleSplitTrainingDay(_ day: String) {
        var selected = Set(splitTrainingDays)
        if selected.contains(day) {
            selected.remove(day)
        } else {
            if selected.count < splitDaysPerWeek {
                selected.insert(day)
            }
        }
        let ordered = weekdaySymbols.filter { selected.contains($0) }
        splitTrainingDays = ordered
        form.workoutDaysPerWeek = splitDaysPerWeek
        form.trainingDaysOfWeek = ordered
        save()
        saveSplitPreferences()
    }

    func skipSplitSetup() {
        splitCreationMode = .ai
        splitDaysPerWeek = 3
        splitTrainingDays = defaultTrainingDays()
        form.workoutDaysPerWeek = splitDaysPerWeek
        form.trainingDaysOfWeek = splitTrainingDays
        save()
        saveSplitPreferences()
        nextStep()
    }
    
    func signInWithGoogle() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionMessage = nil
        defer { isSubmitting = false }
        
        do {
            let url = try await SupabaseService.shared.googleSignInURL()
            guard let callbackScheme = SupabaseConfig.redirectURL?.scheme else {
                throw SupabaseError.missingRedirectURL
            }

            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                guard let self else { return }

                Task { @MainActor in
                    defer { self.authSession = nil }

                    if let error = error as? ASWebAuthenticationSessionError,
                       error.code == .canceledLogin {
                        return
                    }

                    if let error = error {
                        self.submissionMessage = error.localizedDescription
                        return
                    }

                    guard let callbackURL else {
                        self.submissionMessage = "Missing callback URL from Google sign-in."
                        return
                    }

                    await self.handleAuthCallback(url: callbackURL)
                }
            }
            session.presentationContextProvider = self
            authSession = session
            let didStart = session.start()
            if !didStart {
                authSession = nil
                submissionMessage = "Unable to start Google sign-in."
            }
        } catch {
            submissionMessage = error.localizedDescription
        }
    }
    
    func handleAuthCallback(url: URL) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            let session = try await SupabaseService.shared.handleAuthCallback(url: url)
            let userId = SupabaseService.shared.getUserId(from: session)
            storeUserId(userId)
            await fetchAndApplyOnboardingState(userId: userId)
            await syncProfileFromForm(userId: userId)
            isComplete = true
            Haptics.success()
        } catch {
            submissionMessage = "Failed to complete sign-in: \(error.localizedDescription)"
        }
    }

    func applyMacros(_ macros: MacroTotals) async {
        guard !isApplyingMacros else { return }
        isApplyingMacros = true
        macroStatusMessage = nil
        defer { isApplyingMacros = false }

        let rounded = MacroTotals(
            calories: macros.calories.rounded(),
            protein: macros.protein.rounded(),
            carbs: macros.carbs.rounded(),
            fats: macros.fats.rounded()
        )

        form.macroProtein = "\(Int(rounded.protein))"
        form.macroCarbs = "\(Int(rounded.carbs))"
        form.macroFats = "\(Int(rounded.fats))"
        form.macroCalories = "\(Int(rounded.calories))"
        save()

        NotificationCenter.default.post(name: .fitAIMacrosUpdated, object: nil)

        guard let userId = resolveUserId() else { return }
        let payload: [String: Any] = [
            "macros": macroPayload(from: rounded)
        ]

        do {
            _ = try await ProfileAPIService.shared.updateProfile(userId: userId, payload: payload)
        } catch {
            macroStatusMessage = error.localizedDescription
        }
    }
    
    func registerAndComplete() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionMessage = nil
        defer { isSubmitting = false }
        
        guard !email.isEmpty && !password.isEmpty else {
            submissionMessage = "Please enter email and password"
            return
        }
        
        guard password == confirmPassword else {
            submissionMessage = "Passwords do not match"
            return
        }
        
        do {
            let response = try await AuthAPIService.shared.register(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            form.userId = response.userId
            storeUserId(response.userId)
            
            // Submit onboarding data
            let _ = try await OnboardingAPIService.shared.submit(
                form: form,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            await syncProfileFromForm(userId: response.userId)
            
            isComplete = true
            Haptics.success()
        } catch {
            submissionMessage = error.localizedDescription
        }
    }
    
    func login() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionMessage = nil
        defer { isSubmitting = false }
        
        guard !email.isEmpty && !password.isEmpty else {
            submissionMessage = "Please enter email and password"
            return
        }
        
        do {
            let response = try await AuthAPIService.shared.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            storeUserId(response.userId)
            await fetchAndApplyOnboardingState(userId: response.userId)
            isComplete = true
            Haptics.success()
        } catch {
            submissionMessage = error.localizedDescription
        }
    }
    
    private func storeUserId(_ userId: String) {
        UserDefaults.standard.set(userId, forKey: "fitai.auth.userId")
        form.userId = userId
        save()
    }

    private func resolveUserId() -> String? {
        if let userId = form.userId, !userId.isEmpty {
            return userId
        }
        if let stored = UserDefaults.standard.string(forKey: "fitai.auth.userId"),
           !stored.isEmpty {
            form.userId = stored
            save()
            return stored
        }
        return nil
    }

    private func syncProfileFromForm(userId: String) async {
        let payload = profilePayload()
        guard !payload.isEmpty else { return }
        do {
            _ = try await ProfileAPIService.shared.updateProfile(userId: userId, payload: payload)
        } catch {
            macroStatusMessage = error.localizedDescription
        }
    }

    private func fetchAndApplyOnboardingState(userId: String) async {
        do {
            guard let fetchedForm = try await OnboardingAPIService.shared.fetchState(userId: userId) else {
                return
            }
            form = fetchedForm
            form.userId = userId
            if form.goal == .loseWeightFast {
                form.goal = .loseWeight
                form.weeklyWeightLossLbs = max(form.weeklyWeightLossLbs, 1.5)
            }
            form.weeklyWeightLossLbs = min(max(form.weeklyWeightLossLbs, 0.5), 2.0)
            save()
            NotificationCenter.default.post(name: .fitAIMacrosUpdated, object: nil)
            NotificationCenter.default.post(name: .fitAIProfileUpdated, object: nil)
        } catch {
            // Ignore onboarding state fetch failures during login.
        }
    }

    private func profilePayload() -> [String: Any] {
        var payload: [String: Any] = [:]

        if !form.fullName.isEmpty {
            payload["full_name"] = form.fullName
        }

        if let age = Int(form.age) {
            payload["age"] = age
        }

        if let height = heightCm() {
            payload["height_cm"] = height
        }

        if let weight = weightKg() {
            payload["weight_kg"] = weight
        }

        payload["goal"] = form.goal.rawValue

        var preferences: [String: Any] = [
            "primary_training_goal": form.primaryTrainingGoal.rawValue,
            "training_level": form.trainingLevel.rawValue,
            "workout_days_per_week": form.workoutDaysPerWeek,
            "workout_duration_minutes": form.workoutDurationMinutes,
            "equipment": form.equipment.rawValue,
            "food_allergies": form.foodAllergies,
            "food_dislikes": form.foodDislikes,
            "diet_style": form.dietStyle,
            "checkin_day": form.checkinDay,
            "gender": form.sex.rawValue,
            "sex": form.sex.rawValue,
            "activity_level": form.activityLevel.rawValue,
            "height_unit": form.heightUnit,
            "weekly_weight_loss_lbs": form.weeklyWeightLossLbs,
            "apple_health_sync": form.healthKitSyncEnabled,
            "physique_focus": form.physiqueFocus,
            "weak_points": form.weakPoints,
            "training_days_of_week": form.trainingDaysOfWeek,
            "habits_sleep": form.habitsSleep,
            "habits_nutrition": form.habitsNutrition,
            "habits_stress": form.habitsStress,
            "habits_recovery": form.habitsRecovery,
            "past_failures": form.pastFailures,
            "past_failures_note": form.pastFailuresNote,
            "checkin_energy": form.checkinEnergy,
            "checkin_readiness": form.checkinReadiness,
            "checkin_soreness": form.checkinSoreness,
            "checkin_weight": form.checkinWeight,
            "last_seen_gap": form.lastSeenGap,
            "coach_signals": form.coachSignals
        ]

        if !form.goalWeightLbs.isEmpty {
            preferences["goal_weight_lbs"] = form.goalWeightLbs
        }
        if let targetDate = form.targetDate {
            preferences["target_date_timestamp"] = targetDate.timeIntervalSince1970
        }
        if let birthday = form.birthday {
            preferences["birthday_timestamp"] = birthday.timeIntervalSince1970
        }
        if !form.specialConsiderations.isEmpty {
            preferences["special_considerations"] = form.specialConsiderations.map { $0.rawValue }
        }
        if !form.additionalNotes.isEmpty {
            preferences["additional_notes"] = form.additionalNotes
        }

        preferences = preferences.filter { value in
            if let text = value.value as? String {
                return !text.isEmpty
            }
            if let array = value.value as? [Any] {
                return !array.isEmpty
            }
            if let number = value.value as? Int {
                return number != 0
            }
            if let number = value.value as? Double {
                return number != 0
            }
            return true
        }

        if !preferences.isEmpty {
            payload["preferences"] = preferences
        }

        let macros = macroPayloadFromForm()
        if !macros.isEmpty {
            payload["macros"] = macros
        }

        return payload
    }

    private func macroPayload(from macros: MacroTotals) -> [String: Any] {
        [
            "calories": Int(macros.calories.rounded()),
            "protein": Int(macros.protein.rounded()),
            "carbs": Int(macros.carbs.rounded()),
            "fats": Int(macros.fats.rounded())
        ]
    }

    private func macroPayloadFromForm() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = Int(form.macroCalories), value > 0 { payload["calories"] = value }
        if let value = Int(form.macroProtein), value > 0 { payload["protein"] = value }
        if let value = Int(form.macroCarbs), value > 0 { payload["carbs"] = value }
        if let value = Int(form.macroFats), value > 0 { payload["fats"] = value }
        return payload
    }

    private func heightCm() -> Double? {
        guard let feet = Double(form.heightFeet),
              let inches = Double(form.heightInches) else {
            return nil
        }
        return (feet * 30.48) + (inches * 2.54)
    }

    private func weightKg() -> Double? {
        let sanitized = form.weightLbs.filter { "0123456789.".contains($0) }
        guard let pounds = Double(sanitized), pounds > 0 else {
            return nil
        }
        return pounds * 0.45359237
    }
    
    func save() {
        guard let encoded = try? JSONEncoder().encode(form) else { return }
        UserDefaults.standard.set(encoded, forKey: persistenceKey)
    }

    private func saveMainGoalSelection() {
        UserDefaults.standard.set(mainGoalSelection.rawValue, forKey: mainGoalKey)
    }

    private func saveTrainingEnvironmentSelection() {
        UserDefaults.standard.set(trainingEnvironmentSelection.rawValue, forKey: trainingEnvironmentKey)
    }

    private func saveFocusAreaSelection() {
        UserDefaults.standard.set(focusAreaSelection.rawValue, forKey: focusAreaKey)
    }

    private func saveSplitPreferences() {
        let preferences = SplitSetupPreferences(
            mode: splitCreationMode.rawValue,
            daysPerWeek: splitDaysPerWeek,
            trainingDays: splitTrainingDays
        )
        guard let encoded = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(encoded, forKey: splitPreferencesKey)
    }
    
    func updateBirthday(_ date: Date) {
        form.birthday = date
        save()
    }
    
    func updateTargetDate(_ date: Date) {
        form.targetDate = date
        save()
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let decoded = try? JSONDecoder().decode(OnboardingForm.self, from: data) else {
            return
        }
        form = decoded
        if form.goal == .loseWeightFast {
            form.goal = .loseWeight
            form.weeklyWeightLossLbs = max(form.weeklyWeightLossLbs, 1.5)
        }
        form.weeklyWeightLossLbs = min(max(form.weeklyWeightLossLbs, 0.5), 2.0)
        if form.primaryTrainingGoal == .hypertrophy {
            switch form.goal {
            case .loseWeight:
                form.primaryTrainingGoal = .fatLoss
            case .gainWeight:
                form.primaryTrainingGoal = .hypertrophy
            case .maintain:
                form.primaryTrainingGoal = .strength
            case .loseWeightFast:
                form.primaryTrainingGoal = .fatLoss
            }
        }
        if let birthday = form.birthday {
            selectedDate = birthday
        }
    }

    private func loadMainGoalSelection() {
        if let raw = UserDefaults.standard.string(forKey: mainGoalKey),
           let option = MainGoalOption(rawValue: raw) {
            setMainGoal(option)
            return
        }

        let derived: MainGoalOption
        switch form.goal {
        case .gainWeight:
            derived = .buildMuscle
        case .loseWeight, .loseWeightFast:
            derived = .loseFat
        case .maintain:
            derived = .performance
        }
        setMainGoal(derived)
    }

    private func loadTrainingEnvironmentSelection() {
        if let raw = UserDefaults.standard.string(forKey: trainingEnvironmentKey),
           let option = TrainingEnvironmentOption(rawValue: raw) {
            setTrainingEnvironment(option)
            return
        }

        let derived: TrainingEnvironmentOption
        switch form.equipment {
        case .home:
            derived = .home
        case .gym, .limited:
            derived = .gym
        }
        setTrainingEnvironment(derived)
    }

    private func loadFocusAreaSelection() {
        if let raw = UserDefaults.standard.string(forKey: focusAreaKey),
           let option = FocusAreaOption(rawValue: raw) {
            focusAreaSelection = option
            form.physiqueFocus = [option.title]
            save()
            return
        }

        if let stored = form.physiqueFocus.first,
           let option = FocusAreaOption(rawValue: stored.lowercased()) {
            focusAreaSelection = option
            saveFocusAreaSelection()
            return
        }

        focusAreaSelection = .strength
        form.physiqueFocus = [focusAreaSelection.title]
        saveFocusAreaSelection()
        save()
    }

    private func loadSplitPreferences() {
        if !form.trainingDaysOfWeek.isEmpty {
            let clamped = min(max(form.trainingDaysOfWeek.count, 2), 7)
            splitDaysPerWeek = clamped
            splitTrainingDays = orderedTrainingDays(form.trainingDaysOfWeek)
            form.workoutDaysPerWeek = clamped
            save()
            return
        }

        if let data = UserDefaults.standard.data(forKey: splitPreferencesKey),
           let decoded = try? JSONDecoder().decode(SplitSetupPreferences.self, from: data) {
            splitCreationMode = SplitCreationMode(rawValue: decoded.mode) ?? .ai
            let clamped = min(max(decoded.daysPerWeek, 2), 7)
            splitDaysPerWeek = clamped
            splitTrainingDays = orderedTrainingDays(decoded.trainingDays)
            form.workoutDaysPerWeek = clamped
            form.trainingDaysOfWeek = splitTrainingDays
            save()
            return
        }

        let defaultDays = form.workoutDaysPerWeek == 3
            ? defaultTrainingDays()
            : normalizedTrainingDays([], targetCount: form.workoutDaysPerWeek)
        splitCreationMode = .ai
        splitDaysPerWeek = form.workoutDaysPerWeek
        splitTrainingDays = defaultDays
        form.trainingDaysOfWeek = defaultDays
        save()
        saveSplitPreferences()
    }

    private func appendAdditionalNote(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if form.additionalNotes.contains(trimmed) {
            return
        }
        if form.additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            form.additionalNotes = trimmed
        } else {
            form.additionalNotes += " | \(trimmed)"
        }
    }

    private func orderedTrainingDays(_ days: [String]) -> [String] {
        let availableDays = weekdaySymbols
        let selected = Set(days.filter { availableDays.contains($0) })
        return availableDays.filter { selected.contains($0) }
    }

    private func normalizedTrainingDays(_ days: [String], targetCount: Int) -> [String] {
        let availableDays = weekdaySymbols
        let filtered = days.filter { availableDays.contains($0) }
        var ordered = availableDays.filter { filtered.contains($0) }

        if ordered.count > targetCount {
            ordered = Array(ordered.prefix(targetCount))
        }

        if ordered.count < targetCount {
            for day in availableDays where !ordered.contains(day) {
                ordered.append(day)
                if ordered.count == targetCount {
                    break
                }
            }
        }

        return ordered
    }

    private func defaultTrainingDays() -> [String] {
        let availableDays = weekdaySymbols
        guard !availableDays.isEmpty else { return [] }
        var selected: [String] = []
        var index = 0
        while selected.count < 3 && index < availableDays.count {
            selected.append(availableDays[index])
            index += 2
        }
        return normalizedTrainingDays(selected, targetCount: 3)
    }
}

#if canImport(AuthenticationServices)
extension OnboardingViewModel: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.compactMap { $0 as? UIWindowScene }.first
        return windowScene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#endif

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    OnboardingView()
}
