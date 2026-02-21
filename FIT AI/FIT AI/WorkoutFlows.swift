import AVKit
import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

struct WorkoutExerciseDraft: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let muscleGroup: String
    let equipment: String
    var sets: Int
    var reps: Int
    var restSeconds: Int
    var notes: String
}

struct ExerciseDefinition: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let muscleGroups: [String]
    let equipment: [String]
}

struct WorkoutExerciseSession: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var sets: [WorkoutSetEntry]
    var restSeconds: Int
    var warmupRestSeconds: Int = 60
    var notes: String = ""
    var unit: WeightUnit = .lb
    var recommendationPreference: ExerciseRecommendationPreference = .none
}

enum WeightUnit: String, CaseIterable, Identifiable, Hashable {
    case lb
    case kg

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }

    var label: String { rawValue }
}

enum ExerciseRecommendationPreference: String, CaseIterable, Hashable {
    case none
    case moreOften
    case lessOften
    case avoid
}

private enum DragAxis {
    case horizontal
    case vertical
}

struct WorkoutSetEntry: Identifiable, Hashable {
    let id = UUID()
    var reps: String
    var weight: String
    var isComplete: Bool
    var isWarmup: Bool = false
    var isDropSet: Bool = false
}

extension WorkoutSetEntry {
    static func batch(
        reps: String,
        weight: String = "",
        isComplete: Bool = false,
        isWarmup: Bool = false,
        isDropSet: Bool = false,
        count: Int
    ) -> [WorkoutSetEntry] {
        guard count > 0 else { return [] }
        return (0..<count).map { _ in
            WorkoutSetEntry(
                reps: reps,
                weight: weight,
                isComplete: isComplete,
                isWarmup: isWarmup,
                isDropSet: isDropSet
            )
        }
    }
}

struct CardioRecommendation: Identifiable, Hashable {
    let id = UUID()
    let title: String
    var intensity: String
    var durationMinutes: Int
}

extension CardioRecommendation {
    static let defaults: [CardioRecommendation] = [
        CardioRecommendation(title: "Treadmill", intensity: "Moderate", durationMinutes: 15),
        CardioRecommendation(title: "Stairmaster", intensity: "Low", durationMinutes: 10),
        CardioRecommendation(title: "Bike", intensity: "Light", durationMinutes: 19)
    ]
}

struct ExercisePickerModal: View {
    let title: String
    let subtitle: String
    let selectedNames: Set<String>
    let onAdd: (ExerciseDefinition) -> Void
    let onClose: () -> Void

    @State private var searchText = ""
    @State private var selectedMuscleGroups: Set<String> = []
    @State private var selectedEquipment: Set<String> = []
    @State private var catalog: [ExerciseDefinition] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var lastQuery = ""
    @State private var isActive = true
    private let localFallbackCatalog: [ExerciseDefinition] = [
        ExerciseDefinition(name: "Bench Press", muscleGroups: ["chest"], equipment: ["Barbell"]),
        ExerciseDefinition(name: "Incline Dumbbell Press", muscleGroups: ["chest"], equipment: ["Dumbbell"]),
        ExerciseDefinition(name: "Push Up", muscleGroups: ["chest"], equipment: ["Bodyweight"]),
        ExerciseDefinition(name: "Lat Pulldown", muscleGroups: ["back"], equipment: ["Cable"]),
        ExerciseDefinition(name: "Seated Row", muscleGroups: ["back"], equipment: ["Cable"]),
        ExerciseDefinition(name: "Overhead Press", muscleGroups: ["shoulders"], equipment: ["Barbell"]),
        ExerciseDefinition(name: "Lateral Raise", muscleGroups: ["shoulders"], equipment: ["Dumbbell"]),
        ExerciseDefinition(name: "Bicep Curl", muscleGroups: ["arms"], equipment: ["Dumbbell"]),
        ExerciseDefinition(name: "Tricep Pushdown", muscleGroups: ["arms"], equipment: ["Cable"]),
        ExerciseDefinition(name: "Back Squat", muscleGroups: ["legs"], equipment: ["Barbell"]),
        ExerciseDefinition(name: "Leg Press", muscleGroups: ["legs"], equipment: ["Machine"]),
        ExerciseDefinition(name: "Romanian Deadlift", muscleGroups: ["hamstrings"], equipment: ["Barbell"]),
        ExerciseDefinition(name: "Hip Thrust", muscleGroups: ["glutes"], equipment: ["Barbell"]),
        ExerciseDefinition(name: "Plank", muscleGroups: ["core"], equipment: ["Bodyweight"]),
        ExerciseDefinition(name: "Hammer Strength Chest Press", muscleGroups: ["chest", "triceps", "shoulders"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Iso-Lateral Chest Press", muscleGroups: ["chest", "triceps", "shoulders"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Incline Chest Press", muscleGroups: ["upper chest", "triceps", "shoulders"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Iso-Lateral Incline Press", muscleGroups: ["upper chest", "triceps", "shoulders"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Decline Chest Press", muscleGroups: ["lower chest", "triceps", "shoulders"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Chest Fly", muscleGroups: ["chest", "shoulders"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Shoulder Press", muscleGroups: ["shoulders", "triceps"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Iso-Lateral Shoulder Press", muscleGroups: ["shoulders", "triceps"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength High Shoulder Press", muscleGroups: ["front delts", "triceps"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Lat Pulldown", muscleGroups: ["lats", "biceps", "upper back"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Iso-Lateral Lat Pulldown", muscleGroups: ["lats", "biceps", "upper back"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength High Row", muscleGroups: ["upper back", "biceps"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Low Row", muscleGroups: ["mid back", "biceps"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Iso-Lateral Row", muscleGroups: ["mid back", "biceps"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Seated Row", muscleGroups: ["mid back", "biceps"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Assisted Pull-Up", muscleGroups: ["lats", "biceps"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Assisted Dip", muscleGroups: ["triceps", "chest", "shoulders"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Biceps Curl", muscleGroups: ["biceps", "forearms"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Preacher Curl", muscleGroups: ["biceps", "forearms"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Triceps Extension", muscleGroups: ["triceps", "shoulders"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Seated Triceps Press", muscleGroups: ["triceps", "chest"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Leg Press", muscleGroups: ["quads", "glutes", "hamstrings"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Iso-Lateral Leg Press", muscleGroups: ["quads", "glutes", "hamstrings"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Hack Squat", muscleGroups: ["quads", "glutes"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Pendulum Squat", muscleGroups: ["quads", "glutes"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength V-Squat", muscleGroups: ["quads", "glutes"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Leg Extension", muscleGroups: ["quads"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Seated Leg Curl", muscleGroups: ["hamstrings", "glutes"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Lying Leg Curl", muscleGroups: ["hamstrings", "glutes"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Glute Drive", muscleGroups: ["glutes", "hamstrings"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Hip Abduction", muscleGroups: ["glutes"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Hip Adduction", muscleGroups: ["adductors"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Standing Calf Raise", muscleGroups: ["calves"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Ab Crunch", muscleGroups: ["abs"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Rotary Torso", muscleGroups: ["obliques", "abs"], equipment: ["Hammer Strength"]),
        ExerciseDefinition(name: "Hammer Strength Back Extension", muscleGroups: ["lower back", "glutes"], equipment: ["Hammer Strength"])
    ]

    init(
        title: String = "Add Exercise",
        subtitle: String = "Search and filter to build your workout.",
        selectedNames: Set<String>,
        onAdd: @escaping (ExerciseDefinition) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.selectedNames = selectedNames
        self.onAdd = onAdd
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                header

                searchField

                filterSection(title: "Muscle Groups", options: muscleGroups, selections: $selectedMuscleGroups)
                filterSection(title: "Equipment", options: equipment, selections: $selectedEquipment)

                ScrollView {
                    VStack(spacing: 12) {
                        if isLoading {
                            Text("Searching…")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if filteredExercises.isEmpty && !isLoading {
                            Text("No exercises found.")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ForEach(filteredExercises) { exercise in
                            ExercisePickerRow(
                                name: exercise.name,
                                muscleGroup: exercise.muscleGroups.first ?? "General",
                                equipment: exercise.equipment.first ?? "Bodyweight",
                                isAdded: selectedNames.contains(exercise.name),
                                onAdd: { onAdd(exercise) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .padding(.top, 12)
        }
        .onAppear {
            isActive = true
            if catalog.isEmpty {
                searchTask?.cancel()
                searchTask = Task { await performSearch(for: "") }
            }
        }
        .onDisappear {
            isActive = false
            searchTask?.cancel()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(FitTheme.textPrimary)
                Text(subtitle)
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(10)
                    .background(FitTheme.cardBackground)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(FitTheme.textSecondary)
            TextField("Search exercises", text: $searchText)
                .foregroundColor(FitTheme.textPrimary)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .onSubmit {
                    searchTask?.cancel()
                    let snapshot = searchText
                    searchTask = Task {
                        await logSearchEvent("submit query=\"\(snapshot)\"")
                        await performSearch(for: snapshot)
                    }
                }
                .onChange(of: searchText) { newValue in
                    scheduleSearch(for: newValue)
                }
        }
        .padding(12)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    private func filterSection(title: String, options: [String], selections: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        let isSelected = selections.wrappedValue.contains(option)
                        Button {
                            if isSelected {
                                selections.wrappedValue.remove(option)
                            } else {
                                selections.wrappedValue.insert(option)
                            }
                        } label: {
                            Text(option)
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textPrimary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(isSelected ? FitTheme.cardHighlight : FitTheme.cardBackground)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var filteredExercises: [ExerciseDefinition] {
        catalog.filter { exercise in
            let matchesSearch = searchText.isEmpty ||
                exercise.name.lowercased().contains(searchText.lowercased())
            let matchesMuscle = selectedMuscleGroups.isEmpty ||
                !selectedMuscleGroups.isDisjoint(with: exercise.muscleGroups)
            let matchesEquipment = selectedEquipment.isEmpty ||
                !selectedEquipment.isDisjoint(with: exercise.equipment)
            return matchesSearch && matchesMuscle && matchesEquipment
        }
    }

    private var muscleGroups: [String] {
        Array(Set(catalog.flatMap { $0.muscleGroups })).sorted()
    }

    private var equipment: [String] {
        Array(Set(catalog.flatMap { $0.equipment })).sorted()
    }

    @MainActor
    private func performSearch(for query: String) async {
        let safeQuery = String(query)
        let trimmed = safeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        await logSearchEvent("start query=\"\(trimmed)\"")
        guard isActive else { return }
        if trimmed.isEmpty {
            catalog = localFallbackCatalog
            isLoading = false
            lastQuery = ""
            await logSearchEvent("skip empty query")
            return
        }
        if !trimmed.isEmpty {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard !Task.isCancelled else { return }
        isLoading = true
        lastQuery = trimmed
        let start = Date()
        let results = await fetchRemoteExercises(query: trimmed)
        guard !Task.isCancelled else { return }
        guard isActive else { return }
        let fallbackMatches = filterFallbackCatalog(query: trimmed)
        let combined = results.isEmpty ? fallbackMatches : results
        catalog = Array(combined.prefix(60))
        isLoading = false
        let elapsed = Date().timeIntervalSince(start)
        let elapsedText = String(format: "%.2f", elapsed)
        await logSearchEvent("done query=\"\(trimmed)\" results=\(results.count) elapsed=\(elapsedText)s")
    }

    private func fetchRemoteExercises(query: String) async -> [ExerciseDefinition] {
        do {
            return try await WorkoutAPIService.shared.searchExercises(query: query)
        } catch {
            return []
        }
    }

    private func filterFallbackCatalog(query: String) -> [ExerciseDefinition] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return localFallbackCatalog }
        return localFallbackCatalog.filter { $0.name.lowercased().contains(trimmed) }
    }

    private func scheduleSearch(for query: String) {
        searchTask?.cancel()
        let snapshot = query
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(for: snapshot)
        }
    }

    private func logSearchEvent(_ message: String) async {
        #if DEBUG
        let stamp = ISO8601DateFormatter().string(from: Date())
        print("[ExerciseSearch] \(stamp) \(message)")
        #else
        _ = message
        #endif
    }
}

private struct ExercisePickerRow: View {
    let name: String
    let muscleGroup: String
    let equipment: String
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textPrimary)
                Text("\(muscleGroup) · \(equipment)")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
            Spacer()
            Button(action: onAdd) {
                Text(isAdded ? "Added" : "Add")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(isAdded ? FitTheme.textSecondary : FitTheme.buttonText)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(isAdded ? FitTheme.cardHighlight : FitTheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
        }
        .padding(14)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct WorkoutTemplateActionsSheet: View {
    let template: WorkoutTemplate
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Drag indicator
                Capsule()
                    .fill(FitTheme.cardStroke)
                    .frame(width: 48, height: 5)
                    .padding(.top, 12)

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.title)
                        .font(FitFont.heading(size: 20))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("Saved workout actions")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                // Action buttons
                VStack(spacing: 12) {
                    WorkoutSheetButton(title: "Start Workout", systemImage: "play.fill", isDestructive: false) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onStart()
                        }
                    }
                    WorkoutSheetButton(title: "Edit Template", systemImage: "slider.horizontal.3", isDestructive: false) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onEdit()
                        }
                    }
                    WorkoutSheetButton(title: "Duplicate", systemImage: "doc.on.doc", isDestructive: false) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDuplicate()
                        }
                    }
                    WorkoutSheetButton(title: "Delete", systemImage: "trash", isDestructive: true) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDelete()
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
    }
}

private struct WorkoutSheetButton: View {
    let title: String
    let systemImage: String
    let isDestructive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundColor(isDestructive ? Color.red : FitTheme.textPrimary)
                Text(title)
                    .font(FitFont.body(size: 15))
                    .foregroundColor(isDestructive ? Color.red : FitTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(14)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct WorkoutSessionView: View {
    let userId: String
    let title: String
    let sessionId: String?
    @State var exercises: [WorkoutExerciseSession]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var restRemaining = 0
    @State private var restActive = false
    @State private var restNotificationId: String?
    @State private var selectedExercise: WorkoutExerciseSession?
    @State private var selectedExerciseIndex: Int?
    @State private var isExerciseSheetPresented = false
    @State private var workoutElapsed = 0
    @State private var isPaused = false
    @State private var exerciseTags: [UUID: ExerciseTag] = [:]
    @State private var exerciseTagLinks: [UUID: UUID] = [:]
    @State private var pendingSupersetRestExerciseId: UUID?
    @State private var showExercisePicker = false
    @State private var showTagPicker = false
    @State private var pendingTagType: ExerciseTag?
    @State private var taggingExerciseIndex: Int?
    @State private var insertionIndex: Int?
    @State private var showCardio = true
    @State private var cardioRecommendations: [CardioRecommendation] = CardioRecommendation.defaults
    @State private var selectedCardioId: UUID?
    @State private var editingCardio: CardioRecommendation?
    @State private var showFinishAlert = false
    @State private var showFinishMessage = false
    @State private var finishMessage = ""
    @State private var isCompleting = false
    @State private var completionSummary: WorkoutSessionCompleteResponse?
    @State private var completionStreak = 0
    @State private var showCompletionSheet = false
    @State private var showCoachChat = false
    @State private var showDiscardAlert = false
    @State private var showSessionActions = false
    @State private var showRenameAlert = false
    @State private var renameDraft = ""
    @State private var showSaveStatus = false
    @State private var saveStatusMessage = ""
    @State private var isSavingTemplate = false
    @State private var sessionTitle = ""
    @State private var showNewPRCelebration = false
    @State private var newPRExercise = ""
    @State private var newPRWeight: Double = 0
    @State private var loggedSetIds: Set<UUID> = []
    @State private var loggedCardioExerciseNames: Set<String> = []

    private let restTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let workoutTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let base = sessionBase
        let withSheets = applySessionSheets(to: base)
        let withLifecycle = applySessionLifecycle(to: withSheets)
        let withAlerts = applySessionAlerts(to: withLifecycle)
        let withPostSheets = applySessionPostSheets(to: withAlerts)
        return applySessionOverlay(to: withPostSheets)
    }

    private var sessionBase: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sessionHeader

                    workoutDurationHeader

                    if restActive {
                        RestTimerCard(
                            remaining: restRemaining,
                            onSkip: stopRestTimer,
                            onAdjust: adjustRestTimer
                        )
                            .padding(.horizontal, 20)
                    }

                    Text(sessionTitle.isEmpty ? title : sessionTitle)
                        .font(FitFont.heading(size: 24))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(.horizontal, 20)

                    VStack(spacing: 12) {
                        ForEach(exercises.indices, id: \.self) { index in
                            ExerciseRowSummary(
                                index: index + 1,
                                exercise: exercises[index],
                                tag: exerciseTags[exercises[index].id],
                                tagDetail: tagDetail(for: exercises[index]),
                                supersetIndicator: supersetIndicator(for: index),
                                onOpen: {
                                    insertionIndex = index
                                    selectedExerciseIndex = index
                                    isExerciseSheetPresented = true
                                },
                                onEdit: {
                                    insertionIndex = index
                                    taggingExerciseIndex = index
                                    openExerciseEditor()
                                },
                                onCreateSuperset: {
                                    insertionIndex = index
                                    taggingExerciseIndex = index
                                    beginTagging(.superset)
                                },
                                onCreateDropSet: {
                                    insertionIndex = index
                                    taggingExerciseIndex = index
                                    beginTagging(.dropSet)
                                },
                                onClearTag: {
                                    clearTag(for: index)
                                },
                                onDelete: {
                                    withAnimation(.spring(response: 0.3)) {
                                        exercises.remove(at: index)
                                    }
                                    Haptics.medium()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    Button(action: { showExercisePicker = true }) {
                        Label("Add Exercise", systemImage: "plus")
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FitTheme.cardHighlight)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 20)

                    if showCardio {
                        CardioRecommendationCard(
                            recommendations: cardioRecommendations,
                            selectedId: selectedCardioId,
                            onSelect: { recommendation in
                                selectedCardioId = recommendation.id
                                editingCardio = recommendation
                            },
                            onDismiss: { showCardio = false }
                        )
                        .padding(.horizontal, 20)
                    }

                    Button(action: { showFinishAlert = true }) {
                        Text(isCompleting ? "Finishing…" : "Finish Workout")
                            .font(FitFont.body(size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.buttonText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canFinish ? FitTheme.accent : FitTheme.cardHighlight)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(isCompleting || !canFinish)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func applySessionSheets<Content: View>(to view: Content) -> some View {
        view
            .sheet(item: $selectedExercise) { exercise in
                ExerciseDetailView(userId: userId, exerciseName: exercise.name, unit: exercise.unit)
            }
            .sheet(item: $editingCardio) { recommendation in
                CardioEditorSheet(
                    recommendation: recommendation,
                    onSave: { updated in
                        if let index = cardioRecommendations.firstIndex(where: { $0.id == updated.id }) {
                            cardioRecommendations[index] = updated
                            selectedCardioId = updated.id
                        }
                    },
                    onLog: { updated in
                        logCardioIfNeeded(updated)
                    }
                )
            }
            .confirmationDialog("Workout options", isPresented: $showSessionActions, titleVisibility: .visible) {
                Button("Save Workout") {
                    Task {
                        await saveSessionTemplate()
                    }
                }
                Button("Rename Workout") {
                    renameDraft = sessionTitle.isEmpty ? title : sessionTitle
                    showRenameAlert = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showTagPicker) {
                if let tag = pendingTagType,
                   let sourceIndex = taggingExerciseIndex,
                   exercises.indices.contains(sourceIndex) {
                    ExercisePairingSheet(
                        title: tag.title,
                        sourceName: exercises[sourceIndex].name,
                        exercises: exercises,
                        sourceIndex: sourceIndex,
                        onSelect: { targetIndex in
                            applyTag(tag, sourceIndex: sourceIndex, targetIndex: targetIndex)
                        },
                        onClose: {
                            pendingTagType = nil
                            showTagPicker = false
                        }
                    )
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerModal(
                    selectedNames: Set(exercises.map(\.name)),
                    onAdd: { definition in
                        addExercise(definition)
                    },
                    onClose: { showExercisePicker = false }
                )
            }
            .fullScreenCover(isPresented: $isExerciseSheetPresented) {
                if let index = selectedExerciseIndex, exercises.indices.contains(index) {
                    WorkoutExerciseLoggingSheet(
                        userId: userId,
                        exercise: $exercises[index],
                        exerciseIndex: index,
                        sessionExercises: exercises,
                        restRemaining: $restRemaining,
                        restActive: $restActive,
                        existingExerciseNames: Set(exercises.map(\.name)),
                        onDeleteExercise: {
                            exercises.remove(at: index)
                        },
                        onCompleteSet: { restSeconds, setEntry in
                            handleSetCompletion(for: index, restSeconds: restSeconds, setEntry: setEntry)
                        },
                        onShowHistory: {
                            selectedExercise = exercises[index]
                        },
                        onSkipRest: stopRestTimer,
                        onAdjustRest: adjustRestTimer,
                        onCreateDropSet: {
                            applyDropSet(to: index)
                        },
                        onCreateSuperset: { targetIndex in
                            applyTag(.superset, sourceIndex: index, targetIndex: targetIndex)
                        }
                    )
                    .id(exercises[index].id)
                }
            }
    }

    private func applySessionLifecycle<Content: View>(to view: Content) -> some View {
        view
            .task {
                if sessionTitle.isEmpty {
                    sessionTitle = title
                }
                // Initial save when session starts
                saveSessionState()

                let now = Date()
                let restEndDate = restActive ? now.addingTimeInterval(TimeInterval(restRemaining)) : nil
                await WorkoutLiveActivityManager.startIfNeeded(
                    startDate: now.addingTimeInterval(-TimeInterval(workoutElapsed)),
                    sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                    isPaused: isPaused,
                    restEndDate: restEndDate,
                    restTotalSeconds: restActive ? restRemaining : nil
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .fitAIRestTimerSkip)) { _ in
                guard restActive else { return }
                stopRestTimer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fitAIRestTimerAdd30)) { _ in
                guard restActive else { return }
                adjustRestTimer(by: 30)
            }
            .onChange(of: isPaused) { _ in
                saveSessionState()
                let now = Date()
                let restEndDate = restActive ? now.addingTimeInterval(TimeInterval(restRemaining)) : nil
                Task {
                    await WorkoutLiveActivityManager.update(
                        sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                        isPaused: isPaused,
                        restEndDate: restEndDate,
                        restTotalSeconds: restActive ? restRemaining : nil
                    )
                }
            }
            .onChange(of: sessionTitle) { _ in
                saveSessionState()
                let now = Date()
                let restEndDate = restActive ? now.addingTimeInterval(TimeInterval(restRemaining)) : nil
                Task {
                    await WorkoutLiveActivityManager.update(
                        sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                        isPaused: isPaused,
                        restEndDate: restEndDate,
                        restTotalSeconds: restActive ? restRemaining : nil
                    )
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background || newPhase == .inactive {
                    // Save session when app goes to background
                    saveSessionState()
                }
            }
            .onChange(of: exercises) { _ in
                // Auto-save when exercises change (set completion, etc.)
                saveSessionState()
            }
            .onReceive(restTicker) { _ in
                guard restActive else { return }
                if restRemaining > 0 {
                    restRemaining -= 1
                }
                if restRemaining <= 0 {
                    completeRestTimer()
                }
            }
            .onReceive(workoutTicker) { _ in
                guard !isPaused else { return }
                workoutElapsed += 1
            }
    }

    private func applySessionAlerts<Content: View>(to view: Content) -> some View {
        view
            .alert("Finish workout?", isPresented: $showFinishAlert) {
                Button("Finish", role: .destructive) {
                    Task {
                        await finishWorkout()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(finishAlertMessage)
            }
            .alert("Discard workout?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) {
                    clearSessionState()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to discard this workout? It won't be saved.")
            }
            .alert("Rename workout", isPresented: $showRenameAlert) {
                TextField("Workout name", text: $renameDraft)
                Button("Save") {
                    let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        sessionTitle = trimmed
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Update the workout title for this session.")
            }
            .alert("Workout Complete", isPresented: $showFinishMessage) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(finishMessage)
            }
            .alert("Save workout", isPresented: $showSaveStatus) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveStatusMessage)
            }
    }

    private func applySessionPostSheets<Content: View>(to view: Content) -> some View {
        view
            .sheet(isPresented: $showCompletionSheet) {
                if let summary = completionSummary {
                    WorkoutCompletionSheet(summary: summary, streakCount: completionStreak) {
                        showCompletionSheet = false
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCoachChat) {
                CoachChatView(userId: userId)
            }
            .fullScreenCover(isPresented: $showNewPRCelebration) {
                PRCelebrationView(
                    exerciseName: newPRExercise,
                    weight: newPRWeight,
                    onDismiss: {
                        showNewPRCelebration = false
                    }
                )
            }
    }

    private func applySessionOverlay<Content: View>(to view: Content) -> some View {
        view
            .overlay(alignment: .bottomTrailing) {
                Button(action: { showCoachChat = true }) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.buttonText)
                        .padding(14)
                        .background(FitTheme.primaryGradient)
                        .clipShape(Circle())
                        .shadow(color: FitTheme.buttonShadow, radius: 10, x: 0, y: 6)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
    }

    private var canFinish: Bool {
        !exercises.isEmpty
    }

    private var completedSetCount: Int {
        exercises.reduce(0) { partial, exercise in
            partial + exercise.sets.filter { $0.isComplete }.count
        }
    }

    private var finishAlertMessage: String {
        if completedSetCount == 0 {
            return "No sets logged yet. Finish anyway?"
        }
        return "This will complete the session and log PRs."
    }

    private var sessionHeader: some View {
        HStack(alignment: .center) {
            Button(action: { showDiscardAlert = true }) {
                Image(systemName: "xmark")
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
            }

            Spacer()

            Text(sessionTitle.isEmpty ? title : sessionTitle)
                .font(FitFont.body(size: 18))
                .foregroundColor(FitTheme.textSecondary)

            Spacer()

            Button(action: { showSessionActions = true }) {
                Image(systemName: "ellipsis")
                    .font(FitFont.body(size: 18, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var workoutDurationHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Workout Duration")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                Text(formatElapsedTime(workoutElapsed))
                    .font(FitFont.heading(size: 36))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)
            }

            Spacer()

            Button(action: { isPaused.toggle() }) {
                Text(isPaused ? "Resume" : "Pause")
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 18)
                    .background(FitTheme.cardHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 20)
    }

    private func startRestTimer(seconds: Int) {
        cancelRestNotification()
        restRemaining = max(seconds, 0)
        restActive = restRemaining > 0
        if restActive {
            scheduleRestNotification(seconds: restRemaining)
        }
        saveSessionState()
        Task {
            let now = Date()
            let restEndDate = restActive ? now.addingTimeInterval(TimeInterval(restRemaining)) : nil
            await WorkoutLiveActivityManager.update(
                sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                isPaused: isPaused,
                restEndDate: restEndDate,
                restTotalSeconds: restActive ? restRemaining : nil
            )
        }
    }

    private func stopRestTimer() {
        restActive = false
        restRemaining = 0
        cancelRestNotification()
        saveSessionState()
        Task {
            await WorkoutLiveActivityManager.update(
                sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                isPaused: isPaused,
                restEndDate: nil,
                restTotalSeconds: nil
            )
        }
    }

    private func adjustRestTimer(by delta: Int) {
        let updated = max(restRemaining + delta, 0)
        restRemaining = updated
        restActive = updated > 0
        cancelRestNotification()
        if restActive {
            scheduleRestNotification(seconds: restRemaining)
        }
        saveSessionState()
        Task {
            let now = Date()
            let restEndDate = restActive ? now.addingTimeInterval(TimeInterval(restRemaining)) : nil
            await WorkoutLiveActivityManager.update(
                sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                isPaused: isPaused,
                restEndDate: restEndDate,
                restTotalSeconds: restActive ? restRemaining : nil
            )
        }
    }

    private func completeRestTimer() {
        restActive = false
        restRemaining = 0
        Haptics.success()
        SoundEffects.restComplete()
        saveSessionState()
        Task {
            await WorkoutLiveActivityManager.update(
                sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                isPaused: isPaused,
                restEndDate: nil,
                restTotalSeconds: nil
            )
        }
    }

    private func scheduleRestNotification(seconds: Int) {
        guard seconds > 0 else { return }
        let notificationId = "fitai.rest.\(UUID().uuidString)"
        restNotificationId = notificationId

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                // Request critical alerts for time-sensitive workout notifications
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
            }
            let updatedSettings = await center.notificationSettings()
            guard updatedSettings.authorizationStatus == .authorized else { return }
            
            // Register notification category with actions
            let skipAction = UNNotificationAction(
                identifier: "fitai.rest.skip",
                title: "Start Next Set",
                options: .foreground
            )
            let add30Action = UNNotificationAction(
                identifier: "fitai.rest.add30",
                title: "+30s Rest",
                options: []
            )
            let category = UNNotificationCategory(
                identifier: "fitai.rest.timer",
                actions: [skipAction, add30Action],
                intentIdentifiers: [],
                options: .customDismissAction
            )
            center.setNotificationCategories([category])

            let content = UNMutableNotificationContent()
            content.title = "💪 Rest Complete!"
            content.body = "Time for your next set. Let's go!"
            content.sound = UNNotificationSound.default
            content.categoryIdentifier = "fitai.rest.timer"
            // Time-sensitive for lockscreen visibility
            content.interruptionLevel = .timeSensitive

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
            let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    private func cancelRestNotification() {
        guard let restNotificationId else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restNotificationId])
        self.restNotificationId = nil
    }

    private func formatElapsedTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remaining = seconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, remaining)
    }

    /// Save current workout session state to persistent storage for crash recovery
    private func saveSessionState() {
        WorkoutSessionStore.save(
            sessionId: sessionId,
            title: sessionTitle.isEmpty ? title : sessionTitle,
            exercises: exercises,
            workoutElapsed: workoutElapsed,
            isPaused: isPaused,
            restRemaining: restRemaining,
            restActive: restActive
        )

        let now = Date()
        WorkoutWidgetStateStore.save(
            WorkoutWidgetState(
                sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                startDate: now.addingTimeInterval(-TimeInterval(workoutElapsed)),
                isPaused: isPaused,
                restEndDate: restActive ? now.addingTimeInterval(TimeInterval(restRemaining)) : nil,
                lastUpdated: now,
                isActive: true
            )
        )
    }

    /// Clear saved session state (called on completion or discard)
    private func clearSessionState() {
        WorkoutSessionStore.clear()
        WorkoutWidgetStateStore.clear()
        Task {
            await WorkoutLiveActivityManager.endAll()
        }
    }

    private func logSetIfNeeded(
        exerciseName: String,
        setEntry: WorkoutSetEntry,
        setIndex: Int,
        unit: WeightUnit
    ) {
        if loggedSetIds.contains(setEntry.id) { return }
        let reps = Int(setEntry.reps) ?? 0
        let rawWeight = Double(setEntry.weight) ?? 0
        let weight = unit == .kg ? rawWeight * 2.20462 : rawWeight
        
        // Check for PR
        if !setEntry.isWarmup {
            Task {
                await checkAndCelebratePR(exerciseName: exerciseName, weight: weight, reps: reps)
            }
        }
        
        if let sessionId {
            Task {
                do {
                    try await WorkoutAPIService.shared.logExerciseSet(
                        sessionId: sessionId,
                        exerciseName: exerciseName,
                        sets: 1,
                        reps: reps,
                        weight: weight,
                        notes: nil,
                        setIndex: setIndex,
                        isWarmup: setEntry.isWarmup,
                        durationSeconds: nil
                    )
                    await MainActor.run {
                        loggedSetIds.insert(setEntry.id)
                    }
                } catch {
                    print("❌ Workout log write failed:", error)
                    print("sessionId=\(sessionId) exercise=\(exerciseName) reps=\(reps) weight=\(weight)")
                }
            }
        } else {
            savePendingLog(
                PendingExerciseLog(
                    sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                    exerciseName: exerciseName,
                    reps: reps,
                    weight: weight,
                    durationMinutes: nil,
                    durationSeconds: nil,
                    isWarmup: setEntry.isWarmup,
                    setIndex: setIndex,
                    createdAt: Date()
                )
            )
        }
    }
    
    @MainActor
    private func checkAndCelebratePR(exerciseName: String, weight: Double, reps: Int) async {
        guard weight > 0, reps > 0 else { return }
        
        do {
            let history = try await WorkoutAPIService.shared.fetchExerciseHistory(
                userId: userId,
                exerciseName: exerciseName
            )
            
            // Check if this is a new weight PR
            if let bestSet = history.bestSet {
                let bestWeight = bestSet.weight ?? 0
                if weight > bestWeight {
                    // New PR!
                    showNewPRCelebration = true
                    newPRExercise = exerciseName
                    newPRWeight = weight
                    Haptics.success()
                    
                    // Post notification to update homepage PR
                    NotificationCenter.default.post(
                        name: .fitAINewPR,
                        object: nil,
                        userInfo: [
                            "exercise": exerciseName,
                            "weight": weight,
                            "reps": reps
                        ]
                    )
                }
            } else {
                // First time doing this exercise - this is a PR by default
                showNewPRCelebration = true
                newPRExercise = exerciseName
                newPRWeight = weight
                Haptics.success()
                
                NotificationCenter.default.post(
                    name: .fitAINewPR,
                    object: nil,
                    userInfo: [
                        "exercise": exerciseName,
                        "weight": weight,
                        "reps": reps
                    ]
                )
            }
        } catch {
            // Silently fail - don't interrupt workout
        }
    }

    private func logCardioIfNeeded(_ recommendation: CardioRecommendation) {
        guard recommendation.durationMinutes > 0 else { return }
        let name = "Cardio - \(recommendation.title)"
        if let sessionId {
            Task {
                do {
                    try await WorkoutAPIService.shared.logCardioDuration(
                        sessionId: sessionId,
                        exerciseName: name,
                        durationMinutes: recommendation.durationMinutes,
                        notes: "Intensity: \(recommendation.intensity)"
                    )
                    await MainActor.run {
                        loggedCardioExerciseNames.insert(name)
                    }
                } catch {
                    // Ignore logging failures during workout
                }
            }
        } else {
            savePendingLog(
                PendingExerciseLog(
                    sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                    exerciseName: name,
                    reps: 0,
                    weight: 0,
                    durationMinutes: recommendation.durationMinutes,
                    durationSeconds: recommendation.durationMinutes * 60,
                    isWarmup: false,
                    setIndex: 1,
                    createdAt: Date()
                )
            )
        }
        if let index = cardioRecommendations.firstIndex(where: { $0.id == recommendation.id }) {
            cardioRecommendations.remove(at: index)
            if selectedCardioId == recommendation.id {
                selectedCardioId = nil
            }
        }
        if cardioRecommendations.isEmpty {
            showCardio = false
        }
        addCardioExerciseEntry(name: name, durationMinutes: recommendation.durationMinutes)
    }

    private func finishWorkout() async {
        // Clear saved session state since we're completing the workout
        clearSessionState()

        let baseProps: [String: Any] = [
            "duration_sec": workoutElapsed,
            "exercise_count": exercises.count,
            "has_server_session": sessionId != nil
        ]
        
        guard let sessionId else {
            let summary = WorkoutSessionCompleteResponse(
                sessionId: "local",
                status: "completed",
                durationSeconds: workoutElapsed,
                prs: []
            )
            let updatedStreak = WorkoutStreakStore.update()
            NotificationCenter.default.post(
                name: .fitAIWorkoutStreakUpdated,
                object: nil,
                userInfo: ["streak": updatedStreak]
            )
            completionSummary = summary
            completionStreak = updatedStreak
            showCompletionSheet = true
            WorkoutCompletionStore.markCompleted(exercises: exercises.map(\.name))
            Haptics.success()

            var props = baseProps
            props["result"] = "success_local"
            PostHogAnalytics.featureUsed(.workoutTracking, action: "complete", properties: props)
            return
        }
        isCompleting = true
        do {
            await logUnloggedSetsIfNeeded(sessionId: sessionId)
            let summary = try await WorkoutAPIService.shared.completeSession(
                sessionId: sessionId,
                durationSeconds: workoutElapsed
            )

            var props = baseProps
            props["result"] = "success"
            props["prs_count"] = summary.prs.count
            PostHogAnalytics.featureUsed(.workoutTracking, action: "complete", properties: props)

            let updatedStreak = WorkoutStreakStore.update()
            NotificationCenter.default.post(
                name: .fitAIWorkoutStreakUpdated,
                object: nil,
                userInfo: ["streak": updatedStreak]
            )
            await MainActor.run {
                completionSummary = summary
                completionStreak = updatedStreak
                showCompletionSheet = true
                isCompleting = false
                WorkoutCompletionStore.markCompleted(exercises: exercises.map(\.name))
                Haptics.success()
            }
        } catch {
            await MainActor.run {
                finishMessage = "Unable to complete workout."
                showFinishMessage = true
                isCompleting = false
            }

            var props = baseProps
            props["result"] = "failure"
            props["error_type"] = String(describing: type(of: error))
            PostHogAnalytics.featureUsed(.workoutTracking, action: "complete", properties: props)
        }
    }

    private func logUnloggedSetsIfNeeded(sessionId: String) async {
        let exerciseSnapshot = await MainActor.run { exercises }

        for exercise in exerciseSnapshot {
            let exerciseName = exercise.name
            let isCardio = exerciseName.lowercased().hasPrefix("cardio -")
            if isCardio {
                let alreadyLogged = await MainActor.run { loggedCardioExerciseNames.contains(exerciseName) }
                if alreadyLogged {
                    continue
                }
                let durationMinutes = exercise.sets.first.flatMap { Int($0.reps.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
                guard durationMinutes > 0 else { continue }
                do {
                    try await WorkoutAPIService.shared.logCardioDuration(
                        sessionId: sessionId,
                        exerciseName: exerciseName,
                        durationMinutes: durationMinutes,
                        notes: exercise.notes.isEmpty ? nil : exercise.notes
                    )
                    await MainActor.run {
                        loggedCardioExerciseNames.insert(exerciseName)
                    }
                } catch {
                    print("❌ Workout log write failed:", error)
                    print("sessionId=\(sessionId) exercise=\(exerciseName) durationMinutes=\(durationMinutes)")
                }
                continue
            }

            for (offset, setEntry) in exercise.sets.enumerated() {
                let alreadyLogged = await MainActor.run { loggedSetIds.contains(setEntry.id) }
                if alreadyLogged {
                    continue
                }
                let repsText = setEntry.reps.trimmingCharacters(in: .whitespacesAndNewlines)
                let weightText = setEntry.weight.trimmingCharacters(in: .whitespacesAndNewlines)
                let reps = Int(repsText) ?? 0
                let rawWeight = Double(weightText) ?? 0
                let hasUserInput = setEntry.isComplete || rawWeight > 0 || (reps > 0 && repsText != "10")
                if !hasUserInput {
                    continue
                }
                let weight = exercise.unit == .kg ? rawWeight * 2.20462 : rawWeight
                do {
                    try await WorkoutAPIService.shared.logExerciseSet(
                        sessionId: sessionId,
                        exerciseName: exerciseName,
                        sets: 1,
                        reps: reps,
                        weight: weight,
                        notes: exercise.notes.isEmpty ? nil : exercise.notes,
                        setIndex: offset + 1,
                        isWarmup: setEntry.isWarmup,
                        durationSeconds: nil
                    )
                    await MainActor.run {
                        loggedSetIds.insert(setEntry.id)
                    }
                } catch {
                    print("❌ Workout log write failed:", error)
                    print("sessionId=\(sessionId) exercise=\(exerciseName) reps=\(reps) weight=\(weight)")
                }
            }
        }
    }

    private func addExercise(_ definition: ExerciseDefinition) {
        var newExercise = WorkoutExerciseSession(
            name: definition.name,
            sets: WorkoutSetEntry.batch(reps: "10", weight: "", count: 3),
            restSeconds: 60
        )
        newExercise.warmupRestSeconds = min(60, newExercise.restSeconds)
        let baseIndex = insertionIndex ?? (exercises.isEmpty ? -1 : exercises.count - 1)
        let insertIndex = baseIndex + 1
        if insertIndex <= exercises.count {
            exercises.insert(newExercise, at: insertIndex)
        } else {
            exercises.append(newExercise)
        }
        insertionIndex = nil
    }

    private func addCardioExerciseEntry(name: String, durationMinutes: Int) {
        guard !exercises.contains(where: { $0.name == name }) else { return }
        var entry = WorkoutExerciseSession(
            name: name,
            sets: [
                WorkoutSetEntry(
                    reps: "\(durationMinutes)",
                    weight: "",
                    isComplete: true,
                    isWarmup: false
                )
            ],
            restSeconds: 0
        )
        entry.warmupRestSeconds = 0
        exercises.append(entry)
    }

    private func saveSessionTemplate() async {
        guard !userId.isEmpty else {
            await MainActor.run {
                saveStatusMessage = "Missing user session. Please log in again."
                showSaveStatus = true
            }
            return
        }
        
        let workoutTitle = sessionTitle.isEmpty ? title : sessionTitle
        guard !workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                saveStatusMessage = "Add a workout name."
                showSaveStatus = true
            }
            return
        }
        
        guard !exercises.isEmpty else {
            await MainActor.run {
                saveStatusMessage = "Add at least one exercise."
                showSaveStatus = true
            }
            return
        }

        await MainActor.run {
            isSavingTemplate = true
            saveStatusMessage = ""
            showSaveStatus = false
        }
        
        do {
            let inputs = exercises.map { exercise in
                let reps = Int(exercise.sets.first?.reps ?? "10") ?? 10
                return WorkoutExerciseInput(
                    name: exercise.name,
                    muscleGroups: [], // Will be populated by backend if needed
                    equipment: [], // Will be populated by backend if needed
                    sets: exercise.sets.count,
                    reps: reps,
                    restSeconds: exercise.restSeconds,
                    notes: exercise.notes.isEmpty ? nil : exercise.notes
                )
            }
            
            _ = try await WorkoutAPIService.shared.createTemplate(
                userId: userId,
                title: workoutTitle,
                description: nil,
                mode: "manual",
                exercises: inputs
            )
            
            await MainActor.run {
                saveStatusMessage = "Workout saved successfully!"
                showSaveStatus = true
                isSavingTemplate = false
                Haptics.success()
            }
        } catch {
            await MainActor.run {
                saveStatusMessage = "Unable to save workout. \(error.localizedDescription)"
                showSaveStatus = true
                isSavingTemplate = false
            }
        }
    }

    private func openExerciseEditor() {
        guard let index = taggingExerciseIndex, exercises.indices.contains(index) else { return }
        selectedExerciseIndex = index
        isExerciseSheetPresented = true
    }

    private func beginTagging(_ tag: ExerciseTag) {
        guard let index = taggingExerciseIndex, exercises.indices.contains(index) else { return }
        if tag == .dropSet {
            applyDropSet(to: index)
            pendingTagType = nil
            showTagPicker = false
            return
        }
        pendingTagType = tag
        showTagPicker = exercises.count > 1
        if exercises.count <= 1 {
            exerciseTags[exercises[index].id] = tag
        }
    }

    private func applyTag(_ tag: ExerciseTag, sourceIndex: Int, targetIndex: Int) {
        guard exercises.indices.contains(sourceIndex),
              exercises.indices.contains(targetIndex) else { return }
        clearTag(for: sourceIndex)
        clearTag(for: targetIndex)
        let sourceId = exercises[sourceIndex].id
        let targetId = exercises[targetIndex].id
        exerciseTags[sourceId] = tag
        exerciseTags[targetId] = tag
        exerciseTagLinks[sourceId] = targetId
        exerciseTagLinks[targetId] = sourceId
        if tag == .superset {
            moveExerciseAdjacentToSource(sourceId: sourceId, targetId: targetId)
        }
        pendingSupersetRestExerciseId = nil
        pendingTagType = nil
        showTagPicker = false
    }

    private func moveExerciseAdjacentToSource(sourceId: UUID, targetId: UUID) {
        guard let sourceIndex = exercises.firstIndex(where: { $0.id == sourceId }),
              let targetIndex = exercises.firstIndex(where: { $0.id == targetId }) else { return }
        guard abs(sourceIndex - targetIndex) > 1 else { return }
        let targetExercise = exercises.remove(at: targetIndex)
        guard let updatedSourceIndex = exercises.firstIndex(where: { $0.id == sourceId }) else { return }
        let insertIndex = min(updatedSourceIndex + 1, exercises.count)
        exercises.insert(targetExercise, at: insertIndex)
        if insertionIndex != nil {
            insertionIndex = updatedSourceIndex
        }
        if taggingExerciseIndex != nil {
            taggingExerciseIndex = updatedSourceIndex
        }
    }

    private func clearTag(for index: Int) {
        guard exercises.indices.contains(index) else { return }
        let id = exercises[index].id
        if let linked = exerciseTagLinks[id] {
            exerciseTags[linked] = nil
            exerciseTagLinks[linked] = nil
            if pendingSupersetRestExerciseId == linked {
                pendingSupersetRestExerciseId = nil
            }
        }
        exerciseTags[id] = nil
        exerciseTagLinks[id] = nil
        if pendingSupersetRestExerciseId == id {
            pendingSupersetRestExerciseId = nil
        }
    }

    private func applyDropSet(to index: Int) {
        guard exercises.indices.contains(index) else { return }
        clearTag(for: index)
        if exercises[index].sets.contains(where: { $0.isDropSet }) {
            exerciseTags[exercises[index].id] = .dropSet
            return
        }
        insertDropSets(for: index)
        exerciseTags[exercises[index].id] = .dropSet
    }

    private func insertDropSets(for index: Int) {
        var updatedSets: [WorkoutSetEntry] = []
        let currentSets = exercises[index].sets
        let workingIndices = currentSets.indices.filter { !currentSets[$0].isWarmup }
        guard let lastWorkingIndex = workingIndices.last else { return }

        for setIndex in currentSets.indices {
            let setEntry = currentSets[setIndex]
            updatedSets.append(setEntry)
            guard !setEntry.isWarmup, setIndex != lastWorkingIndex else { continue }
            let dropSet = WorkoutSetEntry(
                reps: doubledRepsString(setEntry.reps),
                weight: halvedWeightString(setEntry.weight),
                isComplete: false,
                isWarmup: false,
                isDropSet: true
            )
            updatedSets.append(dropSet)
        }

        exercises[index].sets = updatedSets
    }

    private func halvedWeightString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let weight = Double(trimmed) else { return value }
        let halved = weight / 2
        let rounded = (halved * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }

    private func doubledRepsString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reps = Int(trimmed) else { return value }
        return "\(reps * 2)"
    }

    private func handleSetCompletion(for index: Int, restSeconds: Int, setEntry: WorkoutSetEntry) {
        guard exercises.indices.contains(index) else { return }
        let setIndex = exercises[index].sets.firstIndex(where: { $0.id == setEntry.id }).map { $0 + 1 } ?? 1
        logSetIfNeeded(
            exerciseName: exercises[index].name,
            setEntry: setEntry,
            setIndex: setIndex,
            unit: exercises[index].unit
        )
        if setEntry.isWarmup {
            startRestTimer(seconds: restSeconds)
            return
        }
        guard let tag = exerciseTags[exercises[index].id] else {
            startRestTimer(seconds: restSeconds)
            return
        }

        switch tag {
        case .superset:
            handleSupersetSetCompletion(
                for: index,
                restSeconds: restSeconds
            )
        case .dropSet:
            startRestTimer(seconds: restSeconds)
        }
    }

    private func handleSupersetSetCompletion(for index: Int, restSeconds: Int) {
        let exerciseId = exercises[index].id
        guard let linkedId = exerciseTagLinks[exerciseId],
              let linkedIndex = exercises.firstIndex(where: { $0.id == linkedId }) else {
            startRestTimer(seconds: restSeconds)
            return
        }

        if pendingSupersetRestExerciseId == exerciseId {
            pendingSupersetRestExerciseId = nil
            startRestTimer(seconds: restSeconds)
            return
        }

        pendingSupersetRestExerciseId = linkedId
        selectedExerciseIndex = linkedIndex
        isExerciseSheetPresented = true
    }

    private func tagDetail(for exercise: WorkoutExerciseSession) -> String? {
        exerciseTags[exercise.id]?.title
    }

    private func supersetIndicator(for index: Int) -> SupersetIndicator? {
        guard exercises.indices.contains(index) else { return nil }
        let exerciseId = exercises[index].id
        guard exerciseTags[exerciseId] == .superset,
              let linkedId = exerciseTagLinks[exerciseId],
              let linkedIndex = exercises.firstIndex(where: { $0.id == linkedId }) else {
            return nil
        }
        if linkedIndex > index {
            return .down
        }
        if linkedIndex < index {
            return .up
        }
        return nil
    }
}

// MARK: - PR Celebration View
private struct PRCelebrationView: View {
    let exerciseName: String
    let weight: Double
    let onDismiss: () -> Void
    
    @State private var showContent = false
    @State private var showConfetti = false
    @State private var ringScale: CGFloat = 0.1
    @State private var ringOpacity: Double = 1.0
    
    var body: some View {
        ZStack {
            // Dark overlay
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            // Pulsing rings
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5 - Double(index) * 0.15), lineWidth: 3)
                    .frame(width: 200 + CGFloat(index * 50), height: 200 + CGFloat(index * 50))
                    .scaleEffect(ringScale + CGFloat(index) * 0.1)
                    .opacity(ringOpacity - Double(index) * 0.2)
            }
            
            // Main content
            VStack(spacing: 24) {
                // Trophy icon with glow
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.4), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.65, blue: 0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.6), radius: 20, x: 0, y: 10)
                    
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(showContent ? 1.0 : 0.5)
                .opacity(showContent ? 1.0 : 0.0)
                
                // Text
                VStack(spacing: 12) {
                    Text("NEW PR!")
                        .font(FitFont.heading(size: 36))
                        .foregroundColor(.white)
                        .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5), radius: 8, x: 0, y: 2)
                    
                    Text(exerciseName)
                        .font(FitFont.body(size: 18))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("\(Int(weight)) lbs")
                        .font(FitFont.heading(size: 48))
                        .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                        .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5), radius: 8, x: 0, y: 2)
                }
                .scaleEffect(showContent ? 1.0 : 0.8)
                .opacity(showContent ? 1.0 : 0.0)
                
                Spacer().frame(height: 40)
                
                // Continue button
                Button(action: onDismiss) {
                    Text("KEEP CRUSHING IT")
                        .font(FitFont.body(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.65, blue: 0.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .padding(.horizontal, 40)
                .opacity(showContent ? 1.0 : 0.0)
            }
        }
        .onAppear {
            // Trigger haptic
            Haptics.heavy()
            
            // Animate content in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showContent = true
            }
            
            // Animate rings
            withAnimation(.easeOut(duration: 1.0)) {
                ringScale = 1.5
                ringOpacity = 0
            }
            
            // Repeat ring animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    ringScale = 2.0
                }
            }
        }
    }
}

private struct WorkoutCompletionSheet: View {
    let summary: WorkoutSessionCompleteResponse
    let streakCount: Int
    let onDone: () -> Void

    @State private var step: CompletionStep
    @State private var animatedStreak = 0
    @State private var streakPulse = false
    
    // PR Animation States
    @State private var trophyScale: CGFloat = 0.5
    @State private var trophyRotation: Double = -15
    @State private var prTextScale: CGFloat = 0.5
    @State private var prTextOpacity: Double = 0
    @State private var weightScale: CGFloat = 0.3
    @State private var weightOpacity: Double = 0
    @State private var confettiTrigger = false
    @State private var glowIntensity: CGFloat = 0
    @State private var sparkleRotation: Double = 0

    init(summary: WorkoutSessionCompleteResponse, streakCount: Int, onDone: @escaping () -> Void) {
        self.summary = summary
        self.streakCount = streakCount
        self.onDone = onDone
        _step = State(initialValue: summary.prs.isEmpty ? .congrats : .pr)
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Capsule()
                    .fill(FitTheme.cardHighlight)
                    .frame(width: 48, height: 5)
                    .padding(.top, 12)

                Group {
                    if step == .pr {
                        prView
                    } else {
                        congratsView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 24)
            }
        }
    }

    private var prView: some View {
        ZStack {
            // Confetti Particles
            ForEach(0..<30, id: \.self) { i in
                ConfettiParticle(index: i, trigger: confettiTrigger)
            }
            
            VStack(spacing: 16) {
                // Animated Trophy with Sparkle Ring
                ZStack {
                    // Rotating sparkle ring
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    FitTheme.accent.opacity(0),
                                    FitTheme.accent.opacity(0.6),
                                    FitTheme.accent.opacity(0),
                                ],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(sparkleRotation))
                    
                    // Glowing circle behind trophy
                    Circle()
                        .fill(FitTheme.accent.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .blur(radius: 20)
                        .scaleEffect(glowIntensity)
                    
                    // Trophy
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    FitTheme.accent,
                                    FitTheme.accent.opacity(0.7),
                                    FitTheme.accent
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(trophyScale)
                        .rotationEffect(.degrees(trophyRotation))
                        .shadow(color: FitTheme.accent.opacity(0.5), radius: 20, x: 0, y: 10)
                }
                .padding(.top, 20)

                // Animated "PR!" Text
                Text("PR!")
                    .font(FitFont.heading(size: 38))
                    .fontWeight(.black)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [FitTheme.accent, FitTheme.accent.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(prTextScale)
                    .opacity(prTextOpacity)
                    .shadow(color: FitTheme.accent.opacity(0.4), radius: 10, x: 0, y: 5)

                // Animated PR Details
                TabView {
                    ForEach(summary.prs) { pr in
                        VStack(spacing: 12) {
                            Text(pr.exerciseName)
                                .font(FitFont.body(size: 18))
                                .foregroundColor(FitTheme.textSecondary)
                            
                            Text("\(Int(pr.value)) lb")
                                .font(FitFont.heading(size: 48))
                                .fontWeight(.heavy)
                                .foregroundColor(FitTheme.textPrimary)
                                .scaleEffect(weightScale)
                                .opacity(weightOpacity)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 140)

                CompletionActionButton(title: "Continue") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        step = .congrats
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            // Trigger haptic
            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
            impactHeavy.impactOccurred()
            
            // Trophy entrance animation
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
                trophyScale = 1.2
                trophyRotation = 0
            }
            
            // Trophy bounce back
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    trophyScale = 1.0
                }
            }
            
            // PR text animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    prTextScale = 1.0
                    prTextOpacity = 1.0
                }
                
                // Second haptic
                let impactMedium = UIImpactFeedbackGenerator(style: .medium)
                impactMedium.impactOccurred()
            }
            
            // Weight animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
                    weightScale = 1.0
                    weightOpacity = 1.0
                }
                
                // Third haptic
                let impactLight = UIImpactFeedbackGenerator(style: .light)
                impactLight.impactOccurred()
            }
            
            // Confetti animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                confettiTrigger = true
            }
            
            // Continuous glow pulse
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowIntensity = 1.3
            }
            
            // Continuous sparkle rotation
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                sparkleRotation = 360
            }
        }
    }

    private var congratsView: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)

            CoachCharacterView(size: 180, showBackground: false, pose: .celebration)

            Text("Workout complete")
                .font(FitFont.heading(size: 34))
                .foregroundColor(FitTheme.textPrimary)

            Text("Quick win, solid effort. Keep it rolling.")
                .font(FitFont.body(size: 18))
                .foregroundColor(FitTheme.textSecondary)

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundColor(FitTheme.accent)
                    Text("\(animatedStreak)")
                        .font(FitFont.heading(size: 46))
                        .foregroundColor(FitTheme.textPrimary)
                }
                .scaleEffect(streakPulse ? 1.08 : 1.0)

                Text("day streak")
                    .font(FitFont.body(size: 18))
                    .foregroundColor(FitTheme.textSecondary)
            }

            Text("Duration · \(formatDuration(summary.durationSeconds))")
                .font(FitFont.body(size: 16))
                .foregroundColor(FitTheme.textSecondary)

            CompletionActionButton(title: "Done", action: onDone)
                .padding(.horizontal, 20)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .onAppear {
            let startValue = max(streakCount - 1, 0)
            animatedStreak = startValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    animatedStreak = max(streakCount, 1)
                    streakPulse.toggle()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        streakPulse = false
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes)m \(remainder)s"
    }

    private enum CompletionStep {
        case pr
        case congrats
    }
}

private struct CompletionActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FitFont.body(size: 14))
                .fontWeight(.semibold)
                .foregroundColor(FitTheme.buttonText)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(FitTheme.primaryGradient)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .shadow(color: FitTheme.buttonShadow, radius: 10, x: 0, y: 6)
        }
    }
}

// MARK: - Confetti Particle Animation
private struct ConfettiParticle: View {
    let index: Int
    let trigger: Bool
    
    @State private var yOffset: CGFloat = 0
    @State private var xOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0
    
    private var randomColor: Color {
        let colors: [Color] = [
            FitTheme.accent,
            .blue,
            .purple,
            .pink,
            .yellow,
            .orange,
            .green
        ]
        return colors[index % colors.count]
    }
    
    private var randomShape: some View {
        Group {
            if index % 3 == 0 {
                Circle()
                    .fill(randomColor)
                    .frame(width: CGFloat.random(in: 6...12), height: CGFloat.random(in: 6...12))
            } else if index % 3 == 1 {
                RoundedRectangle(cornerRadius: 2)
                    .fill(randomColor)
                    .frame(width: CGFloat.random(in: 6...10), height: CGFloat.random(in: 6...10))
            } else {
                Diamond()
                    .fill(randomColor)
                    .frame(width: CGFloat.random(in: 8...12), height: CGFloat.random(in: 8...12))
            }
        }
    }
    
    var body: some View {
        randomShape
            .offset(x: xOffset, y: yOffset)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .scaleEffect(scale)
            .onChange(of: trigger) { newValue in
                if newValue {
                    startAnimation()
                }
            }
    }
    
    private func startAnimation() {
        // Random starting position near center
        let startX = CGFloat.random(in: -50...50)
        let startY = CGFloat.random(in: -100...0)
        
        // Random end position (spread out)
        let endX = CGFloat.random(in: -180...180)
        let endY = CGFloat.random(in: 300...600)
        
        // Random rotation
        let endRotation = Double.random(in: 360...720)
        
        // Staggered delay
        let delay = Double(index) * 0.02
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Fade in and scale up quickly
            withAnimation(.easeOut(duration: 0.2)) {
                opacity = 1.0
                scale = 1.0
                xOffset = startX
                yOffset = startY
            }
            
            // Fall and fade out
            withAnimation(.easeIn(duration: Double.random(in: 1.2...2.0))) {
                xOffset = endX
                yOffset = endY
                rotation = endRotation
            }
            
            // Fade out near the end
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeIn(duration: 0.6)) {
                    opacity = 0
                }
            }
        }
    }
}

// MARK: - Diamond Shape for Confetti
private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct PendingExerciseLog: Codable {
    let sessionTitle: String
    let exerciseName: String
    let reps: Int
    let weight: Double
    let durationMinutes: Int?
    let durationSeconds: Int?
    let isWarmup: Bool?
    let setIndex: Int?
    let createdAt: Date
}

private enum PendingExerciseLogStore {
    static let key = "fitai.pending.exerciseLogs"
}

private func savePendingLog(_ log: PendingExerciseLog) {
    let defaults = UserDefaults.standard
    var logs = loadPendingLogs()
    logs.append(log)
    if let data = try? JSONEncoder().encode(logs) {
        defaults.set(data, forKey: PendingExerciseLogStore.key)
    }
}

private func loadPendingLogs() -> [PendingExerciseLog] {
    let defaults = UserDefaults.standard
    guard let data = defaults.data(forKey: PendingExerciseLogStore.key),
          let logs = try? JSONDecoder().decode([PendingExerciseLog].self, from: data) else {
        return []
    }
    return logs
}

private struct ExerciseRowSummary: View {
    let index: Int
    let exercise: WorkoutExerciseSession
    let tag: ExerciseTag?
    let tagDetail: String?
    let supersetIndicator: SupersetIndicator?
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onCreateSuperset: () -> Void
    let onCreateDropSet: () -> Void
    let onClearTag: () -> Void
    let onDelete: () -> Void
    
    @State private var showMenu = false
    @State private var swipeOffset: CGFloat = 0
    @State private var showDeleteButton = false
    @State private var dragAxis: DragAxis?
    
    private let deleteButtonWidth: CGFloat = 80

    var body: some View {
        rowBase
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var completedSets: Int {
        exercise.sets.filter { $0.isComplete }.count
    }

    private var isComplete: Bool {
        !exercise.sets.isEmpty && completedSets == exercise.sets.count
    }

    private var isCardioExercise: Bool {
        exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("cardio")
    }

    private var cardioDurationText: String? {
        guard isCardioExercise else { return nil }
        let repsText = exercise.sets.first?.reps ?? ""
        let trimmed = repsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let minutes = Int(trimmed), minutes > 0 {
            return "\(minutes) min"
        }
        return "Cardio"
    }

    private var detailText: String {
        if let cardioDurationText {
            return cardioDurationText
        }
        let repsText = exercise.sets.first?.reps ?? "10"
        return "\(completedSets)/\(exercise.sets.count) sets  •  \(repsText) reps"
    }

    private var rowBase: some View {
        ZStack(alignment: .leading) {
            deleteButton
            rowContent
        }
    }

    private var deleteButton: some View {
        HStack {
            Spacer()
            Button(action: {
                Haptics.medium()
                withAnimation(.spring(response: 0.3)) {
                    swipeOffset = 0
                    showDeleteButton = false
                }
                onDelete()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Delete")
                        .font(FitFont.body(size: 10))
                }
                .foregroundColor(.white)
                .frame(width: deleteButtonWidth)
                .frame(maxHeight: .infinity)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            indexIndicator
            exerciseInfo

            Spacer()

            if let supersetIndicator {
                Image(systemName: supersetIndicator.systemImage)
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(ExerciseTag.superset.color)
                    .padding(6)
                    .background(ExerciseTag.superset.color.opacity(0.12))
                    .clipShape(Circle())
            }

            menuButton
            openButton
        }
        .padding(14)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
        .offset(x: swipeOffset)
        .simultaneousGesture(rowSwipeGesture)
    }

    private var indexIndicator: some View {
        ZStack {
            Circle()
                .fill(isComplete ? FitTheme.success.opacity(0.18) : FitTheme.cardHighlight)
                .frame(width: 36, height: 36)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.success)
            } else {
                Text("\(index)")
                    .font(FitFont.body(size: 16))
                    .foregroundColor(FitTheme.textPrimary)
            }
        }
    }

    private var exerciseInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(exercise.name)
                    .font(FitFont.body(size: 18))
                    .foregroundColor(FitTheme.textPrimary)

                if let tag {
                    Text(tagDetail ?? tag.title)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(tag.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tag.color.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Text(detailText)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private var menuButton: some View {
        Menu {
            Button {
                onEdit()
            } label: {
                Label("Edit Sets & Reps", systemImage: "slider.horizontal.3")
            }
            Button {
                onCreateSuperset()
            } label: {
                Label("Create Superset", systemImage: "arrow.up.arrow.down")
            }
            Button {
                onCreateDropSet()
            } label: {
                Label("Create Drop Set", systemImage: "arrow.down.right")
            }
            if tag != nil {
                Divider()
                Button(role: .destructive) {
                    onClearTag()
                } label: {
                    Label("Clear Tag", systemImage: "xmark.circle")
                }
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove Exercise", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(FitFont.body(size: 14, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(FitTheme.cardHighlight)
                .clipShape(Circle())
        }
    }

    private var openButton: some View {
        Button(action: onOpen) {
            Image(systemName: "chevron.right")
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(FitTheme.cardHighlight.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var rowSwipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragAxis == nil {
                    let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                    dragAxis = isHorizontal ? .horizontal : .vertical
                }
                guard dragAxis == .horizontal else { return }
                let translation = value.translation.width
                if translation < 0 {
                    swipeOffset = max(translation, -deleteButtonWidth - 20)
                } else if showDeleteButton {
                    swipeOffset = min(0, -deleteButtonWidth + translation)
                }
            }
            .onEnded { value in
                defer { dragAxis = nil }
                guard dragAxis == .horizontal else { return }
                withAnimation(.spring(response: 0.3)) {
                    if showDeleteButton && value.translation.width > 0 {
                        swipeOffset = 0
                        showDeleteButton = false
                        return
                    }
                    if value.translation.width < -40 {
                        swipeOffset = -deleteButtonWidth
                        showDeleteButton = true
                    } else {
                        swipeOffset = 0
                        showDeleteButton = false
                    }
                }
            }
    }
}

private enum SupersetIndicator {
    case up
    case down

    var systemImage: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        }
    }
}

private enum ExerciseTag: String {
    case superset
    case dropSet

    var title: String {
        switch self {
        case .superset: return "Super Set"
        case .dropSet: return "Drop Set"
        }
    }

    var color: Color {
        switch self {
        case .superset: return Color.orange
        case .dropSet: return Color.purple
        }
    }
}

private struct ExercisePairingSheet: View {
    let title: String
    let sourceName: String
    let exercises: [WorkoutExerciseSession]
    let sourceIndex: Int
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(FitFont.heading(size: 22))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Pick an exercise to pair with \(sourceName).")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(10)
                            .background(FitTheme.cardBackground)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(exercises.indices, id: \.self) { index in
                            if index != sourceIndex {
                                Button(action: { onSelect(index) }) {
                                    HStack {
                                        Text(exercises[index].name)
                                            .font(FitFont.body(size: 15))
                                            .foregroundColor(FitTheme.textPrimary)
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(FitTheme.accent)
                                    }
                                    .padding(12)
                                    .background(FitTheme.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(FitTheme.cardStroke, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

private struct CardioRecommendationCard: View {
    let recommendations: [CardioRecommendation]
    let selectedId: UUID?
    let onSelect: (CardioRecommendation) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(cardAccentGradient)
                        .frame(width: 44, height: 44)
                    Image(systemName: "figure.run")
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Recommended Cardio")
                        .font(FitFont.heading(size: 20))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("Tuned to your recovery + goal")
                        .font(FitFont.body(size: 13, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                }

                Spacer()

                Text("Today")
                    .font(FitFont.body(size: 11, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(FitTheme.cardBackground.opacity(0.9))
                    )

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                        .padding(8)
                        .background(FitTheme.cardBackground)
                        .clipShape(Circle())
                }
            }

            VStack(spacing: 12) {
                ForEach(recommendations) { recommendation in
                    CardioRow(
                        recommendation: recommendation,
                        isSelected: recommendation.id == selectedId,
                        onSelect: { onSelect(recommendation) }
                    )
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(FitFont.body(size: 11, weight: .semibold))
                    .foregroundColor(FitTheme.cardWorkoutAccent)
                Text("Tap a row to tweak time + intensity.")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(cardSurfaceGradient)
                Circle()
                    .fill(Color(red: 0.22, green: 0.72, blue: 0.88).opacity(0.12))
                    .frame(width: 160, height: 160)
                    .offset(x: 140, y: -90)
                Circle()
                    .fill(Color(red: 0.16, green: 0.42, blue: 0.92).opacity(0.12))
                    .frame(width: 140, height: 140)
                    .offset(x: -120, y: 120)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(red: 0.2, green: 0.36, blue: 0.46).opacity(0.25), lineWidth: 1)
        )
    }

    private var cardSurfaceGradient: LinearGradient {
        LinearGradient(
            colors: [
                FitTheme.cardWorkout.opacity(0.9),
                FitTheme.cardBackground
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardAccentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.56, blue: 0.98),
                Color(red: 0.18, green: 0.78, blue: 0.86)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct CardioRow: View {
    let recommendation: CardioRecommendation
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(intensityColor.opacity(0.2))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .stroke(intensityColor.opacity(0.5), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "bolt.fill")
                                .font(FitFont.body(size: 12, weight: .semibold))
                                .foregroundColor(intensityColor)
                        )

                    Text(recommendation.title)
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)

                    Spacer()

                    Text("\(recommendation.durationMinutes) min")
                        .font(FitFont.mono(size: 13, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(FitTheme.cardHighlight)
                        )
                }

                HStack(spacing: 8) {
                    Text(recommendation.intensity.uppercased())
                        .font(FitFont.body(size: 10, weight: .semibold))
                        .foregroundColor(intensityColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(intensityColor.opacity(0.12))
                        )

                    if isSelected {
                        Label("Selected", systemImage: "checkmark.circle.fill")
                            .font(FitFont.body(size: 11, weight: .semibold))
                            .foregroundColor(FitTheme.cardWorkoutAccent)
                    } else {
                        Text("Tap to customize")
                            .font(FitFont.body(size: 11, weight: .regular))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? Color.white.opacity(0.9) : FitTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? intensityColor.opacity(0.55) : FitTheme.cardStroke, lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: isSelected ? intensityColor.opacity(0.15) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var intensityColor: Color {
        let lower = recommendation.intensity.lowercased()
        if lower.contains("low") {
            return FitTheme.cardProgressAccent
        }
        if lower.contains("light") {
            return Color(red: 0.22, green: 0.66, blue: 0.88)
        }
        if lower.contains("moderate") {
            return FitTheme.cardWorkoutAccent
        }
        return Color(red: 0.92, green: 0.48, blue: 0.28)
    }
}

private struct CardioEditorSheet: View {
    let recommendation: CardioRecommendation
    let onSave: (CardioRecommendation) -> Void
    let onLog: (CardioRecommendation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var durationMinutes: Int
    @State private var intensity: String
    @State private var remainingSeconds: Int
    @State private var elapsedSeconds = 0
    @State private var isRunning = false
    @State private var didComplete = false
    @State private var timerTask: Task<Void, Never>?

    private let intensityOptions = ["Low", "Light", "Moderate", "High"]

    init(
        recommendation: CardioRecommendation,
        onSave: @escaping (CardioRecommendation) -> Void,
        onLog: @escaping (CardioRecommendation) -> Void
    ) {
        self.recommendation = recommendation
        self.onSave = onSave
        self.onLog = onLog
        _durationMinutes = State(initialValue: recommendation.durationMinutes)
        _intensity = State(initialValue: recommendation.intensity)
        _remainingSeconds = State(initialValue: recommendation.durationMinutes * 60)
    }

    var body: some View {
        let base = editorBase
        return applyEditorLifecycle(to: base)
    }

    private var editorBase: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 18) {
                editorHeader
                summaryCard
                timerSection
                Spacer()
            }
        }
    }

    private func applyEditorLifecycle<Content: View>(to view: Content) -> some View {
        view
            .onDisappear {
                timerTask?.cancel()
                timerTask = nil
            }
            .onChange(of: durationMinutes) { newValue in
                guard !isRunning else { return }
                remainingSeconds = newValue * 60
            }
    }

    private var editorHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(recommendation.title)
                    .font(FitFont.heading(size: 24))
                    .foregroundColor(FitTheme.textPrimary)
                Text("Customize your cardio session")
                    .font(FitFont.body(size: 12, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(10)
                    .background(FitTheme.cardBackground)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var summaryCard: some View {
        VStack(spacing: 14) {
            sessionSummary
            durationControls
            intensityControls
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(FitTheme.cardWorkout.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color(red: 0.2, green: 0.36, blue: 0.46).opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private var sessionSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Session")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                Text("\(durationMinutes) min")
                    .font(FitFont.heading(size: 28))
                    .foregroundColor(FitTheme.textPrimary)
            }

            Spacer()

            Text(intensity)
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(accentGradient)
                )
        }
    }

    private var durationControls: some View {
        HStack(spacing: 12) {
            Button(action: { adjustDuration(-1) }) {
                Image(systemName: "minus")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(FitTheme.cardBackground)
                    .clipShape(Circle())
            }

            VStack(spacing: 4) {
                Text("Adjust duration")
                    .font(FitFont.body(size: 11, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                Text("1 - 120 min")
                    .font(FitFont.body(size: 11, weight: .regular))
                    .foregroundColor(FitTheme.textSecondary.opacity(0.8))
            }

            Button(action: { adjustDuration(1) }) {
                Image(systemName: "plus")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(FitTheme.cardBackground)
                    .clipShape(Circle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var intensityControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Intensity")
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)

            HStack(spacing: 8) {
                ForEach(Array(intensityOptions.enumerated()), id: \.offset) { _, option in
                    let isActive = intensity == option
                    let backgroundStyle = isActive
                        ? AnyShapeStyle(accentGradient)
                        : AnyShapeStyle(FitTheme.cardHighlight)
                    Button(action: { intensity = option }) {
                        Text(option)
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(isActive ? .white : FitTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(backgroundStyle)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var timerSection: some View {
        VStack(spacing: 12) {
            timerStatus
            timerActions
        }
        .padding(.horizontal, 20)
    }

    private var timerStatus: some View {
        VStack(spacing: 8) {
            HStack {
                Text(isRunning ? "Live timer" : "Last session")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                Spacer()
                if isRunning {
                    Text(timeString(from: remainingSeconds))
                        .font(FitFont.mono(size: 20, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                } else if elapsedSeconds > 0 {
                    Text("Completed \(timeString(from: elapsedSeconds))")
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                } else {
                    Text("Ready to start")
                        .font(FitFont.body(size: 12, weight: .regular))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }

            if isRunning {
                ProgressView(value: progressValue)
                    .tint(Color(red: 0.2, green: 0.66, blue: 0.88))
            }
        }
    }

    private var timerActions: some View {
        HStack(spacing: 12) {
            if isRunning {
                Button(action: endAndSaveCardio) {
                    Text("End & Save")
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(FitTheme.cardHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            } else {
                Button(action: startCardio) {
                    Text(didComplete ? "Restart Cardio" : "Start Cardio")
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: FitTheme.cardWorkoutAccent.opacity(0.3), radius: 10, x: 0, y: 6)
                }
            }

            Button(action: saveCardio) {
                Text("Save Cardio")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(FitTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(FitTheme.cardStroke, lineWidth: 1)
                    )
            }
            .disabled(isRunning)
        }
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.56, blue: 0.98),
                Color(red: 0.18, green: 0.78, blue: 0.86)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var progressValue: Double {
        let total = max(1, remainingSeconds + elapsedSeconds)
        return 1.0 - (Double(remainingSeconds) / Double(total))
    }

    private func adjustDuration(_ delta: Int) {
        let updated = min(120, max(1, durationMinutes + delta))
        if updated != durationMinutes {
            durationMinutes = updated
        }
    }

    private func startCardio() {
        remainingSeconds = durationMinutes * 60
        elapsedSeconds = 0
        didComplete = false
        isRunning = true
        startTimerLoop()
    }

    private func endCardio() {
        isRunning = false
        stopTimerLoop()
    }

    private func endAndSaveCardio() {
        isRunning = false
        stopTimerLoop()
        saveCardio()
    }

    private func saveCardio() {
        var updated = recommendation
        if elapsedSeconds > 0 {
            updated.durationMinutes = max(1, Int(round(Double(elapsedSeconds) / 60.0)))
        } else {
            updated.durationMinutes = durationMinutes
        }
        updated.intensity = intensity
        onSave(updated)
        onLog(updated)
        Haptics.success()
        dismiss()
    }

    private func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let remaining = seconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }

    private func startTimerLoop() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let shouldContinue = await MainActor.run { () -> Bool in
                    guard isRunning else { return false }
                    if remainingSeconds > 0 {
                        remainingSeconds -= 1
                        elapsedSeconds += 1
                        return true
                    }
                    isRunning = false
                    didComplete = true
                    return false
                }
                if !shouldContinue {
                    break
                }
            }
        }
    }

    private func stopTimerLoop() {
        timerTask?.cancel()
        timerTask = nil
    }
}

private struct WorkoutExerciseLoggingSheet: View {
    let userId: String
    @Binding var exercise: WorkoutExerciseSession
    let exerciseIndex: Int
    let sessionExercises: [WorkoutExerciseSession]
    @Binding var restRemaining: Int
    @Binding var restActive: Bool
    let existingExerciseNames: Set<String>
    let onDeleteExercise: () -> Void
    let onCompleteSet: (Int, WorkoutSetEntry) -> Void
    let onShowHistory: () -> Void
    let onSkipRest: () -> Void
    let onAdjustRest: (Int) -> Void
    let onCreateDropSet: () -> Void
    let onCreateSuperset: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showCoachChat = false
    @State private var showRestPicker = false
    @State private var showWarmupRestPicker = false
    @State private var showMoreSheet = false
    @State private var showReplacePicker = false
    @State private var showNotesEditor = false
    @State private var showDeleteAlert = false
    @State private var showSupersetPicker = false
    @State private var showSupersetUnavailableAlert = false
    @State private var recommendedWeight: Double?
    @State private var lastSetInfo: String?
    @State private var isLoadingRecommendation = false
    @State private var showSetAddedFeedback = false
    @State private var isKeyboardVisible = false
    @State private var activeSetId: UUID?

    var body: some View {
        let base = loggingBase
        let withGestures = applyLoggingGestures(to: base)
        let withSheets = applyLoggingSheets(to: withGestures)
        let withAlerts = applyLoggingAlerts(to: withSheets)
        let withPostSheets = applyLoggingPostSheets(to: withAlerts)
        let withOverlay = applyLoggingOverlay(to: withPostSheets)
        return applyLoggingObservers(to: withOverlay)
    }

    private var loggingBase: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    // Weight Recommendation Card
                    if let recommended = recommendedWeight {
                        weightRecommendationCard(recommended: recommended, lastSet: lastSetInfo)
                    }

                    actionPills

                    if !warmupIndices.isEmpty {
                        sectionTitle("Warm-up Sets")
                        ForEach(Array(warmupIndices.enumerated()), id: \.element) { index, setIndex in
                        WorkoutSetRow(
                            index: index + 1,
                            unit: exercise.unit,
                            setEntry: $exercise.sets[setIndex],
                            activeSetId: $activeSetId,
                            isKeyboardVisible: isKeyboardVisible,
                            onComplete: { isComplete in
                                guard isComplete else { return }
                                onCompleteSet(exercise.warmupRestSeconds, exercise.sets[setIndex])
                            },
                            onDelete: { removeSet(id: exercise.sets[setIndex].id) }
                            )
                        }
                        warmupSetActions
                    }

                    sectionTitle("Working Sets")
                    ForEach(Array(workingIndices.enumerated()), id: \.element) { index, setIndex in
                        WorkoutSetRow(
                            index: index + 1,
                            unit: exercise.unit,
                            setEntry: $exercise.sets[setIndex],
                            activeSetId: $activeSetId,
                            isKeyboardVisible: isKeyboardVisible,
                            onComplete: { isComplete in
                                guard isComplete else { return }
                                // Auto-fill remaining sets when first working set is completed
                                if index == 0 {
                                    autoFillRemainingSets(from: setIndex)
                                }
                                onCompleteSet(exercise.restSeconds, exercise.sets[setIndex])
                            },
                            onDelete: { removeSet(id: exercise.sets[setIndex].id) }
                        )
                    }

                    setActions
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                await loadWeightRecommendation()
            }

            // Set Added Feedback Toast
            if showSetAddedFeedback {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Set added")
                            .font(FitFont.body(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 120)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: showSetAddedFeedback)
            }
        }
    }

    private func applyLoggingGestures<Content: View>(to view: Content) -> some View {
        view
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            // Swipe down gesture to go back (like FitBod)
            .simultaneousGesture(
                DragGesture(minimumDistance: 40, coordinateSpace: .local)
                    .onEnded { value in
                        guard !isKeyboardVisible else { return }
                        let isVertical = abs(value.translation.width) < 80
                        let isDownward = value.translation.height > 120
                        if isVertical && isDownward {
                            dismiss()
                        }
                    }
            )
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if restActive {
                        RestTimerCard(
                            remaining: restRemaining,
                            onSkip: onSkipRest,
                            onAdjust: onAdjustRest
                        )
                        .padding(.horizontal, 20)
                    }

                    // Primary action: log next set, then "Done" when finished.
                    let allSetsLogged = !hasIncompleteSets
                    Button {
                        if allSetsLogged {
                            dismiss()
                        } else {
                            logNextSet()
                        }
                    } label: {
                        Text(allSetsLogged ? "Done" : "Log Set")
                            .font(FitFont.body(size: 16, weight: .semibold))
                            .foregroundColor(FitTheme.buttonText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                if allSetsLogged {
                                    FitTheme.success
                                } else {
                                    FitTheme.primaryGradient
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .shadow(color: FitTheme.buttonShadow, radius: 12, x: 0, y: 8)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 10)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                    .foregroundColor(FitTheme.accent)
                }
            }
    }

    private func applyLoggingSheets<Content: View>(to view: Content) -> some View {
        view
            .sheet(isPresented: $showRestPicker) {
                RestTimePickerSheet(restSeconds: $exercise.restSeconds)
            }
            .sheet(isPresented: $showWarmupRestPicker) {
                RestTimePickerSheet(
                    restSeconds: $exercise.warmupRestSeconds,
                    title: "Warm-up Rest",
                    subtitle: "Set rest time between warm-up sets."
                )
            }
            .sheet(isPresented: $showReplacePicker) {
                ExercisePickerModal(
                    title: "Replace Exercise",
                    subtitle: "Search to swap this exercise.",
                    selectedNames: existingExerciseNames.subtracting([exercise.name]),
                    onAdd: { definition in
                        applyReplacement(definition)
                        showReplacePicker = false
                    },
                    onClose: { showReplacePicker = false }
                )
            }
            .sheet(isPresented: $showMoreSheet) {
                ExerciseMoreSheet(
                    notes: $exercise.notes,
                    unit: $exercise.unit,
                    recommendationPreference: $exercise.recommendationPreference,
                    onAddWarmup: addWarmupSet,
                    onEditNotes: {
                        showMoreSheet = false
                        showNotesEditor = true
                    },
                    onDelete: {
                        showMoreSheet = false
                        showDeleteAlert = true
                    },
                    onClose: { showMoreSheet = false }
                )
            }
            .sheet(isPresented: $showSupersetPicker) {
                ExercisePairingSheet(
                    title: ExerciseTag.superset.title,
                    sourceName: exercise.name,
                    exercises: sessionExercises,
                    sourceIndex: exerciseIndex,
                    onSelect: { targetIndex in
                        onCreateSuperset(targetIndex)
                        showSupersetPicker = false
                    },
                    onClose: { showSupersetPicker = false }
                )
            }
            .sheet(isPresented: $showNotesEditor) {
                ExerciseNotesSheet(notes: $exercise.notes)
            }
    }

    private func applyLoggingAlerts<Content: View>(to view: Content) -> some View {
        view
            .alert("Add another exercise", isPresented: $showSupersetUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Supersets need at least two exercises in the workout.")
            }
            .alert("Delete exercise?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    onDeleteExercise()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the exercise and its sets from the workout.")
            }
    }

    private func applyLoggingPostSheets<Content: View>(to view: Content) -> some View {
        view
            .sheet(isPresented: $showCoachChat) {
                CoachChatView(userId: userId)
            }
    }

    private func applyLoggingOverlay<Content: View>(to view: Content) -> some View {
        view
            .overlay(alignment: .bottomTrailing) {
                Button(action: { showCoachChat = true }) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.buttonText)
                        .padding(12)
                        .background(FitTheme.primaryGradient)
                        .clipShape(Circle())
                        .shadow(color: FitTheme.buttonShadow, radius: 10, x: 0, y: 6)
                }
                .padding(.trailing, 20)
                .padding(.bottom, restActive ? 180 : 84)
            }
    }

    private func applyLoggingObservers<Content: View>(to view: Content) -> some View {
        view
            .onChange(of: exercise.unit) { newValue in
                convertWeights(to: newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
    }

    private func addSet() {
        let last = exercise.sets.last
        let reps = last?.reps ?? "10"
        let weight = last?.weight ?? ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            exercise.sets.append(WorkoutSetEntry(reps: reps, weight: weight, isComplete: false, isWarmup: false))
        }
        Haptics.medium()
        showSetAddedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSetAddedFeedback = false
        }
    }

    private func addWarmupSet() {
        let lastWarmup = exercise.sets.last { $0.isWarmup }
        let reference = lastWarmup ?? exercise.sets.first
        let reps = reference?.reps ?? "10"
        let weight = reference?.weight ?? ""
        let entry = WorkoutSetEntry(reps: reps, weight: weight, isComplete: false, isWarmup: true)
        if let firstWorkingIndex = exercise.sets.firstIndex(where: { !$0.isWarmup }) {
            exercise.sets.insert(entry, at: firstWorkingIndex)
        } else {
            exercise.sets.append(entry)
        }
        Haptics.medium()
    }

    /// Auto-fill remaining working sets with the weight and reps from the first completed working set
    private func autoFillRemainingSets(from completedIndex: Int) {
        let completedSet = exercise.sets[completedIndex]
        let weight = completedSet.weight
        let reps = completedSet.reps
        
        // Only auto-fill if the completed set has both weight and reps
        guard !weight.isEmpty, !reps.isEmpty else { return }
        
        // Get all working set indices after the first one
        let workingSetIndices = exercise.sets.indices.filter { !exercise.sets[$0].isWarmup }
        
        // Skip the first working set (the one just completed) and fill the rest
        for setIndex in workingSetIndices.dropFirst() {
            // Only fill if the set hasn't been completed yet and is currently empty
            if !exercise.sets[setIndex].isComplete {
                // Only fill weight if it's empty (preserve user edits)
                if exercise.sets[setIndex].weight.isEmpty {
                    exercise.sets[setIndex].weight = weight
                }
                // Only fill reps if it's empty or still the default
                if exercise.sets[setIndex].reps.isEmpty || exercise.sets[setIndex].reps == "10" {
                    exercise.sets[setIndex].reps = reps
                }
            }
        }
    }

    private func removeSet(id: UUID) {
        exercise.sets.removeAll { $0.id == id }
    }

    private func applyReplacement(_ definition: ExerciseDefinition) {
        exercise.name = definition.name
        exercise.notes = ""
        exercise.recommendationPreference = .none
        let updatedSets = exercise.sets.map {
            WorkoutSetEntry(
                reps: $0.reps,
                weight: "",
                isComplete: false,
                isWarmup: $0.isWarmup
            )
        }
        exercise.sets = updatedSets
    }

    private func convertWeights(to newUnit: WeightUnit) {
        let oldUnit: WeightUnit = newUnit == .kg ? .lb : .kg
        guard oldUnit != newUnit else { return }
        exercise.sets = exercise.sets.map { entry in
            let converted = convertWeightString(entry.weight, from: oldUnit, to: newUnit)
            return WorkoutSetEntry(
                reps: entry.reps,
                weight: converted,
                isComplete: entry.isComplete,
                isWarmup: entry.isWarmup
            )
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

    private var completedSetsCount: Int {
        exercise.sets.filter { $0.isComplete && !$0.isWarmup }.count
    }
    
    private var totalWorkingSets: Int {
        exercise.sets.filter { !$0.isWarmup }.count
    }
    
    private var header: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(FitTheme.cardHighlight)
                .frame(width: 44, height: 5)
                .padding(.top, 4)

            // Top bar with close button
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
            
            // Exercise info card
            VStack(spacing: 16) {
                // Icon and name
                HStack(spacing: 14) {
                    // Exercise icon
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
                        Text(exercise.name)
                            .font(FitFont.heading(size: 22))
                            .foregroundColor(FitTheme.textPrimary)
                            .lineLimit(2)
                        
                        HStack(spacing: 8) {
                            // Progress indicator
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(completedSetsCount > 0 ? FitTheme.cardWorkoutAccent : FitTheme.textSecondary)
                                Text("\(completedSetsCount)/\(totalWorkingSets) sets")
                                    .font(FitFont.body(size: 12, weight: .medium))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                            
                            Text("•")
                                .foregroundColor(FitTheme.textSecondary.opacity(0.5))
                            
                            // Rest time badge
                            HStack(spacing: 3) {
                                Image(systemName: "timer")
                                    .font(.system(size: 10))
                                Text(formatRest(exercise.restSeconds))
                                    .font(FitFont.body(size: 12))
                            }
                            .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                    
                    Spacer()
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(FitTheme.cardStroke)
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [FitTheme.cardWorkoutAccent, FitTheme.cardWorkoutAccent.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: totalWorkingSets > 0 ? geometry.size.width * CGFloat(completedSetsCount) / CGFloat(totalWorkingSets) : 0, height: 6)
                            .animation(.spring(response: 0.4), value: completedSetsCount)
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
    
    private var exerciseIcon: String {
        let name = exercise.name.lowercased()
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
        } else {
            return "figure.strengthtraining.functional"
        }
    }

    private var actionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ExerciseActionPill(
                    title: "Edit Rest",
                    systemImage: "timer",
                    accentColor: FitTheme.accent,
                    action: { showRestPicker = true }
                )
                ExerciseActionPill(
                    title: "History",
                    systemImage: "chart.bar.fill",
                    accentColor: FitTheme.cardWorkoutAccent,
                    action: onShowHistory
                )
                ExerciseActionPill(
                    title: "Superset",
                    systemImage: "arrow.up.arrow.down",
                    accentColor: ExerciseTag.superset.color,
                    action: {
                        if sessionExercises.count > 1 {
                            showSupersetPicker = true
                        } else {
                            showSupersetUnavailableAlert = true
                        }
                    }
                )
                ExerciseActionPill(
                    title: "Drop Set",
                    systemImage: "arrow.down.right",
                    accentColor: ExerciseTag.dropSet.color,
                    action: {
                        onCreateDropSet()
                        Haptics.medium()
                    }
                )
                ExerciseActionPill(
                    title: "Replace",
                    systemImage: "arrow.triangle.2.circlepath",
                    accentColor: FitTheme.cardNutritionAccent,
                    action: { showReplacePicker = true }
                )
                ExerciseActionPill(
                    title: "More",
                    systemImage: "ellipsis.circle.fill",
                    accentColor: FitTheme.textSecondary,
                    action: { showMoreSheet = true }
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var setActions: some View {
        HStack(spacing: 12) {
            Button(action: addSet) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Add Set")
                        .font(FitFont.body(size: 14, weight: .semibold))
                }
                .foregroundColor(FitTheme.cardWorkoutAccent)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(FitTheme.cardWorkoutAccent.opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(FitTheme.cardWorkoutAccent.opacity(0.3), lineWidth: 1)
                )
            }

            Spacer()

            // Only show keyboard dismiss button when keyboard is visible
            if isKeyboardVisible {
                Button(action: dismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(FitTheme.textSecondary)
                        .padding(10)
                        .background(FitTheme.cardBackground)
                        .clipShape(Circle())
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
    }

    private var warmupSetActions: some View {
        HStack(spacing: 12) {
            Button(action: addWarmupSet) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Add Warm-up")
                        .font(FitFont.body(size: 14, weight: .semibold))
                }
                .foregroundColor(FitTheme.textSecondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(FitTheme.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(FitTheme.cardStroke, lineWidth: 1)
                )
            }

            Button(action: { showWarmupRestPicker = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Warm-up \(formatRest(exercise.warmupRestSeconds))")
                        .font(FitFont.body(size: 13, weight: .semibold))
                }
                .foregroundColor(FitTheme.textSecondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(FitTheme.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(FitTheme.cardStroke, lineWidth: 1)
                )
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(FitTheme.cardWorkoutAccent)
                .frame(width: 3, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            
            Text(text.uppercased())
                .font(FitFont.body(size: 11, weight: .bold))
                .foregroundColor(FitTheme.textSecondary)
                .tracking(1)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var warmupIndices: [Int] {
        exercise.sets.indices.filter { exercise.sets[$0].isWarmup }
    }

    private var workingIndices: [Int] {
        exercise.sets.indices.filter { !exercise.sets[$0].isWarmup }
    }

    private var hasIncompleteSets: Bool {
        exercise.sets.contains { !$0.isComplete }
    }

    private func logNextSet() {
        if let activeSetId,
           let activeIndex = exercise.sets.firstIndex(where: { $0.id == activeSetId }),
           !exercise.sets[activeIndex].isComplete {
            logSet(at: activeIndex)
            return
        }

        guard let nextIndex = exercise.sets.firstIndex(where: { !$0.isComplete }) else { return }
        logSet(at: nextIndex)
    }

    private func logSet(at index: Int) {
        guard exercise.sets.indices.contains(index) else { return }
        guard !exercise.sets[index].isComplete else { return }

        if !exercise.sets[index].isWarmup,
           let firstWorkingIndex = workingIndices.first,
           index == firstWorkingIndex {
            autoFillRemainingSets(from: index)
        }

        exercise.sets[index].isComplete = true
        let restSeconds = exercise.sets[index].isWarmup ? exercise.warmupRestSeconds : exercise.restSeconds
        onCompleteSet(restSeconds, exercise.sets[index])
        Haptics.light()
    }

    private func formatRest(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private func convertWeightString(_ value: String, from: WeightUnit, to: WeightUnit) -> String {
        guard from != to, let number = Double(value) else { return value }
        let converted = from == .lb ? number / 2.20462 : number * 2.20462
        let rounded = (converted * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
    
    // MARK: - Weight Recommendation
    
    private func weightRecommendationCard(recommended: Double, lastSet: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 20))
                .foregroundColor(FitTheme.accent)
                .frame(width: 36, height: 36)
                .background(FitTheme.accent.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Recommended")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Button {
                        applyRecommendedWeight(recommended)
                    } label: {
                        Text("Apply")
                            .font(FitFont.body(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(FitTheme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatWeight(recommended))
                        .font(FitFont.heading(size: 22, weight: .bold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(exercise.unit.label)
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                if let lastSet {
                    Text(lastSet)
                        .font(FitFont.body(size: 11))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            
            Spacer()
        }
        .padding(14)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(FitTheme.accent.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func loadWeightRecommendation() async {
        isLoadingRecommendation = true
        defer { Task { @MainActor in isLoadingRecommendation = false } }
        
        do {
            let history = try await WorkoutAPIService.shared.fetchExerciseHistory(
                userId: userId,
                exerciseName: exercise.name
            )
            
            guard let bestSet = history.bestSet else { return }
            
            // Progressive overload: recommend 2.5-5% increase from best set
            // or same weight if recent, to ensure user can complete sets
            let progressMultiplier = 1.025 // 2.5% increase
            let recommended = (bestSet.weight * progressMultiplier / 5).rounded() * 5 // Round to nearest 5
            
            // Convert if needed
            let finalWeight: Double
            if exercise.unit == .kg {
                finalWeight = (recommended / 2.20462 / 2.5).rounded() * 2.5 // Round to nearest 2.5 for kg
            } else {
                finalWeight = recommended
            }
            
            await MainActor.run {
                recommendedWeight = finalWeight
                lastSetInfo = "Last best: \(formatWeight(bestSet.weight)) lb × \(bestSet.reps) reps"
            }
        } catch {
            // Silently fail - just don't show recommendation
        }
    }
    
    private func applyRecommendedWeight(_ weight: Double) {
        let weightStr = formatWeight(weight)
        for index in exercise.sets.indices {
            if !exercise.sets[index].isComplete && !exercise.sets[index].isWarmup {
                exercise.sets[index].weight = weightStr
            }
        }
        Haptics.light()
    }
    
    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        }
        return String(format: "%.1f", weight)
    }
}

private struct ExerciseActionPill: View {
    let title: String
    let systemImage: String
    var accentColor: Color = FitTheme.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                Text(title)
                    .font(FitFont.body(size: 13, weight: .medium))
                    .foregroundColor(FitTheme.textPrimary)
            }
            .padding(.vertical, 10)
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .background(FitTheme.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(accentColor.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: accentColor.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct RestTimePickerSheet: View {
    @Binding var restSeconds: Int
    var title: String = "Rest Time"
    var subtitle: String = "Scroll to set the default rest timer."

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int = 60

    private let options = Array(stride(from: 30, through: 300, by: 5))

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Capsule()
                    .fill(FitTheme.cardHighlight)
                    .frame(width: 44, height: 5)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(FitFont.heading(size: 20))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(subtitle)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                Picker("Rest time", selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(timeString(from: option))
                            .tag(option)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .colorScheme(.light)

                Button {
                    restSeconds = selection
                    dismiss()
                } label: {
                    Text("Done")
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(FitTheme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .shadow(color: FitTheme.buttonShadow, radius: 12, x: 0, y: 8)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                Spacer()
            }
        }
        .onAppear {
            selection = nearestOption(to: restSeconds)
        }
        .onChange(of: selection) { newValue in
            restSeconds = newValue
        }
    }

    private func nearestOption(to value: Int) -> Int {
        options.min(by: { abs($0 - value) < abs($1 - value) }) ?? options[0]
    }

    private func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}

private struct ExerciseMoreSheet: View {
    @Binding var notes: String
    @Binding var unit: WeightUnit
    @Binding var recommendationPreference: ExerciseRecommendationPreference
    let onAddWarmup: () -> Void
    let onEditNotes: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void
    
    @State private var showWarmupAddedToast = false

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Capsule()
                    .fill(FitTheme.cardHighlight)
                    .frame(width: 44, height: 5)
                    .padding(.top, 12)

                HStack {
                    Text("Exercise options")
                        .font(FitFont.heading(size: 20))
                        .foregroundColor(FitTheme.textPrimary)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(8)
                            .background(FitTheme.cardBackground)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    ExerciseMoreRow(
                        title: notes.isEmpty ? "Add notes" : "Notes",
                        systemImage: "square.and.pencil",
                        isDestructive: false,
                        action: onEditNotes
                    )

                    ExerciseMoreRow(
                        title: "Add warm-up set",
                        systemImage: "flame",
                        isDestructive: false,
                        action: {
                            onAddWarmup()
                            Haptics.success()
                            withAnimation(.spring(response: 0.3)) {
                                showWarmupAddedToast = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    showWarmupAddedToast = false
                                }
                            }
                        }
                    )

                    HStack(spacing: 12) {
                        Image(systemName: "ruler")
                            .foregroundColor(FitTheme.textSecondary)
                        Text("Units")
                            .font(FitFont.body(size: 15))
                            .foregroundColor(FitTheme.textPrimary)
                        Spacer()
                        Picker("Units", selection: $unit) {
                            ForEach(WeightUnit.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                    .padding(14)
                    .background(FitTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    ExerciseToggleRow(
                        title: "Recommend more often",
                        systemImage: "arrow.up",
                        isOn: preferenceBinding(.moreOften)
                    )

                    ExerciseToggleRow(
                        title: "Recommend less often",
                        systemImage: "arrow.down",
                        isOn: preferenceBinding(.lessOften)
                    )

                    ExerciseToggleRow(
                        title: "Don't recommend again",
                        systemImage: "slash.circle",
                        isOn: preferenceBinding(.avoid)
                    )

                    if recommendationPreference != .none {
                        ExerciseMoreRow(
                            title: "Recommend again",
                            systemImage: "arrow.counterclockwise",
                            isDestructive: false,
                            action: { recommendationPreference = .none }
                        )
                    }

                    ExerciseMoreRow(
                        title: "Delete from workout",
                        systemImage: "trash",
                        isDestructive: true,
                        action: onDelete
                    )
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            
            // Warm-up added toast
            if showWarmupAddedToast {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 20))
                        Text("Warm-up set added")
                            .font(FitFont.body(size: 15, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(FitTheme.cardBackground)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func preferenceBinding(_ preference: ExerciseRecommendationPreference) -> Binding<Bool> {
        Binding(
            get: { recommendationPreference == preference },
            set: { isOn in
                recommendationPreference = isOn ? preference : .none
            }
        )
    }
}

private struct ExerciseMoreRow: View {
    let title: String
    let systemImage: String
    let isDestructive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundColor(isDestructive ? Color.red : FitTheme.textSecondary)
                Text(title)
                    .font(FitFont.body(size: 15))
                    .foregroundColor(isDestructive ? Color.red : FitTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(14)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct ExerciseToggleRow: View {
    let title: String
    let systemImage: String
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundColor(FitTheme.textSecondary)
                Text(title)
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textPrimary)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: FitTheme.accent))
        .padding(14)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ExerciseNotesSheet: View {
    @Binding var notes: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Text("Notes")
                        .font(FitFont.heading(size: 20))
                        .foregroundColor(FitTheme.textPrimary)
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.accent)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                TextEditor(text: $notes)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(12)
                    .frame(minHeight: 160)
                    .background(FitTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(FitTheme.cardStroke, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                Spacer()
            }
        }
    }
}

private struct RestTimerCard: View {
    let remaining: Int
    let onSkip: () -> Void
    let onAdjust: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rest Timer")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                Text(timeString(from: remaining))
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(FitTheme.textPrimary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { onAdjust(-10) }) {
                    Text("-10s")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(FitTheme.cardHighlight)
                        .clipShape(Capsule())
                }
                Button(action: { onAdjust(10) }) {
                    Text("+10s")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(FitTheme.cardHighlight)
                        .clipShape(Capsule())
                }
            }
            Button(action: onSkip) {
                Text("Skip")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.buttonText)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(FitTheme.primaryGradient)
                    .clipShape(Capsule())
                    .shadow(color: FitTheme.buttonShadow, radius: 8, x: 0, y: 6)
            }
        }
        .padding(14)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}

private struct WorkoutSetRow: View {
    let index: Int
    let unit: WeightUnit
    @Binding var setEntry: WorkoutSetEntry
    @Binding var activeSetId: UUID?
    let isKeyboardVisible: Bool
    let onComplete: (Bool) -> Void
    let onDelete: () -> Void
    @FocusState private var focusedField: Field?
    @State private var swipeOffset: CGFloat = 0
    @State private var showDeleteButton = false
    @State private var rowWidth: CGFloat = 0
    @State private var didTriggerLogHaptic = false
    @State private var dragAxis: DragAxis?

    private enum Field {
        case reps
        case weight
    }
    
    private let deleteButtonWidth: CGFloat = 80
    private let logThresholdRatio: CGFloat = 0.5
    private let minLogThreshold: CGFloat = 140
    private let maxLogSwipePadding: CGFloat = 30

    var body: some View {
        rowBase
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var isComplete: Bool {
        setEntry.isComplete
    }

    private var isWarmup: Bool {
        setEntry.isWarmup
    }

    private var isDropSet: Bool {
        setEntry.isDropSet
    }

    private var logThreshold: CGFloat {
        max(rowWidth * logThresholdRatio, minLogThreshold)
    }

    private var maxLogSwipe: CGFloat {
        max(rowWidth - maxLogSwipePadding, logThreshold + 20)
    }

	    private var logFillWidth: CGFloat {
	        max(0, min(swipeOffset, rowWidth))
	    }

	    private var swipeToggleLabel: String {
	        isComplete ? "UNLOG" : "LOG"
	    }

	    private var swipeToggleColor: Color {
	        isComplete ? FitTheme.accentMuted : FitTheme.success
	    }

    private var rowBase: some View {
        ZStack(alignment: .leading) {
            logBackground
            deleteButton
            rowContent
        }
    }

	    @ViewBuilder
	    private var logBackground: some View {
	        if swipeOffset > 0 {
	            RoundedRectangle(cornerRadius: 16, style: .continuous)
	                .fill(swipeToggleColor)
	                .frame(width: logFillWidth)
	                .overlay(
	                    Text(swipeToggleLabel)
	                        .font(FitFont.body(size: 13, weight: .bold))
	                        .foregroundColor(.white)
	                        .opacity(min(1, logFillWidth / 60))
	                        .padding(.leading, 16),
                    alignment: .leading
                )
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if swipeOffset < 0 {
            HStack {
                Spacer()
                Button(action: {
                    Haptics.medium()
                    withAnimation(.spring(response: 0.3)) {
                        swipeOffset = 0
                        showDeleteButton = false
                    }
                    onDelete()
                }) {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: deleteButtonWidth, height: 56)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var isSwipeGestureEnabled: Bool {
        !isKeyboardVisible && focusedField == nil
    }

    private var rowContentBase: some View {
        HStack(spacing: 0) {
            setNumber
            setMeta

            Spacer()

            setFieldModern(title: "Reps", value: $setEntry.reps, field: .reps, isComplete: isComplete)
                .padding(.trailing, 8)
            setFieldModern(title: unit.label.uppercased(), value: $setEntry.weight, field: .weight, isComplete: isComplete)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(rowBackground(isComplete: isComplete, isWarmup: isWarmup, isDropSet: isDropSet))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isComplete ? FitTheme.success.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
        .offset(x: swipeOffset)
        .background(rowWidthReader)
        .onChange(of: focusedField) { newValue in
            guard newValue != nil else { return }
            activeSetId = setEntry.id
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        if isSwipeGestureEnabled {
            rowContentBase
                .simultaneousGesture(swipeGesture, including: .gesture)
        } else {
            rowContentBase
        }
    }

    private var setNumber: some View {
        ZStack {
            Circle()
                .fill(setNumberBackground(isComplete: isComplete, isWarmup: isWarmup))
                .frame(width: 40, height: 40)

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text("\(index)")
                    .font(FitFont.body(size: 16, weight: .bold))
                    .foregroundColor(isWarmup ? FitTheme.textSecondary : FitTheme.cardWorkoutAccent)
            }
        }
        .padding(.trailing, 14)
    }

    private var setMeta: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isWarmup ? "Warm-up" : "Set \(index)")
                .font(FitFont.body(size: 12, weight: .medium))
                .foregroundColor(isComplete ? FitTheme.success : FitTheme.textSecondary)
            if isDropSet {
                Text("DROP SET")
                    .font(FitFont.body(size: 9, weight: .bold))
                    .foregroundColor(FitTheme.accent)
                    .tracking(0.5)
            }
        }
        .frame(width: 65, alignment: .leading)
    }

    private var rowWidthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    rowWidth = proxy.size.width
                }
                .onChange(of: proxy.size.width) { newValue in
                    rowWidth = newValue
                }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragAxis == nil {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    let isHorizontal = horizontal > max(vertical * 1.2, 12)
                    dragAxis = isHorizontal ? .horizontal : .vertical
                }
                guard dragAxis == .horizontal else { return }
                let translation = value.translation.width
                if showDeleteButton {
                    if translation > 0 {
                        swipeOffset = min(0, -deleteButtonWidth + translation)
                    }
                    return
                }
	                if translation < 0 {
	                    swipeOffset = max(translation, -deleteButtonWidth - 20)
	                    didTriggerLogHaptic = false
	                } else if translation > 0 {
	                    swipeOffset = min(translation, maxLogSwipe)
	                    let reachedThreshold = swipeOffset >= logThreshold
	                    if reachedThreshold && !didTriggerLogHaptic {
	                        isComplete ? Haptics.warning() : Haptics.success()
	                        didTriggerLogHaptic = true
	                    } else if !reachedThreshold {
	                        didTriggerLogHaptic = false
	                    }
	                }
            }
            .onEnded { value in
                defer { dragAxis = nil }
                guard dragAxis == .horizontal else { return }
                withAnimation(.spring(response: 0.3)) {
                    if showDeleteButton && value.translation.width > 0 {
                        swipeOffset = 0
                        showDeleteButton = false
                        didTriggerLogHaptic = false
	                    } else if value.translation.width < -40 {
	                        swipeOffset = -deleteButtonWidth
	                        showDeleteButton = true
	                    } else if value.translation.width >= logThreshold {
	                        swipeOffset = 0
	                        showDeleteButton = false
	                        didTriggerLogHaptic = false
	                        setCompletion(!isComplete, triggerHaptics: false)
	                    } else {
	                        swipeOffset = 0
	                        showDeleteButton = false
	                        didTriggerLogHaptic = false
                    }
                }
            }
    }

    private func rowBackground(isComplete: Bool, isWarmup: Bool, isDropSet: Bool) -> Color {
        if isComplete {
            return FitTheme.success.opacity(0.08)
        }
        if isDropSet {
            return FitTheme.accentMuted
        }
        if isWarmup {
            return FitTheme.cardBackground.opacity(0.6)
        }
        return FitTheme.cardBackground
    }
    
    private func setNumberBackground(isComplete: Bool, isWarmup: Bool) -> Color {
        if isComplete {
            return FitTheme.success
        }
        if isWarmup {
            return FitTheme.cardStroke
        }
        return FitTheme.cardWorkoutAccent.opacity(0.15)
    }

	    private func setField(title: String, value: Binding<String>, field: Field) -> some View {
	        VStack(alignment: .leading, spacing: 2) {
	            Text(title)
	                .font(FitFont.body(size: 10))
                .foregroundColor(FitTheme.textSecondary)
	            TextField("0", text: value)
	                .keyboardType(.numberPad)
	                .font(FitFont.body(size: 13))
	                .foregroundColor(FitTheme.textPrimary)
	                .focused($focusedField, equals: field)
	                .submitLabel(.done)
	        }
	        .frame(width: 70)
	    }
    
    private func setFieldModern(title: String, value: Binding<String>, field: Field, isComplete: Bool) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(FitFont.body(size: 10, weight: .medium))
                .foregroundColor(FitTheme.textSecondary.opacity(0.7))
            
	            TextField("—", text: value)
	                .keyboardType(.numberPad)
	                .font(FitFont.heading(size: 18))
	                .foregroundColor(isComplete ? FitTheme.success : FitTheme.textPrimary)
	                .multilineTextAlignment(.center)
	                .focused($focusedField, equals: field)
	                .submitLabel(.done)
	                .frame(width: 55)
	                .padding(.vertical, 6)
	                .padding(.horizontal, 8)
	                .background(isComplete ? FitTheme.success.opacity(0.08) : FitTheme.cardHighlight)
	                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
	        }
	    }

	    private func setCompletion(_ value: Bool, triggerHaptics: Bool = true) {
	        guard setEntry.isComplete != value else { return }
	        // Dismiss keyboard when completing a set
	        focusedField = nil
	        setEntry.isComplete = value
	        onComplete(value)
	        if triggerHaptics {
	            value ? Haptics.light() : Haptics.selection()
	        }
	    }
	}

struct ExerciseDetailView: View {
    let userId: String
    let exerciseName: String
    let unit: WeightUnit

    @State private var history: ExerciseHistoryResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    movementVideoCard

                    if isLoading {
                        Text("Loading history…")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    } else if let history {
                        statCard(history: history)

                        trendCard(history: history)

                        historyCard(history: history)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .task {
            await loadHistory()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exerciseName)
                .font(FitFont.heading(size: 26))
                .foregroundColor(FitTheme.textPrimary)
            Text("Results and trends")
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private var movementVideoCard: some View {
        if let url = ExerciseVideoLibrary.url(for: exerciseName) {
            return AnyView(
                WorkoutDetailCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Movement video")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            )
        }
        return AnyView(
            WorkoutDetailCard {
                HStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(FitTheme.cardWorkoutAccent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Movement video")
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Add a video source to show form demos.")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    Spacer()
                }
            }
        )
    }

    private func statCard(history: ExerciseHistoryResponse) -> some View {
        let bestSet = history.bestSet
        return WorkoutDetailCard {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Best Set")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                    Text(bestSet.map { "\(formatWeight($0.weight)) \(unit.label) x \($0.reps)" } ?? "No data")
                        .font(FitFont.body(size: 20))
                        .foregroundColor(FitTheme.textPrimary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Estimated 1RM")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                    Text(history.estimated1rm > 0 ? "\(formatWeight(history.estimated1rm)) \(unit.label)" : "No data")
                        .font(FitFont.body(size: 20))
                        .foregroundColor(FitTheme.textPrimary)
                }
            }
        }
    }

    private func trendCard(history: ExerciseHistoryResponse) -> some View {
        let values = history.trend.map { convertWeight($0.estimated1rm) }
        return WorkoutDetailCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("4-Week Trend")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                ExerciseTrendChart(values: values)
                    .frame(height: 140)
            }
        }
    }

    private func historyCard(history: ExerciseHistoryResponse) -> some View {
        return WorkoutDetailCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Sessions")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                if history.entries.isEmpty {
                    Text("No sessions logged yet.")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                ForEach(history.entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date ?? "Unknown date")
                                .font(FitFont.body(size: 14))
                                .foregroundColor(FitTheme.textPrimary)
                            Text("\(entry.sets) sets · \(entry.reps) reps · \(formatWeight(entry.weight)) \(unit.label)")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        Spacer()
                        Text("\(formatWeight(entry.estimated1rm)) 1RM")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    .padding(12)
                    .background(FitTheme.cardHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func loadHistory() async {
        guard !userId.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await WorkoutAPIService.shared.fetchExerciseHistory(
                userId: userId,
                exerciseName: exerciseName
            )
            await MainActor.run {
                history = result
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Unable to load exercise history."
                isLoading = false
            }
        }
    }

    private func convertWeight(_ weight: Double) -> Double {
        unit == .kg ? weight / 2.20462 : weight
    }

    private func formatWeight(_ weight: Double) -> String {
        let value = convertWeight(weight)
        let rounded = (value * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}

private struct ExerciseTrendChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(FitTheme.accent, lineWidth: 2)

                ForEach(points.indices, id: \.self) { index in
                    Circle()
                        .fill(FitTheme.accent)
                        .frame(width: 6, height: 6)
                        .position(points[index])
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1,
              let minValue = values.min(),
              let maxValue = values.max(),
              maxValue > minValue else {
            return []
        }
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let x = CGFloat(index) * stepX
            let normalized = (value - minValue) / (maxValue - minValue)
            let y = size.height - CGFloat(normalized) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}

private struct WorkoutDetailCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: FitTheme.shadow, radius: 12, x: 0, y: 6)
    }
}
