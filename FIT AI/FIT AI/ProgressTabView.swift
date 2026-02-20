import Charts
import Combine
import CoreImage
import PhotosUI
import SwiftUI
import UIKit

fileprivate let progressDisplayDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

fileprivate let progressAPIDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

fileprivate let progressISODateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

fileprivate let progressISODateFormatterWithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

fileprivate func parseProgressPhotoDate(_ value: String) -> Date? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let parsed = progressAPIDateFormatter.date(from: trimmed)
        ?? progressISODateFormatterWithFractional.date(from: trimmed)
        ?? progressISODateFormatter.date(from: trimmed) {
        return parsed
    }

    // Supabase timestamps can include formats DateFormatter/ISO8601DateFormatter reject.
    if trimmed.count >= 10 {
        return progressAPIDateFormatter.date(from: String(trimmed.prefix(10)))
    }
    return nil
}

fileprivate let workoutSessionDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

fileprivate let workoutSessionDateFormatterWithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

fileprivate func checkinComparisonText(source: String?, comparisonPhotoCount: Int) -> String? {
    switch source?.lowercased() {
    case "previous_checkin":
        return "Compared against your previous check-in photos."
    case "starting_photos":
        return "Compared against your starting photos."
    case "none":
        break
    case .some:
        break
    case .none:
        break
    }

    if comparisonPhotoCount >= 12 {
        let capped = min(24, comparisonPhotoCount)
        return "Compared against your last \(capped) progress photos."
    }
    if comparisonPhotoCount > 1 {
        return "Compared against your recent progress photos."
    }
    return "Coach compared your latest check-in photos with your recent progress shots."
}

fileprivate func formatWorkoutWeight(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded.truncatingRemainder(dividingBy: 1) == 0 {
        return "\(Int(rounded))"
    }
    return String(format: "%.1f", rounded)
}

struct ProgressTabView: View {
    enum WeightRange: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case quarter = "3 Mo"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            }
        }
    }

    struct WeightPoint: Identifiable {
        let id = UUID()
        let date: Date
        let weight: Double
    }

    enum MacroMetric: String, CaseIterable, Identifiable {
        case calories = "Calories"
        case protein = "Protein"
        case carbs = "Carbs"
        case fats = "Fats"

        var id: String { rawValue }

        var unit: String {
            switch self {
            case .calories: return "kcal"
            case .protein, .carbs, .fats: return "g"
            }
        }

        func value(from payload: MacroTotalsPayload?) -> Double {
            switch self {
            case .calories: return payload?.calories ?? 0
            case .protein: return payload?.protein ?? 0
            case .carbs: return payload?.carbs ?? 0
            case .fats: return payload?.fats ?? 0
            }
        }
    }

    struct MacroAdherencePoint: Identifiable {
        let id = UUID()
        let date: Date
        let loggedValue: Double
        let targetValue: Double
    }

    struct WorkoutDaySummary {
        let sessions: [WorkoutSession]
        let totalMinutes: Int
    }

    struct ProgressPhotoItem: Identifiable {
        let id: String
        let imageURL: URL
        let date: Date?
        let type: String?
        let category: String?
        let isLocal: Bool
    }

    let userId: String
    @Binding private var intent: ProgressTabIntent?
    @EnvironmentObject private var guidedTour: GuidedTourCoordinator

    init(userId: String, intent: Binding<ProgressTabIntent?> = .constant(nil)) {
        self.userId = userId
        _intent = intent
        _localProgressPhotos = State(initialValue: ProgressPhotoLocalStore.load(userId: userId))
    }

    @State private var checkins: [WeeklyCheckin] = []
    @State private var progressPhotos: [ProgressPhoto] = []
    @State private var localProgressPhotos: [LocalProgressPhoto] = []
    @State private var macroAdherence: [MacroAdherenceDay] = []
    @State private var selectedRange: WeightRange = .month
    @State private var macroRange: WeightRange = .month
    @State private var macroMetric: MacroMetric = .calories
    @State private var workoutSessions: [WorkoutSession] = []
    @State private var healthWorkoutSessions: [WorkoutSession] = []
    @State private var calendarMonth = Date()
    @State private var selectedWorkoutDate: Date?
    @State private var selectedDaySessions: [WorkoutSession] = []
    @State private var showWorkoutDetail = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showPhotos = false
    @State private var selectedCheckin: WeeklyCheckin?
    @State private var pendingCheckin: WeeklyCheckin?
    @State private var pendingRecapText: String?
    @State private var lastRecapFallback: String?
    @State private var showPhysiqueGoalsOnboarding = false
    @State private var showCheckinFlow = false
    @State private var showBodyScanFlow = false
    @State private var showBodyScanHistory = false
    @State private var bodyScanHeroPulse = false
    @State private var bodyScanResults: [BodyScanResult] = BodyScanStore.load()
    @State private var startingPhotos = StartingPhotosStore.load()
    @State private var profileGoal: OnboardingForm.Goal = .maintain
    @State private var profileSex: OnboardingForm.Sex = .preferNotToSay
    @State private var profilePreferences: [String: Any] = [:]
    @State private var profileHeightCm: Double?
    @State private var profileWeightLbs: Double?
    @State private var profileAge: Int?
    @State private var profileActivityLevel: OnboardingForm.ActivityLevel = .moderatelyActive
    @State private var storedPhysiquePriority: String?
    @State private var storedSecondaryPriority: String?
    @State private var storedPhysiquePriorityGoal: String?
    @State private var showCheckinLockedSheet = false
    @AppStorage("checkinDay") private var checkinDay: Int = 0  // 0 = Sunday
    @StateObject private var healthSyncState = HealthSyncState.shared
    @State private var isHealthSyncing = false
    @State private var healthSyncMessage: String?
    
    private var checkinDayName: String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[checkinDay]
    }
    
    private var daysUntilCheckin: Int {
        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: Date()) - 1  // 0 = Sunday
        let targetDay = checkinDay
        let diff = (targetDay - today + 7) % 7
        return diff == 0 ? 0 : diff
    }
    
    private var isCheckinUnlocked: Bool {
        daysUntilCheckin == 0
    }

    private var sortedBodyScans: [BodyScanResult] {
        bodyScanResults.sorted { $0.timestamp > $1.timestamp }
    }

    private var latestBodyScan: BodyScanResult? {
        sortedBodyScans.first
    }

    private var previousBodyScan: BodyScanResult? {
        sortedBodyScans.dropFirst().first
    }

    private var hasCompletedPhysiqueGoalsIntake: Bool {
        if preferenceBool(
            profilePreferences,
            keys: ["checkinPersonalizationCompleted", "checkin_personalization_completed"]
        ) == true {
            return true
        }
        if let goal = storedPhysiquePriorityGoal?.trimmingCharacters(in: .whitespacesAndNewlines),
           !goal.isEmpty {
            return true
        }
        if preferenceString(profilePreferences, keys: ["physiquePriorityGoal", "physique_priority_goal"]) != nil {
            return true
        }
        return false
    }

    private var shouldShowPhysiqueGoalsOnboardingBeforeCheckin: Bool {
        checkins.isEmpty && !hasCompletedPhysiqueGoalsIntake
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        checkinCard
                            .tourTarget(
                                .progressCheckinCard,
                                shape: .roundedRect(cornerRadius: 24),
                                padding: 0
                            )
                            .id(GuidedTourTargetID.progressCheckinCard)
                        bodyScanCard
                            .tourTarget(
                                .progressBodyScanCard,
                                shape: .roundedRect(cornerRadius: 24),
                                padding: 0
                            )
                            .id(GuidedTourTargetID.progressBodyScanCard)
                        workoutCalendarCard
                        photosCard
                            .tourTarget(
                                .progressPhotosCard,
                                shape: .roundedRect(cornerRadius: 24),
                                padding: 0
                            )
                            .id(GuidedTourTargetID.progressPhotosCard)
                        if latestCheckin != nil {
                            resultsCard
                        }

                        if let loadError {
                            Text(loadError)
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .onAppear {
                    scrollToGuidedTourTarget(using: proxy)
                }
                .onChange(of: guidedTour.currentStep?.id) { _ in
                    scrollToGuidedTourTarget(using: proxy)
                }
            }
        }
        .sheet(isPresented: $showPhotos) {
            ProgressPhotoGalleryView(items: photoItems)
        }
        .sheet(isPresented: $showPhysiqueGoalsOnboarding) {
            PhysiqueGoalsOnboardingView(
                userId: userId,
                profileGoal: profileGoal,
                profileSex: profileSex
            ) { primary, secondary, description in
                await savePhysiqueGoals(primary: primary, secondary: secondary, description: description)
                await MainActor.run {
                    let trimmedPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalizedSecondary = secondary
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && $0 != trimmedPrimary }
                    storedPhysiquePriority = trimmedPrimary.isEmpty ? nil : trimmedPrimary
                    storedSecondaryPriority = normalizedSecondary.first
                    profilePreferences["physiquePriority"] = trimmedPrimary
                    profilePreferences["secondaryGoals"] = normalizedSecondary
                    profilePreferences["physiquePriorityGoal"] = profileGoal.rawValue
                    storedPhysiquePriorityGoal = profileGoal.rawValue
                    profilePreferences["checkinPersonalizationCompleted"] = true
                    profilePreferences["checkin_personalization_completed"] = true
                    if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !description.isEmpty {
                        profilePreferences["physiqueGoalDescription"] = description
                    } else {
                        profilePreferences.removeValue(forKey: "physiqueGoalDescription")
                    }
                }
                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showCheckinFlow = true
                    }
                }
            }
        }
        .sheet(isPresented: $showCheckinFlow) {
            CheckinFlowView(
                userId: userId,
                storedPhysiquePriority: storedPhysiquePriority,
                storedSecondaryPriority: storedSecondaryPriority
            ) { response in
                if let recapText = response.aiResult?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !recapText.isEmpty {
                    pendingRecapText = recapText
                    lastRecapFallback = recapText
                }
                if let checkin = response.checkin {
                    if let index = checkins.firstIndex(where: { $0.id == checkin.id }) {
                        checkins[index] = checkin
                    } else {
                        checkins.insert(checkin, at: 0)
                    }
                    pendingCheckin = checkin
                }
                await loadData()
            }
        }
        .sheet(isPresented: $showBodyScanFlow) {
            BodyScanFlowView(
                userId: userId,
                profileHeightCm: profileHeightCm,
                profileWeightLbs: profileWeightLbs,
                profileAge: profileAge,
                profileSex: profileSex,
                profileActivityLevel: profileActivityLevel,
                profileGoal: profileGoal,
                previousResult: latestBodyScan
            ) { result in
                var updated = bodyScanResults
                updated.insert(result, at: 0)
                updated.sort { $0.timestamp > $1.timestamp }
                if updated.count > 50 {
                    updated = Array(updated.prefix(50))
                }
                bodyScanResults = updated
                BodyScanStore.save(updated)
            }
        }
        .sheet(isPresented: $showBodyScanHistory) {
            BodyScanHistoryView(results: $bodyScanResults)
        }
        .sheet(item: $selectedCheckin, onDismiss: {
            pendingCheckin = nil
            pendingRecapText = nil
        }) { checkin in
            let override = pendingRecapText ?? lastRecapFallback
            CheckinResultsView(
                userId: userId,
                checkin: checkin,
                previousCheckin: previousCheckin(for: checkin),
                goal: profileGoal,
                physiquePriority: storedPhysiquePriority,
                secondaryPriority: storedSecondaryPriority,
                comparisonPhotoCount: comparisonPhotoCount,
                overrideSummary: override
            )
        }
        .sheet(isPresented: $showWorkoutDetail) {
            if let selectedWorkoutDate {
                WorkoutDayDetailView(
                    userId: userId,
                    date: selectedWorkoutDate,
                    sessions: selectedDaySessions
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .task {
            startingPhotos = StartingPhotosStore.load()
            bodyScanResults = BodyScanStore.load()
            localProgressPhotos = ProgressPhotoLocalStore.load(userId: userId)
            applyBodyScanProfileFallbackFromOnboarding()
            await loadData()
        }
        .onChange(of: showCheckinFlow) { isShowing in
            guard !isShowing, let pendingCheckin else { return }
            selectedCheckin = pendingCheckin
        }
        .onChange(of: intent) { newIntent in
            guard let newIntent else { return }
            switch newIntent {
            case .startCheckin:
                presentCheckinEntry()
            }
            intent = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIStartingPhotosUpdated)) { _ in
            startingPhotos = StartingPhotosStore.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIProgressPhotosUpdated)) { _ in
            localProgressPhotos = ProgressPhotoLocalStore.load(userId: userId)
        }
        .onChange(of: showWorkoutDetail) { isShowing in
            if !isShowing {
                selectedWorkoutDate = nil
                selectedDaySessions = []
            }
        }
    }

    private func scrollToGuidedTourTarget(using proxy: ScrollViewProxy) {
        guard let step = guidedTour.currentStep else { return }
        guard step.screen == .progress else { return }
        guard let target = step.target else { return }

        let anchor: UnitPoint
        switch target {
        case .progressCheckinCard:
            anchor = .top
        case .progressBodyScanCard, .progressPhotosCard:
            anchor = .center
        default:
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(target, anchor: anchor)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Progress")
                    .font(FitFont.heading(size: 30))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                Text("Track your trends and weekly check-ins.")
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textSecondary)

                if healthSyncState.isEnabled {
                    Text(healthHeaderText)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }

            Spacer()

            VStack(spacing: 10) {
                CoachCharacterView(size: 72, showBackground: false, pose: .idle)
                    .allowsHitTesting(false)

                Button(action: {
                    guidedTour.startScreenTour(.progress)
                }) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(10)
                        .background(FitTheme.cardBackground)
                        .clipShape(Circle())
                }
            }
        }
    }

    private var weightTrendCard: some View {
        CardContainer(isAccented: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weight trend")
                            .font(FitFont.body(size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Latest: \(latestWeightText)  •  Δ \(weightDeltaText)")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    Spacer()

                    Picker("Range", selection: $selectedRange) {
                        ForEach(WeightRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(FitTheme.cardHighlight)
                    .frame(width: 200)
                }

                if isLoading {
                    SwiftUI.ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if filteredWeightPoints.isEmpty {
                    Text("No weight check-ins yet.")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                } else {
                    Chart(filteredWeightPoints) { point in
                        // Area fill with gradient (matches onboarding style)
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.weight)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    FitTheme.cardProgressAccent.opacity(0.25),
                                    FitTheme.cardProgressAccent.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        
                        // Line on top
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.weight)
                        )
                        .foregroundStyle(FitTheme.cardProgressAccent)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.catmullRom)

                        // Point markers
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.weight)
                        )
                        .foregroundStyle(Color.white)
                        .annotation(position: .overlay) {
                            Circle()
                                .stroke(FitTheme.cardProgressAccent, lineWidth: 3)
                                .frame(width: 10, height: 10)
                                .background(Circle().fill(Color.white))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                                .foregroundStyle(FitTheme.cardStroke.opacity(0.6))
                            AxisTick()
                                .foregroundStyle(FitTheme.cardStroke.opacity(0.6))
                            AxisValueLabel()
                                .font(FitFont.body(size: 10))
                                .foregroundStyle(FitTheme.textSecondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                                .foregroundStyle(FitTheme.cardStroke.opacity(0.6))
                            AxisTick()
                                .foregroundStyle(FitTheme.cardStroke.opacity(0.6))
                            AxisValueLabel()
                                .font(FitFont.body(size: 10))
                                .foregroundStyle(FitTheme.textSecondary)
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    private var bodyScanCard: some View {
        let latest = latestBodyScan
        let previous = previousBodyScan
        let progress = latest.map { bodyScanConfidenceProgress(for: $0.confidence) } ?? 0.38
        let confidenceColor = latest.map { BodyScanPalette.confidenceColor(for: $0.confidence) } ?? BodyScanPalette.cyan

        return CardContainer(isAccented: true) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(BodyScanPalette.heroGradient)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.35), Color.clear],
                                center: .topTrailing,
                                startRadius: 0,
                                endRadius: 220
                            )
                        )

                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 10)
                                .frame(width: 92, height: 92)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white, confidenceColor],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 92, height: 92)
                                .shadow(color: confidenceColor.opacity(0.35), radius: 8, x: 0, y: 4)
                            Image(systemName: "figure.stand")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .scaleEffect(bodyScanHeroPulse ? 1.03 : 0.95)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Body Scan")
                                .font(FitFont.heading(size: 22))
                                .foregroundColor(.white)
                            Text(latest == nil ? "Immersive 60-second baseline capture." : "Latest scan intelligence")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(Color.white.opacity(0.82))

                            if let latest {
                                Text(latest.bodyFatRangeText)
                                    .font(FitFont.heading(size: 24))
                                    .foregroundColor(.white)
                                    .padding(.top, 2)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .frame(height: 164)

                if let latest {
                    HStack(spacing: 10) {
                        bodyScanMetaPill(
                            icon: "scope",
                            title: "Confidence",
                            value: latest.confidence.title
                        )
                        bodyScanMetaPill(
                            icon: "flame.fill",
                            title: "Maintain",
                            value: latest.tdeeRangeText
                        )
                    }

                    if let trendText = bodyScanTrendText(latest: latest, previous: previous) {
                        Text(trendText)
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                            .padding(.top, 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Capture tips")
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Consistent lighting")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                        Text("Full body in frame")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                        Text("Same pose every scan")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    .padding(12)
                    .background(FitTheme.cardHighlight.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                HStack(spacing: 10) {
                    if latest != nil {
                        Button {
                            showBodyScanHistory = true
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("History")
                                    .font(FitFont.body(size: 13, weight: .semibold))
                            }
                            .foregroundColor(FitTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FitTheme.cardHighlight)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    Button {
                        showBodyScanFlow = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(latest == nil ? "Start scan" : "New scan")
                                .font(FitFont.body(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BodyScanPalette.actionGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: BodyScanPalette.cyan.opacity(0.35), radius: 12, x: 0, y: 6)
                    }
                }
            }
        }
        .onAppear {
            guard !bodyScanHeroPulse else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                bodyScanHeroPulse = true
            }
        }
    }

    private func bodyScanMetaPill(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BodyScanPalette.cyan)
                .frame(width: 24, height: 24)
                .background(BodyScanPalette.cyan.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FitFont.body(size: 11))
                    .foregroundColor(FitTheme.textSecondary)
                Text(value)
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(FitTheme.cardHighlight.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func bodyScanConfidenceProgress(for confidence: BodyScanConfidence) -> CGFloat {
        switch confidence {
        case .high:
            return 0.9
        case .medium:
            return 0.72
        case .low:
            return 0.55
        }
    }

    private var workoutCalendarCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workout calendar")
                            .font(FitFont.body(size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Tap a day to review your sessions.")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button(action: { shiftCalendarMonth(by: -1) }) {
                            Image(systemName: "chevron.left")
                                .font(FitFont.body(size: 12, weight: .semibold))
                                .foregroundColor(FitTheme.textPrimary)
                                .padding(6)
                                .background(FitTheme.cardHighlight)
                                .clipShape(Circle())
                        }
                        Text(calendarMonthLabel)
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textPrimary)
                        Button(action: { shiftCalendarMonth(by: 1) }) {
                            Image(systemName: "chevron.right")
                                .font(FitFont.body(size: 12, weight: .semibold))
                                .foregroundColor(FitTheme.textPrimary)
                                .padding(6)
                                .background(FitTheme.cardHighlight)
                                .clipShape(Circle())
                        }
                    }
                }

                healthSyncRow

                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { symbol in
                        Text(symbol.uppercased())
                            .font(FitFont.body(size: 10))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    ForEach(calendarGridDates.indices, id: \.self) { index in
                        let date = calendarGridDates[index]
                        WorkoutCalendarDayCell(
                            date: date,
                            summary: date.flatMap { workoutSummaryByDay[$0] },
                            onSelect: { selectedDate in
                                selectWorkoutDay(selectedDate)
                            }
                        )
                    }
                }
            }
        }
    }

    private var healthSyncRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(FitTheme.cardWorkoutAccent)
                    .clipShape(Circle())

                Text("Apple Health")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)

                Spacer()

                Button(action: {
                    Task { await syncHealthWorkoutsWithStatus() }
                }) {
                    Text(isHealthSyncing ? "Syncing…" : "Sync now")
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(healthSyncState.isEnabled ? FitTheme.buttonText : FitTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            healthSyncState.isEnabled
                                ? FitTheme.primaryGradient
                                : LinearGradient(
                                    colors: [FitTheme.cardHighlight, FitTheme.cardHighlight],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                        .clipShape(Capsule())
                }
                .disabled(isHealthSyncing || !healthSyncState.isEnabled)
            }

            Text(healthSyncStatusText)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)

            if let healthSyncMessage {
                Text(healthSyncMessage)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .padding(12)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var healthSyncStatusText: String {
        if !healthSyncState.isEnabled {
            return "Sync is off. Enable Apple Health in Settings to import workouts."
        }
        if let lastSync = healthSyncState.lastSyncDate {
            return "Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Not synced yet. Tap Sync now to import workouts."
    }

    private var healthHeaderText: String {
        if healthWorkoutSessions.isEmpty {
            return "Apple Health: no workouts synced yet."
        }
        let count = healthWorkoutSessions.count
        return "Apple Health: \(count) workout\(count == 1 ? "" : "s") synced."
    }

    private var macroAdherenceCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Macro adherence")
                            .font(FitFont.body(size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.textPrimary)
                        Text(macroTargetText)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    Spacer()

                    Picker("Range", selection: $macroRange) {
                        ForEach(WeightRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(FitTheme.cardHighlight)
                    .frame(width: 200)
                }

                Picker("Metric", selection: $macroMetric) {
                    ForEach(MacroMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .tint(FitTheme.cardHighlight)

                if isLoading {
                    SwiftUI.ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if filteredMacroAdherencePoints.isEmpty {
                    Text("No nutrition logs yet.")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                } else {
                    Chart(filteredMacroAdherencePoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Logged", point.loggedValue)
                        )
                        .foregroundStyle(FitTheme.accent)

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Target", point.targetValue)
                        )
                        .foregroundStyle(FitTheme.textSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                                .foregroundStyle(FitTheme.cardStroke.opacity(0.6))
                            AxisTick()
                                .foregroundStyle(FitTheme.cardStroke.opacity(0.6))
                            AxisValueLabel()
                                .font(FitFont.body(size: 10))
                                .foregroundStyle(FitTheme.textSecondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                                .foregroundStyle(FitTheme.cardStroke.opacity(0.6))
                            AxisTick()
                                .foregroundStyle(FitTheme.cardStroke.opacity(0.6))
                            AxisValueLabel()
                                .font(FitFont.body(size: 10))
                                .foregroundStyle(FitTheme.textSecondary)
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    private var checkinCard: some View {
        let accentColor = isCheckinUnlocked ? FitTheme.cardProgressAccent : Color(red: 0.55, green: 0.55, blue: 0.60)
        
        return VStack(alignment: .leading, spacing: 16) {
            // Header with icon
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: isCheckinUnlocked ? "chart.line.uptrend.xyaxis" : "lock.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Weekly Check-in")
                            .font(FitFont.heading(size: 18))
                            .foregroundColor(isCheckinUnlocked ? FitTheme.textPrimary : FitTheme.textSecondary)
                        
                        if !isCheckinUnlocked {
                            Text("LOCKED")
                                .font(FitFont.body(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    
                    if isCheckinUnlocked {
                        Text("Log weight, photos, and adherence")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    } else {
                        Text("Available on \(checkinDayName)")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                
                Spacer()
                
                if !isCheckinUnlocked {
                    Image(systemName: "lock.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(accentColor.opacity(0.6))
                }
            }
            
            // Stats row
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14))
                        .foregroundColor(accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last check-in")
                            .font(FitFont.body(size: 11))
                            .foregroundColor(FitTheme.textSecondary)
                        Text(latestCheckinDateText)
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(isCheckinUnlocked ? FitTheme.textPrimary : FitTheme.textSecondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                HStack(spacing: 8) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 14))
                        .foregroundColor(accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weight")
                            .font(FitFont.body(size: 11))
                            .foregroundColor(FitTheme.textSecondary)
                        Text(latestWeightText)
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(isCheckinUnlocked ? FitTheme.textPrimary : FitTheme.textSecondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Progress indicator when locked
            if !isCheckinUnlocked && daysUntilCheckin > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day < (7 - daysUntilCheckin) ? accentColor : accentColor.opacity(0.2))
                            .frame(height: 4)
                    }
                }
            }
            
            // Start button
            Button {
                presentCheckinEntry()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCheckinUnlocked ? "plus.circle.fill" : "lock.fill")
                        .font(.system(size: 16))
                    Text(isCheckinUnlocked ? "Start Check-in" : "Locked • \(daysUntilCheckin) day\(daysUntilCheckin == 1 ? "" : "s") until \(checkinDayName)")
                        .font(FitFont.body(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [accentColor, accentColor.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: accentColor.opacity(isCheckinUnlocked ? 0.3 : 0.15), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            
            // Hint text when locked
            if !isCheckinUnlocked {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(FitTheme.textSecondary.opacity(0.6))
                    Text("Tap to change your check-in day")
                        .font(FitFont.body(size: 11))
                        .foregroundColor(FitTheme.textSecondary.opacity(0.6))
                }
            }
        }
        .padding(18)
        .background(isCheckinUnlocked ? FitTheme.cardProgress : FitTheme.cardProgress.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .opacity(isCheckinUnlocked ? 1.0 : 0.9)
        .sheet(isPresented: $showCheckinLockedSheet) {
            ProgressCheckinLockedSheet(checkinDayName: checkinDayName, daysUntilCheckin: daysUntilCheckin)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardProgressAccent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: FitTheme.cardProgressAccent.opacity(0.1), radius: 12, x: 0, y: 6)
    }

    private var photosCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with icon
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [FitTheme.cardNutritionAccent, FitTheme.cardNutritionAccent.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: FitTheme.cardNutritionAccent.opacity(0.3), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Progress Photos")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("Store your weekly shots")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                Spacer()
                
                Button {
                    showPhotos = true
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(FitTheme.cardNutritionAccent)
                }
                .buttonStyle(.plain)
            }
            
            // Photo count with icon
            HStack(spacing: 10) {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 14))
                    .foregroundColor(FitTheme.cardNutritionAccent)
                Text("\(photoItems.count) photos logged")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textPrimary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FitTheme.cardNutritionAccent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(18)
        .background(FitTheme.cardNutrition)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardNutritionAccent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: FitTheme.cardNutritionAccent.opacity(0.1), radius: 12, x: 0, y: 6)
        .onTapGesture {
            showPhotos = true
        }
    }

    private func presentCheckinEntry() {
        guard isCheckinUnlocked else {
            showCheckinLockedSheet = true
            return
        }
        if shouldShowPhysiqueGoalsOnboardingBeforeCheckin {
            showPhysiqueGoalsOnboarding = true
        } else {
            showCheckinFlow = true
        }
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with coach icon
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [FitTheme.cardCoachAccent, FitTheme.cardCoachAccent.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: FitTheme.cardCoachAccent.opacity(0.3), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach Recap")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("Latest check-in feedback")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                Spacer()
                
                if latestCheckin != nil {
                    Button {
                        if let latest = latestCheckin {
                            selectedCheckin = latest
                        }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(FitTheme.cardCoachAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            let highlights = latestRecapHighlights
            if !highlights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(highlights.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: recapIcon(for: index))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(FitTheme.cardCoachAccent)
                                .frame(width: 20)
                            Text(highlights[index])
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textPrimary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FitTheme.cardCoachAccent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            } else {
                Text(latestCheckinSummary ?? latestFallbackSummary ?? "Your latest check-in is logged.")
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)
                    .lineLimit(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FitTheme.cardHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let context = latestRecapPhotoContext {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12))
                        .foregroundColor(FitTheme.cardCoachAccent)
                    Text(context)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }

            if let latest = latestCheckin {
                MacroUpdateActionRow(userId: userId, checkin: latest, isCompact: true)
            }
        }
        .padding(18)
        .background(FitTheme.cardCoach)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardCoachAccent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: FitTheme.cardCoachAccent.opacity(0.1), radius: 12, x: 0, y: 6)
    }
    
    private func recapIcon(for index: Int) -> String {
        switch index {
        case 0: return "arrow.up.circle.fill"
        case 1: return "target"
        case 2: return "lightbulb.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private var latestCheckin: WeeklyCheckin? {
        sortedCheckins.first
    }

    private var latestCheckinSummary: String? {
        guard let summary = latestCheckin?.aiSummary?.raw?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !summary.isEmpty
        else {
            return lastRecapFallback
        }
        // Don't return raw JSON - it shows as gibberish to users
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        // Check for direct JSON
        if trimmed.first == "{" || trimmed.first == "[" {
            return lastRecapFallback
        }
        // Check for JSON in markdown code blocks
        if trimmed.hasPrefix("```") {
            return lastRecapFallback
        }
        // Check for JSON-like content patterns
        if trimmed.contains("\"improvements\":") ||
           trimmed.contains("\"improvements\"") ||
           trimmed.contains("\"needs work\":") ||
           trimmed.contains("\"needs_work\":") ||
           trimmed.contains("\"photo notes\":") ||
           trimmed.contains("\"photo_notes\":") ||
           trimmed.contains("\"targets\":") ||
           trimmed.contains("\"summary\":") {
            return lastRecapFallback
        }
        return summary
    }

    private var latestRecap: CheckinRecap {
        CheckinRecap(
            raw: latestCheckinSummary,
            parsed: latestCheckin?.aiSummary?.parsed,
            meta: latestCheckin?.aiSummary?.meta
        )
    }

    private var recapFocusAreas: [String] {
        var areas: [String] = []
        if let primary = storedPhysiquePriority?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            areas.append(primary)
        }
        if let secondary = storedSecondaryPriority?.trimmingCharacters(in: .whitespacesAndNewlines),
           !secondary.isEmpty,
           secondary != areas.first {
            areas.append(secondary)
        }
        return areas
    }

    private var latestRecapHighlights: [String] {
        guard let latestCheckin else { return [] }
        let fallback = CheckinRecapFallback(
            goal: profileGoal,
            checkin: latestCheckin,
            previousCheckin: previousCheckin(for: latestCheckin),
            comparisonPhotoCount: comparisonPhotoCount,
            comparisonSource: latestCheckin.aiSummary?.meta?.comparisonSource,
            focusAreas: recapFocusAreas
        )
        let highlights = latestRecap.highlights
        
        // Extra safety: filter out any JSON-looking content that slipped through
        let safeHighlights = highlights.filter { item in
            !item.contains("\"improvements\"") &&
            !item.contains("\"needs work\"") &&
            !item.contains("\"targets\"") &&
            !item.contains("\"summary\"") &&
            !item.contains("```json") &&
            !item.contains("```") &&
            !(item.trimmingCharacters(in: .whitespacesAndNewlines).first == "{") &&
            !(item.trimmingCharacters(in: .whitespacesAndNewlines).first == "[")
        }
        
        return safeHighlights.isEmpty ? fallback.highlights : safeHighlights
    }

    private var latestRecapPhotoContext: String? {
        guard latestCheckin != nil else { return nil }
        return photoContextText(
            for: latestCheckin?.aiSummary?.meta?.comparisonSource,
            comparisonPhotoCount: comparisonPhotoCount
        )
    }

    private var latestFallbackSummary: String? {
        guard let latestCheckin else { return nil }
        return CheckinRecapFallback(
            goal: profileGoal,
            checkin: latestCheckin,
            previousCheckin: previousCheckin(for: latestCheckin),
            comparisonPhotoCount: comparisonPhotoCount,
            comparisonSource: latestCheckin.aiSummary?.meta?.comparisonSource,
            focusAreas: recapFocusAreas
        ).summary
    }

    private var sortedCheckins: [WeeklyCheckin] {
        checkins.sorted { (lhs, rhs) in
            (lhs.dateValue ?? .distantPast) > (rhs.dateValue ?? .distantPast)
        }
    }

    private var weightPoints: [WeightPoint] {
        checkins.compactMap { checkin in
            guard let date = checkin.dateValue, let weight = checkin.weight else {
                return nil
            }
            return WeightPoint(date: date, weight: weight)
        }
        .sorted { $0.date < $1.date }
    }

    private var filteredWeightPoints: [WeightPoint] {
        guard let endDate = weightPoints.last?.date else {
            return []
        }
        let startDate = Calendar.current.date(byAdding: .day, value: -selectedRange.days + 1, to: endDate) ?? endDate
        return weightPoints.filter { $0.date >= startDate }
    }

    private var macroAdherencePoints: [MacroAdherencePoint] {
        macroAdherence.compactMap { day in
            guard let date = day.dateValue else { return nil }
            let loggedValue = macroMetric.value(from: day.logged)
            let targetValue = macroMetric.value(from: day.target)
            if loggedValue == 0 && targetValue == 0 {
                return nil
            }
            return MacroAdherencePoint(
                date: date,
                loggedValue: loggedValue,
                targetValue: targetValue
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var filteredMacroAdherencePoints: [MacroAdherencePoint] {
        guard let endDate = macroAdherencePoints.last?.date else {
            return []
        }
        let startDate = Calendar.current.date(byAdding: .day, value: -macroRange.days + 1, to: endDate) ?? endDate
        return macroAdherencePoints.filter { $0.date >= startDate }
    }

    private var macroTargetText: String {
        guard let target = macroAdherence.map({ macroMetric.value(from: $0.target) }).first(where: { $0 > 0 }) else {
            return "Target: —"
        }
        let value = macroMetric == .calories ? Int(target) : Int(target.rounded())
        return "Target: \(value) \(macroMetric.unit)"
    }

    private var photoItems: [ProgressPhotoItem] {
        let localRemoteURLs = Set(localProgressPhotos.compactMap(\.remoteURL))
        let checkinPhotoDatesByURL: [String: Date] = checkins.reduce(into: [:]) { partial, checkin in
            let fallbackDate = checkin.dateValue
            for photo in checkin.photos ?? [] {
                let parsedDate = photo.date.flatMap(parseProgressPhotoDate) ?? fallbackDate
                guard let date = parsedDate else { continue }
                let existing = partial[photo.url] ?? .distantPast
                if date > existing {
                    partial[photo.url] = date
                }
            }
        }

        let localItems: [ProgressPhotoItem] = localProgressPhotos.compactMap { local in
            guard let url = ProgressPhotoLocalStore.fileURL(userId: userId, filename: local.localFilename) else {
                return nil
            }
            return ProgressPhotoItem(
                id: "local-\(local.id.uuidString)",
                imageURL: url,
                date: local.date,
                type: local.type,
                category: local.category,
                isLocal: true
            )
        }

        let progressItems: [ProgressPhotoItem] = progressPhotos.compactMap { photo in
            if localRemoteURLs.contains(photo.url) {
                return nil
            }

            let parsedDate = photo.date.flatMap(parseProgressPhotoDate)

            let date = parsedDate
                ?? checkinPhotoDatesByURL[photo.url]
                ?? ProgressPhotoLocalStore.date(forRemoteURL: photo.url, userId: userId)

            guard let url = URL(string: photo.url) else { return nil }
            return ProgressPhotoItem(
                id: "remote-\(photo.id)",
                imageURL: url,
                date: date,
                type: photo.type,
                category: photo.category,
                isLocal: false
            )
        }
        let checkinItems: [ProgressPhotoItem]
        if progressPhotos.isEmpty {
            checkinItems = checkins.flatMap { checkin in
                return (checkin.photos ?? []).compactMap { photo -> ProgressPhotoItem? in
                    let parsedDate = photo.date.flatMap(parseProgressPhotoDate)
                    let date = parsedDate ?? checkin.dateValue
                    guard let url = URL(string: photo.url) else { return nil }
                    return ProgressPhotoItem(
                        id: "checkin-\(photo.url)",
                        imageURL: url,
                        date: date,
                        type: photo.type,
                        category: "checkin",
                        isLocal: false
                    )
                }
            }
        } else {
            checkinItems = []
        }
        let startingItems: [ProgressPhotoItem] = startingPhotos.entries.compactMap { entry in
            guard let url = URL(string: entry.photo.url) else { return nil }
            return ProgressPhotoItem(
                id: "starting-\(entry.id)",
                imageURL: url,
                date: entry.photo.date,
                type: entry.type.title,
                category: "starting",
                isLocal: false
            )
        }
        return (startingItems + checkinItems + progressItems + localItems).sorted { lhs, rhs in
            (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
        }
    }

    private var latestWeightText: String {
        guard let weight = weightPoints.last?.weight else {
            return "—"
        }
        return formatWeight(weight)
    }

    private var latestCheckinDateText: String {
        guard let date = latestCheckin?.dateValue else {
            return "—"
        }
        return progressDisplayDateFormatter.string(from: date)
    }

    private var weightDeltaText: String {
        guard weightPoints.count >= 2 else {
            return "—"
        }
        let latest = weightPoints[weightPoints.count - 1].weight
        let previous = weightPoints[weightPoints.count - 2].weight
        let delta = latest - previous
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", delta)) lb"
    }

    private var calendarMonthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: calendarMonth)
    }

    private var calendarGridDates: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: calendarMonth),
              let range = calendar.range(of: .day, in: .month, for: calendarMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let weekdayOffset = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: weekdayOffset)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: interval.start) {
                days.append(calendar.startOfDay(for: date))
            }
        }
        return days
    }

    private var workoutSummaryByDay: [Date: WorkoutDaySummary] {
        let calendar = Calendar.current
        var summary: [Date: WorkoutDaySummary] = [:]
        // Only show completed workouts on the calendar
        for session in combinedWorkoutSessions where session.status == "completed" {
            guard let sessionDate = sessionDate(from: session.createdAt) else { continue }
            let dayKey = calendar.startOfDay(for: sessionDate)
            var sessions = summary[dayKey]?.sessions ?? []
            sessions.append(session)
            let totalMinutes = sessions.reduce(0) { partial, session in
                partial + Int((session.durationSeconds ?? 0) / 60)
            }
            summary[dayKey] = WorkoutDaySummary(sessions: sessions, totalMinutes: totalMinutes)
        }
        return summary
    }

    private var combinedWorkoutSessions: [WorkoutSession] {
        workoutSessions + healthWorkoutSessions
    }

    private func photoContextText(for source: String?, comparisonPhotoCount: Int) -> String? {
        checkinComparisonText(source: source, comparisonPhotoCount: comparisonPhotoCount)
    }

    private func preferenceString(_ preferences: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = preferences[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func preferenceBool(_ preferences: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = preferences[key] as? Bool {
                return value
            }
            if let value = preferences[key] as? NSNumber {
                return value.boolValue
            }
            if let value = preferences[key] as? String {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                switch normalized {
                case "true", "1", "yes":
                    return true
                case "false", "0", "no":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }

    private func preferenceStringArray(_ preferences: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let values = preferences[key] as? [String] {
                let cleaned = values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !cleaned.isEmpty {
                    return cleaned
                }
                continue
            }

            if let values = preferences[key] as? [Any] {
                let cleaned = values.compactMap { value -> String? in
                    guard let stringValue = value as? String else { return nil }
                    let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return []
    }

    private func formatWeight(_ value: Double) -> String {
        String(format: "%.1f lb", value)
    }

    private func bodyScanTrendText(latest: BodyScanResult, previous: BodyScanResult?) -> String? {
        guard let previous else { return nil }
        let latestMid = (latest.bodyFatLow + latest.bodyFatHigh) / 2
        let previousMid = (previous.bodyFatLow + previous.bodyFatHigh) / 2
        let diff = latestMid - previousMid
        guard abs(diff) >= 0.1 else { return "Since last scan: body fat steady" }
        let direction = diff > 0 ? "up" : "down"
        return String(format: "Since last scan: body fat %@ %.1f%%", direction, abs(diff))
    }

    private func selectWorkoutDay(_ date: Date) {
        let dayKey = Calendar.current.startOfDay(for: date)
        if let summary = workoutSummaryByDay[dayKey] {
            selectedWorkoutDate = dayKey
            selectedDaySessions = summary.sessions.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            showWorkoutDetail = true
        }
    }

    private func shiftCalendarMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: calendarMonth) {
            calendarMonth = newDate
        }
    }

    private func sessionDate(from value: String?) -> Date? {
        guard let value else { return nil }
        return workoutSessionDateFormatterWithFractional.date(from: value)
            ?? workoutSessionDateFormatter.date(from: value)
    }

    private func loadData() async {
        isLoading = true
        loadError = nil
        do {
            async let checkinsTask = ProgressAPIService.shared.fetchCheckins(userId: userId)
            async let photosTask = ProgressAPIService.shared.fetchProgressPhotos(userId: userId)
            async let profileTask = ProfileAPIService.shared.fetchProfile(userId: userId)
            async let sessionsTask = WorkoutAPIService.shared.fetchSessions(userId: userId)
            let (checkins, photos) = try await (checkinsTask, photosTask)
            self.checkins = checkins
            self.progressPhotos = photos
            workoutSessions = (try? await sessionsTask) ?? []
            _ = await syncHealthWorkouts()
            let profile = try? await profileTask
            if let profile {
                let preferences = profile["preferences"] as? [String: Any] ?? [:]
                profilePreferences = preferences
                let legacyPhysiqueFocus = preferenceStringArray(
                    preferences,
                    keys: ["physique_focus", "physiqueFocus"]
                )
                let primaryPriority = preferenceString(
                    preferences,
                    keys: ["physiquePriority", "physique_priority"]
                ) ?? legacyPhysiqueFocus.first
                storedPhysiquePriority = primaryPriority

                let secondaryFromPriority = preferenceString(
                    preferences,
                    keys: ["secondaryPriority", "secondary_priority"]
                )
                let secondaryFromGoals = preferenceStringArray(
                    preferences,
                    keys: ["secondaryGoals", "secondary_goals"]
                ).first
                let secondaryFromLegacy = legacyPhysiqueFocus.dropFirst().first
                let secondaryCandidate = secondaryFromPriority ?? secondaryFromGoals ?? secondaryFromLegacy
                if let secondaryCandidate, secondaryCandidate != primaryPriority {
                    storedSecondaryPriority = secondaryCandidate
                } else {
                    storedSecondaryPriority = nil
                }
                storedPhysiquePriorityGoal = preferenceString(
                    preferences,
                    keys: ["physiquePriorityGoal", "physique_priority_goal"]
                )

                if let starting = preferences["starting_photos"],
                   let parsed = StartingPhotosState.fromDictionary(starting) {
                    StartingPhotosStore.save(parsed)
                    startingPhotos = parsed
                }

                if let goalRaw = profile["goal"] as? String,
                   let goal = OnboardingForm.Goal(rawValue: goalRaw) {
                    profileGoal = goal
                }

                if let sexRaw = (profile["sex"] as? String)
                    ?? (preferences["sex"] as? String)
                    ?? (preferences["gender"] as? String),
                   let sex = parseProfileSex(sexRaw) {
                    profileSex = sex
                }

                if let activityRaw = (preferences["activity_level"] as? String)
                    ?? (profile["activity_level"] as? String),
                   let parsed = parseActivityLevel(activityRaw) {
                    profileActivityLevel = parsed
                }

                if let height = doubleValue(from: profile["height_cm"]), height > 0 {
                    profileHeightCm = height
                }

                if let weightLbs = doubleValue(from: profile["weight_lbs"]), weightLbs > 0 {
                    profileWeightLbs = weightLbs
                } else if let weightKg = doubleValue(from: profile["weight_kg"]), weightKg > 0 {
                    profileWeightLbs = weightKg * 2.20462
                }

                if let age = intValue(from: profile["age"]), age > 0 {
                    profileAge = age
                } else if let birthdayTimestamp = doubleValue(from: preferences["birthday_timestamp"]) {
                    let birthday = Date(timeIntervalSince1970: birthdayTimestamp)
                    let years = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year
                    if let years, years > 0 {
                        profileAge = years
                    }
                }
            }
            if latestCheckinSummary == nil {
                if let fallback = try? await ProgressAPIService.shared.fetchLatestCheckinSummary(userId: userId) {
                    lastRecapFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func applyBodyScanProfileFallbackFromOnboarding() {
        guard profileHeightCm == nil || profileWeightLbs == nil || profileAge == nil || profilePreferences.isEmpty else {
            return
        }
        guard let data = UserDefaults.standard.data(forKey: "fitai.onboarding.form"),
              let form = try? JSONDecoder().decode(OnboardingForm.self, from: data)
        else {
            return
        }

        if profilePreferences.isEmpty {
            profileGoal = form.goal
            profileSex = form.sex
            profileActivityLevel = form.activityLevel
        }

        if profileAge == nil {
            if let age = Int(form.age), age > 0 {
                profileAge = age
            } else if let birthday = form.birthday {
                let years = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year
                if let years, years > 0 {
                    profileAge = years
                }
            }
        }

        if profileHeightCm == nil {
            if form.heightUnit.lowercased() == "cm", let cm = Double(form.heightFeet), cm > 0 {
                profileHeightCm = cm
            } else if let feet = Double(form.heightFeet),
                      let inches = Double(form.heightInches) {
                let cm = (feet * 30.48) + (inches * 2.54)
                if cm > 0 {
                    profileHeightCm = cm
                }
            }
        }

        if profileWeightLbs == nil {
            let sanitized = form.weightLbs.filter { "0123456789.".contains($0) }
            if let lbs = Double(sanitized), lbs > 0 {
                profileWeightLbs = lbs
            }
        }
    }

    private func doubleValue(from any: Any?) -> Double? {
        switch any {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private func intValue(from any: Any?) -> Int? {
        switch any {
        case let value as Int:
            return value
        case let value as Double:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }
    
    private func savePhysiqueGoals(primary: String, secondary: [String], description: String?) async {
        do {
            var updatedPreferences = profilePreferences
            if updatedPreferences.isEmpty {
                let profile = try await ProfileAPIService.shared.fetchProfile(userId: userId)
                if let preferences = profile["preferences"] as? [String: Any] {
                    updatedPreferences = preferences
                }
            }
            
            // Save primary goal
            updatedPreferences["physiquePriority"] = primary
            
            // Save secondary goals as array
            if !secondary.isEmpty {
                updatedPreferences["secondaryGoals"] = secondary
            }
            
            // Save custom description if provided
            if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                updatedPreferences["physiqueGoalDescription"] = description
            }
            
            // Save the goal context
            updatedPreferences["physiquePriorityGoal"] = profileGoal.rawValue
            updatedPreferences["checkinPersonalizationCompleted"] = true
            updatedPreferences["checkin_personalization_completed"] = true
            
            let payload: [String: Any] = ["preferences": updatedPreferences]
            _ = try await ProfileAPIService.shared.updateProfile(userId: userId, payload: payload)
        } catch {
            print("Error saving physique goals: \(error.localizedDescription)")
        }
    }

    private func parseProfileSex(_ raw: String) -> OnboardingForm.Sex? {
        if let direct = OnboardingForm.Sex(rawValue: raw) {
            return direct
        }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        switch normalized {
        case "male": return .male
        case "female": return .female
        case "other": return .other
        case "prefernotosay", "prefernot": return .preferNotToSay
        default: return nil
        }
    }

    private func parseActivityLevel(_ raw: String) -> OnboardingForm.ActivityLevel? {
        if let direct = OnboardingForm.ActivityLevel(rawValue: raw) {
            return direct
        }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        switch normalized {
        case "sedentary": return .sedentary
        case "lightlyactive", "light": return .lightlyActive
        case "moderatelyactive", "moderate": return .moderatelyActive
        case "veryactive": return .veryActive
        case "extremelyactive": return .extremelyActive
        default: return nil
        }
    }

    private func syncHealthWorkouts() async -> [HealthWorkout] {
        guard HealthSyncState.shared.isEnabled else {
            await MainActor.run {
                healthWorkoutSessions = []
            }
            return []
        }

        let newWorkouts = await HealthKitManager.shared.syncWorkoutsIfEnabled()
        let healthWorkouts = HealthWorkoutStore.allWorkouts()
        let sessions = healthWorkouts.map { workoutSession(from: $0) }
        await MainActor.run {
            healthWorkoutSessions = sessions
        }
        return newWorkouts
    }

    private func syncHealthWorkoutsWithStatus() async {
        guard healthSyncState.isEnabled else {
            healthSyncMessage = "Enable Apple Health in Settings to sync workouts."
            return
        }
        isHealthSyncing = true
        healthSyncMessage = nil
        let newWorkouts = await syncHealthWorkouts()
        isHealthSyncing = false
        if newWorkouts.isEmpty {
            healthSyncMessage = "No new workouts found."
        } else if newWorkouts.count == 1 {
            healthSyncMessage = "Imported 1 workout from Apple Health."
        } else {
            healthSyncMessage = "Imported \(newWorkouts.count) workouts from Apple Health."
        }
    }

    private func workoutSession(from workout: HealthWorkout) -> WorkoutSession {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return WorkoutSession(
            id: "health-\(workout.id)",
            templateId: nil,
            templateTitle: "Apple Health • \(workout.activityType)",
            status: "completed",
            durationSeconds: workout.durationSeconds,
            createdAt: formatter.string(from: workout.startDate)
        )
    }

    private var comparisonPhotoCount: Int {
        progressPhotos.count + startingPhotos.entries.count
    }

    private func previousCheckin(for checkin: WeeklyCheckin) -> WeeklyCheckin? {
        let sorted = sortedCheckins
        guard let index = sorted.firstIndex(where: { $0.id == checkin.id }) else {
            return nil
        }
        let nextIndex = index + 1
        guard sorted.indices.contains(nextIndex) else { return nil }
        return sorted[nextIndex]
    }

}

private struct WorkoutCalendarDayCell: View {
    let date: Date?
    let summary: ProgressTabView.WorkoutDaySummary?
    let onSelect: (Date) -> Void

    var body: some View {
        if let date {
            let day = Calendar.current.component(.day, from: date)
            let hasHealthWorkout = summary?.sessions.contains { $0.isHealthWorkout } == true
            Button(action: { onSelect(date) }) {
                VStack(spacing: 4) {
                    Text("\(day)")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textPrimary)

                    if let summary {
                        if summary.totalMinutes > 0 {
                            Text("\(summary.totalMinutes)m")
                                .font(FitFont.body(size: 10))
                                .foregroundColor(FitTheme.success)
                        } else {
                            Image(systemName: "checkmark")
                                .font(FitFont.body(size: 10, weight: .semibold))
                                .foregroundColor(FitTheme.success)
                        }
                    } else {
                        Text("")
                            .font(FitFont.body(size: 10))
                            .foregroundColor(.clear)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.vertical, 4)
                .background(summary == nil ? FitTheme.cardBackground : FitTheme.success.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .overlay(alignment: .topTrailing) {
                if hasHealthWorkout {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
            .buttonStyle(.plain)
            .disabled(summary == nil)
        } else {
            Color.clear
                .frame(minHeight: 36)
        }
    }
}

private struct WorkoutDayDetailView: View {
    let userId: String
    let date: Date
    let sessions: [WorkoutSession]

    private struct LoggedExercise: Identifiable {
        let id: String
        let session: WorkoutSession
        let log: WorkoutSessionLogEntry
    }

    @Environment(\.dismiss) private var dismiss
    @State private var logsBySession: [String: [WorkoutSessionLogEntry]] = [:]
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedExercise: LoggedExercise?

    private var headerDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        let dateText = formatter.string(from: date)
        if let timeText = primarySessionTimeText {
            return "\(dateText), \(timeText)"
        }
        return dateText
    }

    private var headerSubtitle: String? {
        guard sessions.count == 1, let session = sortedSessions.first else { return nil }
        let title = (session.templateTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        return session.isHealthWorkout ? "Apple Health Workout" : "Workout"
    }

    private var totalDuration: Int {
        sessions.reduce(0) { $0 + ($1.durationSeconds ?? 0) } / 60
    }

    private var exerciseCount: Int {
        // Count unique exercises across all sessions
        let uniqueExercises = Set(logsBySession.values.flatMap { logs in
            logs.map { $0.exerciseName }
        })
        let count = uniqueExercises.count
        if count > 0 {
            return count
        }
        return sessions.isEmpty ? 0 : sessions.count
    }
    
    /// Groups logs by exercise name, combining all sets from the same exercise
    private func groupedLogs(for sessionId: String) -> [WorkoutSessionLogEntry] {
        guard let logs = logsBySession[sessionId], !logs.isEmpty else { return [] }
        
        // Group logs by exercise name
        let grouped = Dictionary(grouping: logs) { $0.exerciseName }
        
        // Combine logs for each exercise
        return grouped.map { exerciseName, exerciseLogs in
            // Sort by created date to maintain order
            let sortedLogs = exerciseLogs.sorted { lhs, rhs in
                guard let lhsDate = lhs.createdAt, let rhsDate = rhs.createdAt else { return false }
                return lhsDate < rhsDate
            }
            
            // Use the first log as base and combine all set details
            guard let firstLog = sortedLogs.first else { return exerciseLogs[0] }
            
            // Collect all set details from all logs
            let allSetDetails = sortedLogs.flatMap { $0.setDetails }
            
            // Create a combined log entry
            return WorkoutSessionLogEntry(
                id: firstLog.id,
                exerciseName: exerciseName,
                sets: allSetDetails.count,
                reps: firstLog.reps,
                weight: firstLog.weight,
                durationMinutes: firstLog.durationMinutes,
                setDetails: allSetDetails,
                notes: firstLog.notes,
                createdAt: firstLog.createdAt
            )
        }.sorted { lhs, rhs in
            // Sort by the first occurrence of each exercise
            guard let lhsDate = lhs.createdAt, let rhsDate = rhs.createdAt else { return false }
            return lhsDate < rhsDate
        }
    }

    private var sortedSessions: [WorkoutSession] {
        sessions.sorted { lhs, rhs in
            sessionDate(for: lhs) > sessionDate(for: rhs)
        }
    }

    private var primarySessionTimeText: String? {
        guard sessions.count == 1 else { return nil }
        return timeText(for: sortedSessions.first?.createdAt)
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if !sessions.isEmpty {
                        statsCard
                    }

                    if isLoading {
                        loadingCard
                    } else if sessions.isEmpty {
                        emptyStateCard
                    } else {
                        let showHeaders = sortedSessions.count > 1
                        ForEach(sortedSessions) { session in
                            WorkoutSessionOverviewCard(
                                session: session,
                                logs: groupedLogs(for: session.id),
                                showHeader: showHeaders,
                                onSelectLog: { log in
                                    selectedExercise = LoggedExercise(id: log.id, session: session, log: log)
                                }
                            )
                        }
                    }

                    if let error = loadError {
                        errorCard(error)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .sheet(item: $selectedExercise) { selection in
            WorkoutLoggedExerciseDetailView(
                userId: userId,
                date: date,
                session: selection.session,
                log: selection.log
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await loadLogs()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(headerDateText)
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                    if let headerSubtitle {
                        Text(headerSubtitle)
                            .font(FitFont.body(size: 13, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                    }
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

            Text("\(exerciseCount) Exercises")
                .font(FitFont.heading(size: 28))
                .fontWeight(.bold)
                .foregroundColor(FitTheme.textPrimary)

            Text("Tap an exercise to view sets and details.")
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private var statsCard: some View {
        HStack(spacing: 12) {
            statItem(icon: "clock.fill", value: "\(totalDuration)", label: "minutes")
            statItem(
                icon: "figure.strengthtraining.traditional",
                value: "\(sessions.count)",
                label: sessions.count == 1 ? "session" : "sessions"
            )
            statItem(icon: "list.bullet", value: "\(exerciseCount)", label: "exercises")
        }
        .padding(16)
        .background(FitTheme.cardWorkout)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FitTheme.cardWorkoutAccent.opacity(0.2), lineWidth: 1)
        )
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(FitTheme.cardWorkoutAccent)
            Text(value)
                .font(FitFont.heading(size: 20))
                .foregroundColor(FitTheme.textPrimary)
            Text(label)
                .font(FitFont.body(size: 11))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingCard: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(FitTheme.cardWorkoutAccent)
            Text("Loading workout logs...")
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.walk")
                .font(.system(size: 40))
                .foregroundColor(FitTheme.textSecondary.opacity(0.5))
            Text("No workouts logged")
                .font(FitFont.heading(size: 18))
                .foregroundColor(FitTheme.textPrimary)
            Text("Start a workout to see your logs here")
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func errorCard(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(FitTheme.cardReminderAccent)
            Text(error)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FitTheme.cardReminder)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sessionDate(for session: WorkoutSession) -> Date {
        guard let value = session.createdAt else { return .distantPast }
        return workoutSessionDateFormatterWithFractional.date(from: value)
            ?? workoutSessionDateFormatter.date(from: value)
            ?? .distantPast
    }

    private func timeText(for value: String?) -> String? {
        guard let value else { return nil }
        let date = workoutSessionDateFormatterWithFractional.date(from: value)
            ?? workoutSessionDateFormatter.date(from: value)
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func loadLogs() async {
        isLoading = true
        loadError = nil
        var results: [String: [WorkoutSessionLogEntry]] = [:]
        for session in sessions {
            if session.isHealthWorkout {
                continue
            }
            do {
                let logs = try await WorkoutAPIService.shared.fetchSessionLogs(sessionId: session.id)
                results[session.id] = logs
            } catch {
                print("❌ Failed to load logs for sessionId=\(session.id):", error)
                if let apiError = error as? OnboardingAPIError {
                    switch apiError {
                    case .serverError(let statusCode, let body):
                        print("ServerError HTTP \(statusCode) sessionId=\(session.id)")
                        print("Server body:", body)
                        if let data = body.data(using: .utf8),
                           let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                           let payload = jsonObject as? [String: Any],
                           let detail = payload["detail"] {
                            print("Server detail:", detail)
                        }
                    default:
                        break
                    }
                }
                loadError = "Some workout logs couldn't be loaded"
            }
        }
        await MainActor.run {
            logsBySession = results
            isLoading = false
        }
    }
}

private struct WorkoutSessionOverviewCard: View {
    let session: WorkoutSession
    let logs: [WorkoutSessionLogEntry]
    let showHeader: Bool
    let onSelectLog: (WorkoutSessionLogEntry) -> Void

    var body: some View {
        let isHealthWorkout = session.isHealthWorkout
        VStack(alignment: .leading, spacing: 14) {
            if showHeader {
                sessionHeader(isHealthWorkout: isHealthWorkout)
            }

            if logs.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundColor(FitTheme.textSecondary)
                    Text(isHealthWorkout ? "Logged from Apple Health." : "No exercises logged for this session")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FitTheme.cardHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 10) {
                    ForEach(logs) { log in
                        WorkoutExerciseOverviewRow(log: log, onTap: { onSelectLog(log) })
                    }
                }
            }
        }
        .padding(18)
        .background(FitTheme.cardWorkout)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardWorkoutAccent.opacity(0.2), lineWidth: 1)
        )
    }

    private func sessionHeader(isHealthWorkout: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [FitTheme.cardWorkoutAccent, FitTheme.cardWorkoutAccent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: FitTheme.cardWorkoutAccent.opacity(0.3), radius: 6, x: 0, y: 3)

                Image(systemName: isHealthWorkout ? "heart.fill" : "figure.strengthtraining.traditional")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTitle(isHealthWorkout: isHealthWorkout))
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
                HStack(spacing: 8) {
                    Text(sessionTimeText)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                    if let durationSeconds = session.durationSeconds, durationSeconds > 0 {
                        Text("•")
                            .foregroundColor(FitTheme.textSecondary)
                        Text("\(durationSeconds / 60) min")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
            }

            Spacer()

            if isHealthWorkout {
                Text("Apple Health")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.cardWorkoutAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(FitTheme.cardWorkoutAccent.opacity(0.12))
                    .clipShape(Capsule())
            } else if !logs.isEmpty {
                Text("\(logs.count)")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.cardWorkoutAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(FitTheme.cardWorkoutAccent.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    private func sessionTitle(isHealthWorkout: Bool) -> String {
        let trimmed = (session.templateTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return isHealthWorkout ? "Apple Health Workout" : "Workout"
    }

    private var sessionTimeText: String {
        guard let value = session.createdAt else { return "Unknown time" }
        let date = workoutSessionDateFormatterWithFractional.date(from: value)
            ?? workoutSessionDateFormatter.date(from: value)
        guard let date else { return "Unknown time" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

private struct WorkoutExerciseOverviewRow: View {
    let log: WorkoutSessionLogEntry
    let onTap: () -> Void

    private var isCardio: Bool {
        log.exerciseName.lowercased().hasPrefix("cardio -")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail

                VStack(alignment: .leading, spacing: 6) {
                    Text(log.exerciseName)
                        .font(FitFont.body(size: 15, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)

                    if summaryLines.isEmpty {
                        Text("No sets logged")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    } else {
                        ForEach(summaryLines.indices, id: \.self) { index in
                            Text(summaryLines[index])
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                    .padding(.top, 4)
            }
            .padding(12)
            .background(FitTheme.cardHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            FitTheme.cardWorkoutAccent.opacity(0.18),
                            FitTheme.cardWorkoutAccent.opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)

            Image(systemName: isCardio ? "figure.run" : "dumbbell.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(FitTheme.cardWorkoutAccent)

            Circle()
                .fill(FitTheme.success)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                )
                .offset(x: 6, y: 6)
        }
    }

    private var summaryLines: [String] {
        if isCardio {
            let minutes = cardioMinutesText()
            if let notes = log.notes, !notes.isEmpty {
                return ["\(minutes) - \(notes)"]
            }
            return [minutes]
        }

        let details = summarySetDetails
        if !details.isEmpty {
            let lines = details.map { summaryLine(for: $0) }
            return cappedLines(from: lines)
        }

        let fallback = fallbackLine()
        guard !fallback.isEmpty else { return [] }
        let count = max(1, min(log.sets, 3))
        var lines = Array(repeating: fallback, count: count)
        if log.sets > 3 {
            lines.append("...")
        }
        return lines
    }

    private var summarySetDetails: [WorkoutSetDetail] {
        guard !log.setDetails.isEmpty else { return [] }
        let working = log.setDetails.filter { !$0.isWarmup }
        return working.isEmpty ? log.setDetails : working
    }

    private func summaryLine(for detail: WorkoutSetDetail) -> String {
        if let durationSeconds = detail.durationSeconds, durationSeconds > 0 {
            let minutes = max(1, durationSeconds / 60)
            return "\(minutes) min"
        }

        var parts: [String] = []
        if detail.reps > 0 {
            parts.append("\(detail.reps) reps")
        }
        if detail.weight > 0 {
            parts.append("\(formatWorkoutWeight(detail.weight)) lb")
        }
        let base = parts.isEmpty ? "Set" : parts.joined(separator: " x ")
        if detail.isWarmup {
            return "Warm-up - \(base)"
        }
        return base
    }

    private func fallbackLine() -> String {
        var parts: [String] = []
        if log.reps > 0 {
            parts.append("\(log.reps) reps")
        }
        if log.weight > 0 {
            parts.append("\(formatWorkoutWeight(log.weight)) lb")
        }
        if parts.isEmpty {
            return "Set logged"
        }
        return parts.joined(separator: " x ")
    }

    private func cappedLines(from lines: [String]) -> [String] {
        guard lines.count > 3 else { return lines }
        var trimmed = Array(lines.prefix(3))
        trimmed.append("...")
        return trimmed
    }

    private func cardioMinutesText() -> String {
        let setDurationSeconds = log.setDetails.first?.durationSeconds ?? 0
        let minutesValue = setDurationSeconds > 0 ? setDurationSeconds / 60 : (log.durationMinutes ?? 0)
        let fallbackMinutes = minutesValue > 0 ? minutesValue : log.reps
        return fallbackMinutes > 0 ? "\(fallbackMinutes) min" : "Cardio"
    }
}

private struct WorkoutLoggedExerciseDetailView: View {
    let userId: String
    let date: Date
    let session: WorkoutSession
    let log: WorkoutSessionLogEntry

    @Environment(\.dismiss) private var dismiss
    @State private var showHistory = false
    @State private var showMore = false
    @State private var showNotes = false

    private var isCardio: Bool {
        log.exerciseName.lowercased().hasPrefix("cardio -")
    }

    private var headerDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private var sessionTimeText: String? {
        guard let value = session.createdAt else { return nil }
        let date = workoutSessionDateFormatterWithFractional.date(from: value)
            ?? workoutSessionDateFormatter.date(from: value)
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private var sessionTitle: String? {
        let trimmed = (session.templateTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return session.isHealthWorkout ? "Apple Health Workout" : "Workout"
    }

    private var hasNotes: Bool {
        !(log.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displaySets: [LoggedSetDisplay] {
        if !log.setDetails.isEmpty {
            let sorted = log.setDetails.enumerated().sorted { lhs, rhs in
                let lhsIndex = lhs.element.setIndex ?? lhs.offset
                let rhsIndex = rhs.element.setIndex ?? rhs.offset
                return lhsIndex < rhsIndex
            }
            return sorted.enumerated().map { index, item in
                LoggedSetDisplay(
                    index: index + 1,
                    reps: item.element.reps,
                    weight: item.element.weight,
                    durationSeconds: item.element.durationSeconds,
                    isWarmup: item.element.isWarmup
                )
            }
        }

        let fallbackMinutes = log.durationMinutes ?? (isCardio ? log.reps : 0)
        let durationSeconds = fallbackMinutes > 0 ? fallbackMinutes * 60 : nil
        let setCount = max(log.sets, (log.reps > 0 || log.weight > 0 || durationSeconds != nil) ? 1 : 0)
        guard setCount > 0 else { return [] }
        return (0..<setCount).map { index in
            LoggedSetDisplay(
                index: index + 1,
                reps: log.reps,
                weight: log.weight,
                durationSeconds: durationSeconds,
                isWarmup: false
            )
        }
    }

    private var warmupSets: [LoggedSetDisplay] {
        displaySets.filter { $0.isWarmup }
    }

    private var workingSets: [LoggedSetDisplay] {
        displaySets.filter { !$0.isWarmup }
    }

    private var totalSetsCount: Int {
        displaySets.count
    }

    private var exerciseIcon: String {
        let name = log.exerciseName.lowercased()
        if name.contains("bench") || name.contains("press") || name.contains("chest") || name.contains("fly") {
            return "figure.strengthtraining.traditional"
        } else if name.contains("squat") || name.contains("leg") || name.contains("lunge") {
            return "figure.walk"
        } else if name.contains("deadlift") || name.contains("row") || name.contains("back") || name.contains("pull") {
            return "figure.rowing"
        } else if name.contains("curl") || name.contains("bicep") || name.contains("tricep") || name.contains("arm") {
            return "dumbbell.fill"
        } else if name.contains("shoulder") || name.contains("lateral") || name.contains("overhead") {
            return "figure.arms.open"
        } else if name.contains("core") || name.contains("ab") || name.contains("crunch") || name.contains("plank") {
            return "figure.core.training"
        } else if isCardio {
            return "figure.run"
        } else {
            return "figure.strengthtraining.functional"
        }
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    actionPills

                    if !warmupSets.isEmpty {
                        sectionTitle("Warm-up Sets")
                        ForEach(warmupSets) { set in
                            WorkoutLoggedSetRow(set: set, unitLabel: "lb", isCardio: isCardio)
                        }
                    }

                    if !workingSets.isEmpty {
                        sectionTitle("Working Sets")
                        ForEach(workingSets) { set in
                            WorkoutLoggedSetRow(set: set, unitLabel: "lb", isCardio: isCardio)
                        }
                    }

                    if displaySets.isEmpty {
                        emptySetsCard
                    }

                    if let notes = log.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        notesCard(notes)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 40, coordinateSpace: .local)
                    .onEnded { value in
                        let isVertical = abs(value.translation.width) < 80
                        let isDownward = value.translation.height > 120
                        let isFromTop = value.startLocation.y < 140
                        if isVertical && isDownward && isFromTop {
                            dismiss()
                        }
                    }
            )
        }
        .sheet(isPresented: $showHistory) {
            ExerciseDetailView(userId: userId, exerciseName: log.exerciseName, unit: .lb)
        }
        .confirmationDialog("More", isPresented: $showMore) {
            if hasNotes {
                Button("View Notes") {
                    showNotes = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Notes", isPresented: $showNotes) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(log.notes ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(FitTheme.cardHighlight)
                .frame(width: 44, height: 5)
                .padding(.top, 4)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                        .padding(10)
                        .background(FitTheme.cardBackground.opacity(0.8))
                        .clipShape(Circle())
                }
            }

            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [FitTheme.cardWorkoutAccent.opacity(0.2), FitTheme.cardWorkoutAccent.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)

                        Image(systemName: exerciseIcon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(FitTheme.cardWorkoutAccent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.exerciseName)
                            .font(FitFont.heading(size: 22))
                            .foregroundColor(FitTheme.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(FitTheme.success)
                                Text("\(totalSetsCount)/\(totalSetsCount) sets")
                                    .font(FitFont.body(size: 12, weight: .medium))
                                    .foregroundColor(FitTheme.textSecondary)
                            }

                            Text("•")
                                .foregroundColor(FitTheme.textSecondary.opacity(0.5))

                            if let sessionTimeText {
                                Text(sessionTimeText)
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            } else {
                                Text(headerDateText)
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                        }
                    }

                    Spacer()
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(FitTheme.cardStroke)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [FitTheme.success, FitTheme.success.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .padding(16)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(FitTheme.cardWorkoutAccent.opacity(0.15), lineWidth: 1)
            )
        }
        .padding(.top, 8)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(FitFont.body(size: 13, weight: .semibold))
            .foregroundColor(FitTheme.textSecondary)
    }

    private var actionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                pillButton(title: "History", icon: "chart.bar.fill") {
                    showHistory = true
                }

                pillButton(title: "More", icon: "ellipsis") {
                    showMore = true
                }
                .opacity(hasNotes ? 1 : 0.4)
                .disabled(!hasNotes)
            }
        }
    }

    private func pillButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(FitFont.body(size: 12, weight: .semibold))
            }
            .foregroundColor(FitTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(FitTheme.cardHighlight)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptySetsCard: some View {
        Text("No sets logged yet.")
            .font(FitFont.body(size: 12))
            .foregroundColor(FitTheme.textSecondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FitTheme.cardHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)
            Text(notes)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct LoggedSetDisplay: Identifiable {
    let id = UUID()
    let index: Int
    let reps: Int
    let weight: Double
    let durationSeconds: Int?
    let isWarmup: Bool
}

private struct WorkoutLoggedSetRow: View {
    let set: LoggedSetDisplay
    let unitLabel: String
    let isCardio: Bool

    var body: some View {
        HStack(spacing: 0) {
            setNumber
            setMeta

            Spacer()

            if isCardio {
                setFieldReadOnly(title: "MIN", value: durationText)
                    .padding(.trailing, 8)
            } else {
                setFieldReadOnly(title: "Reps", value: repsText)
                    .padding(.trailing, 8)
                setFieldReadOnly(title: unitLabel.uppercased(), value: weightText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.success.opacity(0.3), lineWidth: 1.5)
        )
    }

    private var setNumber: some View {
        ZStack {
            Circle()
                .fill(FitTheme.success)
                .frame(width: 40, height: 40)

            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.trailing, 14)
    }

    private var setMeta: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(set.isWarmup ? "Warm-up" : "Set \(set.index)")
                .font(FitFont.body(size: 12, weight: .medium))
                .foregroundColor(FitTheme.success)
        }
        .frame(width: 65, alignment: .leading)
    }

    private var rowBackground: Color {
        if set.isWarmup {
            return FitTheme.cardBackground.opacity(0.6)
        }
        return FitTheme.success.opacity(0.08)
    }

    private var repsText: String {
        (set.reps > 0) ? "\(set.reps)" : "—"
    }

    private var weightText: String {
        (set.weight > 0) ? formatWorkoutWeight(set.weight) : "—"
    }

    private var durationText: String {
        guard let durationSeconds = set.durationSeconds, durationSeconds > 0 else {
            return "—"
        }
        let minutes = max(1, durationSeconds / 60)
        return "\(minutes)"
    }

    private func setFieldReadOnly(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(FitFont.body(size: 10, weight: .medium))
                .foregroundColor(FitTheme.textSecondary.opacity(0.7))

            Text(value)
                .font(FitFont.heading(size: 18))
                .foregroundColor(FitTheme.success)
                .frame(width: 55)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(FitTheme.success.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(width: 70)
    }
}

// MARK: - Progress Check-In Locked Sheet
private struct ProgressCheckinLockedSheet: View {
    let checkinDayName: String
    let daysUntilCheckin: Int
    
    @Environment(\.dismiss) private var dismiss
    @State private var showDayPicker = false
    
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Close button
                HStack {
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
                .padding(.top, 20)
                
                Spacer()
                
                // Lock icon
                ZStack {
                    Circle()
                        .fill(FitTheme.cardProgressAccent.opacity(0.15))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(FitTheme.cardProgressAccent)
                }
                
                // Title
                Text("Check-In Locked")
                    .font(FitFont.heading(size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(FitTheme.textPrimary)
                
                // Message
                VStack(spacing: 8) {
                    Text("Your weekly check-in is available on")
                        .font(FitFont.body(size: 16))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Text(checkinDayName)
                        .font(FitFont.heading(size: 24))
                        .foregroundColor(FitTheme.cardProgressAccent)
                    
                    if daysUntilCheckin == 1 {
                        Text("That's tomorrow!")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                    } else {
                        Text("That's in \(daysUntilCheckin) days")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Change day button
                VStack(spacing: 12) {
                    Text("Would you like to change your check-in day?")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Button(action: {
                        showDayPicker = true
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Change Check-In Day")
                                .font(FitFont.body(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [FitTheme.cardProgressAccent, FitTheme.cardProgressAccent.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: FitTheme.cardProgressAccent.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showDayPicker) {
            ProgressCheckinDayPickerSheet(onDismissParent: { dismiss() })
        }
    }
}

// MARK: - Progress Check-In Day Picker Sheet
private struct ProgressCheckinDayPickerSheet: View {
    let onDismissParent: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("checkinDay") private var checkinDay: Int = 0
    @State private var selectedDay: Int = 0
    @State private var isSaving = false
    
    private let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(FitTheme.cardHighlight)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("Check-In Day")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    Spacer()
                    
                    Color.clear
                        .frame(width: 32, height: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Hero
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(FitTheme.cardProgressAccent.opacity(0.15))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(FitTheme.cardProgressAccent)
                    }
                    
                    Text("Choose Your Check-In Day")
                        .font(FitFont.heading(size: 22))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    Text("Pick the day that works best for your schedule")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
                
                // Day picker
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { index in
                            Button(action: {
                                selectedDay = index
                                Haptics.light()
                            }) {
                                HStack {
                                    Text(days[index])
                                        .font(FitFont.body(size: 16, weight: selectedDay == index ? .semibold : .regular))
                                        .foregroundColor(selectedDay == index ? .white : FitTheme.textPrimary)
                                    
                                    Spacer()
                                    
                                    if selectedDay == index {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .background(selectedDay == index ? FitTheme.cardProgressAccent : FitTheme.cardHighlight)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                // Save button
                Button(action: saveDay) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Save Changes")
                            .font(FitFont.body(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [FitTheme.cardProgressAccent, FitTheme.cardProgressAccent.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: FitTheme.cardProgressAccent.opacity(0.4), radius: 12, x: 0, y: 6)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            selectedDay = checkinDay
        }
    }
    
    private func saveDay() {
        isSaving = true
        checkinDay = selectedDay
        Haptics.success()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
            onDismissParent()
        }
    }
}

private struct CheckinFlowView: View {
    private enum AdherenceChoice: String, CaseIterable, Identifiable {
        case missed = "Missed"
        case onTrack = "On track"
        case exceeded = "Exceeded"

        var id: String { rawValue }
    }

    private enum WellnessChoice: String, CaseIterable, Identifiable {
        case low = "Low"
        case okay = "Okay"
        case great = "Great"

        var id: String { rawValue }
    }

    private enum PhotoRetentionChoice: String, CaseIterable, Identifiable {
        case store
        case deleteAfterScan

        var id: String { rawValue }

        var title: String {
            switch self {
            case .store:
                return "Store photos"
            case .deleteAfterScan:
                return "Delete after scan"
            }
        }

        var subtitle: String {
            switch self {
            case .store:
                return "Coach can use them for future comparisons."
            case .deleteAfterScan:
                return "Use once for this check-in, then permanently delete."
            }
        }

        var apiValue: CheckinPhotoRetention {
            switch self {
            case .store:
                return .store
            case .deleteAfterScan:
                return .deleteAfterScan
            }
        }
    }

    let userId: String
    let storedPhysiquePriority: String?
    let storedSecondaryPriority: String?
    let onSubmitSuccess: (CheckinSubmitResponse) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var checkinDate = Date()
    @State private var weightText = ""
    @State private var workoutsChoice: AdherenceChoice = .onTrack
    @State private var caloriesChoice: AdherenceChoice = .onTrack
    @State private var sleepChoice: WellnessChoice = .okay
    @State private var stepsChoice: WellnessChoice = .okay
    @State private var moodChoice: WellnessChoice = .okay
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isShowingCamera = false
    @State private var cameraError: String?
    @State private var isLoadingPhotos = false
    @State private var photoRetentionChoice: PhotoRetentionChoice = .store
    @State private var showDeletePhotoWarning = false

    private let fieldBackground = FitTheme.cardHighlight
    private static let checkinDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private var effectivePrimaryFocus: String? {
        storedPhysiquePriority
    }

    private var effectiveSecondaryFocus: String? {
        storedSecondaryPriority
    }

    private var focusSummaryText: String? {
        guard let primary = effectivePrimaryFocus, !primary.isEmpty else { return nil }
        if let secondary = effectiveSecondaryFocus, !secondary.isEmpty {
            return "Focus this week: \(primary) + \(secondary)"
        }
        return "Focus this week: \(primary)"
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    basicsCard
                    adherenceCard
                    photosCard
                    submitSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }

            if isSubmitting {
                CheckinAnalyzingOverlay()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSubmitting)
        .onTapGesture {
            dismissKeyboard()
        }
        .alert("Delete photos after scan?", isPresented: $showDeletePhotoWarning) {
            Button("Submit and Delete", role: .destructive) {
                Task {
                    await submit()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("If you delete photos after this check-in, your coach will not be able to reference previous check-in photos for accurate progress summaries.")
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            // Close button row
            HStack {
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
            
            // Hero section
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(FitTheme.cardProgressAccent.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(FitTheme.cardProgressAccent)
                }
                
                Text("Weekly Check-in")
                    .font(FitFont.heading(size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(FitTheme.textPrimary)
                
                Text("Track your progress and keep the momentum going!")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                    .multilineTextAlignment(.center)

                if let focusSummaryText {
                    Text(focusSummaryText)
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.accentMuted)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardProgressAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text("Basics")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Check-in date")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textPrimary)
                    Spacer()
                    DatePicker("", selection: $checkinDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(FitTheme.accent)
                }
                .padding(14)
                .background(FitTheme.cardHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                
                HStack {
                    Text("Current weight")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textPrimary)
                    Spacer()
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .frame(width: 80)
                    Text("lbs")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textSecondary)
                }
                .padding(14)
                .background(FitTheme.cardHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(18)
        .background(FitTheme.cardProgress)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardProgressAccent.opacity(0.2), lineWidth: 1)
        )
    }

    private var adherenceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardWorkoutAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Adherence")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("How did the week go?")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            
            VStack(spacing: 10) {
                CheckinChoiceRow(title: "Workouts hit", icon: "figure.run", selection: $workoutsChoice)
                CheckinChoiceRow(title: "Calories hit", icon: "fork.knife", selection: $caloriesChoice)
                CheckinChoiceRow(title: "Sleep quality", icon: "moon.zzz.fill", selection: $sleepChoice)
                CheckinChoiceRow(title: "Steps hit", icon: "shoeprints.fill", selection: $stepsChoice)
                CheckinChoiceRow(title: "Mood", icon: "face.smiling.fill", selection: $moodChoice)
            }
        }
        .padding(18)
        .background(FitTheme.cardWorkout)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardWorkoutAccent.opacity(0.2), lineWidth: 1)
        )
    }

    private var photosCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardNutritionAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Progress Photos")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("Add up to 3 photos (optional)")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }

            if !selectedImages.isEmpty {
                photoGrid
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Photo handling")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                HStack(spacing: 8) {
                    ForEach(PhotoRetentionChoice.allCases) { choice in
                        let isSelected = choice == photoRetentionChoice
                        Button {
                            photoRetentionChoice = choice
                        } label: {
                            Text(choice.title)
                                .font(FitFont.body(size: 12, weight: .semibold))
                                .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    isSelected
                                        ? AnyShapeStyle(FitTheme.primaryGradient)
                                        : AnyShapeStyle(FitTheme.cardHighlight)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(photoRetentionChoice.subtitle)
                    .font(FitFont.body(size: 11))
                    .foregroundColor(FitTheme.textSecondary)
                if photoRetentionChoice == .deleteAfterScan && !selectedImages.isEmpty {
                    Text("After this check-in is analyzed, selected photos will be removed and won't appear in your progress timeline.")
                        .font(FitFont.body(size: 11))
                        .foregroundColor(FitTheme.accentMuted)
                }
            }

            HStack(spacing: 12) {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isShowingCamera = true
                        cameraError = nil
                    } else {
                        cameraError = "Camera is not available on this device."
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.system(size: 14, weight: .medium))
                        Text("Camera")
                            .font(FitFont.body(size: 14, weight: .semibold))
                    }
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(FitTheme.cardHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(selectedImages.count >= 3)

                PhotosPicker(
                    selection: $photoSelections,
                    maxSelectionCount: max(0, 3 - selectedImages.count),
                    matching: .images
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 14, weight: .medium))
                        Text("Gallery")
                            .font(FitFont.body(size: 14, weight: .semibold))
                    }
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(FitTheme.cardHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(selectedImages.count >= 3)
            }

            if isLoadingPhotos {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading photos...")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }

            if let cameraError {
                Text(cameraError)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(18)
        .background(FitTheme.cardNutrition)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardNutritionAccent.opacity(0.2), lineWidth: 1)
        )
        .onChange(of: photoSelections) { newSelections in
            Task {
                await loadSelectedPhotos(from: newSelections)
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraPicker(image: $selectedImages, isPresented: $isShowingCamera)
        }
    }

    private var submitSection: some View {
        VStack(spacing: 16) {
            Button {
                handleSubmitTapped()
            } label: {
                HStack(spacing: 10) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    }
                    Text(isSubmitting ? "Analyzing..." : "Submit Check-in")
                        .font(FitFont.body(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [FitTheme.accent, FitTheme.accent.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: FitTheme.accent.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(isSubmitting)
            .opacity(isSubmitting ? 0.8 : 1.0)
            
            Text(photoRetentionChoice == .deleteAfterScan && !selectedImages.isEmpty
                ? "Your AI coach will analyze these photos once, then delete them."
                : "Your AI coach will analyze your progress")
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func labeledField(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.none)
                .disableAutocorrection(true)
                .padding(12)
                .background(fieldBackground)
                .foregroundColor(FitTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func handleSubmitTapped() {
        if photoRetentionChoice == .deleteAfterScan && !selectedImages.isEmpty {
            showDeletePhotoWarning = true
            return
        }
        Task {
            await submit()
        }
    }

    private func submit() async {
        errorMessage = nil
        dismissKeyboard()

        guard let weight = Double(weightText), weight > 0 else {
            errorMessage = "Enter a valid weight before submitting."
            return
        }

        let adherence: [String: Any] = [
            "current_weight": weight,
            "workouts": workoutsChoice.rawValue,
            "calories": caloriesChoice.rawValue,
            "sleep": sleepChoice.rawValue,
            "steps": stepsChoice.rawValue,
            "mood": moodChoice.rawValue,
        ]
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let uploadedPhotos: [[String: String]]
            do {
                uploadedPhotos = try await uploadSelectedPhotos()
            } catch OnboardingAPIError.serverError(let statusCode, _) where statusCode == 404 {
                uploadedPhotos = []
            } catch {
                errorMessage = checkinErrorMessage(for: error)
                return
            }
            let response = try await ProgressAPIService.shared.submitCheckin(
                userId: userId,
                checkinDate: checkinDate,
                adherence: adherence,
                photos: uploadedPhotos,
                photoRetention: photoRetentionChoice.apiValue
            )
            await onSubmitSuccess(response)
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = checkinErrorMessage(for: error)
        }
    }

    private func checkinErrorMessage(for error: Error) -> String {
        if let onboardingError = error as? OnboardingAPIError,
           case let .serverError(statusCode, body) = onboardingError {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Check-in failed (HTTP \(statusCode))."
            }
            return "Check-in failed (HTTP \(statusCode)): \(trimmed)"
        }
        return error.localizedDescription
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var photoGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: 96), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button {
                        selectedImages.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(FitTheme.buttonText)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(6)
                }
            }
        }
    }

    private func loadSelectedPhotos(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }

        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImages.append(image)
                    if selectedImages.count >= 3 {
                        break
                    }
                }
            } catch {
                errorMessage = "Unable to load one of the selected photos."
            }
        }
        photoSelections = []
    }

    private func uploadSelectedPhotos() async throws -> [[String: String]] {
        guard !selectedImages.isEmpty else { return [] }

        var uploadedPhotos: [[String: String]] = []
        let photoTypes = ["front", "side", "back"]
        let shouldPersistPhotos = photoRetentionChoice == .store

        for (index, image) in selectedImages.enumerated() {
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                continue
            }
            let type = index < photoTypes.count ? photoTypes[index] : "checkin"
            let response = try await ProgressAPIService.shared.uploadProgressPhoto(
                userId: userId,
                checkinDate: checkinDate,
                photoType: type,
                photoCategory: "checkin",
                imageData: data,
                persistPhoto: shouldPersistPhotos
            )
            if let url = response.photoUrl {
                let dateString = response.date ?? Self.checkinDateFormatter.string(from: checkinDate)
                uploadedPhotos.append(["url": url, "type": type, "date": dateString])
                if shouldPersistPhotos {
                    _ = ProgressPhotoLocalStore.save(
                        imageData: data,
                        userId: userId,
                        remoteURL: url,
                        date: checkinDate,
                        type: type,
                        category: "checkin"
                    )
                }
            }
        }
        return uploadedPhotos
    }
}

private struct CheckinAnalyzingOverlay: View {
    private let steps = [
        "Analyzing photos",
        "Reviewing check-in answers",
        "Comparing past check-ins",
        "Building next-week targets"
    ]
    @State private var stepIndex = 0
    @State private var pulse = false
    private let timer = Timer.publish(every: 2.3, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
                .opacity(0.98)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(FitTheme.accent.opacity(0.3), lineWidth: 2)
                        .frame(width: 170, height: 170)
                        .scaleEffect(pulse ? 1.08 : 0.92)
                        .opacity(pulse ? 0.25 : 0.6)

                    CoachCharacterView(size: 120, showBackground: false, pose: .thinking)
                }
                .padding(.bottom, 8)

                Text("Analyzing check-in")
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(FitTheme.textPrimary)

                Text(steps[stepIndex])
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                    .transition(.opacity)

                SwiftUI.ProgressView()
                    .tint(FitTheme.textSecondary)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                stepIndex = (stepIndex + 1) % steps.count
            }
        }
    }
}

private enum BodyScanConfidence: String, Codable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

private struct BodyScanResult: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let bodyFatLow: Double
    let bodyFatHigh: Double
    let confidence: BodyScanConfidence
    let fatMass: Double
    let leanMass: Double
    let tdeeLow: Double
    let tdeeHigh: Double
    let action: String
    let qualityIssues: [String]
    let qualityScore: Double

    var bodyFatRangeText: String {
        String(format: "%.0f–%.0f%%", bodyFatLow, bodyFatHigh)
    }

    var tdeeRangeText: String {
        let low = Int(tdeeLow.rounded())
        let high = Int(tdeeHigh.rounded())
        return "\(low)–\(high) kcal"
    }
}

private enum BodyScanStore {
    private static let key = "fitai.body_scan_results"

    static func load() -> [BodyScanResult] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([BodyScanResult].self, from: data)) ?? []
    }

    static func save(_ results: [BodyScanResult]) {
        guard let data = try? JSONEncoder().encode(results) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private enum BodyScanPalette {
    static let deep = Color(red: 0.05, green: 0.12, blue: 0.20)
    static let ocean = Color(red: 0.08, green: 0.34, blue: 0.52)
    static let cyan = Color(red: 0.24, green: 0.85, blue: 0.88)
    static let mint = Color(red: 0.43, green: 0.91, blue: 0.72)
    static let amber = Color(red: 0.99, green: 0.70, blue: 0.29)
    static let rose = Color(red: 0.93, green: 0.45, blue: 0.51)
    static let shell = Color.white.opacity(0.1)
    static let shellBorder = Color.white.opacity(0.22)

    static let heroGradient = LinearGradient(
        colors: [deep, ocean, cyan.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassGradient = LinearGradient(
        colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let actionGradient = LinearGradient(
        colors: [cyan, mint],
        startPoint: .leading,
        endPoint: .trailing
    )

    static func confidenceColor(for confidence: BodyScanConfidence) -> Color {
        switch confidence {
        case .high:
            return mint
        case .medium:
            return amber
        case .low:
            return rose
        }
    }
}

private struct BodyScanHistoryView: View {
    @Binding var results: [BodyScanResult]

    @Environment(\.dismiss) private var dismiss

    private var sortedResults: [BodyScanResult] {
        results.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                if sortedResults.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.stand")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                        Text("No body scans yet")
                            .font(FitFont.heading(size: 18))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Run your first scan to set a baseline.")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    .padding(.horizontal, 24)
                } else {
                    List {
                        ForEach(sortedResults.indices, id: \.self) { index in
                            let result = sortedResults[index]
                            NavigationLink {
                                BodyScanResultDetailView(
                                    result: result,
                                    previousResult: previousResult(forIndex: index)
                                )
                            } label: {
                                BodyScanHistoryRow(
                                    result: result,
                                    isLatest: index == 0
                                )
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Body Scan History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(FitTheme.textPrimary)
                }
                if !sortedResults.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                            .foregroundColor(FitTheme.textPrimary)
                    }
                }
            }
        }
    }

    private func previousResult(forIndex index: Int) -> BodyScanResult? {
        let previousIndex = index + 1
        guard previousIndex < sortedResults.count else { return nil }
        return sortedResults[previousIndex]
    }

    private func delete(at offsets: IndexSet) {
        let ids: [UUID] = offsets.compactMap { offset -> UUID? in
            guard offset < sortedResults.count else { return nil }
            return sortedResults[offset].id
        }
        guard !ids.isEmpty else { return }
        results.removeAll { ids.contains($0.id) }
        BodyScanStore.save(results)
    }
}

private struct BodyScanHistoryRow: View {
    let result: BodyScanResult
    let isLatest: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(BodyScanPalette.actionGradient)
                    .frame(width: 42, height: 42)
                Image(systemName: "figure.stand")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black.opacity(0.76))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(result.timestamp.formatted(date: .abbreviated, time: .omitted))
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    if isLatest {
                        Text("Latest")
                            .font(FitFont.mono(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }

                Text("Body fat \(result.bodyFatRangeText)")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))

                HStack(spacing: 8) {
                    Text("Maintenance \(result.tdeeRangeText)")
                        .font(FitFont.body(size: 11))
                        .foregroundColor(.white.opacity(0.72))
                    Text(result.confidence.title)
                        .font(FitFont.mono(size: 10, weight: .semibold))
                        .foregroundColor(.black.opacity(0.78))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(BodyScanPalette.confidenceColor(for: result.confidence))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.62))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BodyScanPalette.deep.opacity(0.92), BodyScanPalette.ocean.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct BodyScanResultDetailView: View {
    let result: BodyScanResult
    let previousResult: BodyScanResult?

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(BodyScanPalette.heroGradient)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [Color.white.opacity(0.32), Color.clear],
                                    center: .topTrailing,
                                    startRadius: 0,
                                    endRadius: 210
                                )
                            )

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Estimated body fat")
                                .font(FitFont.body(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                            Text(result.bodyFatRangeText)
                                .font(FitFont.heading(size: 40))
                                .foregroundColor(.white)
                            HStack(spacing: 8) {
                                Text("Confidence \(result.confidence.title)")
                                    .font(FitFont.body(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.86))
                                Text(result.tdeeRangeText)
                                    .font(FitFont.mono(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.86))
                            }
                        }
                        .padding(16)
                    }
                    .frame(height: 170)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Action")
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.76))
                        Text(result.action)
                            .font(FitFont.body(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Body composition")
                            .font(FitFont.body(size: 13, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.82))
                        compositionBar(title: "Lean mass", value: result.leanMass, total: max(1, result.leanMass + result.fatMass), tint: BodyScanPalette.mint)
                        compositionBar(title: "Fat mass", value: result.fatMass, total: max(1, result.leanMass + result.fatMass), tint: BodyScanPalette.amber)
                    }

                    if let previousResult, let trend = bodyFatTrendText(latest: result, previous: previousResult) {
                        Text(trend)
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.82))
                    }

                    if !result.qualityIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Accuracy notes")
                                .font(FitFont.body(size: 12, weight: .semibold))
                                .foregroundColor(BodyScanPalette.amber)
                            ForEach(result.qualityIssues, id: \.self) { issue in
                                Text("• \(issue)")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(Color.white.opacity(0.84))
                            }
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.26))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [BodyScanPalette.deep.opacity(0.94), BodyScanPalette.ocean.opacity(0.82)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(result.timestamp.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bodyFatTrendText(latest: BodyScanResult, previous: BodyScanResult) -> String? {
        let latestMid = (latest.bodyFatLow + latest.bodyFatHigh) / 2
        let previousMid = (previous.bodyFatLow + previous.bodyFatHigh) / 2
        let diff = latestMid - previousMid
        if abs(diff) < 0.05 { return nil }
        let direction = diff > 0 ? "up" : "down"
        return String(format: "Since previous scan: body fat %@ %.1f%%", direction, abs(diff))
    }

    private func compositionBar(title: String, value: Double, total: Double, tint: Color) -> some View {
        let fraction = max(0.0, min(1.0, value / max(1.0, total)))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(Color.white.opacity(0.78))
                Spacer()
                Text(String(format: "%.0f lb", value))
                    .font(FitFont.mono(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 8)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(10, proxy.size.width * fraction), height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

private struct BodyScanFlowView: View {
    private enum Step: Int, CaseIterable {
        case intro
        case profileSummary
        case frontPhoto
        case sidePhoto
        case review
        case analyzing
        case results

        var title: String {
            switch self {
            case .intro:
                return "Scanner setup"
            case .profileSummary:
                return "Profile calibration"
            case .frontPhoto:
                return "Capture front frame"
            case .sidePhoto:
                return "Capture side frame"
            case .review:
                return "Quality review"
            case .analyzing:
                return "AI analysis"
            case .results:
                return "Scan insights"
            }
        }

        var shortLabel: String {
            switch self {
            case .intro: return "Intro"
            case .profileSummary: return "Profile"
            case .frontPhoto: return "Front"
            case .sidePhoto: return "Side"
            case .review: return "Review"
            case .analyzing: return "Analyze"
            case .results: return "Result"
            }
        }
    }

    let userId: String
    let previousResult: BodyScanResult?
    let onComplete: (BodyScanResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .intro
    @State private var heightFeet = ""
    @State private var heightInches = ""
    @State private var weightText = ""
    @State private var ageText = ""
    @State private var sex: OnboardingForm.Sex
    @State private var activityLevel: OnboardingForm.ActivityLevel
    @State private var goal: OnboardingForm.Goal
    @State private var frontImage: UIImage?
    @State private var sideImage: UIImage?
    @State private var frontPickerItem: PhotosPickerItem?
    @State private var sidePickerItem: PhotosPickerItem?
    @State private var showFrontCamera = false
    @State private var showSideCamera = false
    @State private var qualityIssues: [String] = []
    @State private var qualityScore: Double = 1.0
    @State private var errorMessage: String?
    @State private var result: BodyScanResult?
    @State private var ambientPulse = false
    @State private var scanLineOffset: CGFloat = -118
    @State private var analyzeSpinner = false
    @State private var analyzingStageIndex = 0
    @State private var startedAnimations = false

    private let analyzingTicker = Timer.publish(every: 1.05, on: .main, in: .common).autoconnect()
    private let analyzingStages = [
        "Checking pose symmetry",
        "Measuring body geometry",
        "Estimating composition model",
        "Calibrating confidence range"
    ]

    init(
        userId: String,
        profileHeightCm: Double?,
        profileWeightLbs: Double?,
        profileAge: Int?,
        profileSex: OnboardingForm.Sex,
        profileActivityLevel: OnboardingForm.ActivityLevel,
        profileGoal: OnboardingForm.Goal,
        previousResult: BodyScanResult?,
        onComplete: @escaping (BodyScanResult) -> Void
    ) {
        self.userId = userId
        self.previousResult = previousResult
        self.onComplete = onComplete

        let height = BodyScanFlowView.heightText(from: profileHeightCm)
        _heightFeet = State(initialValue: height.feet)
        _heightInches = State(initialValue: height.inches)

        if let profileWeightLbs, profileWeightLbs > 0 {
            _weightText = State(initialValue: BodyScanFlowView.formatWeightInput(profileWeightLbs))
        } else {
            _weightText = State(initialValue: "")
        }

        if let profileAge, profileAge > 0 {
            _ageText = State(initialValue: "\(profileAge)")
        } else {
            _ageText = State(initialValue: "")
        }

        _sex = State(initialValue: profileSex)
        _activityLevel = State(initialValue: profileActivityLevel)
        _goal = State(initialValue: profileGoal)
    }

    var body: some View {
        ZStack {
            flowBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    progressTrack
                    stepContent
                        .id(step.rawValue)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                        )

                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(BodyScanPalette.amber)
                            Text(errorMessage)
                                .font(FitFont.body(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.36))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showFrontCamera) {
            BodyScanCameraPicker(image: $frontImage, isPresented: $showFrontCamera)
        }
        .sheet(isPresented: $showSideCamera) {
            BodyScanCameraPicker(image: $sideImage, isPresented: $showSideCamera)
        }
        .onChange(of: frontPickerItem) { newItem in
            Task { await loadPickerItem(newItem, assignTo: $frontImage) }
        }
        .onChange(of: sidePickerItem) { newItem in
            Task { await loadPickerItem(newItem, assignTo: $sideImage) }
        }
        .onChange(of: step) { newStep in
            if newStep == .analyzing {
                analyzingStageIndex = 0
                if !analyzeSpinner {
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                        analyzeSpinner = true
                    }
                }
            }
        }
        .onReceive(analyzingTicker) { _ in
            guard step == .analyzing else { return }
            withAnimation(MotionTokens.easeInOut) {
                analyzingStageIndex = (analyzingStageIndex + 1) % analyzingStages.count
            }
        }
        .onAppear {
            startAmbientAnimationsIfNeeded()
        }
        .animation(MotionTokens.springSoft, value: step)
    }

    private var flowBackground: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            RadialGradient(
                colors: [BodyScanPalette.cyan.opacity(ambientPulse ? 0.24 : 0.1), Color.clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 460
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.22), Color.clear, Color.black.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .blendMode(.overlay)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Body Scan")
                    .font(FitFont.heading(size: 30))
                    .foregroundColor(.white)
                Text(step.title)
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.86))
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(FitFont.mono(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.68))
            }

            Spacer()

            HStack(spacing: 8) {
                if step != .intro {
                    headerCircleButton(
                        icon: "chevron.left",
                        tint: .white,
                        action: { goBack() }
                    )
                }
                headerCircleButton(
                    icon: "xmark",
                    tint: Color.white.opacity(0.82),
                    action: { dismiss() }
                )
            }
        }
    }

    private func headerCircleButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.32))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
    }

    private var progressTrack: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let width = max(20, proxy.size.width * stepProgress)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 8)
                    Capsule()
                        .fill(BodyScanPalette.actionGradient)
                        .frame(width: width, height: 8)
                }
            }
            .frame(height: 8)

            HStack(spacing: 0) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(step.rawValue >= item.rawValue ? Color.white : Color.white.opacity(0.35))
                            .frame(width: 6, height: 6)
                        Text(item.shortLabel)
                            .font(FitFont.mono(size: 9, weight: .semibold))
                            .foregroundColor(
                                step.rawValue >= item.rawValue
                                    ? Color.white.opacity(0.94)
                                    : Color.white.opacity(0.52)
                            )
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BodyScanPalette.glassGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var stepProgress: CGFloat {
        CGFloat(step.rawValue + 1) / CGFloat(Step.allCases.count)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .intro:
            introCard
        case .profileSummary:
            profileSummaryCard
        case .frontPhoto:
            VStack(spacing: 12) {
                photoCaptureCard(
                    title: "Front capture",
                    subtitle: "Stand tall, keep arms slightly away from your torso.",
                    image: frontImage,
                    onCamera: { showFrontCamera = true },
                    isFinalStep: false
                )
                photoPickerRow(
                    pickerItem: $frontPickerItem,
                    label: "Import front photo from gallery"
                )
            }
        case .sidePhoto:
            VStack(spacing: 12) {
                photoCaptureCard(
                    title: "Side capture",
                    subtitle: "Turn 90°. Keep posture neutral and arms relaxed.",
                    image: sideImage,
                    onCamera: { showSideCamera = true },
                    isFinalStep: true
                )
                photoPickerRow(
                    pickerItem: $sidePickerItem,
                    label: "Import side photo from gallery"
                )
            }
        case .review:
            reviewCard
        case .analyzing:
            analyzingCard
        case .results:
            resultsCard
        }
    }

    private func scanCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BodyScanPalette.deep.opacity(0.93), BodyScanPalette.ocean.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: BodyScanPalette.cyan.opacity(0.26), radius: 18, x: 0, y: 10)
    }

    private var introCard: some View {
        scanCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Immersive scan mode")
                    .font(FitFont.heading(size: 24))
                    .foregroundColor(.white)
                Text("Two guided photos with consistency checks deliver a tighter body-fat range.")
                    .font(FitFont.body(size: 13))
                    .foregroundColor(Color.white.opacity(0.78))
            }

            scannerHero

            VStack(alignment: .leading, spacing: 8) {
                scanTipRow(icon: "sun.max.fill", text: "Use even lighting and avoid shadows")
                scanTipRow(icon: "figure.stand.line.dotted.figure.stand", text: "Keep full body visible in both frames")
                scanTipRow(icon: "ruler.fill", text: "Keep distance and pose consistent each week")
            }

            scanPrimaryButton(
                title: "Begin setup",
                icon: "arrow.right.circle.fill",
                disabled: false
            ) {
                step = .profileSummary
            }
        }
    }

    private var scannerHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2)
                .frame(width: 152, height: 152)
                .scaleEffect(ambientPulse ? 1.05 : 0.95)

            Circle()
                .stroke(BodyScanPalette.cyan.opacity(0.45), lineWidth: 1)
                .frame(width: 108, height: 108)
                .scaleEffect(ambientPulse ? 0.94 : 1.08)

            Image(systemName: "figure.stand")
                .font(.system(size: 74, weight: .light))
                .foregroundColor(.white.opacity(0.88))

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, BodyScanPalette.cyan.opacity(0.85), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)
                .offset(y: scanLineOffset)
                .shadow(color: BodyScanPalette.cyan.opacity(0.62), radius: 8, x: 0, y: 0)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func scanTipRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BodyScanPalette.mint)
                .frame(width: 20)
            Text(text)
                .font(FitFont.body(size: 12))
                .foregroundColor(Color.white.opacity(0.84))
        }
    }

    private var isMissingRequiredProfileData: Bool {
        guard let weight = Double(weightText), weight > 0 else { return true }
        return false
    }

    private var profileSummaryCard: some View {
        scanCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Calibration profile")
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(.white)
                Text("Auto-loaded from your account so scans remain comparable over time.")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(Color.white.opacity(0.76))
            }

            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                profileMetricTile(title: "Height", value: heightSummaryText, icon: "ruler")
                profileMetricTile(title: "Weight", value: weightSummaryText, icon: "scalemass.fill")
                profileMetricTile(title: "Age", value: ageSummaryText, icon: "person.crop.circle")
                profileMetricTile(title: "Sex", value: sex.title, icon: "figure.2")
                profileMetricTile(title: "Activity", value: activityLevel.title, icon: "figure.run")
                profileMetricTile(title: "Goal", value: goal.title, icon: "target")
            }

            if isMissingRequiredProfileData {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BodyScanPalette.amber)
                    Text("Add your weight in Profile to run a scan.")
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.9))
                }
                .padding(.vertical, 10)

                scanSecondaryButton(title: "Close", icon: "xmark") {
                    dismiss()
                }
            } else {
                scanPrimaryButton(title: "Continue to capture", icon: "arrow.right") {
                    step = .frontPhoto
                }
            }
        }
    }

    private func profileMetricTile(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BodyScanPalette.cyan)
                Text(title)
                    .font(FitFont.body(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.78))
            }

            Text(value)
                .font(FitFont.body(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var heightSummaryText: String {
        let feet = Int(heightFeet) ?? 0
        let inches = Int(heightInches) ?? 0
        guard feet > 0 else { return "—" }
        return "\(feet) ft \(inches) in"
    }

    private var weightSummaryText: String {
        guard let weight = Double(weightText), weight > 0 else { return "—" }
        let rounded = (weight * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) lbs"
        }
        return "\(rounded) lbs"
    }

    private var ageSummaryText: String {
        if let age = Int(ageText), age > 0 { return "\(age)" }
        return "—"
    }

    private static func heightText(from cm: Double?) -> (feet: String, inches: String) {
        guard let cm, cm > 0 else { return ("", "") }
        let totalInches = (cm / 2.54).rounded()
        let feet = Int(totalInches / 12.0)
        let inches = Int(totalInches) - (feet * 12)
        if feet <= 0 { return ("", "") }
        return ("\(feet)", "\(max(0, min(11, inches)))")
    }

    private static func formatWeightInput(_ lbs: Double) -> String {
        let rounded = (lbs * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))"
        }
        return "\(rounded)"
    }

    private func photoCaptureCard(
        title: String,
        subtitle: String,
        image: UIImage?,
        onCamera: @escaping () -> Void,
        isFinalStep: Bool
    ) -> some View {
        scanCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(FitFont.heading(size: 22))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(Color.white.opacity(0.78))
                }
                Spacer()
                captureStatusPill(isCaptured: image != nil)
            }

            captureCanvas(image: image)

            HStack(spacing: 10) {
                scanSecondaryButton(title: "Open camera", icon: "camera.fill", action: onCamera)
                scanPrimaryButton(
                    title: isFinalStep ? "Review quality" : "Next frame",
                    icon: "arrow.right",
                    disabled: image == nil
                ) {
                    if isFinalStep {
                        step = .review
                        Task { await runQualityCheck() }
                    } else {
                        step = .sidePhoto
                    }
                }
            }
        }
    }

    private func captureStatusPill(isCaptured: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isCaptured ? BodyScanPalette.mint : BodyScanPalette.amber)
                .frame(width: 7, height: 7)
            Text(isCaptured ? "Captured" : "Waiting")
                .font(FitFont.mono(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func captureCanvas(image: UIImage?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.black.opacity(0.24)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 68, weight: .light))
                        .foregroundColor(Color.white.opacity(0.8))
                    Text("Align full body in frame")
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.78))
                }
            }

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.42), style: StrokeStyle(lineWidth: 1.5, dash: [8, 7]))

            VStack {
                HStack {
                    scanGuideLabel("Head clear")
                    Spacer()
                    scanGuideLabel("Feet visible")
                }
                Spacer()
            }
            .padding(12)

            if image == nil {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, BodyScanPalette.cyan.opacity(0.84), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 3)
                    .offset(y: scanLineOffset * 0.85)
                    .shadow(color: BodyScanPalette.cyan.opacity(0.65), radius: 8, x: 0, y: 0)
            }
        }
        .frame(height: 324)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func scanGuideLabel(_ text: String) -> some View {
        Text(text)
            .font(FitFont.mono(size: 9, weight: .semibold))
            .foregroundColor(.white.opacity(0.78))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.34))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }

    private func photoPickerRow(
        pickerItem: Binding<PhotosPickerItem?>,
        label: String
    ) -> some View {
        PhotosPicker(
            selection: pickerItem,
            matching: .images
        ) {
            HStack(spacing: 8) {
                Image(systemName: "photo.fill.on.rectangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BodyScanPalette.cyan)
                Text(label)
                    .font(FitFont.body(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var reviewCard: some View {
        scanCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quality gate")
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(.white)
                Text("Review both captures before analysis to improve range accuracy.")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(Color.white.opacity(0.78))
            }

            HStack(spacing: 10) {
                photoPreview(image: frontImage, label: "Front")
                photoPreview(image: sideImage, label: "Side")
            }

            let qualityPercent = max(0, min(100, Int((qualityScore * 100).rounded())))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Readiness")
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.8))
                    Spacer()
                    Text("\(qualityPercent)%")
                        .font(FitFont.mono(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }

                GeometryReader { proxy in
                    let width = proxy.size.width * CGFloat(Double(qualityPercent) / 100.0)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .frame(height: 8)
                        Capsule()
                            .fill(BodyScanPalette.actionGradient)
                            .frame(width: max(10, width), height: 8)
                    }
                }
                .frame(height: 8)
            }

            if qualityIssues.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BodyScanPalette.mint)
                    Text("Frames look clean. You are ready to analyze.")
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.9))
                }
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Retake suggested")
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(BodyScanPalette.amber)
                    ForEach(qualityIssues, id: \.self) { issue in
                        Text("• \(issue)")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(Color.white.opacity(0.84))
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
            }

            HStack(spacing: 10) {
                scanSecondaryButton(title: "Retake", icon: "arrow.uturn.backward") {
                    step = .frontPhoto
                }
                scanPrimaryButton(title: "Analyze scan", icon: "sparkles") {
                    startAnalysis()
                }
            }
        }
    }

    private var analyzingCard: some View {
        scanCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Analyzing your scan")
                    .font(FitFont.heading(size: 24))
                    .foregroundColor(.white)
                Text("Please stay in app while we process your composition estimate.")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(Color.white.opacity(0.8))
            }

            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 12)
                        .frame(width: 124, height: 124)
                    Circle()
                        .trim(from: 0.04, to: 0.72)
                        .stroke(
                            BodyScanPalette.actionGradient,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(analyzeSpinner ? 360 : 0))
                        .frame(width: 124, height: 124)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(analyzingStages[analyzingStageIndex])
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .animation(MotionTokens.easeInOut, value: analyzingStageIndex)
                    SwiftUI.ProgressView(
                        value: Double(analyzingStageIndex + 1),
                        total: Double(analyzingStages.count)
                    )
                    .tint(BodyScanPalette.mint)
                }
            }
        }
    }

    private var resultsCard: some View {
        let latest = result

        return scanCard {
            Text("Scan insights")
                .font(FitFont.heading(size: 24))
                .foregroundColor(.white)

            if let latest {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(BodyScanPalette.heroGradient)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.3), Color.clear],
                                center: .topTrailing,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Estimated body fat")
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.8))
                        Text(latest.bodyFatRangeText)
                            .font(FitFont.heading(size: 36))
                            .foregroundColor(.white)
                        Text("Confidence \(latest.confidence.title)")
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.85))
                    }
                    .padding(16)
                }
                .frame(height: 152)

                HStack(spacing: 10) {
                    resultPill(title: "Maintenance", value: latest.tdeeRangeText, icon: "flame.fill")
                    resultPill(title: "Action", value: latest.action, icon: "target")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Composition estimate")
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.82))

                    compositionBar(
                        title: "Lean mass",
                        value: latest.leanMass,
                        total: max(1, latest.leanMass + latest.fatMass),
                        color: BodyScanPalette.mint
                    )
                    compositionBar(
                        title: "Fat mass",
                        value: latest.fatMass,
                        total: max(1, latest.leanMass + latest.fatMass),
                        color: BodyScanPalette.amber
                    )
                }

                if let previousResult {
                    Text(bodyFatTrendText(latest: latest, previous: previousResult))
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.82))
                        .padding(.vertical, 2)
                }

                if !latest.qualityIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Accuracy notes")
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(BodyScanPalette.amber)
                        ForEach(latest.qualityIssues, id: \.self) { issue in
                            Text("• \(issue)")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(Color.white.opacity(0.84))
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }

                scanPrimaryButton(title: "Done", icon: "checkmark.circle.fill") {
                    dismiss()
                }

                scanSecondaryButton(title: "Retake scan", icon: "camera.rotate") {
                    step = .frontPhoto
                }
            } else {
                Text("No results yet.")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(Color.white.opacity(0.82))
            }
        }
    }

    private func resultPill(title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BodyScanPalette.cyan)
                .padding(7)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(FitFont.body(size: 11))
                    .foregroundColor(Color.white.opacity(0.72))
                Text(value)
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func compositionBar(title: String, value: Double, total: Double, color: Color) -> some View {
        let fraction = max(0.0, min(1.0, value / max(1.0, total)))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(Color.white.opacity(0.78))
                Spacer()
                Text(String(format: "%.0f lb", value))
                    .font(FitFont.mono(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 8)
                    Capsule()
                        .fill(color)
                        .frame(width: max(10, proxy.size.width * fraction), height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    private func photoPreview(image: UIImage?, label: String) -> some View {
        VStack(spacing: 8) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 186)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 150, height: 186)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundColor(Color.white.opacity(0.65))
                    )
            }
            Text(label)
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.76))
        }
        .frame(maxWidth: .infinity)
    }

    private func scanPrimaryButton(
        title: String,
        icon: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(FitFont.body(size: 14, weight: .semibold))
            }
            .foregroundColor(.black.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        disabled
                            ? AnyShapeStyle(Color.white.opacity(0.3))
                            : AnyShapeStyle(BodyScanPalette.actionGradient)
                    )
            )
        }
        .disabled(disabled)
        .opacity(disabled ? 0.7 : 1.0)
    }

    private func scanSecondaryButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(FitFont.body(size: 14, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.92))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func startAmbientAnimationsIfNeeded() {
        guard !startedAnimations else { return }
        startedAnimations = true

        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            ambientPulse = true
        }

        withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
            scanLineOffset = 118
        }
    }

    private func goBack() {
        errorMessage = nil
        if step == .results {
            step = .review
            return
        }
        let previous = Step(rawValue: step.rawValue - 1) ?? .intro
        step = previous
    }

    private func startAnalysis() {
        errorMessage = nil
        let blocking = photoBlockingIssues()
        if !blocking.isEmpty {
            errorMessage = "Add both photos before analyzing."
            qualityIssues = blocking
            return
        }
        step = .analyzing
        analyzingStageIndex = 0

        let generated = buildResult()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            if let generated {
                result = generated
                if let frontImage, let data = frontImage.jpegData(compressionQuality: 0.85) {
                    _ = ProgressPhotoLocalStore.save(
                        imageData: data,
                        userId: userId,
                        remoteURL: nil,
                        date: generated.timestamp,
                        type: "body scan front",
                        category: "misc"
                    )
                }
                if let sideImage, let data = sideImage.jpegData(compressionQuality: 0.85) {
                    _ = ProgressPhotoLocalStore.save(
                        imageData: data,
                        userId: userId,
                        remoteURL: nil,
                        date: generated.timestamp,
                        type: "body scan side",
                        category: "misc"
                    )
                }
                onComplete(generated)
                Haptics.success()
                step = .results
            } else {
                errorMessage = "Check inputs and try again."
                step = .review
            }
        }
    }

    private func photoBlockingIssues() -> [String] {
        var issues: [String] = []
        if frontImage == nil { issues.append("Front photo missing") }
        if sideImage == nil { issues.append("Side photo missing") }
        return issues
    }

    private func runQualityCheck() async {
        let check = await computeQualityIssues()
        await MainActor.run {
            qualityIssues = check.issues
            qualityScore = check.score
        }
    }

    private func computeQualityIssues() async -> (issues: [String], score: Double) {
        var issues: [String] = []
        issues.append(contentsOf: photoBlockingIssues())

        let missingInputs = missingInputIssues()
        issues.append(contentsOf: missingInputs)

        if let frontImage, let score = averageBrightness(for: frontImage), score < 0.25 {
            issues.append("Low light in front photo")
        }
        if let sideImage, let score = averageBrightness(for: sideImage), score < 0.25 {
            issues.append("Low light in side photo")
        }

        let scores = [
            averageBrightness(for: frontImage),
            averageBrightness(for: sideImage)
        ].compactMap { $0 }
        let avg = scores.isEmpty ? 1.0 : (scores.reduce(0, +) / Double(scores.count))
        return (issues, avg)
    }

    private func missingInputIssues() -> [String] {
        var issues: [String] = []
        if Double(heightFeet) == nil && Double(heightInches) == nil { issues.append("Height missing") }
        if Double(weightText) == nil { issues.append("Weight missing") }
        if Int(ageText) == nil { issues.append("Age missing") }
        if sex == .preferNotToSay { issues.append("Sex not provided") }
        return issues
    }

    private func buildResult() -> BodyScanResult? {
        guard let weight = Double(weightText), weight > 0 else { return nil }
        let age = Double(ageText) ?? 30

        var base: Double
        switch sex {
        case .male:
            base = 18
        case .female:
            base = 26
        case .other, .preferNotToSay:
            base = 22
        }

        let ageAdjustment = max(-4, min(6, (age - 30) * 0.2))
        let activityAdjustment: Double
        switch activityLevel {
        case .sedentary: activityAdjustment = 3
        case .lightlyActive: activityAdjustment = 1.5
        case .moderatelyActive: activityAdjustment = 0
        case .veryActive: activityAdjustment = -1.5
        case .extremelyActive: activityAdjustment = -3
        }
        let goalAdjustment: Double
        switch goal {
        case .loseWeight, .loseWeightFast: goalAdjustment = -2
        case .gainWeight: goalAdjustment = 1
        case .maintain: goalAdjustment = 0
        }

        let estimate = max(6, min(45, base + ageAdjustment + activityAdjustment + goalAdjustment))

        let confidence = confidenceLevel()
        let rangeWidth: Double
        switch confidence {
        case .high: rangeWidth = 4
        case .medium: rangeWidth = 6
        case .low: rangeWidth = 8
        }

        let bodyFatLow = max(4, estimate - rangeWidth / 2)
        let bodyFatHigh = min(55, estimate + rangeWidth / 2)

        let fatMass = weight * (estimate / 100.0)
        let leanMass = max(0, weight - fatMass)

        let lbmKg = leanMass * 0.453592
        let bmr = 370 + (21.6 * lbmKg)
        let activityFactor = activityFactorValue()
        let tdee = bmr * activityFactor
        let tdeeLow = tdee * 0.95
        let tdeeHigh = tdee * 1.05

        let action: String
        switch goal {
        case .loseWeight, .loseWeightFast:
            action = "Cut 250 cals to lose fat"
        case .gainWeight:
            action = "Add 250 cals to gain"
        case .maintain:
            action = "Hold maintenance calories"
        }

        let issues = missingInputIssues()
        let result = BodyScanResult(
            id: UUID(),
            timestamp: Date(),
            bodyFatLow: bodyFatLow,
            bodyFatHigh: bodyFatHigh,
            confidence: confidence,
            fatMass: fatMass,
            leanMass: leanMass,
            tdeeLow: tdeeLow,
            tdeeHigh: tdeeHigh,
            action: action,
            qualityIssues: issues,
            qualityScore: qualityScore
        )

        return result
    }

    private func confidenceLevel() -> BodyScanConfidence {
        var score = 1.0
        let missing = missingInputIssues().count
        score -= Double(missing) * 0.12
        if frontImage == nil || sideImage == nil { score -= 0.4 }
        if score >= 0.75 { return .high }
        if score >= 0.5 { return .medium }
        return .low
    }

    private func activityFactorValue() -> Double {
        switch activityLevel {
        case .sedentary: return 1.2
        case .lightlyActive: return 1.375
        case .moderatelyActive: return 1.55
        case .veryActive: return 1.725
        case .extremelyActive: return 1.9
        }
    }

    private func loadPickerItem(_ item: PhotosPickerItem?, assignTo image: Binding<UIImage?>) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    image.wrappedValue = uiImage
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Unable to load photo."
            }
        }
    }

    private func averageBrightness(for image: UIImage?) -> Double? {
        guard let image, let ciImage = CIImage(image: image) else { return nil }
        let context = CIContext(options: nil)
        let extent = ciImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let outputImage = filter.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        return (r + g + b) / 3.0
    }

    private func bodyFatTrendText(latest: BodyScanResult, previous: BodyScanResult) -> String {
        let latestMid = (latest.bodyFatLow + latest.bodyFatHigh) / 2
        let previousMid = (previous.bodyFatLow + previous.bodyFatHigh) / 2
        let diff = latestMid - previousMid
        let direction = diff > 0 ? "up" : "down"
        return String(format: "Since last scan: body fat %@ %.1f%%", direction, abs(diff))
    }
}

private struct BodyScanCameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isPresented: Bool

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
        let parent: BodyScanCameraPicker

        init(parent: BodyScanCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: [UIImage]
    @Binding var isPresented: Bool

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
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image.append(uiImage)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

private struct CheckinChoicePicker<Choice: CaseIterable & Identifiable & RawRepresentable & Hashable>: View
where Choice.RawValue == String {
    let title: String
    @Binding var selection: Choice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)

            Picker(title, selection: $selection) {
                ForEach(Array(Choice.allCases)) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .tint(FitTheme.cardHighlight)
        }
    }
}

private struct CheckinChoiceRow<Choice: CaseIterable & Identifiable & RawRepresentable & Hashable>: View
where Choice.RawValue == String {
    let title: String
    let icon: String
    @Binding var selection: Choice
    
    private func colorForChoice(_ choice: Choice) -> Color {
        switch choice.rawValue {
        case "Missed", "Low":
            return Color(red: 0.92, green: 0.30, blue: 0.25)
        case "On track", "Okay":
            return FitTheme.cardWorkoutAccent
        case "Exceeded", "Great":
            return FitTheme.success
        default:
            return FitTheme.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FitTheme.textSecondary)
                Text(title)
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textPrimary)
            }
            
            HStack(spacing: 8) {
                ForEach(Array(Choice.allCases)) { choice in
                    Button {
                        selection = choice
                        Haptics.light()
                    } label: {
                        Text(choice.rawValue)
                            .font(FitFont.body(size: 12, weight: selection == choice ? .semibold : .regular))
                            .foregroundColor(selection == choice ? .white : FitTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(selection == choice ? colorForChoice(choice) : FitTheme.cardHighlight)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct FocusChip: View {
    let title: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? FitTheme.cardCoachAccent : FitTheme.cardHighlight)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(FitTheme.cardCoachAccent.opacity(isSelected ? 0.3 : 0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

private struct ProgressPhotoGalleryView: View {
    let items: [ProgressTabView.ProgressPhotoItem]
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private enum PhotoCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case starting = "Starting"
        case checkin = "Check-in"
        case misc = "Misc"

        var id: String { rawValue }

        var filterValue: String? {
            switch self {
            case .all: return nil
            case .starting: return "starting"
            case .checkin: return "checkin"
            case .misc: return "misc"
            }
        }
    }

    private enum PhotoRange: String, CaseIterable, Identifiable {
        case all = "All"
        case month = "30d"
        case quarter = "90d"

        var id: String { rawValue }

        var days: Int? {
            switch self {
            case .all: return nil
            case .month: return 30
            case .quarter: return 90
            }
        }
    }
    
    private enum ViewMode: String, CaseIterable, Identifiable {
        case timeline = "Timeline"
        case grid = "Grid"
        
        var id: String { rawValue }
    }

    @State private var selectedCategory: PhotoCategory = .all
    @State private var selectedRange: PhotoRange = .all
    @State private var viewMode: ViewMode = .timeline
    @State private var expandedPhoto: ProgressTabView.ProgressPhotoItem?

    private var filteredItems: [ProgressTabView.ProgressPhotoItem] {
        let categoryFiltered = items.filter { item in
            guard let filterValue = selectedCategory.filterValue else { return true }
            return normalizedCategory(item.category) == filterValue
        }

        guard let days = selectedRange.days else {
            return categoryFiltered
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return categoryFiltered.filter { ($0.date ?? .distantPast) >= cutoff }
    }
    
    // Group photos by date for timeline view
    private var photosByDate: [(date: Date, photos: [ProgressTabView.ProgressPhotoItem])] {
        let grouped = Dictionary(grouping: filteredItems) { item -> Date in
            guard let date = item.date else { return Date.distantPast }
            return Calendar.current.startOfDay(for: date)
        }
        return grouped.sorted { $0.key > $1.key }.map { (date: $0.key, photos: $0.value) }
    }

    private func normalizedCategory(_ value: String?) -> String? {
        guard let value = value?.lowercased() else { return nil }
        return value.replacingOccurrences(of: "-", with: "")
    }
    
    private func formatTimelineDate(_ date: Date) -> String {
        if date == Date.distantPast { return "Unknown Date" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func relativeDate(_ date: Date) -> String {
        if date == Date.distantPast { return "" }
        let calendar = Calendar.current
        let now = Date()
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days) days ago" }
        if days < 30 { return "\(days / 7) week\(days / 7 == 1 ? "" : "s") ago" }
        return "\(days / 30) month\(days / 30 == 1 ? "" : "s") ago"
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    header
                    
                    // Filters card
                    filtersCard
                    
                    // View mode picker
                    viewModePicker
                    
                    // Photos content
                    if viewMode == .timeline {
                        timelineView
                    } else {
                        photosGridCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            
            // Expanded photo overlay
            if let photo = expandedPhoto {
                ExpandedPhotoView(photo: photo) {
                    withAnimation(.spring(response: 0.3)) {
                        expandedPhoto = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.spring(response: 0.3), value: expandedPhoto != nil)
    }
    
    private var header: some View {
        VStack(spacing: 16) {
            // Close button row
            HStack {
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
            
            // Hero section
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(FitTheme.cardNutritionAccent.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(FitTheme.cardNutritionAccent)
                }
                
                Text("Progress Photos")
                    .font(FitFont.heading(size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(FitTheme.textPrimary)
                
                Text("Track your visual progress over time")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var filtersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardNutritionAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text("Filters")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
            }
            
            VStack(spacing: 12) {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(PhotoCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                
                Picker("Range", selection: $selectedRange) {
                    ForEach(PhotoRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(18)
        .background(FitTheme.cardNutrition)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardNutritionAccent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var viewModePicker: some View {
        HStack(spacing: 8) {
            ForEach(ViewMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        viewMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode == .timeline ? "clock.fill" : "square.grid.2x2.fill")
                            .font(.system(size: 12))
                        Text(mode.rawValue)
                            .font(FitFont.body(size: 13, weight: .medium))
                    }
                    .foregroundColor(viewMode == mode ? .white : FitTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(viewMode == mode ? FitTheme.cardNutritionAccent : FitTheme.cardHighlight)
                    .clipShape(Capsule())
                }
            }
            Spacer()
            
            Text("\(filteredItems.count) photos")
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
        }
    }
    
    private var timelineView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if photosByDate.isEmpty {
                emptyStateCard
            } else {
                ForEach(Array(photosByDate.enumerated()), id: \.element.date) { index, group in
                    TimelineDateSection(
                        date: group.date,
                        formattedDate: formatTimelineDate(group.date),
                        relativeDate: relativeDate(group.date),
                        photos: group.photos,
                        isLast: index == photosByDate.count - 1,
                        onPhotoTap: { photo in
                            withAnimation(.spring(response: 0.3)) {
                                expandedPhoto = photo
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var photosGridCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardProgressAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Photos")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("\(filteredItems.count) photos")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            
            if filteredItems.isEmpty {
                emptyStateContent
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filteredItems) { item in
                        GridPhotoTile(item: item) {
                            withAnimation(.spring(response: 0.3)) {
                                expandedPhoto = item
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(FitTheme.cardProgress)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardProgressAccent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(FitTheme.textSecondary.opacity(0.4))
            Text("No photos yet")
                .font(FitFont.heading(size: 18))
                .foregroundColor(FitTheme.textPrimary)
            Text("Add photos during your weekly check-in to track your visual progress")
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    
    private var emptyStateContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(FitTheme.textSecondary.opacity(0.5))
            Text("No photos uploaded yet")
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
            Text("Add photos during your weekly check-in")
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Timeline Date Section
private struct TimelineDateSection: View {
    let date: Date
    let formattedDate: String
    let relativeDate: String
    let photos: [ProgressTabView.ProgressPhotoItem]
    let isLast: Bool
    let onPhotoTap: (ProgressTabView.ProgressPhotoItem) -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline line and dot
            VStack(spacing: 0) {
                Circle()
                    .fill(FitTheme.cardNutritionAccent)
                    .frame(width: 12, height: 12)
                
                if !isLast {
                    Rectangle()
                        .fill(FitTheme.cardNutritionAccent.opacity(0.3))
                        .frame(width: 2)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 12) {
                // Date header
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate)
                        .font(FitFont.heading(size: 16))
                        .foregroundColor(FitTheme.textPrimary)
                    if !relativeDate.isEmpty {
                        Text(relativeDate)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                
                // Photos grid
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(photos) { photo in
                        TimelinePhotoTile(item: photo) {
                            onPhotoTap(photo)
                        }
                    }
                }
                .padding(.bottom, isLast ? 0 : 24)
            }
        }
        .padding(.leading, 4)
    }
}

private struct ProgressPhotoImageLoadError: Error {}

private struct ProgressPhotoImage<Content: View>: View {
    let url: URL
    let content: (AsyncImagePhase) -> Content

    @State private var localPhase: AsyncImagePhase = .empty
    
    init(url: URL, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        if url.isFileURL {
            content(localPhase)
                .task(id: url) {
                    await loadLocalImage()
                }
        } else {
            AsyncImage(url: url, content: content)
        }
    }

    private func loadLocalImage() async {
        await MainActor.run {
            localPhase = .empty
        }

        let data: Data? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: try? Data(contentsOf: url))
            }
        }

        await MainActor.run {
            guard let data, let image = UIImage(data: data) else {
                localPhase = .failure(ProgressPhotoImageLoadError())
                return
            }
            localPhase = .success(Image(uiImage: image))
        }
    }
}

// MARK: - Timeline Photo Tile
private struct TimelinePhotoTile: View {
    let item: ProgressTabView.ProgressPhotoItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ProgressPhotoImage(url: item.imageURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(FitTheme.cardHighlight)
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
                        .fill(FitTheme.cardHighlight)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(FitTheme.textSecondary.opacity(0.5))
                        )
                @unknown default:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(FitTheme.cardHighlight)
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(FitTheme.cardStroke.opacity(0.2), lineWidth: 1)
            )
            .overlay(
                // Type badge
                Group {
                    if let type = item.type, !type.isEmpty {
                        Text(type.capitalized)
                            .font(FitFont.body(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                    }
                }
                .padding(6),
                alignment: .bottomLeading
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grid Photo Tile
private struct GridPhotoTile: View {
    let item: ProgressTabView.ProgressPhotoItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ProgressPhotoImage(url: item.imageURL) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(FitTheme.cardHighlight)
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
                            .fill(FitTheme.cardHighlight)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 20))
                                    .foregroundColor(FitTheme.textSecondary.opacity(0.5))
                            )
                    @unknown default:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(FitTheme.cardHighlight)
                    }
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(FitTheme.cardStroke.opacity(0.2), lineWidth: 1)
                )
                
                if let date = item.date {
                    Text(progressDisplayDateFormatter.string(from: date))
                        .font(FitFont.body(size: 10))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Expanded Photo View
private struct ExpandedPhotoView: View {
    let photo: ProgressTabView.ProgressPhotoItem
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @GestureState private var magnifyBy = 1.0
    
    private var dateText: String {
        guard let date = photo.date else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dateText)
                            .font(FitFont.heading(size: 16))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 8) {
                            if let type = photo.type, !type.isEmpty {
                                Text(type.capitalized)
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            if let category = photo.category, !category.isEmpty {
                                Text("•")
                                    .foregroundColor(.white.opacity(0.5))
                                Text(category.capitalized)
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 20)
                
                // Photo
                ProgressPhotoImage(url: photo.imageURL) { phase in
                    switch phase {
                    case .empty:
                        SwiftUI.ProgressView()
                            .tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale * magnifyBy)
                            .gesture(
                                MagnificationGesture()
                                    .updating($magnifyBy) { value, state, _ in
                                        state = value
                                    }
                                    .onEnded { value in
                                        scale = min(max(scale * value, 1.0), 4.0)
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring(response: 0.3)) {
                                    scale = scale > 1.0 ? 1.0 : 2.0
                                }
                            }
                    case .failure:
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.5))
                            Text("Failed to load image")
                                .font(FitFont.body(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Hint
                Text("Pinch to zoom • Double-tap to zoom in/out")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 40)
            }
        }
    }
}

private struct CheckinResultsView: View {
    let userId: String
    let checkin: WeeklyCheckin
    let previousCheckin: WeeklyCheckin?
    let goal: OnboardingForm.Goal
    let physiquePriority: String?
    let secondaryPriority: String?
    let comparisonPhotoCount: Int
    let overrideSummary: String?
    @Environment(\.dismiss) private var dismiss
    
    private var recap: CheckinRecap {
        let raw = checkin.aiSummary?.raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = checkin.aiSummary?.parsed
        let meta = checkin.aiSummary?.meta
        if let raw, !raw.isEmpty {
            return CheckinRecap(raw: raw, parsed: parsed, meta: meta)
        }
        return CheckinRecap(raw: overrideSummary, parsed: parsed, meta: meta)
    }
    private var fallback: CheckinRecapFallback {
        CheckinRecapFallback(
            goal: goal,
            checkin: checkin,
            previousCheckin: previousCheckin,
            comparisonPhotoCount: comparisonPhotoCount,
            comparisonSource: checkin.aiSummary?.meta?.comparisonSource,
            focusAreas: focusAreas
        )
    }

    private var focusAreas: [String] {
        var areas: [String] = []
        if let primary = physiquePriority?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            areas.append(primary)
        }
        if let secondary = secondaryPriority?.trimmingCharacters(in: .whitespacesAndNewlines),
           !secondary.isEmpty,
           secondary != areas.first {
            areas.append(secondary)
        }
        return areas
    }

    private var comparisonText: String? {
        guard checkin.photos?.isEmpty == false else { return nil }
        return checkinComparisonText(
            source: checkin.aiSummary?.meta?.comparisonSource,
            comparisonPhotoCount: comparisonPhotoCount
        )
    }

    private var displayImprovements: [String] {
        recap.improvements.isEmpty ? fallback.improvements : recap.improvements
    }

    private var displayNeedsWork: [String] {
        recap.needsWork.isEmpty ? fallback.needsWork : recap.needsWork
    }

    private var displayPhotoNotes: [String] {
        recap.photoNotes.isEmpty ? fallback.photoNotes : recap.photoNotes
    }

    private var displayTargets: [String] {
        recap.targets.isEmpty ? fallback.targets : recap.targets
    }

    private var displaySummary: String? {
        if let summary = recap.summary, !summary.isEmpty {
            // Don't show raw JSON as summary
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.first == "{" || trimmed.first == "[" || trimmed.contains("\"improvements\"") {
                return fallback.summary
            }
            return summary
        }
        return fallback.summary
    }

    private var displayCardioSummary: String {
        if let summary = checkin.cardioSummary, !summary.isEmpty {
            return summary
        }
        return fallback.cardioSummary
    }

    private var displayCardioPlan: [String] {
        let plan = checkin.cardioPlan
        if !plan.isEmpty {
            return plan
        }
        return fallback.cardioPlan
    }

    private var shouldShowCardio: Bool {
        goal != .gainWeight
    }
    
    private var checkinDateText: String {
        guard let date = checkin.dateValue else { return "Recent" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    
                    improvementsCard
                    
                    needsWorkCard
                    
                    photoNotesCard
                    
                    targetsCard

                    if shouldShowCardio {
                        cardioCard
                    }

                    if let summary = displaySummary, !summary.isEmpty {
                        summaryCard(text: summary)
                    }

                    chatCard

                    if checkin.macroUpdateSuggested {
                        macroUpdateCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }
    
    private var header: some View {
        VStack(spacing: 16) {
            // Close button row
            HStack {
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
            
            // Hero section
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(FitTheme.cardCoachAccent.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(FitTheme.cardCoachAccent)
                }
                
                Text("Coach Recap")
                    .font(FitFont.heading(size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(FitTheme.textPrimary)
                
                Text("Your check-in from \(checkinDateText)")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var improvementsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardProgressAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text("Improved")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if displayImprovements.isEmpty {
                    recapBulletItem("Consistency stayed strong this week.")
                } else {
                    ForEach(displayImprovements.indices, id: \.self) { index in
                        recapBulletItem(displayImprovements[index])
                    }
                }
            }
        }
        .padding(18)
        .background(FitTheme.cardProgress)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardProgressAccent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var needsWorkCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardReminderAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text("Needs Work")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if displayNeedsWork.isEmpty {
                    recapBulletItem("Focus areas will tighten as more data comes in.")
                } else {
                    ForEach(displayNeedsWork.indices, id: \.self) { index in
                        recapBulletItem(displayNeedsWork[index])
                    }
                }
            }
        }
        .padding(18)
        .background(FitTheme.cardReminder)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardReminderAccent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var photoNotesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardNutritionAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Photo Notes")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    if let context = comparisonText {
                        Text(context)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(displayPhotoNotes.indices, id: \.self) { index in
                    recapBulletItem(displayPhotoNotes[index])
                }
            }
            
            if checkin.photos?.isEmpty == false, !recap.photoFocus.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What I looked at")
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(recap.photoFocus, id: \.self) { area in
                            Text(area)
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(FitTheme.cardHighlight)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(FitTheme.cardNutrition)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardNutritionAccent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var targetsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardWorkoutAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text("Next-Week Targets")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if displayTargets.isEmpty {
                    recapBulletItem("Lock in one small target and repeat it daily.")
                } else {
                    ForEach(displayTargets.indices, id: \.self) { index in
                        recapBulletItem(displayTargets[index])
                    }
                }
            }
        }
        .padding(18)
        .background(FitTheme.cardWorkout)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardWorkoutAccent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardStreakAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text("Cardio Recommendation")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
            }
            
            Text(displayCardioSummary)
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(displayCardioPlan.indices, id: \.self) { index in
                    recapBulletItem(displayCardioPlan[index])
                }
            }
        }
        .padding(18)
        .background(FitTheme.cardStreak)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardStreakAccent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var macroUpdateCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text("Macro Update")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
            }
            
            MacroUpdateActionRow(userId: userId, checkin: checkin, isCompact: false)
        }
        .padding(18)
        .background(FitTheme.cardCoach)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardCoachAccent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func summaryCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "text.quote")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardCoachAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text("Coach Summary")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
            }
            
            Text(text)
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
                .lineSpacing(4)
        }
        .padding(18)
        .background(FitTheme.cardCoach)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardCoachAccent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var chatCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Your Coach")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("Get clarification or ask follow-ups")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            
            RecapChatBox(userId: userId)
        }
        .padding(18)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.accent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func recapBulletItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(FitTheme.textSecondary.opacity(0.5))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
        }
    }
}

// Flow layout for tags
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        
        let height = y + rowHeight
        return (CGSize(width: maxWidth, height: height), frames)
    }
}

private struct CheckinRecap {
    let improvements: [String]
    let needsWork: [String]
    let photoNotes: [String]
    let photoFocus: [String]
    let targets: [String]
    let summary: String?
    let comparisonSource: String?

    var highlights: [String] {
        let ordered = improvements + needsWork + photoNotes + targets
        // Filter out any JSON-looking content that slipped through
        let filtered = ordered.filter { item in
            !item.contains("\"improvements\"") &&
            !item.contains("\"needs work\"") &&
            !item.contains("\"targets\"") &&
            !item.contains("```json") &&
            !item.contains("```") &&
            !(item.trimmingCharacters(in: .whitespacesAndNewlines).first == "{")
        }
        if !filtered.isEmpty {
            return Array(filtered.prefix(3))
        }
        // Don't fall back to summary if it looks like JSON
        if let summary, !summary.isEmpty, !Self.isLikelyJSON(summary) {
            let firstLine = summary.split(separator: "\n").first.map(String.init) ?? summary
            // Extra check on the first line
            if !firstLine.contains("\"improvements\"") && !firstLine.contains("```") {
                return [firstLine]
            }
        }
        return []
    }

    init(raw: String?, parsed: CheckinSummaryParsed? = nil, meta: CheckinSummaryMeta? = nil) {
        comparisonSource = meta?.comparisonSource
        let rawText = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawIsJson = Self.isLikelyJSON(rawText)
        let parsedCandidate = parsed ?? (rawIsJson ? Self.parseRawSummary(rawText) : nil)
        let sanitizedFocus = Self.sanitizeFocus(parsedCandidate?.photoFocus ?? [])
        photoFocus = sanitizedFocus

        if let parsedCandidate {
            let sanitizedImprovements = Self.sanitizeList(parsedCandidate.improvements)
            let sanitizedNeedsWork = Self.sanitizeList(parsedCandidate.needsWork)
            let sanitizedPhotoNotes = Self.sanitizePhotoNotes(parsedCandidate.photoNotes)
            let sanitizedTargets = Self.sanitizeList(parsedCandidate.targets)
            let sanitizedSummary = Self.sanitizeSummary(parsedCandidate.summary)

            if !sanitizedImprovements.isEmpty
                || !sanitizedNeedsWork.isEmpty
                || !sanitizedPhotoNotes.isEmpty
                || !sanitizedTargets.isEmpty
                || (sanitizedSummary?.isEmpty == false) {
                improvements = sanitizedImprovements
                needsWork = sanitizedNeedsWork
                photoNotes = sanitizedPhotoNotes
                targets = sanitizedTargets
                summary = sanitizedSummary
                return
            }
        }

        if rawIsJson {
            improvements = []
            needsWork = []
            photoNotes = []
            targets = []
            summary = nil
            return
        }

        if let parsed,
           !parsed.improvements.isEmpty
            || !parsed.needsWork.isEmpty
            || !parsed.photoNotes.isEmpty
            || !parsed.targets.isEmpty
            || (parsed.summary?.isEmpty == false) {
            improvements = Self.sanitizeList(parsed.improvements)
            needsWork = Self.sanitizeList(parsed.needsWork)
            photoNotes = Self.sanitizePhotoNotes(parsed.photoNotes)
            targets = Self.sanitizeList(parsed.targets)
            summary = Self.sanitizeSummary(parsed.summary)
            return
        }

        guard let raw = rawText,
              !raw.isEmpty
        else {
            improvements = []
            needsWork = []
            photoNotes = []
            targets = []
            summary = nil
            return
        }

        var current: Section?
        var improvements: [String] = []
        var needsWork: [String] = []
        var photoNotes: [String] = []
        var targets: [String] = []
        var summaryLines: [String] = []
        var extras: [String] = []

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()

            if lower.hasPrefix("improvements") || lower.hasPrefix("improved") || lower.hasPrefix("what improved") {
                current = .improvements
                continue
            }
            if lower.hasPrefix("needs work") || lower.hasPrefix("needs") || lower.hasPrefix("still needs") {
                current = .needsWork
                continue
            }
            if lower.hasPrefix("photo comparison") || lower.hasPrefix("photo notes")
                || lower.hasPrefix("photo analysis") || lower.hasPrefix("visual changes") {
                current = .photoNotes
                continue
            }
            if lower.hasPrefix("next week") || lower.hasPrefix("next-week") || lower.hasPrefix("targets") {
                current = .targets
                continue
            }
            if lower.hasPrefix("coach recap") || lower == "recap" || lower.hasPrefix("summary") {
                current = .summary
                continue
            }

            let cleaned = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
            guard !cleaned.isEmpty else { continue }

            switch current {
            case .improvements:
                improvements.append(cleaned)
            case .needsWork:
                needsWork.append(cleaned)
            case .photoNotes:
                photoNotes.append(cleaned)
            case .targets:
                targets.append(cleaned)
            case .summary:
                summaryLines.append(cleaned)
            case .none:
                extras.append(cleaned)
            }
        }

        self.improvements = Self.sanitizeList(improvements)
        self.needsWork = Self.sanitizeList(needsWork)
        self.photoNotes = Self.sanitizePhotoNotes(photoNotes)
        self.targets = Self.sanitizeList(targets)
        if !summaryLines.isEmpty {
            summary = Self.sanitizeSummary(summaryLines.joined(separator: "\n"))
        } else if !extras.isEmpty {
            summary = Self.sanitizeSummary(extras.joined(separator: "\n"))
        } else {
            summary = nil
        }
    }

    private enum Section {
        case improvements
        case needsWork
        case photoNotes
        case targets
        case summary
    }

    private static func parseRawSummary(_ raw: String?) -> CheckinSummaryParsed? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }
        guard let startIndex = raw.firstIndex(of: "{"),
              let endIndex = raw.lastIndex(of: "}")
        else {
            return nil
        }
        let jsonString = String(raw[startIndex...endIndex])
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CheckinSummaryParsed.self, from: data)
    }

    private static func isLikelyJSON(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Direct JSON
        if trimmed.first == "{" || trimmed.first == "[" {
            return true
        }
        // JSON in markdown code blocks
        if trimmed.hasPrefix("```") && trimmed.contains("{") {
            return true
        }
        // JSON-like content patterns
        if trimmed.contains("\"improvements\":") || 
           trimmed.contains("\"needs work\":") ||
           trimmed.contains("\"needs_work\":") ||
           trimmed.contains("\"photo notes\":") ||
           trimmed.contains("\"photo_notes\":") ||
           trimmed.contains("\"targets\":") ||
           trimmed.contains("\"summary\":") {
            return true
        }
        return false
    }

    private static func sanitizeFocus(_ focus: [String]) -> [String] {
        focus
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !containsTechnicalLanguage($0) }
    }

    private static func sanitizeList(_ items: [String]) -> [String] {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { casualizeLine($0) }
            .filter { !isBlockedLine($0) }
    }

    private static func sanitizePhotoNotes(_ notes: [String]) -> [String] {
        notes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { casualizeLine($0) }
            .filter { !isBlockedLine($0) }
            .filter { !containsTechnicalLanguage($0) }
    }

    private static func sanitizeSummary(_ summary: String?) -> String? {
        guard let summary else { return nil }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lineParts = trimmed.split(whereSeparator: { $0 == "\n" })
        let sentenceParts = lineParts.flatMap { line in
            line.split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
        }
        let cleaned = sentenceParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { casualizeLine($0) }
            .filter { !isBlockedLine($0) }
        guard !cleaned.isEmpty else { return nil }
        return cleaned.joined(separator: ". ")
    }

    private static func isBlockedLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let blocked = [
            "cardio",
            "lighting",
            "camera",
            "same angle",
            "retake",
            "re-take",
            "repeat photo"
        ]
        if blocked.contains(where: { lower.contains($0) }) {
            return true
        }
        return false
    }

    private static func containsTechnicalLanguage(_ line: String) -> Bool {
        let lower = line.lowercased()
        let technical = [
            "alignment",
            "symmetry",
            "asymmetry",
            "posture",
            "tilt",
            "rotation",
            "pelvic",
            "scap",
            "lordosis",
            "kyphosis",
            "imbalance",
            "structural"
        ]
        return technical.contains(where: { lower.contains($0) })
    }

    private static func casualizeLine(_ line: String) -> String {
        var updated = line
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "calorie intake", with: "calories")
            .replacingOccurrences(of: "calories intake", with: "calories")
            .replacingOccurrences(of: "body fat", with: "leanness")
            .replacingOccurrences(of: "development", with: "size")

        if updated.contains(" - ") {
            let parts = updated.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                let left = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedRight = right
                    .replacingOccurrences(of: "appears", with: "looks")
                    .replacingOccurrences(of: "showing", with: "looks")
                updated = "\(left) \(normalizedRight)"
            }
        }

        updated = updated
            .replacingOccurrences(of: "rear deltoid", with: "rear shoulders")
            .replacingOccurrences(of: "deltoid", with: "shoulders")
            .replacingOccurrences(of: "lat engagement", with: "upper back activation")
            .replacingOccurrences(of: "lats", with: "upper back")
        return updated.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CheckinRecapFallback {
    let goal: OnboardingForm.Goal
    let checkin: WeeklyCheckin
    let previousCheckin: WeeklyCheckin?
    let comparisonPhotoCount: Int
    let comparisonSource: String?
    let focusAreas: [String]

    private var hasPhotos: Bool {
        checkin.photos?.isEmpty == false
    }

    private var weightDelta: Double? {
        guard let current = checkin.weight,
              let previous = previousCheckin?.weight else {
            return nil
        }
        return current - previous
    }

    var improvements: [String] {
        var items: [String] = []
        if let delta = weightDelta {
            switch goal {
            case .loseWeight, .loseWeightFast where delta < -0.1:
                items.append("Scale down \(formatDelta(delta)) lb since last check-in.")
            case .gainWeight where delta > 0.1:
                items.append("Scale up \(formatDelta(delta)) lb since last check-in.")
            case .maintain where abs(delta) <= 0.6:
                items.append("Weight steady within \(formatDelta(delta)) lb week-over-week.")
            default:
                break
            }
        }
        if hasPhotos {
            items.append("Check-in photos logged for consistent comparisons.")
        }
        if checkin.weight != nil {
            items.append("Weight logged on check-in day.")
        }
        if items.isEmpty {
            items.append("Consistency stayed strong with a full check-in logged.")
        }
        return unique(items).prefix(3).map { $0 }
    }

    var needsWork: [String] {
        var items: [String] = []
        if let delta = weightDelta {
            switch goal {
            case .loseWeight, .loseWeightFast where delta >= 0.1:
                items.append("Scale up \(formatDelta(delta)) lb; tighten calories or steps.")
            case .gainWeight where delta <= -0.1:
                items.append("Scale down \(formatDelta(delta)) lb; add a small surplus.")
            case .maintain where abs(delta) > 0.8:
                items.append("Weight swung \(formatDelta(delta)) lb; aim for steadier intake.")
            default:
                break
            }
        }
        if !hasPhotos {
            items.append("Add front/side/back photos next check-in for clearer visual deltas.")
        }
        if items.isEmpty {
            items.append("Keep steps and protein consistent to sharpen trends.")
        }
        return unique(items).prefix(3).map { $0 }
    }

    var photoNotes: [String] {
        if !hasPhotos {
            return [
                "Add front, side, and back photos next check-in.",
                "That gives your coach the best look at weekly changes."
            ]
        }
        if let delta = weightDelta {
            switch goal {
            case .loseWeight, .loseWeightFast where delta < -0.1:
                return [
                    "Midsection looks a bit tighter this week.",
                    "Abs look a touch more defined."
                ]
            case .loseWeight, .loseWeightFast where delta > 0.1:
                return [
                    "Midsection looks a little softer than last week.",
                    "Let’s tighten food consistency this week."
                ]
            case .gainWeight where delta > 0.1:
                return [
                    "Arms and shoulders look a bit fuller.",
                    "Upper body looks thicker."
                ]
            case .gainWeight where delta < -0.1:
                return [
                    "Upper body looks a bit flatter than last week.",
                    "We can push food consistency to add size."
                ]
            case .maintain where abs(delta) <= 0.6:
                return [
                    "Shape looks consistent this week.",
                    "Definition looks steady."
                ]
            default:
                return [
                    "Your look is trending in the right direction.",
                    "We can sharpen it with consistent training and meals."
                ]
            }
        }
        return [
            "Your look is trending in the right direction.",
            "Consistency will keep the changes coming."
        ]
    }

    var targets: [String] {
        var items: [String] = []
        if let primary = focusAreas.first {
            items.append("Add 2-4 extra hard sets for \(primary) this week.")
        }
        if focusAreas.count > 1 {
            items.append("Keep 1-2 extra sets for \(focusAreas[1]) each session.")
        }
        switch goal {
        case .loseWeight, .loseWeightFast:
            items.append("Hit your macros at least 5 days this week.")
            items.append("Log meals before the day ends.")
        case .gainWeight:
            items.append("Add one extra snack or shake daily.")
            items.append("Hit protein every day.")
        case .maintain:
            items.append("Hit protein and calories 5 days this week.")
            items.append("Keep training 3-4 sessions.")
        }
        items.append("Sleep 7+ hours for better recovery.")
        items.append("Keep daily steps consistent.")
        return items.prefix(3).map { $0 }
    }

    var summary: String {
        var lines: [String] = []
        if let delta = weightDelta {
            switch goal {
            case .loseWeight, .loseWeightFast:
                lines.append(delta < -0.1 ? "Weight trend is moving down." : "Weight trend is flat to up.")
            case .gainWeight:
                lines.append(delta > 0.1 ? "Weight trend is moving up." : "Weight trend is flat to down.")
            case .maintain:
                lines.append(abs(delta) <= 0.6 ? "Weight is steady this week." : "Weight moved outside the ideal range.")
            }
        } else {
            lines.append("Solid check-in logged.")
        }
        if let firstTarget = targets.first {
            lines.append("Next week: \(firstTarget)")
        }
        return lines.joined(separator: " ")
    }

    var highlights: [String] {
        let combined = improvements + needsWork + targets
        if !combined.isEmpty {
            return Array(combined.prefix(3))
        }
        return []
    }

    var cardioSummary: String {
        switch goal {
        case .loseWeight, .loseWeightFast:
            return "Cardio will support a steady calorie deficit without draining recovery."
        case .gainWeight:
            return "Cardio stays optional while you focus on surplus and strength."
        case .maintain:
            return "Light cardio keeps conditioning up while you maintain."
        }
    }

    var cardioPlan: [String] {
        switch goal {
        case .loseWeight, .loseWeightFast:
            return [
                "2-3 sessions · 20 min incline walk",
                "1 session · 10 min bike finisher"
            ]
        case .gainWeight:
            return []
        case .maintain:
            return [
                "2 sessions · 15 min easy cardio",
                "Optional 1 short finisher after lifting"
            ]
        }
    }

    private func formatDelta(_ value: Double) -> String {
        String(format: "%.1f", abs(value))
    }

    private func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { item in
            if seen.contains(item) {
                return false
            }
            seen.insert(item)
            return true
        }
    }
}

private struct RecapSectionCard: View {
    let title: String
    let items: [String]
    let fallback: String

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(FitFont.body(size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                if items.isEmpty {
                    Text(fallback)
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items.indices, id: \.self) { index in
                            Text("• \(items[index])")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

private struct RecapTextCard: View {
    let title: String
    let text: String

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(FitFont.body(size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                Text(text)
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }
}

private struct RecapPhotoAnalysisCard: View {
    let notes: [String]
    let focus: [String]
    let comparisonText: String?
    let hasPhoto: Bool

    private var contextText: String? {
        if let comparisonText, !comparisonText.isEmpty {
            return comparisonText
        }
        return hasPhoto ? "Coach is looking at your latest check-in photos." : nil
    }

    private var focusAreas: [String] {
        if !focus.isEmpty {
            return focus
        }
        return [
            "Midsection and waist",
            "Arms and shoulders",
            "Upper back",
            "Overall definition",
            "Leg shape",
        ]
    }

    private var fallbackNotes: [String] {
        if !hasPhoto {
            return [
                "Add front, side, and back photos next check-in.",
                "That gives your coach the best look at weekly changes."
            ]
        }
        return [
            "I looked for changes in definition and overall shape.",
            "Most noticeable areas tend to be the waist and arms.",
            "We will keep tracking the big shifts week to week."
        ]
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("Photo notes")
                    .font(FitFont.body(size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                if let contextText {
                    Text(contextText)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }

                let displayNotes = notes.isEmpty ? fallbackNotes : notes
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displayNotes.indices, id: \.self) { index in
                        Text("• \(displayNotes[index])")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }

                if hasPhoto {
                    Text("What I looked at")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(focusAreas.indices, id: \.self) { index in
                            Text("• \(focusAreas[index])")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

private struct CardioUpdateCard: View {
    let summary: String
    let plan: [String]

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cardio recommendation")
                    .font(FitFont.body(size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                Text(summary)
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.indices, id: \.self) { index in
                        Text("• \(plan[index])")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
            }
        }
    }
}

private struct MacroUpdateCard: View {
    let userId: String
    let checkin: WeeklyCheckin

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Macro update")
                    .font(FitFont.body(size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                MacroUpdateActionRow(userId: userId, checkin: checkin, isCompact: false)
            }
        }
    }
}

private struct MacroUpdateActionRow: View {
    let userId: String
    let checkin: WeeklyCheckin
    let isCompact: Bool

    @State private var isApplying = false
    @State private var statusMessage: String?
    @State private var appliedOverride = false

    private var suggestedMacros: MacroTotals? {
        checkin.suggestedMacros
    }

    private var deltaSummary: String? {
        guard let delta = checkin.macroDeltaTotals else { return nil }
        let items = [
            formatDelta(label: "Calories", value: delta.calories, unit: "kcal"),
            formatDelta(label: "Protein", value: delta.protein, unit: "g"),
            formatDelta(label: "Carbs", value: delta.carbs, unit: "g"),
            formatDelta(label: "Fats", value: delta.fats, unit: "g"),
        ].compactMap { $0 }
        guard !items.isEmpty else { return nil }
        return "Change: " + items.joined(separator: " · ")
    }

    private var isApplied: Bool {
        appliedOverride || (checkin.macroUpdate?.applied ?? false)
    }

    var body: some View {
        if checkin.macroUpdateSuggested {
            VStack(alignment: .leading, spacing: 8) {
                if let macros = suggestedMacros {
                    if !isCompact {
                        Text("Suggested macros")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    Text(macroSummary(macros))
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)

                    if let deltaSummary, !isCompact {
                        Text(deltaSummary)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    ActionButton(
                        title: isApplied ? "Macros updated" : (isApplying ? "Updating macros..." : "Update macros"),
                        style: isApplied ? .secondary : .primary
                    ) {
                        applyMacros()
                    }
                    .disabled(isApplying || isApplied)
                } else if !isCompact {
                    Text("Macro update suggested. Targets will appear once synced.")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fitAIMacrosUpdated)) { _ in
                appliedOverride = true
            }
        }
    }

    private func macroSummary(_ macros: MacroTotals) -> String {
        let calories = Int(macros.calories.rounded())
        let protein = Int(macros.protein.rounded())
        let carbs = Int(macros.carbs.rounded())
        let fats = Int(macros.fats.rounded())
        return "\(calories) kcal · P \(protein)g · C \(carbs)g · F \(fats)g"
    }

    private func formatDelta(label: String, value: Double, unit: String) -> String? {
        let rounded = Int(value.rounded())
        guard rounded != 0 else { return nil }
        let sign = rounded > 0 ? "+" : ""
        return "\(label) \(sign)\(rounded)\(unit)"
    }

    private func applyMacros() {
        guard let macros = suggestedMacros else {
            statusMessage = "No macro targets available yet."
            return
        }
        guard !userId.isEmpty else {
            statusMessage = "Profile unavailable."
            return
        }
        isApplying = true
        statusMessage = nil
        Task {
            do {
                let payload: [String: Any] = [
                    "macros": [
                        "calories": Int(macros.calories.rounded()),
                        "protein": Int(macros.protein.rounded()),
                        "carbs": Int(macros.carbs.rounded()),
                        "fats": Int(macros.fats.rounded()),
                    ],
                ]
                _ = try await ProfileAPIService.shared.updateProfile(userId: userId, payload: payload)
                NotificationCenter.default.post(name: .fitAIMacrosUpdated, object: nil)
                appliedOverride = true
                statusMessage = "Macros updated across the app."
                Haptics.success()
            } catch {
                statusMessage = error.localizedDescription
            }
            isApplying = false
        }
    }
}

private struct RecapChatBox: View {
    let userId: String

    @StateObject private var viewModel: RecapChatViewModel
    @State private var draft = ""

    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: RecapChatViewModel(userId: userId))
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Talk to your coach")
                    .font(FitFont.body(size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                if !viewModel.messages.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.messages) { message in
                                RecapChatMessageRow(message: message)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }

                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }

                if viewModel.isApplyingAction {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: FitTheme.cardCoachAccent))
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                RecapChatInputBar(
                    text: $draft,
                    isSending: viewModel.isSending
                ) {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    draft = ""
                    Task {
                        await viewModel.send(trimmed)
                    }
                }
            }
        }
    }
}

private struct RecapChatMessageRow: View {
    let message: CoachChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        if message.text.isEmpty {
            EmptyView()
        } else {
            HStack {
                if isUser { Spacer(minLength: 40) }

                Text(message.text)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(isUser ? FitTheme.buttonText : FitTheme.textPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(isUser ? FitTheme.accent : FitTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isUser ? FitTheme.accent : FitTheme.cardStroke, lineWidth: 1)
                    )

                if !isUser { Spacer(minLength: 40) }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
    }
}

private struct RecapChatInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Ask your coach...", text: $text, axis: .vertical)
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textPrimary)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(FitTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FitTheme.cardStroke, lineWidth: 1)
                )
                .submitLabel(.send)
                .onSubmit(onSend)

            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.buttonText)
                    .padding(10)
                    .background(isSending ? FitTheme.cardHighlight : FitTheme.accent)
                    .clipShape(Circle())
            }
            .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

@MainActor
private final class RecapChatViewModel: ObservableObject {
    @Published var messages: [CoachChatMessage] = []
    @Published var isSending = false
    @Published var isApplyingAction = false
    @Published var statusMessage: String?

    private let userId: String
    private var threadId: String?

    init(userId: String) {
        self.userId = userId
    }

    private static let assistantHeadingRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: #"(?m)^\s{0,3}#{1,6}\s+"#)) ?? (try! NSRegularExpression(pattern: #"(?!)"#))
    }()

    private static let assistantListMarkerRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: #"(?m)^\s*(?:[-•*]|\d+\s*[.)])\s+"#)) ?? (try! NSRegularExpression(pattern: #"(?!)"#))
    }()

    private static let assistantWhitespaceRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: #"\s+"#)) ?? (try! NSRegularExpression(pattern: #"(?!)"#))
    }()

    private func sanitizeAssistantText(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(of: "```", with: "")
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "`", with: "")

        text = Self.assistantHeadingRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: ""
        )
        text = Self.assistantListMarkerRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: ""
        )
        text = Self.assistantWhitespaceRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: " "
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func send(_ text: String) async {
        guard !userId.isEmpty else { return }
        statusMessage = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if threadId == nil {
            do {
                let thread = try await ChatAPIService.shared.createThread(
                    userId: userId,
                    title: "AI Coach"
                )
                threadId = thread.id
            } catch {
                statusMessage = "Unable to start recap chat."
                return
            }
        }
        guard let threadId else { return }

        let userMessage = CoachChatMessage(id: UUID().uuidString, role: .user, text: trimmed)
        messages.append(userMessage)

        let assistantId = UUID().uuidString
        messages.append(CoachChatMessage(id: assistantId, role: .assistant, text: ""))
        isSending = true

        do {
            try await ChatAPIService.shared.sendMessageStream(
                userId: userId,
                threadId: threadId,
                content: trimmed
            ) { [weak self] event in
                Task { @MainActor in
                    self?.applyAssistantEvent(event, messageId: assistantId)
                }
            }
        } catch {
            statusMessage = "Unable to send your message."
        }
        isSending = false
    }

    private func applyAssistantEvent(_ event: ChatStreamEvent, messageId: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        switch event {
        case let .delta(text):
            let updated = sanitizeAssistantText(messages[index].text + text)
            messages[index] = CoachChatMessage(id: messageId, role: .assistant, text: updated)
        case let .replace(text):
            messages[index] = CoachChatMessage(id: messageId, role: .assistant, text: sanitizeAssistantText(text))
        case let .coachAction(proposal):
            Task { @MainActor in
                await applyActionProposal(proposal)
            }
        }
    }

    private func applyActionProposal(_ proposal: CoachActionProposal) async {
        guard !isApplyingAction else { return }
        isApplyingAction = true
        defer { isApplyingAction = false }

        statusMessage = proposal.actionType == .updateMacros ? "Updating macro targets..." : "Applying coach update..."
        do {
            let resultMessage = try await CoachActionExecutor.apply(proposal: proposal, userId: userId)
            messages.append(
                CoachChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    text: sanitizeAssistantText(resultMessage)
                )
            )
            statusMessage = "Changes applied."
            Haptics.success()
        } catch {
            statusMessage = error.localizedDescription
            Haptics.error()
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FitFont.body(size: 18))
                .fontWeight(.semibold)
                .foregroundColor(FitTheme.textPrimary)
            Text(subtitle)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)
        }
    }
}

private struct StatBlock: View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private enum ActionButtonStyle {
    case primary
    case secondary
}

private struct ActionButton: View {
    let title: String
    let style: ActionButtonStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FitFont.body(size: 14))
                .fontWeight(.semibold)
                .foregroundColor(style == .primary ? FitTheme.buttonText : FitTheme.textPrimary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background {
                    if style == .primary {
                        FitTheme.primaryGradient
                    } else {
                        FitTheme.cardBackground
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(style == .secondary ? FitTheme.cardStroke : Color.clear, lineWidth: 1)
                )
                .shadow(color: style == .primary ? FitTheme.buttonShadow : .clear, radius: 12, x: 0, y: 6)
        }
    }
}

private struct CardContainer<Content: View>: View {
    var isAccented: Bool
    @ViewBuilder let content: Content
    
    init(
        isAccented: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.isAccented = isAccented
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isAccented ? FitTheme.cardProgress : FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isAccented ? FitTheme.cardProgressAccent.opacity(0.3) : FitTheme.cardStroke.opacity(0.6), lineWidth: isAccented ? 1.5 : 1)
            )
            .shadow(color: isAccented ? FitTheme.cardProgressAccent.opacity(0.15) : FitTheme.shadow, radius: 18, x: 0, y: 10)
    }
}

// MARK: - Physique Goals Onboarding View
private struct PhysiqueGoalsOnboardingView: View {
    enum Step {
        case welcome
        case primaryGoal
        case secondaryGoals
        case customDescription
        case review
    }
    
    let userId: String
    let profileGoal: OnboardingForm.Goal
    let profileSex: OnboardingForm.Sex
    let onComplete: (String, [String], String?) async -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: Step = .welcome
    @State private var selectedPrimaryGoal: String?
    @State private var selectedSecondaryGoals: Set<String> = []
    @State private var customDescription: String = ""
    @State private var showCustomInput = false
    
    // Primary goals (broad physique objectives)
    private var primaryGoalOptions: [String] {
        switch profileSex {
        case .female:
            switch profileGoal {
            case .loseWeight, .loseWeightFast:
                return [
                    "Get lean & toned all over",
                    "Build visible muscle definition",
                    "Lose fat while maintaining muscle",
                    "Achieve athletic physique",
                    "Custom goal..."
                ]
            case .gainWeight:
                return [
                    "Build muscle mass throughout body",
                    "Gain size & strength",
                    "Develop hourglass shape",
                    "Build athletic powerful physique",
                    "Custom goal..."
                ]
            case .maintain:
                return [
                    "Maintain lean toned physique",
                    "Enhance muscle definition",
                    "Improve overall body composition",
                    "Stay athletic & fit",
                    "Custom goal..."
                ]
            }
        case .male:
            switch profileGoal {
            case .loseWeight, .loseWeightFast:
                return [
                    "Get lean with visible abs",
                    "Lose fat while maintaining muscle",
                    "Achieve athletic V-taper",
                    "Gain overall mass",
                    "Custom goal..."
                ]
            case .gainWeight:
                return [
                    "Build mass throughout upper body",
                    "Get bigger & stronger overall",
                    "Develop V-taper physique",
                    "Build powerful athletic look",
                    "Custom goal..."
                ]
            case .maintain:
                return [
                    "Maintain lean athletic physique",
                    "Enhance muscle definition",
                    "Improve body composition",
                    "Stay fit & strong",
                    "Custom goal..."
                ]
            }
        case .other, .preferNotToSay:
            return [
                "Build overall muscle mass",
                "Get lean & defined",
                "Achieve athletic physique",
                "Improve body composition",
                "Custom goal..."
            ]
        }
    }
    
    // Secondary goals (specific body areas)
    private var secondaryGoalOptions: [String] {
        switch profileSex {
        case .female:
            return [
                "Build stronger glutes",
                "Tone & shape legs",
                "Develop shoulder definition",
                "Build lean arms",
                "Sculpt back muscles",
                "Define core & abs",
                "Lift & shape chest"
            ]
        case .male:
            return [
                "Bigger chest",
                "Wider back & lats",
                "Broader shoulders",
                "Bigger arms",
                "Defined abs & core",
                "Stronger legs",
                "Thicker traps & neck"
            ]
        case .other, .preferNotToSay:
            return [
                "Build upper body",
                "Build lower body",
                "Core & abs",
                "Arms",
                "Shoulders",
                "Back",
                "Chest"
            ]
        }
    }
    
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    
                    switch currentStep {
                    case .welcome:
                        welcomeStep
                    case .primaryGoal:
                        primaryGoalStep
                    case .secondaryGoals:
                        secondaryGoalsStep
                    case .customDescription:
                        customDescriptionStep
                    case .review:
                        reviewStep
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .onTapGesture {
            dismissKeyboard()
        }
    }
    
    private var header: some View {
        HStack {
            if currentStep != .welcome {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(FitTheme.cardHighlight)
                        .clipShape(Circle())
                }
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
    }
    
    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Hero section
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [FitTheme.cardCoachAccent.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [FitTheme.cardCoachAccent, FitTheme.cardCoachAccent.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: FitTheme.cardCoachAccent.opacity(0.3), radius: 18, x: 0, y: 10)
                    
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 8)
                
                Text("Let's Tailor Your Experience")
                    .font(FitFont.heading(size: 32))
                    .fontWeight(.bold)
                    .foregroundColor(FitTheme.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text("Answer a few questions so your AI coach can give you goal-specific feedback every week.")
                    .font(FitFont.body(size: 16))
                    .foregroundColor(FitTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            
            // Benefits
            VStack(alignment: .leading, spacing: 16) {
                benefitRow(
                    icon: "target",
                    title: "Goal-Focused Feedback",
                    description: "Get recommendations aligned with YOUR specific physique goals"
                )
                
                benefitRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Personalized Progress Tracking",
                    description: "Track the areas that matter most to you"
                )
                
                benefitRow(
                    icon: "brain.head.profile",
                    title: "Smarter AI Coaching",
                    description: "Your coach will understand exactly what you're working toward"
                )
            }
            .padding(.top, 8)
            
            Spacer(minLength: 32)
            
            // Continue button
            Button(action: { withAnimation { currentStep = .primaryGoal } }) {
                HStack(spacing: 10) {
                    Text("Get Started")
                        .font(FitFont.body(size: 16, weight: .bold))
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [FitTheme.cardCoachAccent, FitTheme.cardCoachAccent.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: FitTheme.cardCoachAccent.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
            Text("Takes about 2 minutes • Asked only once")
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private var primaryGoalStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("What's Your Main Physique Goal?")
                    .font(FitFont.heading(size: 28))
                    .foregroundColor(FitTheme.textPrimary)
                
                Text("Choose the broad objective that best describes what you want to achieve with your body.")
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textSecondary)
            }
            
            VStack(spacing: 12) {
                ForEach(primaryGoalOptions, id: \.self) { option in
                    GoalOptionButton(
                        title: option,
                        isSelected: selectedPrimaryGoal == option,
                        accentColor: FitTheme.cardCoachAccent
                    ) {
                        if option == "Custom goal..." {
                            selectedPrimaryGoal = option
                            showCustomInput = true
                        } else {
                            selectedPrimaryGoal = option
                            showCustomInput = false
                        }
                    }
                }
            }
            
            if showCustomInput {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe your goal")
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    TextEditor(text: $customDescription)
                        .font(FitFont.body(size: 15))
                        .foregroundColor(FitTheme.textPrimary)
                        .frame(height: 100)
                        .padding(12)
                        .background(FitTheme.cardHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(FitTheme.cardCoachAccent.opacity(0.3), lineWidth: 1)
                        )
                    
                    Text("Example: \"Build upper body mass, especially chest and shoulders\"")
                        .font(FitFont.body(size: 11))
                        .foregroundColor(FitTheme.textSecondary.opacity(0.7))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            Spacer(minLength: 24)
            
            Button(action: { withAnimation { currentStep = .secondaryGoals } }) {
                HStack(spacing: 8) {
                    Text("Continue")
                        .font(FitFont.body(size: 16, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    selectedPrimaryGoal != nil
                        ? LinearGradient(
                            colors: [FitTheme.cardCoachAccent, FitTheme.cardCoachAccent.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [FitTheme.textSecondary.opacity(0.3), FitTheme.textSecondary.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(
                    color: selectedPrimaryGoal != nil ? FitTheme.cardCoachAccent.opacity(0.3) : .clear,
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
            .disabled(selectedPrimaryGoal == nil)
        }
    }
    
    private var secondaryGoalsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Target Specific Areas")
                    .font(FitFont.heading(size: 28))
                    .foregroundColor(FitTheme.textPrimary)
                
                Text("Select up to 3 specific body areas you want to focus on. Your coach will track progress in these areas.")
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textSecondary)
            }
            
            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(secondaryGoalOptions, id: \.self) { option in
                    GoalChipButton(
                        title: option,
                        isSelected: selectedSecondaryGoals.contains(option),
                        isDisabled: !selectedSecondaryGoals.contains(option) && selectedSecondaryGoals.count >= 3,
                        accentColor: FitTheme.cardProgressAccent
                    ) {
                        if selectedSecondaryGoals.contains(option) {
                            selectedSecondaryGoals.remove(option)
                        } else if selectedSecondaryGoals.count < 3 {
                            selectedSecondaryGoals.insert(option)
                        }
                    }
                }
            }
            
            if !selectedSecondaryGoals.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(FitTheme.cardProgressAccent)
                    Text("\(selectedSecondaryGoals.count) area\(selectedSecondaryGoals.count == 1 ? "" : "s") selected")
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                }
            }
            
            Spacer(minLength: 24)
            
            VStack(spacing: 12) {
                Button(action: { withAnimation { currentStep = .customDescription } }) {
                    HStack(spacing: 8) {
                        Text("Continue")
                            .font(FitFont.body(size: 16, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        !selectedSecondaryGoals.isEmpty
                            ? LinearGradient(
                                colors: [FitTheme.cardProgressAccent, FitTheme.cardProgressAccent.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [FitTheme.textSecondary.opacity(0.3), FitTheme.textSecondary.opacity(0.2)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(
                        color: !selectedSecondaryGoals.isEmpty ? FitTheme.cardProgressAccent.opacity(0.3) : .clear,
                        radius: 8,
                        x: 0,
                        y: 4
                    )
                }
                .disabled(selectedSecondaryGoals.isEmpty)
                
                Button(action: { withAnimation { currentStep = .customDescription } }) {
                    Text("Skip for now")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textSecondary)
                        .underline()
                }
            }
        }
    }
    
    private var customDescriptionStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add More Details (Optional)")
                    .font(FitFont.heading(size: 28))
                    .foregroundColor(FitTheme.textPrimary)
                
                Text("Want to add anything else about your goals? Your coach will remember this and reference it in every check-in.")
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textSecondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Your goal description")
                    .font(FitFont.body(size: 13, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                
                TextEditor(text: $customDescription)
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textPrimary)
                    .frame(height: 140)
                    .padding(12)
                    .background(FitTheme.cardHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(FitTheme.cardCoachAccent.opacity(0.3), lineWidth: 1)
                    )
                
                Text("Example: \"I want to build upper body mass, especially chest and shoulders. I'm okay with some body fat gain as long as I'm getting stronger.\"")
                    .font(FitFont.body(size: 11))
                    .foregroundColor(FitTheme.textSecondary.opacity(0.7))
                    .padding(.horizontal, 4)
            }
            
            Spacer(minLength: 24)
            
            VStack(spacing: 12) {
                Button(action: { withAnimation { currentStep = .review } }) {
                    HStack(spacing: 8) {
                        Text("Continue")
                            .font(FitFont.body(size: 16, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [FitTheme.cardCoachAccent, FitTheme.cardCoachAccent.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: FitTheme.cardCoachAccent.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                
                Button(action: { withAnimation { currentStep = .review } }) {
                    Text("Skip for now")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textSecondary)
                        .underline()
                }
            }
        }
    }
    
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review Your Goals")
                    .font(FitFont.heading(size: 28))
                    .foregroundColor(FitTheme.textPrimary)
                
                Text("Here's what your AI coach will focus on during your weekly check-ins.")
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textSecondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                // Primary goal
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 14))
                            .foregroundColor(FitTheme.cardCoachAccent)
                        Text("Main Goal")
                            .font(FitFont.body(size: 13, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    
                    Text(selectedPrimaryGoal ?? "")
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FitTheme.cardCoach)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Secondary goals
                if !selectedSecondaryGoals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "target")
                                .font(.system(size: 14))
                                .foregroundColor(FitTheme.cardProgressAccent)
                            Text("Focus Areas")
                                .font(FitFont.body(size: 13, weight: .semibold))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        
                        ForEach(Array(selectedSecondaryGoals).sorted(), id: \.self) { goal in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(FitTheme.cardProgressAccent)
                                Text(goal)
                                    .font(FitFont.body(size: 15))
                                    .foregroundColor(FitTheme.textPrimary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FitTheme.cardProgress)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                
                // Custom description
                if !customDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "text.quote")
                                .font(.system(size: 14))
                                .foregroundColor(FitTheme.cardNutritionAccent)
                            Text("Additional Details")
                                .font(FitFont.body(size: 13, weight: .semibold))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        
                        Text(customDescription)
                            .font(FitFont.body(size: 15))
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FitTheme.cardNutrition)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.top, 8)
            
            Spacer(minLength: 24)
            
            VStack(spacing: 12) {
                Button(action: saveAndContinue) {
                    HStack(spacing: 10) {
                        Text("Save & Continue to Check-in")
                            .font(FitFont.body(size: 16, weight: .bold))
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [FitTheme.accent, FitTheme.accent.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: FitTheme.accent.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                
                Button(action: { withAnimation { currentStep = .primaryGoal } }) {
                    Text("Edit my goals")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textSecondary)
                        .underline()
                }
            }
        }
    }
    
    private func benefitRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(FitTheme.cardCoachAccent.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FitTheme.cardCoachAccent)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FitFont.body(size: 15, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                Text(description)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }
    
    private func goBack() {
        withAnimation {
            switch currentStep {
            case .primaryGoal:
                currentStep = .welcome
            case .secondaryGoals:
                currentStep = .primaryGoal
            case .customDescription:
                currentStep = .secondaryGoals
            case .review:
                currentStep = .customDescription
            case .welcome:
                break
            }
        }
    }
    
    private func saveAndContinue() {
        guard let primary = selectedPrimaryGoal else { return }
        let secondary = Array(selectedSecondaryGoals)
        let description = customDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            await onComplete(primary, secondary, description.isEmpty ? nil : description)
            dismiss()
        }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct GoalOptionButton: View {
    let title: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? accentColor : FitTheme.cardStroke, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 14, height: 14)
                    }
                }
                
                Text(title)
                    .font(FitFont.body(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? FitTheme.textPrimary : FitTheme.textSecondary)
                
                Spacer()
            }
            .padding(16)
            .background(isSelected ? accentColor.opacity(0.12) : FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? accentColor : FitTheme.cardStroke.opacity(0.6), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct GoalChipButton: View {
    let title: String
    let isSelected: Bool
    let isDisabled: Bool
    let accentColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text(title)
                    .font(FitFont.body(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : (isDisabled ? FitTheme.textSecondary.opacity(0.5) : FitTheme.textPrimary))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? LinearGradient(
                        colors: [accentColor, accentColor.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [FitTheme.cardBackground, FitTheme.cardBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? accentColor : (isDisabled ? FitTheme.cardStroke.opacity(0.3) : FitTheme.cardStroke.opacity(0.6)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? accentColor.opacity(0.2) : .clear,
                radius: 4,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

#Preview {
    ProgressTabView(userId: "demo-user")
        .environmentObject(GuidedTourCoordinator())
}
