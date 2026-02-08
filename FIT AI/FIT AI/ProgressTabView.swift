import Charts
import Combine
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
        let id = UUID()
        let url: String
        let date: Date?
        let type: String?
        let category: String?
    }

    let userId: String
    @Binding private var intent: ProgressTabIntent?

    init(userId: String, intent: Binding<ProgressTabIntent?> = .constant(nil)) {
        self.userId = userId
        _intent = intent
    }

    @State private var checkins: [WeeklyCheckin] = []
    @State private var progressPhotos: [ProgressPhoto] = []
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
    @State private var showCheckinFlow = false
    @State private var startingPhotos = StartingPhotosStore.load()
    @State private var profileGoal: OnboardingForm.Goal = .maintain
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

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    checkinCard
                    workoutCalendarCard
                    photosCard
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
        }
        .sheet(isPresented: $showPhotos) {
            ProgressPhotoGalleryView(items: photoItems)
        }
        .sheet(isPresented: $showCheckinFlow) {
            CheckinFlowView(userId: userId) { response in
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
                comparisonPhotoCount: comparisonPhotoCount,
                overrideSummary: override
            )
        }
        .sheet(isPresented: $showWorkoutDetail) {
            if let selectedWorkoutDate {
                WorkoutDayDetailView(
                    date: selectedWorkoutDate,
                    sessions: selectedDaySessions
                )
            }
        }
        .task {
            startingPhotos = StartingPhotosStore.load()
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
                showCheckinFlow = true
            }
            intent = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIStartingPhotosUpdated)) { _ in
            startingPhotos = StartingPhotosStore.load()
        }
        .onChange(of: showWorkoutDetail) { isShowing in
            if !isShowing {
                selectedWorkoutDate = nil
                selectedDaySessions = []
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
                if isCheckinUnlocked {
                    showCheckinFlow = true
                } else {
                    showCheckinLockedSheet = true
                }
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

    private var latestRecapHighlights: [String] {
        guard let latestCheckin else { return [] }
        let fallback = CheckinRecapFallback(
            goal: profileGoal,
            checkin: latestCheckin,
            previousCheckin: previousCheckin(for: latestCheckin),
            comparisonPhotoCount: comparisonPhotoCount,
            comparisonSource: latestCheckin.aiSummary?.meta?.comparisonSource
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
            comparisonSource: latestCheckin.aiSummary?.meta?.comparisonSource
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
        let progressItems = progressPhotos.map { photo in
            let parsedDate = photo.date.flatMap {
                progressAPIDateFormatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
            }
            return ProgressPhotoItem(
                url: photo.url,
                date: parsedDate,
                type: photo.type,
                category: photo.category
            )
        }
        let checkinItems = progressPhotos.isEmpty ? checkins.flatMap { checkin in
            let date = checkin.dateValue
            return (checkin.photos ?? []).map { photo in
                ProgressPhotoItem(url: photo.url, date: date, type: photo.type, category: "checkin")
            }
        } : []
        let startingItems = startingPhotos.entries.map { entry in
            ProgressPhotoItem(
                url: entry.photo.url,
                date: entry.photo.date,
                type: entry.type.title,
                category: "starting"
            )
        }
        return (startingItems + checkinItems + progressItems).sorted { lhs, rhs in
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

    private func formatWeight(_ value: Double) -> String {
        String(format: "%.1f lb", value)
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
            if let profile,
               let preferences = profile["preferences"] as? [String: Any],
               let starting = preferences["starting_photos"],
               let parsed = StartingPhotosState.fromDictionary(starting) {
                StartingPhotosStore.save(parsed)
                startingPhotos = parsed
            }
            if let profile,
               let goalRaw = profile["goal"] as? String,
               let goal = OnboardingForm.Goal(rawValue: goalRaw) {
                profileGoal = goal
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
    let date: Date
    let sessions: [WorkoutSession]

    @Environment(\.dismiss) private var dismiss
    @State private var logsBySession: [String: [WorkoutSessionLogEntry]] = [:]
    @State private var isLoading = false
    @State private var loadError: String?
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
    
    private var totalDuration: Int {
        sessions.reduce(0) { $0 + ($1.durationSeconds ?? 0) } / 60
    }
    
    private var totalExercises: Int {
        logsBySession.values.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    header
                    
                    // Stats summary
                    if !sessions.isEmpty {
                        statsCard
                    }
                    
                    // Sessions
                    if isLoading {
                        loadingCard
                    } else if sessions.isEmpty {
                        emptyStateCard
                    } else {
                        ForEach(sessions) { session in
                            WorkoutSessionDetailCard(
                                session: session,
                                logs: logsBySession[session.id] ?? []
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
        .task {
            await loadLogs()
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
                        .fill(FitTheme.cardWorkoutAccent.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(FitTheme.cardWorkoutAccent)
                }
                
                Text("Workout Log")
                    .font(FitFont.heading(size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(FitTheme.textPrimary)
                
                Text(formattedDate)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }
    
    private var statsCard: some View {
        HStack(spacing: 12) {
            statItem(icon: "clock.fill", value: "\(totalDuration)", label: "minutes")
            statItem(icon: "figure.strengthtraining.traditional", value: "\(sessions.count)", label: sessions.count == 1 ? "session" : "sessions")
            statItem(icon: "list.bullet", value: "\(totalExercises)", label: "exercises")
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
                print("Failed to load logs for session \(session.id): \(error)")
                loadError = "Some workout logs couldn't be loaded"
            }
        }
        await MainActor.run {
            logsBySession = results
            isLoading = false
        }
    }
}

private struct WorkoutSessionDetailCard: View {
    let session: WorkoutSession
    let logs: [WorkoutSessionLogEntry]

    var body: some View {
        let isHealthWorkout = session.isHealthWorkout
        VStack(alignment: .leading, spacing: 16) {
            // Header
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
                    Text(session.templateTitle ?? (isHealthWorkout ? "Apple Health Workout" : "Workout"))
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    HStack(spacing: 8) {
                        Text(sessionTime)
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

            // Exercise list
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
                VStack(spacing: 8) {
                    ForEach(logs) { log in
                        let isCardio = log.exerciseName.lowercased().hasPrefix("cardio -")
                        let detailText = cardioDetail(for: log, isCardio: isCardio)
                        HStack(spacing: 12) {
                            // Exercise icon
                            Image(systemName: isCardio ? "figure.run" : "dumbbell.fill")
                                .font(.system(size: 14))
                                .foregroundColor(FitTheme.cardWorkoutAccent)
                                .frame(width: 28, height: 28)
                                .background(FitTheme.cardWorkoutAccent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(log.exerciseName)
                                    .font(FitFont.body(size: 14, weight: .medium))
                                    .foregroundColor(FitTheme.textPrimary)
                                Text(detailText)
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                            
                            Spacer()
                            
                            // Weight badge for strength exercises
                            if !isCardio && log.weight > 0 {
                                Text("\(Int(log.weight)) lb")
                                    .font(FitFont.body(size: 12, weight: .semibold))
                                    .foregroundColor(FitTheme.cardWorkoutAccent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(FitTheme.cardWorkoutAccent.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(12)
                        .background(FitTheme.cardHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
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

    private var sessionTime: String {
        guard let value = session.createdAt else { return "Unknown time" }
        let date = workoutSessionDateFormatterWithFractional.date(from: value)
            ?? workoutSessionDateFormatter.date(from: value)
        guard let date else { return "Unknown time" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func cardioDetail(for log: WorkoutSessionLogEntry, isCardio: Bool) -> String {
        if isCardio {
            let storedDuration = log.durationMinutes ?? 0
            let minutesValue = storedDuration > 0 ? storedDuration : log.reps
            let minutes = minutesValue > 0 ? "\(minutesValue) min" : "Cardio"
            if let notes = log.notes, !notes.isEmpty {
                return "\(minutes) · \(notes)"
            }
            return minutes
        }
        return "\(log.sets) sets × \(log.reps) reps"
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

    let userId: String
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

    private let fieldBackground = FitTheme.cardHighlight

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
                Task {
                    await submit()
                }
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
            
            Text("Your AI coach will analyze your progress")
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
                errorMessage = error.localizedDescription
                return
            }
            let response = try await ProgressAPIService.shared.submitCheckin(
                userId: userId,
                checkinDate: checkinDate,
                adherence: adherence,
                photos: uploadedPhotos
            )
            await onSubmitSuccess(response)
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
                imageData: data
            )
            if let url = response.photoUrl {
                uploadedPhotos.append(["url": url, "type": type])
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

// MARK: - Timeline Photo Tile
private struct TimelinePhotoTile: View {
    let item: ProgressTabView.ProgressPhotoItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            AsyncImage(url: URL(string: item.url)) { phase in
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
                AsyncImage(url: URL(string: item.url)) { phase in
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
                AsyncImage(url: URL(string: photo.url)) { phase in
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
            comparisonSource: checkin.aiSummary?.meta?.comparisonSource
        )
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

                    if checkin.macroUpdateSuggested {
                        macroUpdateCard
                    }

                    if let summary = displaySummary, !summary.isEmpty {
                        summaryCard(text: summary)
                    }

                    chatCard
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
                        title: isApplied ? "Macros applied" : (isApplying ? "Applying..." : "Accept new macros"),
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
    @Published var statusMessage: String?

    private let userId: String
    private var threadId: String?

    init(userId: String) {
        self.userId = userId
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
            ) { [weak self] chunk in
                Task { @MainActor in
                    self?.appendAssistantChunk(chunk, messageId: assistantId)
                }
            }
        } catch {
            statusMessage = "Unable to send your message."
        }
        isSending = false
    }

    private func appendAssistantChunk(_ chunk: String, messageId: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let updated = messages[index].text + chunk
        messages[index] = CoachChatMessage(id: messageId, role: .assistant, text: updated)
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
                .clipShape(Capsule())
                .overlay(
                    Capsule()
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

#Preview {
    ProgressTabView(userId: "demo-user")
}
