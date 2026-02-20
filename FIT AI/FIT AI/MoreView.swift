import Combine
import PhotosUI
import PhotosUI
import SwiftUI
import UIKit

struct MoreView: View {
    let userId: String

    @StateObject private var viewModel: MoreViewModel
    @StateObject private var healthSyncState = HealthSyncState.shared
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system

    private var macroSummary: String {
        let entries = [
            macroLabel("P", viewModel.macroProtein, unit: "g"),
            macroLabel("C", viewModel.macroCarbs, unit: "g"),
            macroLabel("F", viewModel.macroFats, unit: "g"),
            macroLabel(nil, viewModel.macroCalories, unit: "kcal")
        ].compactMap { $0 }

        return entries.isEmpty ? "Set your targets" : entries.joined(separator: " · ")
    }

    private var profileSummary: String {
        let ageText = viewModel.age.trimmingCharacters(in: .whitespacesAndNewlines)
        let heightText = heightLabel(feet: viewModel.heightFeet, inches: viewModel.heightInches)
        let weightText = viewModel.weightLbs.trimmingCharacters(in: .whitespacesAndNewlines)
        let genderText = viewModel.sex.title

        var entries: [String] = []
        if !ageText.isEmpty { entries.append("\(ageText) yrs") }
        if let heightText { entries.append(heightText) }
        if !weightText.isEmpty { entries.append("\(weightText) lb") }
        entries.append(genderText)
        return entries.joined(separator: " · ")
    }

    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: MoreViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        SettingsSection(title: "Profile") {
                            NavigationLink {
                                ProfileDetailView(
                                    age: $viewModel.age,
                                    heightFeet: $viewModel.heightFeet,
                                    heightInches: $viewModel.heightInches,
                                    weightLbs: $viewModel.weightLbs,
                                    sex: $viewModel.sex,
                                    statusMessage: viewModel.profileStatusMessage,
                                    isSaveEnabled: viewModel.hasUnsavedChanges && !viewModel.isSavingProfile,
                                    isSaving: viewModel.isSavingProfile,
                                    onSave: {
                                        Task { await viewModel.saveProfile() }
                                    }
                                )
                            } label: {
                                SettingsCard(
                                    title: "Body Details",
                                    subtitle: "Age, height, weight, gender",
                                    value: profileSummary,
                                    icon: "figure.stand",
                                    iconColor: .cyan
                                )
                            }
                        }

                        SettingsSection(title: "Plan") {
                            NavigationLink {
                                GoalsDetailView(
                                    goal: $viewModel.goal,
                                    statusMessage: viewModel.profileStatusMessage,
                                    isSaveEnabled: viewModel.hasUnsavedChanges && !viewModel.isSavingProfile,
                                    isSaving: viewModel.isSavingProfile,
                                    onSave: {
                                        Task { await viewModel.saveProfile() }
                                    }
                                )
                            } label: {
                                SettingsCard(
                                    title: "Goals",
                                    subtitle: "Cut, bulk, or maintain",
                                    value: viewModel.goal.title,
                                    icon: "target",
                                    iconColor: .orange
                                )
                            }

                            NavigationLink {
                                MacroTargetsDetailView(
                                    protein: $viewModel.macroProtein,
                                    carbs: $viewModel.macroCarbs,
                                    fats: $viewModel.macroFats,
                                    calories: $viewModel.macroCalories,
                                    statusMessage: viewModel.profileStatusMessage,
                                    isSaveEnabled: viewModel.hasUnsavedChanges && !viewModel.isSavingProfile,
                                    isSaving: viewModel.isSavingProfile,
                                    onSave: {
                                        Task { await viewModel.saveProfile() }
                                    }
                                )
                            } label: {
                                SettingsCard(
                                    title: "Macro Targets",
                                    subtitle: "Daily nutrition targets",
                                    value: macroSummary,
                                    icon: "chart.pie.fill",
                                    iconColor: .green
                                )
                            }
                        }

                        SettingsSection(title: "Appearance") {
                            NavigationLink {
                                AppearanceDetailView()
                            } label: {
                                SettingsCard(
                                    title: "Theme",
                                    subtitle: "Light, dark, or system",
                                    value: appAppearance.title,
                                    icon: "circle.lefthalf.filled",
                                    iconColor: .teal
                                )
                            }
                        }

                        SettingsSection(title: "Integrations") {
                            NavigationLink {
                                HealthSyncDetailView()
                            } label: {
                                SettingsCard(
                                    title: "Apple Health",
                                    subtitle: "Sync workouts automatically",
                                    value: healthSyncState.isEnabled ? "On" : "Off",
                                    icon: "heart.fill",
                                    iconColor: .red
                                )
                            }
                        }

                        SettingsSection(title: "Check-ins") {
                            NavigationLink {
                                CheckInDayDetailView(
                                    selectedDay: $viewModel.checkinDay,
                                    statusMessage: viewModel.profileStatusMessage,
                                    isSaveEnabled: viewModel.hasUnsavedChanges && !viewModel.isSavingProfile,
                                    isSaving: viewModel.isSavingProfile,
                                    onSave: {
                                        Task { await viewModel.saveProfile() }
                                    }
                                )
                            } label: {
                                SettingsCard(
                                    title: "Check-in Day",
                                    subtitle: "Weekly progress review",
                                    value: viewModel.checkinDay,
                                    icon: "calendar.badge.checkmark",
                                    iconColor: .purple
                                )
                            }

                            NavigationLink {
                                StartingPhotosDetailView(
                                    userId: userId,
                                    photos: $viewModel.startingPhotos,
                                    statusMessage: viewModel.profileStatusMessage,
                                    isSaveEnabled: viewModel.hasUnsavedChanges && !viewModel.isSavingProfile,
                                    isSaving: viewModel.isSavingProfile,
                                    onSave: {
                                        Task { await viewModel.saveProfile() }
                                    }
                                )
                            } label: {
                                SettingsCard(
                                    title: "Starting Photos",
                                    subtitle: "Front, side, back",
                                    value: viewModel.startingPhotos.summary,
                                    icon: "camera.fill",
                                    iconColor: .pink
                                )
                            }
                        }

                        SettingsSection(title: "Page Guides") {
                            NavigationLink {
                                WalkthroughReplayView(onReplay: viewModel.replayWalkthrough)
                            } label: {
                                SettingsCard(
                                    title: "Replay Page Guides",
                                    subtitle: "Show first-visit explainers again",
                                    value: "Tap to start",
                                    icon: "play.circle.fill",
                                    iconColor: .indigo
                                )
                            }
                        }

                        SettingsSection(title: "Account") {
                            NavigationLink {
                                AccountDetailView(
                                    email: $viewModel.email,
                                    subscriptionStatus: $viewModel.subscriptionStatus,
                                    statusMessage: viewModel.profileStatusMessage,
                                    onRefresh: {
                                        Task {
                                            await viewModel.refreshProfile()
                                        }
                                    }
                                )
                            } label: {
                                SettingsCard(
                                    title: "Account",
                                    subtitle: viewModel.email,
                                    value: viewModel.subscriptionStatus,
                                    icon: "person.crop.circle.fill",
                                    iconColor: .blue
                                )
                            }
                        }

                        SettingsSection(title: "Labs") {
                            NavigationLink {
                                StreakBadgesDemoView()
                            } label: {
                                SettingsCard(
                                    title: "Holographic Badges",
                                    subtitle: "Interactive shimmer demo",
                                    value: "Try it",
                                    icon: "sparkles",
                                    iconColor: .mint
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .tint(FitTheme.accent)
        .onReceive(NotificationCenter.default.publisher(for: .fitAIMacrosUpdated)) { _ in
            Task { await viewModel.refreshProfile() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(FitFont.heading(size: 30))
                .fontWeight(.semibold)
                .foregroundColor(FitTheme.textPrimary)

            Text("Manage profile, goals, check-ins, and account details.")
                .font(FitFont.body(size: 16))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private func macroLabel(_ prefix: String?, _ value: String, unit: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let prefix {
            return "\(prefix) \(trimmed)\(unit)"
        }
        return "\(trimmed) \(unit)"
    }

    private func heightLabel(feet: String, inches: String) -> String? {
        let trimmedFeet = feet.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInches = inches.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFeet.isEmpty, !trimmedInches.isEmpty else { return nil }
        return "\(trimmedFeet)'\(trimmedInches)\""
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)

            VStack(spacing: 12) {
                content
            }
        }
    }
}

private struct SettingsCard: View {
    let title: String
    let subtitle: String
    let value: String
    var icon: String = "gearshape.fill"
    var iconColor: Color = FitTheme.accent

    var body: some View {
        HStack(spacing: 14) {
            // Icon badge (similar to check-in numbered badge)
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FitFont.body(size: 17, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)

                Text(value)
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Chevron in subtle circle
            ZStack {
                Circle()
                    .fill(FitTheme.cardHighlight)
                    .frame(width: 32, height: 32)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(iconColor.opacity(0.2), lineWidth: 1.5)
        )
        .shadow(color: FitTheme.shadow.opacity(0.5), radius: 12, x: 0, y: 6)
    }
}

private struct GoalsDetailView: View {
    @Binding var goal: OnboardingForm.Goal
    let statusMessage: String?
    let isSaveEnabled: Bool
    let isSaving: Bool
    let onSave: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        DetailContainer(
            title: "Goals",
            subtitle: "Pick the primary focus for your plan.",
            statusMessage: statusMessage,
            isSaveEnabled: isSaveEnabled,
            isSaving: isSaving,
            onSave: onSave
        ) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(OnboardingForm.Goal.allCases) { item in
                    Button {
                        goal = item
                    } label: {
                        SelectionChip(
                            title: item.title,
                            isSelected: goal == item
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ProfileDetailView: View {
    @Binding var age: String
    @Binding var heightFeet: String
    @Binding var heightInches: String
    @Binding var weightLbs: String
    @Binding var sex: OnboardingForm.Sex
    let statusMessage: String?
    let isSaveEnabled: Bool
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        DetailContainer(
            title: "Body Details",
            subtitle: "Update profile metrics used in your plan.",
            statusMessage: statusMessage,
            isSaveEnabled: isSaveEnabled,
            isSaving: isSaving,
            onSave: onSave
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    DetailField(title: "Age", text: $age, placeholder: "Years")
                    DetailField(title: "Weight", text: $weightLbs, placeholder: "lbs")
                }

                HStack(spacing: 12) {
                    DetailField(title: "Height (ft)", text: $heightFeet, placeholder: "ft")
                    DetailField(title: "Height (in)", text: $heightInches, placeholder: "in")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Gender")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                    Picker("Gender", selection: $sex) {
                        ForEach(OnboardingForm.Sex.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(FitTheme.accent)
                }
            }
        }
    }
}

private struct MacroTargetsDetailView: View {
    @Binding var protein: String
    @Binding var carbs: String
    @Binding var fats: String
    @Binding var calories: String
    let statusMessage: String?
    let isSaveEnabled: Bool
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        DetailContainer(
            title: "Macro Targets",
            subtitle: "Update daily nutrition targets.",
            statusMessage: statusMessage,
            isSaveEnabled: isSaveEnabled,
            isSaving: isSaving,
            onSave: onSave
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    MacroField(title: "Protein", value: $protein, unit: "g")
                    MacroField(title: "Carbs", value: $carbs, unit: "g")
                }

                HStack(spacing: 12) {
                    MacroField(title: "Fats", value: $fats, unit: "g")
                    MacroField(title: "Calories", value: $calories, unit: "kcal")
                }
            }
        }
    }
}

private struct AppearanceDetailView: View {
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        DetailContainer(
            title: "Appearance",
            subtitle: "Choose how the app should look."
        ) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(AppAppearance.allCases) { appearance in
                    Button {
                        appAppearance = appearance
                    } label: {
                        SelectionChip(
                            title: appearance.title,
                            isSelected: appAppearance == appearance
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CheckInDayDetailView: View {
    @Binding var selectedDay: String
    let statusMessage: String?
    let isSaveEnabled: Bool
    let isSaving: Bool
    let onSave: () -> Void
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        DetailContainer(
            title: "Check-in Day",
            subtitle: "Choose the day for weekly progress reviews.",
            statusMessage: statusMessage,
            isSaveEnabled: isSaveEnabled,
            isSaving: isSaving,
            onSave: onSave
        ) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(OnboardingForm.checkinDays, id: \.self) { day in
                    Button {
                        selectedDay = day
                    } label: {
                        SelectionChip(title: day, isSelected: selectedDay == day)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StartingPhotosDetailView: View {
    let userId: String
    @Binding var photos: StartingPhotosState
    let statusMessage: String?
    let isSaveEnabled: Bool
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        DetailContainer(
            title: "Starting Photos",
            subtitle: "Capture or select front, side, and back photos.",
            statusMessage: statusMessage,
            isSaveEnabled: isSaveEnabled,
            isSaving: isSaving,
            onSave: onSave
        ) {
            VStack(spacing: 12) {
                ForEach(StartingPhotoType.allCases) { type in
                    StartingPhotoPickerRow(userId: userId, type: type, photos: $photos)
                }
            }
        }
    }
}

private struct WalkthroughReplayView: View {
    let onReplay: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DetailContainer(title: "Page Guides", subtitle: "Replay first-visit page explainers any time.") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tap below to reset all page intro popups. You can also use the help icon on any screen to open that page’s guide.")
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textSecondary)

                Button("Replay guides") {
                    onReplay()
                    dismiss()
                }
                .buttonStyle(PrimaryActionButton())
            }
        }
    }
}

private struct AccountDetailView: View {
    @Binding var email: String
    @Binding var subscriptionStatus: String
    let statusMessage: String?
    let onRefresh: () -> Void
    @State private var showingLogout = false

    var body: some View {
        DetailContainer(title: "Account", subtitle: "Manage login and subscription details.") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledValue(title: "Email", value: email)
                LabeledValue(title: "Subscription", value: subscriptionStatus)

                Button("Refresh profile") {
                    onRefresh()
                }
                .buttonStyle(SecondaryActionButton())

                Button("Log out") {
                    showingLogout = true
                }
                .buttonStyle(SecondaryActionButton())
                .alert("Log out", isPresented: $showingLogout) {
                    Button("Cancel", role: .cancel) {}
                    Button("Log out", role: .destructive) {}
                } message: {
                    Text("Logout will be wired once auth is connected.")
                }

                if let statusMessage, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
        }
    }
}

private struct DetailContainer<Content: View>: View {
    let title: String
    let subtitle: String
    let statusMessage: String?
    let isSaveEnabled: Bool
    let isSaving: Bool
    let onSave: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        statusMessage: String? = nil,
        isSaveEnabled: Bool = false,
        isSaving: Bool = false,
        onSave: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusMessage = statusMessage
        self.isSaveEnabled = isSaveEnabled
        self.isSaving = isSaving
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(FitFont.heading(size: 30))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.textPrimary)

                        Text(subtitle)
                            .font(FitFont.body(size: 16))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    CardContainer {
                        content
                    }

                    if let onSave {
                        Button(isSaving ? "Saving…" : "Save Changes") {
                            onSave()
                        }
                        .buttonStyle(PrimaryActionButton())
                        .disabled(!isSaveEnabled || isSaving)
                        .opacity(isSaveEnabled && !isSaving ? 1 : 0.6)
                    }

                    if let statusMessage, !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct CardContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: FitTheme.shadow, radius: 18, x: 0, y: 10)
    }
}

private struct SelectionChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(FitFont.body(size: 16))
            .foregroundColor(isSelected ? FitTheme.accent : FitTheme.textPrimary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? FitTheme.accentSoft : FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? FitTheme.accent : FitTheme.cardStroke, lineWidth: 1)
            )
    }
}

private struct DetailField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .numberPad

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundColor(FitTheme.textPrimary)
                .padding(12)
                .background(FitTheme.cardHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MacroField: View {
    let title: String
    @Binding var value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)

            HStack {
                TextField(title, text: $value)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .foregroundColor(FitTheme.textPrimary)

                Text(unit)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(12)
            .background(FitTheme.cardHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PhotoSlot: View {
    let title: String
    let url: String
    let localImage: UIImage?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let url = URL(string: url), !url.absoluteString.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(FitTheme.cardBackground)
                            .overlay(
                                SwiftUI.ProgressView()
                                    .tint(FitTheme.textSecondary)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(FitTheme.cardBackground)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(FitTheme.textSecondary)
                            )
                    @unknown default:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(FitTheme.cardBackground)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(FitTheme.cardBackground)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .foregroundColor(FitTheme.textSecondary)
                    )
                    .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FitFont.body(size: 18))
                    .foregroundColor(FitTheme.textPrimary)

                Text(statusText)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var statusText: String {
        if localImage != nil || !url.isEmpty {
            return "Photo ready"
        }
        return "No photo added"
    }
}

private struct StartingPhotoPickerRow: View {
    let userId: String
    let type: StartingPhotoType
    @Binding var photos: StartingPhotosState

    @State private var selectedItem: PhotosPickerItem?
    @State private var localImage: UIImage?
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var isShowingCamera = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotoSlot(title: type.title, url: photos.url(for: type), localImage: localImage)

            HStack(spacing: 12) {
                Button("Take photo") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isShowingCamera = true
                        uploadError = nil
                    } else {
                        uploadError = "Camera is not available on this device."
                    }
                }
                .buttonStyle(SecondaryActionButton())
                .disabled(isUploading)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Text("Choose photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButton())
                .disabled(isUploading)
            }

            if isUploading {
                Text("Uploading...")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }

            if let uploadError {
                Text(uploadError)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .onChange(of: selectedItem) { _ in
            Task {
                await uploadSelectedPhoto()
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            SingleImageCameraPicker(isPresented: $isShowingCamera) { image in
                handleCapturedImage(image)
            }
        }
    }

    private func uploadSelectedPhoto() async {
        guard let item = selectedItem else { return }
        isUploading = true
        uploadError = nil
        defer {
            isUploading = false
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                uploadError = "Unable to load photo data."
                return
            }
            localImage = image
            await uploadImageData(data)
            selectedItem = nil
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func handleCapturedImage(_ image: UIImage) {
        localImage = image
        Task {
            await uploadCapturedImage(image)
        }
    }

    private func uploadCapturedImage(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        await uploadImageData(data)
    }

    private func uploadImageData(_ data: Data) async {
        isUploading = true
        uploadError = nil
        defer {
            isUploading = false
        }

        do {
            let response = try await ProgressAPIService.shared.uploadProgressPhoto(
                userId: userId,
                checkinDate: Date(),
                photoType: type.rawValue,
                photoCategory: "starting",
                imageData: data
            )
            if let url = response.photoUrl, !url.isEmpty {
                photos.set(url: url, for: type)
                Haptics.success()
            } else {
                uploadError = "Upload succeeded, but no URL returned."
            }
        } catch {
            uploadError = error.localizedDescription
        }
    }
}

private struct SingleImageCameraPicker: UIViewControllerRepresentable {
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
        let parent: SingleImageCameraPicker

        init(parent: SingleImageCameraPicker) {
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
private struct LabeledValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)

            Text(value)
                .font(FitFont.body(size: 16))
                .foregroundColor(FitTheme.textPrimary)
        }
    }
}

private struct PrimaryActionButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FitFont.body(size: 16))
            .fontWeight(.semibold)
            .foregroundColor(FitTheme.buttonText)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(FitTheme.primaryGradient)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: FitTheme.buttonShadow, radius: 12, x: 0, y: 8)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct SecondaryActionButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FitFont.body(size: 16))
            .fontWeight(.semibold)
            .foregroundColor(FitTheme.textPrimary)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview {
    MoreView(userId: "demo-user")
}
