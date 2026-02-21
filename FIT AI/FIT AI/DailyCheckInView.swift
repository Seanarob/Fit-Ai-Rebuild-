import SwiftUI
import Combine

// MARK: - Daily Check-In View

struct DailyCheckInView: View {
    let onComplete: () -> Void
    
    @StateObject private var viewModel = DailyCheckInViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            
            if viewModel.showingCoachResponse {
                coachResponseView
                    .transition(.opacity.combined(with: .scale))
            } else {
                checkInFormView
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showingCoachResponse)
    }
    
    // MARK: - Check-In Form
    
    private var checkInFormView: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            ScrollView {
                VStack(spacing: 24) {
                    // Progress indicator
                    progressIndicator
                    
                    // Question 1: Macros
                    questionCard(
                        number: 1,
                        question: "Did you hit your macros yesterday?",
                        isActive: true
                    ) {
                        HStack(spacing: 12) {
                            selectionButton(
                                title: "Yes",
                                icon: "checkmark.circle.fill",
                                isSelected: viewModel.hitMacros == true,
                                color: .green
                            ) {
                                viewModel.hitMacros = true
                            }
                            
                            selectionButton(
                                title: "No",
                                icon: "xmark.circle.fill",
                                isSelected: viewModel.hitMacros == false,
                                color: .red
                            ) {
                                viewModel.hitMacros = false
                            }
                        }
                    }
                    
                    // Question 2: Training
                    questionCard(
                        number: 2,
                        question: "Did you train or was it an off day?",
                        isActive: viewModel.hitMacros != nil
                    ) {
                        HStack(spacing: 12) {
                            ForEach(DailyCheckInData.TrainingStatus.allCases, id: \.self) { status in
                                selectionButton(
                                    title: status.title,
                                    icon: status.icon,
                                    isSelected: viewModel.trainingStatus == status,
                                    color: status == .trained ? FitTheme.cardWorkoutAccent : FitTheme.textSecondary
                                ) {
                                    viewModel.trainingStatus = status
                                }
                            }
                        }
                    }
                    
                    // Question 3: Sleep
                    questionCard(
                        number: 3,
                        question: "How was your sleep?",
                        isActive: viewModel.trainingStatus != nil
                    ) {
                        HStack(spacing: 12) {
                            ForEach(DailyCheckInData.SleepQuality.allCases, id: \.self) { quality in
                                sleepButton(quality: quality)
                            }
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            
            // Submit Button
            submitButton
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Check-In")
                    .font(FitFont.heading(size: 24))
                    .foregroundColor(FitTheme.textPrimary)
                
                Text("Save your streak in 10 seconds")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardHighlight)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { step in
                Capsule()
                    .fill(stepColor(for: step))
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.currentStep)
    }
    
    private func stepColor(for step: Int) -> Color {
        if step <= viewModel.currentStep {
            return FitTheme.accent
        }
        return FitTheme.cardHighlight
    }
    
    // MARK: - Question Card
    
    private func questionCard<Content: View>(
        number: Int,
        question: String,
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(FitFont.body(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(isActive ? FitTheme.accent : FitTheme.cardHighlight)
                    .clipShape(Circle())
                
                Text(question)
                    .font(FitFont.body(size: 16, weight: .medium))
                    .foregroundColor(isActive ? FitTheme.textPrimary : FitTheme.textSecondary)
            }
            
            content()
                .opacity(isActive ? 1 : 0.5)
                .allowsHitTesting(isActive)
        }
        .padding(18)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isActive ? FitTheme.accent.opacity(0.3) : FitTheme.cardStroke.opacity(0.5), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
    
    // MARK: - Selection Button
    
    private func selectionButton(
        title: String,
        icon: String,
        isSelected: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                
                Text(title)
                    .font(FitFont.body(size: 15, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : FitTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? color : FitTheme.cardHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? color : FitTheme.cardStroke, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Sleep Button
    
    private func sleepButton(quality: DailyCheckInData.SleepQuality) -> some View {
        let isSelected = viewModel.sleepQuality == quality
        let color: Color = {
            switch quality {
            case .good: return .green
            case .okay: return .yellow
            case .poor: return .red
            }
        }()
        
        return Button(action: {
            Haptics.selection()
            viewModel.sleepQuality = quality
        }) {
            VStack(spacing: 6) {
                Text(quality.emoji)
                    .font(.system(size: 28))
                
                Text(quality.title)
                    .font(FitFont.body(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : FitTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? color : FitTheme.cardHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? color : FitTheme.cardStroke, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Submit Button
    
    private var submitButton: some View {
        VStack(spacing: 0) {
            Divider()
            
            Button(action: {
                Task {
                    await viewModel.submitCheckIn()
                }
            }) {
                HStack(spacing: 10) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                        Text("Complete Check-In")
                            .font(FitFont.body(size: 17, weight: .semibold))
                    }
                }
                .foregroundColor(FitTheme.buttonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    viewModel.isComplete
                        ? FitTheme.primaryGradient
                        : LinearGradient(colors: [FitTheme.cardHighlight, FitTheme.cardHighlight], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!viewModel.isComplete || viewModel.isSubmitting)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(FitTheme.cardBackground)
    }
    
    // MARK: - Coach Response View
    
    private var coachResponseView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Coach avatar
            ZStack {
                Circle()
                    .fill(FitTheme.cardCoach)
                    .frame(width: 120, height: 120)
                    .shadow(color: FitTheme.cardCoachAccent.opacity(0.3), radius: 20)
                
                CoachArtView(pose: .celebration)
                    .frame(width: 100, height: 100)
            }
            
            // Streak celebration
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("\(StreakStore.shared.appStreak.currentStreak) Day Streak!")
                        .font(FitFont.heading(size: 28))
                        .foregroundColor(FitTheme.textPrimary)
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                }
                
                Text("Streak saved!")
                    .font(FitFont.body(size: 16))
                    .foregroundColor(FitTheme.textSecondary)
            }
            
            // Coach response
            if let response = viewModel.coachResponse {
                Text("\"\(response)\"")
                    .font(FitFont.body(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
                    .background(FitTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(FitTheme.cardCoachAccent.opacity(0.3), lineWidth: 1.5)
                    )
            }
            
            Spacer()
            
            // Continue button
            Button(action: {
                Haptics.success()
                onComplete()
                dismiss()
            }) {
                Text("Continue")
                    .font(FitFont.body(size: 17, weight: .semibold))
                    .foregroundColor(FitTheme.buttonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Daily Check-In View Model

@MainActor
final class DailyCheckInViewModel: ObservableObject {
    @Published var hitMacros: Bool?
    @Published var trainingStatus: DailyCheckInData.TrainingStatus?
    @Published var sleepQuality: DailyCheckInData.SleepQuality?
    @Published var isSubmitting = false
    @Published var showingCoachResponse = false
    @Published var coachResponse: String?
    
    var isComplete: Bool {
        hitMacros != nil && trainingStatus != nil && sleepQuality != nil
    }
    
    var currentStep: Int {
        if sleepQuality != nil { return 3 }
        if trainingStatus != nil { return 2 }
        if hitMacros != nil { return 1 }
        return 0
    }
    
    func submitCheckIn() async {
        guard let hitMacros, let trainingStatus, let sleepQuality else { return }
        
        isSubmitting = true
        
        // Generate local coach response
        coachResponse = generateCoachResponse()
        
        // Small delay for feel
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Create check-in data
        let checkInData = DailyCheckInData(
            hitMacros: hitMacros,
            trainingStatus: trainingStatus,
            sleepQuality: sleepQuality,
            completedAt: Date(),
            coachResponse: coachResponse
        )
        
        // Complete the check-in
        PostHogAnalytics.featureUsed(
            .checkIn,
            action: "submit",
            properties: [
                "check_in_type": "daily",
                "hit_macros": hitMacros,
                "training_status": trainingStatus.rawValue,
                "sleep_quality": sleepQuality.rawValue
            ]
        )
        StreakStore.shared.completeCheckIn(checkInData)
        
        isSubmitting = false
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showingCoachResponse = true
        }
        
        Haptics.success()
    }
    
    private func generateCoachResponse() -> String {
        // Local response generation based on answers
        let macrosText = hitMacros == true
        let trained = trainingStatus == .trained
        let goodSleep = sleepQuality == .good
        
        let responses: [String]
        
        if macrosText && trained && goodSleep {
            responses = [
                "Perfect day yesterday! Keep that energy going today. 💪",
                "You're crushing it! Consistency like this builds champions.",
                "Elite habits! Your future self is thanking you right now.",
                "All boxes checked! This is how transformations happen."
            ]
        } else if macrosText && trained {
            responses = [
                "Great work on training and nutrition! Prioritize sleep tonight.",
                "Two out of three ain't bad! Rest up and keep building.",
                "Solid effort! Better sleep = better gains tomorrow."
            ]
        } else if macrosText {
            responses = [
                "Nutrition on point! Rest day recovery is important too.",
                "Macros hit! Even rest days are progress days.",
                "Great job fueling right! Your body's recovering."
            ]
        } else if trained {
            responses = [
                "Great workout! Let's dial in those macros today.",
                "Training done! Fuel that body right and watch the gains come.",
                "Good session! Remember: nutrition amplifies your hard work."
            ]
        } else {
            responses = [
                "New day, fresh start! Let's make today count.",
                "Every day is a chance to build momentum. Let's go!",
                "Progress isn't always perfect. Keep showing up!",
                "One day at a time. You've got this! 💪"
            ]
        }
        
        return responses.randomElement() ?? "Keep showing up! You've got this."
    }
}

// MARK: - Preview

#Preview {
    DailyCheckInView(onComplete: {})
}
