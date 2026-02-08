import Combine
import Foundation

@MainActor
final class MoreViewModel: ObservableObject {
    @Published var goal: OnboardingForm.Goal = .maintain {
        didSet { persistOnboarding(); markDirty() }
    }
    @Published var macroProtein: String = "" {
        didSet { persistOnboarding(); markDirty() }
    }
    @Published var macroCarbs: String = "" {
        didSet { persistOnboarding(); markDirty() }
    }
    @Published var macroFats: String = "" {
        didSet { persistOnboarding(); markDirty() }
    }
    @Published var macroCalories: String = "" {
        didSet { persistOnboarding(); markDirty() }
    }
    @Published var checkinDay: String = OnboardingForm.checkinDays.first ?? "Monday" {
        didSet { persistOnboarding(); markDirty() }
    }
    @Published var age: String = "" {
        didSet { persistOnboarding(); markDirty() }
    }
    @Published var heightFeet: String = "" {
        didSet { persistOnboarding(); markDirty() }
    }
    @Published var heightInches: String = "" {
        didSet { persistOnboarding(); markDirty() }
    }
    @Published var weightLbs: String = "" {
        didSet { persistOnboarding(); markDirty() }
    }
    @Published var sex: OnboardingForm.Sex = .male {
        didSet { persistOnboarding(); markDirty() }
    }
    @Published var startingPhotos = StartingPhotosState() {
        didSet { persistStartingPhotos(); markDirty() }
    }
    @Published var email: String = "Add email"
    @Published var subscriptionStatus: String = "Free"
    @Published var profileStatusMessage: String?
    @Published var hasUnsavedChanges: Bool = false
    @Published var isSavingProfile: Bool = false

    private let userId: String
    private let onboardingKey = "fitai.onboarding.form"
    private let walkthroughReplayKey = "fitai.walkthrough.replayRequested"
    private var onboardingForm = OnboardingForm()
    private var didLoad = false
    private var isApplyingProfile = false
    private var profilePreferences: [String: Any] = [:]
    private var profileMacros: [String: Any] = [:]

    init(userId: String) {
        self.userId = userId
        load()
        Task {
            await refreshProfile()
        }
    }

    func replayWalkthrough() {
        UserDefaults.standard.set(Date(), forKey: walkthroughReplayKey)
        NotificationCenter.default.post(name: .fitAIWalkthroughReplayRequested, object: nil)
    }

    func refreshProfile() async {
        profileStatusMessage = nil
        do {
            let profile = try await ProfileAPIService.shared.fetchProfile(userId: userId)
            await MainActor.run {
                applyProfile(profile)
                profileStatusMessage = "Profile updated."
            }
        } catch {
            await MainActor.run {
                profileStatusMessage = error.localizedDescription
            }
        }
    }

    func saveProfile() async {
        guard hasUnsavedChanges else { return }
        profileStatusMessage = nil
        isSavingProfile = true
        await syncProfile()
        await MainActor.run {
            isSavingProfile = false
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: onboardingKey),
           let decoded = try? JSONDecoder().decode(OnboardingForm.self, from: data) {
            onboardingForm = decoded
            goal = decoded.goal
            macroProtein = decoded.macroProtein
            macroCarbs = decoded.macroCarbs
            macroFats = decoded.macroFats
            macroCalories = decoded.macroCalories
            checkinDay = decoded.checkinDay
            age = decoded.age
            heightFeet = decoded.heightFeet
            heightInches = decoded.heightInches
            weightLbs = decoded.weightLbs
            sex = decoded.sex
        }

        startingPhotos = StartingPhotosStore.load()

        didLoad = true
    }

    private func persistOnboarding() {
        guard didLoad else { return }
        onboardingForm.goal = goal
        onboardingForm.macroProtein = macroProtein
        onboardingForm.macroCarbs = macroCarbs
        onboardingForm.macroFats = macroFats
        onboardingForm.macroCalories = macroCalories
        onboardingForm.checkinDay = checkinDay
        onboardingForm.age = age
        onboardingForm.heightFeet = heightFeet
        onboardingForm.heightInches = heightInches
        onboardingForm.weightLbs = weightLbs
        onboardingForm.sex = sex
        onboardingForm.healthKitSyncEnabled = HealthSyncState.shared.isEnabled
        if onboardingForm.userId == nil {
            onboardingForm.userId = userId
        }
        guard let encoded = try? JSONEncoder().encode(onboardingForm) else { return }
        UserDefaults.standard.set(encoded, forKey: onboardingKey)
    }

    private func persistStartingPhotos() {
        guard didLoad else { return }
        StartingPhotosStore.save(startingPhotos)
        NotificationCenter.default.post(name: .fitAIStartingPhotosUpdated, object: nil)
    }

    private func markDirty() {
        guard didLoad, !isApplyingProfile else { return }
        hasUnsavedChanges = true
    }

    private func syncProfile() async {
        let payload = buildProfilePayload()
        guard !payload.isEmpty else { return }
        do {
            let profile = try await ProfileAPIService.shared.updateProfile(
                userId: userId,
                payload: payload
            )
            await MainActor.run {
                applyProfile(profile)
                hasUnsavedChanges = false
                profileStatusMessage = "Profile saved."
            }
            NotificationCenter.default.post(name: .fitAIMacrosUpdated, object: nil)
            NotificationCenter.default.post(name: .fitAIProfileUpdated, object: nil)
        } catch {
            await MainActor.run {
                profileStatusMessage = error.localizedDescription
            }
        }
    }

    private func buildProfilePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "goal": goal.rawValue,
        ]
        if let ageValue = Int(age.trimmingCharacters(in: .whitespacesAndNewlines)) {
            payload["age"] = ageValue
        }
        if let heightCm = heightCmValue() {
            payload["height_cm"] = heightCm
        }
        if let weightKg = weightKgValue() {
            payload["weight_kg"] = weightKg
        }
        var macros = profileMacros
        for (key, value) in macroPayload() {
            macros[key] = value
        }
        if !macros.isEmpty {
            payload["macros"] = macros
        }
        var preferences = profilePreferences
        preferences["checkin_day"] = checkinDay
        preferences["gender"] = sex.rawValue
        preferences["sex"] = sex.rawValue
        preferences["apple_health_sync"] = HealthSyncState.shared.isEnabled
        preferences["weekly_weight_loss_lbs"] = onboardingForm.weeklyWeightLossLbs
        if !startingPhotos.isEmpty {
            preferences["starting_photos"] = startingPhotos.asDictionary()
        }
        payload["preferences"] = preferences
        return payload
    }

    private func macroPayload() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = number(from: macroProtein) {
            payload["protein"] = value
        }
        if let value = number(from: macroCarbs) {
            payload["carbs"] = value
        }
        if let value = number(from: macroFats) {
            payload["fats"] = value
        }
        if let value = number(from: macroCalories) {
            payload["calories"] = value
        }
        return payload
    }

    private func number(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private func applyProfile(_ profile: [String: Any]) {
        isApplyingProfile = true
        defer { isApplyingProfile = false }
        if let email = profile["email"] as? String, !email.isEmpty {
            self.email = email
        }
        if let status = profile["subscription_status"] as? String, !status.isEmpty {
            subscriptionStatus = status
        }
        if let goalRaw = profile["goal"] as? String,
           let parsedGoal = OnboardingForm.Goal(rawValue: goalRaw) {
            goal = parsedGoal
        }
        if let macros = profile["macros"] as? [String: Any] {
            profileMacros = macros
            macroProtein = Self.stringValue(macros["protein"], fallback: macroProtein)
            macroCarbs = Self.stringValue(macros["carbs"], fallback: macroCarbs)
            macroFats = Self.stringValue(macros["fats"], fallback: macroFats)
            macroCalories = Self.stringValue(macros["calories"], fallback: macroCalories)
        }
        if let preferences = profile["preferences"] as? [String: Any] {
            profilePreferences = preferences
            if let checkin = preferences["checkin_day"] as? String, !checkin.isEmpty {
                checkinDay = checkin
            }
            if let appleHealth = preferences["apple_health_sync"] as? Bool {
                HealthSyncState.shared.isEnabled = appleHealth
                onboardingForm.healthKitSyncEnabled = appleHealth
            }
            if let gender = preferences["gender"] as? String,
               let parsed = OnboardingForm.Sex(rawValue: gender) {
                sex = parsed
            } else if let gender = preferences["sex"] as? String,
                      let parsed = OnboardingForm.Sex(rawValue: gender) {
                sex = parsed
            }
            if let starting = preferences["starting_photos"],
               let parsed = StartingPhotosState.fromDictionary(starting) {
                startingPhotos = parsed
                StartingPhotosStore.save(parsed)
            }
        }
        if let ageValue = profile["age"] as? Int {
            age = "\(ageValue)"
        } else if let ageValue = profile["age"] as? NSNumber {
            age = ageValue.stringValue
        }
        if let heightCm = profile["height_cm"] as? Double {
            applyHeight(cm: heightCm)
        } else if let heightCm = profile["height_cm"] as? NSNumber {
            applyHeight(cm: heightCm.doubleValue)
        }
        if let weightKg = profile["weight_kg"] as? Double {
            weightLbs = String(format: "%.0f", weightKg * 2.20462)
        } else if let weightKg = profile["weight_kg"] as? NSNumber {
            weightLbs = String(format: "%.0f", weightKg.doubleValue * 2.20462)
        }
        updateCheckinDayStorage(checkinDay)
        hasUnsavedChanges = false
    }

    private static func stringValue(_ value: Any?, fallback: String) -> String {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let double = value as? Double {
            return String(format: "%.0f", double)
        }
        return fallback
    }

    private func heightCmValue() -> Double? {
        let trimmedFeet = heightFeet.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInches = heightInches.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let feet = Double(trimmedFeet), let inches = Double(trimmedInches) else {
            return nil
        }
        return feet * 30.48 + inches * 2.54
    }

    private func weightKgValue() -> Double? {
        let trimmed = weightLbs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lbs = Double(trimmed) else { return nil }
        return lbs / 2.20462
    }

    private func applyHeight(cm: Double) {
        guard cm > 0 else { return }
        let totalInches = cm / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(round(totalInches.truncatingRemainder(dividingBy: 12)))
        heightFeet = "\(feet)"
        heightInches = "\(inches)"
    }

    private func updateCheckinDayStorage(_ day: String) {
        if let index = OnboardingForm.checkinDays.firstIndex(of: day) {
            UserDefaults.standard.set(index, forKey: "checkinDay")
        }
    }
}

extension Notification.Name {
    static let fitAIWalkthroughReplayRequested = Notification.Name("fitai.walkthrough.replayRequested")
    static let fitAIStartingPhotosUpdated = Notification.Name("fitai.startingPhotos.updated")
    static let fitAIMacrosUpdated = Notification.Name("fitai.macros.updated")
    static let fitAIProfileUpdated = Notification.Name("fitai.profile.updated")
}
