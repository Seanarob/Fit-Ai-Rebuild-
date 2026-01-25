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

    @State private var checkins: [WeeklyCheckin] = []
    @State private var progressPhotos: [ProgressPhoto] = []
    @State private var macroAdherence: [MacroAdherenceDay] = []
    @State private var selectedRange: WeightRange = .month
    @State private var macroRange: WeightRange = .month
    @State private var macroMetric: MacroMetric = .calories
    @State private var workoutSessions: [WorkoutSession] = []
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

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    weightTrendCard
                    workoutCalendarCard
                    checkinCard
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
                .padding(.bottom, 32)
            }

            CoachCornerPeek(alignment: .bottomTrailing, title: "Coach")
                .padding(.trailing, 16)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(false)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Progress")
                .font(FitFont.heading(size: 30))
                .fontWeight(.semibold)
                .foregroundColor(FitTheme.textPrimary)

            Text("Track your trends and weekly check-ins.")
                .font(FitFont.body(size: 15))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private var weightTrendCard: some View {
        CardContainer {
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
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.weight)
                        )
                        .foregroundStyle(FitTheme.accent)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.weight)
                        )
                        .foregroundStyle(FitTheme.accent)
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
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Weekly check-in", subtitle: "Log weight, photos, and adherence.")

                HStack(spacing: 14) {
                    StatBlock(title: "Last check-in", value: latestCheckinDateText)
                    StatBlock(title: "Weight", value: latestWeightText)
                }

                ActionButton(title: "Start check-in", style: .primary) {
                    showCheckinFlow = true
                }
            }
        }
    }

    private var photosCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Progress photos", subtitle: "Store your weekly shots.")

                Text("\(photoItems.count) photos logged")
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)

                ActionButton(title: "View progress photos", style: .secondary) {
                    showPhotos = true
                }
            }
        }
    }

    private var resultsCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Coach recap", subtitle: "Latest check-in feedback.")

                let highlights = latestRecapHighlights
                if !highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(highlights.indices, id: \.self) { index in
                            Text("• \(highlights[index])")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                } else {
                    Text(latestCheckinSummary ?? latestFallbackSummary ?? "Your latest check-in is logged.")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                        .lineLimit(4)
                }

                if let context = latestRecapPhotoContext {
                    Text(context)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }

                if let latest = latestCheckin {
                    MacroUpdateActionRow(userId: userId, checkin: latest, isCompact: true)
                }

                ActionButton(title: "View full recap", style: .secondary) {
                    if let latest = latestCheckin {
                        selectedCheckin = latest
                    }
                }
            }
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
        return highlights.isEmpty ? fallback.highlights : highlights
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
        for session in workoutSessions {
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

    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isLoading {
                            Text("Loading workout logs…")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                        }

                        if sessions.isEmpty {
                            Text("No workouts logged.")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                        } else {
                            ForEach(sessions) { session in
                                WorkoutSessionDetailCard(
                                    session: session,
                                    logs: logsBySession[session.id] ?? []
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(progressDisplayDateFormatter.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(FitTheme.textPrimary)
                }
            }
            .task {
                await loadLogs()
            }
        }
    }

    private func loadLogs() async {
        isLoading = true
        var results: [String: [WorkoutSessionLogEntry]] = [:]
        for session in sessions {
            if let logs = try? await WorkoutAPIService.shared.fetchSessionLogs(sessionId: session.id) {
                results[session.id] = logs
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
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.templateTitle ?? "Workout")
                            .font(FitFont.body(size: 16))
                            .foregroundColor(FitTheme.textPrimary)
                        Text(sessionTime)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    Spacer()

                    if let durationSeconds = session.durationSeconds, durationSeconds > 0 {
                        Text("\(durationSeconds / 60)m")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }

                if logs.isEmpty {
                    Text("No exercise logs available.")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                } else {
                    ForEach(logs) { log in
                        let isCardio = log.exerciseName.lowercased().hasPrefix("cardio -")
                        let detailText = cardioDetail(for: log, isCardio: isCardio)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(log.exerciseName)
                                    .font(FitFont.body(size: 14))
                                    .foregroundColor(FitTheme.textPrimary)
                                Text(detailText)
                                    .font(FitFont.body(size: 11))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(FitTheme.cardHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
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
        return "\(log.sets) sets · \(log.reps) reps · \(Int(log.weight)) lb"
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Weekly Check-in")
                    .font(FitFont.heading(size: 28))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                Text("Log weight and adherence.")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
            .font(FitFont.body(size: 14))
            .foregroundColor(FitTheme.textSecondary)
        }
    }

    private var basicsCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Basics", subtitle: "Date and current weight.")

                DatePicker("Check-in date", selection: $checkinDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(FitTheme.cardHighlight)

                labeledField("Current weight (lb)", text: $weightText, keyboard: .decimalPad)
            }
        }
    }

    private var adherenceCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Adherence", subtitle: "How did the week go?")

                CheckinChoicePicker(title: "Workouts hit", selection: $workoutsChoice)
                CheckinChoicePicker(title: "Calories hit", selection: $caloriesChoice)
                CheckinChoicePicker(title: "Sleep quality", selection: $sleepChoice)
                CheckinChoicePicker(title: "Steps hit", selection: $stepsChoice)
                CheckinChoicePicker(title: "Mood", selection: $moodChoice)
            }
        }
    }

    private var photosCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Photos", subtitle: "Add up to three check-in photos.")

                if !selectedImages.isEmpty {
                    photoGrid
                }

                HStack(spacing: 12) {
                    ActionButton(title: "Take photo", style: .secondary) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            isShowingCamera = true
                            cameraError = nil
                        } else {
                            cameraError = "Camera is not available on this device."
                        }
                    }
                    .disabled(selectedImages.count >= 3)

                    PhotosPicker(
                        selection: $photoSelections,
                        maxSelectionCount: max(0, 3 - selectedImages.count),
                        matching: .images
                    ) {
                        Text("Choose photos")
                            .font(FitFont.body(size: 14))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(FitTheme.cardHighlight)
                            .clipShape(Capsule())
                    }
                    .disabled(selectedImages.count >= 3)
                }

                if isLoadingPhotos {
                    Text("Loading photos...")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }

                if let cameraError {
                    Text(cameraError)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                }
            }
        }
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
        VStack(spacing: 12) {
            ActionButton(title: isSubmitting ? "Saving..." : "Submit check-in", style: .primary) {
                Task {
                    await submit()
                }
            }
            .disabled(isSubmitting)
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

private struct ProgressPhotoGalleryView: View {
    let items: [ProgressTabView.ProgressPhotoItem]

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 12),
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

    @State private var selectedCategory: PhotoCategory = .all
    @State private var selectedRange: PhotoRange = .all

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

    private func normalizedCategory(_ value: String?) -> String? {
        guard let value = value?.lowercased() else { return nil }
        return value.replacingOccurrences(of: "-", with: "")
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Progress Photos")
                        .font(FitFont.heading(size: 26))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(PhotoCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(FitTheme.cardHighlight)

                    Picker("Range", selection: $selectedRange) {
                        ForEach(PhotoRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(FitTheme.cardHighlight)

                    Text("\(filteredItems.count) photos")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)

                    if filteredItems.isEmpty {
                        Text("No photos uploaded yet.")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredItems) { item in
                                ProgressPhotoTile(item: item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct ProgressPhotoTile: View {
    let item: ProgressTabView.ProgressPhotoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: item.url)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 16)
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
                    RoundedRectangle(cornerRadius: 16)
                        .fill(FitTheme.cardHighlight)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(FitTheme.textSecondary)
                        )
                @unknown default:
                    RoundedRectangle(cornerRadius: 16)
                        .fill(FitTheme.cardHighlight)
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(item.date.map { progressDisplayDateFormatter.string(from: $0) } ?? "—")
                .font(FitFont.body(size: 11))
                .foregroundColor(FitTheme.textSecondary)

            if let category = formattedCategory {
                Text(category)
                    .font(FitFont.body(size: 11))
                    .foregroundColor(FitTheme.textSecondary)
            }

            if let type = item.type, !type.isEmpty {
                Text(type)
                    .font(FitFont.body(size: 11))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }

    private var formattedCategory: String? {
        guard let category = item.category?.trimmingCharacters(in: .whitespacesAndNewlines),
              !category.isEmpty
        else {
            return nil
        }
        switch category.lowercased() {
        case "checkin", "check-in":
            return "Check-in"
        case "starting":
            return "Starting"
        case "misc":
            return "Misc"
        default:
            return category.replacingOccurrences(of: "_", with: " ").capitalized
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

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Coach Recap")
                        .font(FitFont.heading(size: 26))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    RecapSectionCard(
                        title: "Improved",
                        items: displayImprovements,
                        fallback: "Consistency stayed strong this week."
                    )

                    RecapSectionCard(
                        title: "Needs work",
                        items: displayNeedsWork,
                        fallback: "Focus areas will tighten as more data comes in."
                    )

                    RecapPhotoAnalysisCard(
                        notes: displayPhotoNotes,
                        focus: recap.photoFocus,
                        comparisonText: comparisonText,
                        hasPhoto: (checkin.photos?.isEmpty == false)
                    )

                    RecapSectionCard(
                        title: "Next-week targets",
                        items: displayTargets,
                        fallback: "Lock in one small target and repeat it daily."
                    )

                    if shouldShowCardio {
                        CardioUpdateCard(summary: displayCardioSummary, plan: displayCardioPlan)
                    }

                    if checkin.macroUpdateSuggested {
                        MacroUpdateCard(userId: userId, checkin: checkin)
                    }

                    if let summary = displaySummary, !summary.isEmpty {
                        RecapTextCard(title: "Coach recap", text: summary)
                    }

                    RecapChatBox(userId: userId)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
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
        if !ordered.isEmpty {
            return Array(ordered.prefix(3))
        }
        if let summary, !summary.isEmpty {
            let firstLine = summary.split(separator: "\n").first.map(String.init) ?? summary
            return [firstLine]
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
        return trimmed.first == "{" || trimmed.first == "["
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
            case .loseWeight where delta < -0.1:
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
            case .loseWeight where delta >= 0.1:
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
            case .loseWeight where delta < -0.1:
                return [
                    "Midsection looks a bit tighter this week.",
                    "Abs look a touch more defined."
                ]
            case .loseWeight where delta > 0.1:
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
        case .loseWeight:
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
            case .loseWeight:
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
        case .loseWeight:
            return "Cardio will support a steady calorie deficit without draining recovery."
        case .gainWeight:
            return "Cardio stays optional while you focus on surplus and strength."
        case .maintain:
            return "Light cardio keeps conditioning up while you maintain."
        }
    }

    var cardioPlan: [String] {
        switch goal {
        case .loseWeight:
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

#Preview {
    ProgressTabView(userId: "demo-user")
}
