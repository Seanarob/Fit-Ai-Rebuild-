import Combine
import SwiftUI
import UIKit

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            if viewModel.currentStep == 0 {
                welcomeScreen
            } else {
                VStack(spacing: 0) {
                    progressDots
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
                    if viewModel.currentStep == 2 {
                        viewModel.updateBirthday(date)
                    } else if viewModel.currentStep == 4 {
                        viewModel.updateTargetDate(date)
                    }
                }
            )
        }
        .onOpenURL { url in
            Task {
                await viewModel.handleAuthCallback(url: url)
            }
        }
    }
    
    // MARK: - Welcome Screen
    
    private var welcomeScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                // Coach character
                CoachCharacterView(size: 200, showBackground: true, pose: .idle)
                
                Text("Welcome to FitAI")
                    .font(FitFont.heading(size: 34, weight: .bold))
                    .foregroundColor(FitTheme.textPrimary)
                
                VStack(spacing: 8) {
                    Text("The most frictionless calorie tracking app in the world.")
                    Text("Built so you stick with it.")
                }
                .font(FitFont.body(size: 16, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
                .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    viewModel.startOnboarding()
                } label: {
                    Text("Get Started")
                        .font(FitFont.body(size: 17, weight: .semibold))
                        .foregroundColor(.white)
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
        .sheet(isPresented: $viewModel.showLogin) {
            LoginView(viewModel: viewModel)
        }
    }
    
    // MARK: - Progress Indicators
    
    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<viewModel.totalSteps, id: \.self) { index in
                if index == viewModel.currentStep {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(FitTheme.accent)
                        .frame(width: 24, height: 4)
                } else {
                    Circle()
                        .fill(FitTheme.accent.opacity(0.3))
                        .frame(width: 4, height: 4)
                }
            }
        }
    }
    
    // MARK: - Hero Illustrations
    
    @ViewBuilder
    private var heroIllustration: some View {
        switch viewModel.currentStep {
        case 1: // Gender
            CoachCharacterView(size: 180, showBackground: true, pose: .idle)
        case 2: // Birthday
            CoachCharacterView(size: 180, showBackground: true, pose: .celebration)
        case 3: // Height
            CoachCharacterView(size: 180, showBackground: true, pose: .idle)
        case 4: // Weight
            CoachCharacterView(size: 180, showBackground: true, pose: .neutral)
        case 5: // Activity
            CoachCharacterView(size: 180, showBackground: true, pose: .thinking)
        case 6: // Special Considerations
            CoachCharacterView(size: 180, showBackground: true, pose: .idle)
        case 7: // Goals
            CoachCharacterView(size: 180, showBackground: true, pose: .talking)
        case 8: // Account
            CoachCharacterView(size: 180, showBackground: true, pose: .idle)
        default:
            CoachCharacterView(size: 180, showBackground: true, pose: .idle)
        }
    }
    
    // MARK: - Step Content
    
    private var stepTitle: String {
        switch viewModel.currentStep {
        case 1: return "What's your gender?"
        case 2: return "When's your birthday?"
        case 3: return "What's your height?"
        case 4: return "What's your weight?"
        case 5: return "What's your activity level?"
        case 6: return "Any special considerations?"
        case 7: return "Your Personalized Goals"
        case 8: return "Save Your Progress"
        default: return ""
        }
    }
    
    private var stepSubtitle: String? {
        switch viewModel.currentStep {
        case 1: return "This helps us calculate accurate calorie and macro goals"
        case 2: return "We only use this to calculate your age for health metrics and goals. Your birthday data is kept private and secure."
        case 5: return "Be honest! This affects your calorie needs"
        case 6: return "Select all that apply (optional)"
        case 8: return "Create an account to sync your data across devices and never lose your progress."
        default: return nil
        }
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case 1:
            genderStep
        case 2:
            birthdayStep
        case 3:
            heightStep
        case 4:
            weightStep
        case 5:
            activityStep
        case 6:
            specialConsiderationsStep
        case 7:
            goalsStep
        case 8:
            accountStep
        default:
            EmptyView()
        }
    }
    
    // MARK: - Step Views
    
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
                viewModel.selectedDate = viewModel.form.birthday ?? Date()
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
                            Text("Dec 5, 2007")
                                .font(FitFont.heading(size: 20, weight: .bold))
                                .foregroundColor(FitTheme.accent)
                            
                            Text("18 years old")
                                .font(FitFont.body(size: 14, weight: .regular))
                                .foregroundColor(FitTheme.accent.opacity(0.7))
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
            
            WeightInputField(
                label: "Goal Weight",
                value: $viewModel.goalWeightLbs,
                placeholder: "188 lbs"
            )
            
            Button {
                viewModel.datePickerTitle = "Target Date"
                viewModel.selectedDate = viewModel.form.targetDate ?? Date()
                viewModel.showDatePicker = true
            } label: {
                HStack {
                    Text(viewModel.form.targetDate != nil ? 
                         viewModel.form.targetDate!.formatted(date: .abbreviated, time: .omitted) :
                         "Set target date")
                        .font(FitFont.body(size: 16, weight: .medium))
                        .foregroundColor(viewModel.form.targetDate != nil ? FitTheme.accent : FitTheme.textSecondary)
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
                
                TextField("e.g. 'Wedding in April', 'Recovering from surgery'", text: $viewModel.additionalNotes)
                    .font(FitFont.body(size: 15, weight: .regular))
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
    
    private var goalsStep: some View {
        VStack(spacing: 20) {
            // Weight goal card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Today")
                        .font(FitFont.body(size: 14, weight: .medium))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(viewModel.weightLbs.isEmpty ? "192" : viewModel.weightLbs)
                        .font(FitFont.heading(size: 18, weight: .bold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("lbs")
                        .font(FitFont.body(size: 14, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Image(systemName: "arrow.right")
                        .foregroundColor(FitTheme.textSecondary)
                    
                    if let targetDate = viewModel.form.targetDate {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(targetDate.formatted(date: .abbreviated, time: .omitted))
                                .font(FitFont.body(size: 12, weight: .regular))
                                .foregroundColor(FitTheme.textSecondary)
                            Text("(\(Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0)d)")
                                .font(FitFont.body(size: 10, weight: .regular))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(viewModel.goalWeightLbs.isEmpty ? "180" : viewModel.goalWeightLbs)
                            .font(FitFont.heading(size: 18, weight: .bold))
                            .foregroundColor(FitTheme.accent)
                        Text("lbs")
                            .font(FitFont.body(size: 14, weight: .regular))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                
                // Simple weight graph placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(FitTheme.accent.opacity(0.2))
                    .frame(height: 80)
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
            
            // Nutrient targets
            VStack(alignment: .leading, spacing: 12) {
                NutrientTargetRow(icon: "flame.fill", iconColor: .orange, label: "Daily Calories", value: "2587 cal")
                NutrientTargetRow(icon: "fish.fill", iconColor: .yellow, label: "Protein Target", value: "146g")
                NutrientTargetRow(icon: "apple.fill", iconColor: .red, label: "Carbs Target", value: "339g")
                NutrientTargetRow(icon: "drop.fill", iconColor: FitTheme.accent, label: "Fat Target", value: "71g")
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
            
            Button {
                // Customize goals action
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(FitTheme.accent)
                    Text("Customize goals")
                        .font(FitFont.body(size: 15, weight: .medium))
                        .foregroundColor(FitTheme.accent)
                }
            }
        }
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
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .sheet(isPresented: $viewModel.showEmailSignup) {
            EmailSignupView(viewModel: viewModel)
        }
    }
    
    // MARK: - Step Actions
    
    private var stepActions: some View {
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
                    await viewModel.advanceStep()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(viewModel.primaryActionTitle)
                        .font(FitFont.body(size: 17, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(FitTheme.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(viewModel.isSubmitting)
        }
    }
}

// MARK: - Supporting Views

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
        case .male: return "figure.male"
        case .female: return "figure.female"
        case .other: return "person.2"
        case .preferNotToSay: return "questionmark.circle"
        }
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
            .foregroundColor(isSelected ? .white : FitTheme.textPrimary)
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
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(20)
        }
        .background(Color.white)
        .presentationDetents([.medium])
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
                Button("Clear") {
                    date = Date()
                }
                .font(FitFont.body(size: 16, weight: .regular))
                .foregroundColor(FitTheme.textSecondary)
                
                Spacer()
                
                Text(title)
                    .font(FitFont.heading(size: 18, weight: .bold))
                
                Spacer()
                
                Button("Done") {
                    onSave?(date)
                    isPresented = false
                }
                .font(FitFont.body(size: 16, weight: .semibold))
                .foregroundColor(FitTheme.accent)
            }
            .padding(20)
            
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
        }
        .background(Color.white)
        .presentationDetents([.medium])
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
                    .padding(.top, 40)
                
                VStack(spacing: 16) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FitTheme.cardStroke, lineWidth: 1)
                        )
                    
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
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
                        .foregroundColor(.white)
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
                    .padding(.top, 40)
                
                VStack(spacing: 16) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FitTheme.cardStroke, lineWidth: 1)
                        )
                    
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.newPassword)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FitTheme.cardStroke, lineWidth: 1)
                        )
                    
                    SecureField("Confirm Password", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
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
                        .foregroundColor(.white)
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
    }
}

// MARK: - ViewModel

@MainActor
final class OnboardingViewModel: ObservableObject {
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
    let totalSteps = 9 // Welcome + 8 steps
    
    var primaryActionTitle: String {
        if currentStep == totalSteps - 1 {
            return "Next"
        }
        return "Next"
    }
    
    init() {
        load()
        OnboardingViewModel.shared = self
    }
    
    func startOnboarding() {
        currentStep = 1
        save()
    }
    
    func nextStep() {
        if currentStep < totalSteps - 1 {
            currentStep += 1
            save()
        }
    }
    
    func previousStep() {
        if currentStep > 0 {
            currentStep -= 1
            save()
        }
    }
    
    func advanceStep() async {
        guard !isSubmitting else { return }
        
        if currentStep == totalSteps - 1 {
            // Final step - account creation
            return
        }
        
        if validateCurrentStep() {
            nextStep()
        }
    }
    
    private func validateCurrentStep() -> Bool {
        switch currentStep {
        case 1: // Gender
            return true // Optional
        case 2: // Birthday
            return form.birthday != nil
        case 3: // Height
            return !form.heightFeet.isEmpty && !form.heightInches.isEmpty
        case 4: // Weight
            return !form.weightLbs.isEmpty
        case 5: // Activity
            return true // Always has default
        case 6: // Special considerations
            return true // Optional
        case 7: // Goals
            return true // Calculated
        default:
            return true
        }
    }
    
    func setSex(_ sex: OnboardingForm.Sex) {
        form.sex = sex
        save()
    }
    
    func setActivityLevel(_ level: OnboardingForm.ActivityLevel) {
        form.activityLevel = level
        save()
    }
    
    func signInWithGoogle() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            let url = try await SupabaseService.shared.googleSignInURL()
            await UIApplication.shared.open(url)
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
            isComplete = true
            Haptics.success()
        } catch {
            submissionMessage = "Failed to complete sign-in: \(error.localizedDescription)"
        }
    }
    
    func registerAndComplete() async {
        guard !isSubmitting else { return }
        isSubmitting = true
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
            
            isComplete = true
            Haptics.success()
        } catch {
            submissionMessage = error.localizedDescription
        }
    }
    
    func login() async {
        guard !isSubmitting else { return }
        isSubmitting = true
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
            isComplete = true
            Haptics.success()
        } catch {
            submissionMessage = error.localizedDescription
        }
    }
    
    private func storeUserId(_ userId: String) {
        UserDefaults.standard.set(userId, forKey: "fitai.auth.userId")
    }
    
    func save() {
        guard let encoded = try? JSONEncoder().encode(form) else { return }
        UserDefaults.standard.set(encoded, forKey: persistenceKey)
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
        if let birthday = form.birthday {
            selectedDate = birthday
        }
    }
}

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

