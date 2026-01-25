import Combine
import PhotosUI
import PhotosUI
import SwiftUI
import UIKit

struct MoreView: View {
    let userId: String

    @StateObject private var viewModel: MoreViewModel

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
                                    sex: $viewModel.sex
                                )
                            } label: {
                                SettingsCard(
                                    title: "Body details",
                                    subtitle: "Age, height, weight, gender",
                                    value: profileSummary
                                )
                            }
                        }

                        SettingsSection(title: "Plan") {
                            NavigationLink {
                                GoalsDetailView(goal: $viewModel.goal)
                            } label: {
                                SettingsCard(
                                    title: "Goals",
                                    subtitle: "Cut, bulk, or maintain",
                                    value: viewModel.goal.title
                                )
                            }

                            NavigationLink {
                                MacroTargetsDetailView(
                                    protein: $viewModel.macroProtein,
                                    carbs: $viewModel.macroCarbs,
                                    fats: $viewModel.macroFats,
                                    calories: $viewModel.macroCalories
                                )
                            } label: {
                                SettingsCard(
                                    title: "Macro targets",
                                    subtitle: "Daily nutrition targets",
                                    value: macroSummary
                                )
                            }
                        }

                        SettingsSection(title: "Check-ins") {
                            NavigationLink {
                                CheckInDayDetailView(selectedDay: $viewModel.checkinDay)
                            } label: {
                                SettingsCard(
                                    title: "Check-in day",
                                    subtitle: "Weekly progress review",
                                    value: viewModel.checkinDay
                                )
                            }

                            NavigationLink {
                                StartingPhotosDetailView(userId: userId, photos: $viewModel.startingPhotos)
                            } label: {
                                SettingsCard(
                                    title: "Starting photos",
                                    subtitle: "Front, side, back",
                                    value: viewModel.startingPhotos.summary
                                )
                            }
                        }

                        SettingsSection(title: "Guided Walkthrough") {
                            NavigationLink {
                                WalkthroughReplayView(onReplay: viewModel.replayWalkthrough)
                            } label: {
                                SettingsCard(
                                    title: "Replay walkthrough",
                                    subtitle: "Run the guided tour again",
                                    value: "Placeholder"
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
                                    value: "Plan: \(viewModel.subscriptionStatus)"
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(FitFont.body(size: 18))
                    .foregroundColor(FitTheme.textPrimary)

                Text(subtitle)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(value)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textPrimary)
                    .multilineTextAlignment(.trailing)

                Image(systemName: "chevron.right")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
        .shadow(color: FitTheme.shadow, radius: 16, x: 0, y: 8)
    }
}

private struct GoalsDetailView: View {
    @Binding var goal: OnboardingForm.Goal

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        DetailContainer(title: "Goals", subtitle: "Pick the primary focus for your plan.") {
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

    var body: some View {
        DetailContainer(title: "Body Details", subtitle: "Update profile metrics used in your plan.") {
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

    var body: some View {
        DetailContainer(title: "Macro Targets", subtitle: "Update daily nutrition targets.") {
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

private struct CheckInDayDetailView: View {
    @Binding var selectedDay: String
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        DetailContainer(title: "Check-in Day", subtitle: "Choose the day for weekly progress reviews.") {
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

    var body: some View {
        DetailContainer(title: "Starting Photos", subtitle: "Capture or select front, side, and back photos.") {
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
    @State private var showingAlert = false

    var body: some View {
        DetailContainer(title: "Guided Walkthrough", subtitle: "Replay the guided tour any time.") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tap below to replay the guided tour the next time it is available.")
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textSecondary)

                Button("Start walkthrough") {
                    onReplay()
                    showingAlert = true
                }
                .buttonStyle(PrimaryActionButton())
                .alert("Walkthrough queued", isPresented: $showingAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("We will launch the guided walkthrough from here once the flow is wired.")
                }
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
    @ViewBuilder let content: Content

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
