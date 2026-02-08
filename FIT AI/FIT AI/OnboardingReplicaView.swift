import SwiftUI
import Combine

private enum ReplicaOnboardingStep: Int, CaseIterable {
    case hero
    case featureCoach
    case featureAnalysis
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

    var isFeatureSlide: Bool {
        switch self {
        case .featureCoach, .featureAnalysis, .featureTraining, .featureChallenges, .featureNutrition, .featureProgress:
            return true
        default:
            return false
        }
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

private struct ReplicaFeatureSlide {
    let title: String
    let subtitle: String
    let imageAsset: String
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
    @State private var buildingStage = 0
    @State private var buildingProgress = 0.0
    @State private var personalizingProgress = 0.0
    @State private var autoTask: Task<Void, Never>?
    @State private var claimDeadline = Date().addingTimeInterval(24 * 60 * 60)
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        stepBody
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
        .preferredColorScheme(.dark)
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
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.11))
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
                    .foregroundColor(.white.opacity(0.88))
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
                                .fill(Color.white.opacity(0.16))
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
                        .foregroundColor(.white.opacity(0.78))
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
        case .featureCoach, .featureAnalysis, .featureTraining, .featureChallenges, .featureNutrition, .featureProgress:
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
                    .foregroundColor(.white)
                Text("Win More")
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundColor(Color(red: 0.09, green: 0.49, blue: 0.98))
            }
            .multilineTextAlignment(.center)

            Text("AI-POWERED FITNESS COACH")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.48))

            VStack(alignment: .leading, spacing: 15) {
                heroBullet(icon: "video.fill", text: "Real-time form breakdowns")
                heroBullet(icon: "figure.strengthtraining.traditional", text: "Personalized training plans")
                heroBullet(icon: "chart.pie.fill", text: "Adaptive macro coaching")
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
                .foregroundColor(.white.opacity(0.92))
        }
    }

    private var featureStep: some View {
        let slide = currentSlide

        return VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .frame(maxWidth: .infinity)
                .frame(height: 318)
                .overlay(
                    Image(slide.imageAsset)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            VStack(spacing: 8) {
                Text(slide.title)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(slide.subtitle)
                    .font(.system(size: 23, weight: .regular))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
            }

            HStack(spacing: 26) {
                featureTag(text: "Personalized", tint: slide.dotColor)
                featureTag(text: "AI-Powered", tint: slide.dotColor)
                featureTag(text: "Real-time", tint: slide.dotColor)
            }
        }
    }

    private func featureTag(text: String, tint: Color) -> some View {
        VStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.76))
        }
    }

    private var featuresListStep: some View {
        VStack(spacing: 14) {
            Text("What makes FIT AI\nspecial?")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
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
                .fill(Color.white.opacity(0.06))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(.white)
                Text(item.detail)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white.opacity(0.66))
            }

            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
                .foregroundColor(.white)

            Text("Help us reach more users by rating us 5 stars")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.center)

            Text("Rate your experience")
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(.white)
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
                    .foregroundColor(.white)
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
                .foregroundColor(.white.opacity(0.62))
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
                    .foregroundColor(.white.opacity(0.5))
            }

            Text(title)
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(.white.opacity(0.68))
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
                    .foregroundColor(.white.opacity(0.95))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.66))
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
                        : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.0 : 0.16), lineWidth: 1)
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
                .foregroundColor(.white.opacity(0.65))

            TextField(placeholder, text: text)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var buildingStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.yellow)

            Text("Building Your Program")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            Text("This will only take a moment")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.white.opacity(0.7))

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
                .foregroundColor(.white.opacity(0.74))
        }
        .padding(.horizontal, 2)
    }

    private func statusRow(index: Int, title: String, isComplete: Bool, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : (isActive ? Color.blue : Color.white.opacity(0.18)))
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
                        .foregroundColor(.white.opacity(0.68))
                }
            }

            Text(title)
                .font(.system(size: 21, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : .white.opacity(0.58))
        }
    }

    private var potentialStep: some View {
        VStack(spacing: 12) {
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
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("See how FIT AI can accelerate your fitness journey")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)

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

    private var projectionStep: some View {
        VStack(spacing: 14) {
            Text("6-Month Progress Projection")
                .font(.system(size: 29, weight: .bold))
                .foregroundColor(.white)

            ProjectionChartView()
                .frame(height: 220)
                .padding(14)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

            HStack(spacing: 10) {
                metricCard(value: "80%", title: "With FIT AI", color: .green)
                metricCard(value: "35%", title: "Traditional", color: .red)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Key Benefits for Your Goals")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)

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
                .foregroundColor(.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
                .foregroundColor(.white.opacity(0.86))
        }
    }

    private var personalizingStep: some View {
        VStack(spacing: 14) {
            Text("Personalizing FIT AI")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Tailoring every feature to your training journey")
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(.white.opacity(0.72))
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
                    .foregroundColor(.white.opacity(0.62))
            }

            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var claimStep: some View {
        VStack(spacing: 14) {
            Text("Claim Your Plan")
                .font(.system(size: 46, weight: .bold))
                .foregroundColor(.white)
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
                    .foregroundColor(.white.opacity(0.8))

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
                    .foregroundColor(.white)

                featureBenefitCard(.init(icon: "video.fill", title: "AI Video Analysis", detail: "Instant feedback on technique and form."))
                featureBenefitCard(.init(icon: "figure.strengthtraining.traditional", title: "Personalized Training Plans", detail: "Adaptive workouts built around your week."))
                featureBenefitCard(.init(icon: "chart.line.uptrend.xyaxis", title: "Progress Tracking", detail: "Track trends and improve with coach recaps."))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("View Premium Plans") {
                step = .paywallReveal
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white.opacity(0.85))
            .buttonStyle(.plain)
        }
    }

    private func timerCell(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.blue)
            Text(unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.66))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var paywallRevealStep: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("Unlock Your Potential")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))

                Text("FIT AI")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(.white)

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
                    .foregroundColor(.white)

                featureBenefitCard(.init(icon: "video.fill", title: "AI Video Analysis", detail: "Instant breakdowns with personalized suggestions."))

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(width: 338, height: 560)
            .background(Color.black.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                        .foregroundColor(.white.opacity(0.72))

                    Text("FIT AI")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundColor(.white)
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
                .foregroundColor(.white)

            featureBenefitCard(.init(icon: "video.fill", title: "AI Video Analysis", detail: "Upload footage and get instant personalized feedback."))
            featureBenefitCard(.init(icon: "brain.head.profile", title: "24/7 AI Coach", detail: "Get guided responses for training and nutrition."))
            featureBenefitCard(.init(icon: "chart.bar.xaxis", title: "Progress Insights", detail: "Track trends and adjust your plan with clarity."))

            Text("Trusted by Athletes")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 4)

            HStack(spacing: 8) {
                trustPill(value: "15K+", label: "Active Users")
                trustPill(value: "98%", label: "See Progress")
                trustPill(value: "4.9", label: "Rating")
            }

            Text("Start Your Journey")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 4)

            VStack(spacing: 10) {
                ForEach(ReplicaPlan.allCases) { plan in
                    planCard(for: plan)
                }
            }

            Text("No commitment required, cancel anytime")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.62))
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
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
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
                            .foregroundColor(.white)

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
                        .foregroundColor(.white.opacity(0.72))
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(selected ? .blue : .white.opacity(0.35))
            }
            .padding(14)
            .background(Color.white.opacity(selected ? 0.1 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.blue : Color.white.opacity(0.1), lineWidth: selected ? 1.7 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var featureBenefits: [BenefitItem] {
        [
            .init(icon: "video.fill", title: "Video Analysis", detail: "AI-powered form checks from your workout clips"),
            .init(icon: "brain.head.profile", title: "Smart Coaching", detail: "Guidance based on your progress and patterns"),
            .init(icon: "figure.strengthtraining.traditional", title: "Workout Builder", detail: "Adaptive sessions for your goals and schedule"),
            .init(icon: "chart.line.uptrend.xyaxis", title: "Progress Tracking", detail: "Clear trends to measure improvement"),
            .init(icon: "flame.fill", title: "Challenge Mode", detail: "Daily check-ins and streaks for accountability"),
            .init(icon: "fork.knife", title: "Nutrition Support", detail: "Macro targets and quick logging to stay on track"),
        ]
    }

    private var currentSlide: ReplicaFeatureSlide {
        switch step {
        case .featureCoach:
            return .init(
                title: "AI Fitness Coach",
                subtitle: "Chat with your personal coach trained on your data",
                imageAsset: "OnboardingFeatureCoach",
                buttonGradient: [Color(red: 0.38, green: 0.50, blue: 0.93), Color(red: 0.44, green: 0.31, blue: 0.75)],
                dotColor: Color(red: 0.35, green: 0.52, blue: 1.0)
            )
        case .featureAnalysis:
            return .init(
                title: "Workout Analysis",
                subtitle: "Get detailed feedback and improvement suggestions",
                imageAsset: "OnboardingFeatureInsights",
                buttonGradient: [Color(red: 0.85, green: 0.46, blue: 0.90), Color(red: 0.95, green: 0.35, blue: 0.43)],
                dotColor: Color(red: 0.94, green: 0.46, blue: 0.86)
            )
        case .featureTraining:
            return .init(
                title: "Personalized Training",
                subtitle: "Create custom plans tailored to your level and goals",
                imageAsset: "OnboardingFeatureTraining",
                buttonGradient: [Color(red: 0.33, green: 0.66, blue: 0.95), Color(red: 0.08, green: 0.83, blue: 0.90)],
                dotColor: Color(red: 0.33, green: 0.66, blue: 0.95)
            )
        case .featureChallenges:
            return .init(
                title: "Daily Challenges",
                subtitle: "Complete check-ins and keep your momentum every day",
                imageAsset: "OnboardingFeatureCheckin",
                buttonGradient: [Color(red: 0.95, green: 0.40, blue: 0.64), Color(red: 0.95, green: 0.84, blue: 0.26)],
                dotColor: Color(red: 0.95, green: 0.40, blue: 0.64)
            )
        case .featureNutrition:
            return .init(
                title: "Nutrition Tracking",
                subtitle: "Track macros quickly and stay aligned to your goal",
                imageAsset: "OnboardingFeatureNutrition",
                buttonGradient: [Color(red: 0.60, green: 0.84, blue: 0.86), Color(red: 0.92, green: 0.82, blue: 0.85)],
                dotColor: Color(red: 0.60, green: 0.84, blue: 0.86)
            )
        case .featureProgress:
            return .init(
                title: "Progress Tracking",
                subtitle: "Monitor weekly trends and celebrate every win",
                imageAsset: "OnboardingFeatureProgress",
                buttonGradient: [Color(red: 0.93, green: 0.88, blue: 0.80), Color(red: 0.93, green: 0.67, blue: 0.58)],
                dotColor: Color(red: 0.94, green: 0.84, blue: 0.76)
            )
        default:
            return .init(
                title: "",
                subtitle: "",
                imageAsset: "OnboardingFeatureCoach",
                buttonGradient: [Color.blue, Color.blue],
                dotColor: .blue
            )
        }
    }

    private var primaryTitle: String {
        switch step {
        case .hero:
            return "Get Started"
        case .featureCoach, .featureAnalysis, .featureTraining, .featureChallenges, .featureNutrition:
            return "Next Feature"
        case .featureProgress:
            return "Continue Journey"
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
        case .hero, .featureCoach, .featureAnalysis, .featureTraining, .featureChallenges, .featureNutrition, .featureProgress, .building, .personalizing:
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
        let goalText = selectedGoal?.previewText ?? "building muscle"
        let daysText = selectedFrequency ?? 3
        let focusText = selectedFocus?.title.lowercased() ?? "strength"
        let durationText = selectedDuration?.rawValue ?? 45

        return "\(namePart) are set on \(goalText), training \(daysText) days each week with \(focusText) as the priority. FIT AI will build \(durationText)-minute sessions and adaptive nutrition targets so you improve with consistency and clear direction."
    }

    private func symbolForGoal(_ option: MainGoalOption) -> String {
        switch option {
        case .buildMuscle:
            return "dumbbell.fill"
        case .loseFat:
            return "flame.fill"
        case .recomp:
            return "arrow.triangle.2.circlepath"
        case .performance:
            return "bolt.fill"
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

private struct ProjectionChartView: View {
    private let withAI: [CGFloat] = [0.18, 0.42, 0.62, 0.73, 0.80, 0.84]
    private let traditional: [CGFloat] = [0.18, 0.18, 0.20, 0.24, 0.30, 0.38]

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
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)

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
                        .foregroundColor(.white.opacity(0.6))
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
                .foregroundColor(.white.opacity(0.85))
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
