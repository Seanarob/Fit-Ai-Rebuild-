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
    let onSearch: (String) async -> [ExerciseDefinition]
    let selectedNames: Set<String>
    let onAdd: (ExerciseDefinition) -> Void
    let onClose: () -> Void

    @State private var searchText = ""
    @State private var selectedMuscleGroups: Set<String> = []
    @State private var selectedEquipment: Set<String> = []
    @State private var catalog: [ExerciseDefinition] = []
    @State private var isLoading = false

    init(
        title: String = "Add Exercise",
        subtitle: String = "Search and filter to build your workout.",
        onSearch: @escaping (String) async -> [ExerciseDefinition],
        selectedNames: Set<String>,
        onAdd: @escaping (ExerciseDefinition) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onSearch = onSearch
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
        .task(id: searchText) {
            isLoading = true
            catalog = await onSearch(searchText)
            isLoading = false
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
                    ForEach(options, id: \.self) { option in
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

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Capsule()
                    .fill(FitTheme.cardHighlight)
                    .frame(width: 48, height: 5)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text(template.title)
                        .font(FitFont.body(size: 20))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("Saved workout actions")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    WorkoutSheetButton(title: "Start Workout", systemImage: "play.fill", isDestructive: false, action: onStart)
                    WorkoutSheetButton(title: "Edit Template", systemImage: "slider.horizontal.3", isDestructive: false, action: onEdit)
                    WorkoutSheetButton(title: "Duplicate", systemImage: "doc.on.doc", isDestructive: false, action: onDuplicate)
                    WorkoutSheetButton(title: "Delete", systemImage: "trash", isDestructive: true, action: onDelete)
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
    @State private var showExerciseMenu = false
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

    private let restTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let workoutTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
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

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                                    onMore: {
                                        insertionIndex = index
                                        taggingExerciseIndex = index
                                        showExerciseMenu = true
                                    },
                                    onTag: { tag in
                                        if tag == nil {
                                            clearTag(for: index)
                                        } else {
                                            exerciseTags[exercises[index].id] = tag
                                        }
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
        .confirmationDialog("Exercise options", isPresented: $showExerciseMenu, titleVisibility: .visible) {
            Button("Edit Sets & Reps") {
                openExerciseEditor()
            }
            Button("Create Superset") {
                beginTagging(.superset)
            }
            Button("Create Drop Set") {
                beginTagging(.dropSet)
            }
            if let index = taggingExerciseIndex,
               exercises.indices.contains(index),
               exerciseTags[exercises[index].id] != nil {
                Button("Clear Tag", role: .destructive) {
                    clearTag(for: index)
                }
            }
            Button("Cancel", role: .cancel) {}
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
                onSearch: { query in
                    (try? await WorkoutAPIService.shared.searchExercises(query: query)) ?? []
                },
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
                    onAdjustRest: adjustRestTimer
                )
                .id(exercises[index].id)
            }
        }
        .task {
            if sessionTitle.isEmpty {
                sessionTitle = title
            }
        }
        .onReceive(restTicker) { _ in
            guard restActive else { return }
            if restRemaining > 0 {
                restRemaining -= 1
                RestTimerLiveActivity.update(remainingSeconds: restRemaining)
            }
            if restRemaining <= 0 {
                completeRestTimer()
            }
        }
        .onReceive(workoutTicker) { _ in
            guard !isPaused else { return }
            workoutElapsed += 1
        }
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
        RestTimerLiveActivity.stop()
        restRemaining = max(seconds, 0)
        restActive = restRemaining > 0
        if restActive {
            scheduleRestNotification(seconds: restRemaining)
            RestTimerLiveActivity.start(workoutName: sessionTitle.isEmpty ? title : sessionTitle, durationSeconds: restRemaining)
        }
    }

    private func stopRestTimer() {
        restActive = false
        restRemaining = 0
        cancelRestNotification()
        RestTimerLiveActivity.stop()
    }

    private func adjustRestTimer(by delta: Int) {
        let updated = max(restRemaining + delta, 0)
        restRemaining = updated
        restActive = updated > 0
        cancelRestNotification()
        if restActive {
            scheduleRestNotification(seconds: restRemaining)
            RestTimerLiveActivity.update(remainingSeconds: restRemaining)
        } else {
            RestTimerLiveActivity.stop()
        }
    }

    private func completeRestTimer() {
        restActive = false
        restRemaining = 0
        RestTimerLiveActivity.stop()
        Haptics.success()
        SoundEffects.restComplete()
    }

    private func scheduleRestNotification(seconds: Int) {
        guard seconds > 0 else { return }
        let notificationId = "fitai.rest.\(UUID().uuidString)"
        restNotificationId = notificationId

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let updatedSettings = await center.notificationSettings()
            guard updatedSettings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Your rest is done!"
            content.body = "Time for your next set."
            content.sound = .default

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

    private func logSetIfNeeded(exerciseName: String, setEntry: WorkoutSetEntry, unit: WeightUnit) {
        guard !setEntry.isWarmup else { return }
        let reps = Int(setEntry.reps) ?? 0
        let rawWeight = Double(setEntry.weight) ?? 0
        let weight = unit == .kg ? rawWeight * 2.20462 : rawWeight
        if let sessionId {
            Task {
                try? await WorkoutAPIService.shared.logExerciseSet(
                    sessionId: sessionId,
                    exerciseName: exerciseName,
                    sets: 1,
                    reps: reps,
                    weight: weight,
                    notes: nil
                )
            }
        } else {
            savePendingLog(
                PendingExerciseLog(
                    sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                    exerciseName: exerciseName,
                    reps: reps,
                    weight: weight,
                    durationMinutes: nil,
                    createdAt: Date()
                )
            )
        }
    }

    private func logCardioIfNeeded(_ recommendation: CardioRecommendation) {
        guard recommendation.durationMinutes > 0 else { return }
        let name = "Cardio - \(recommendation.title)"
        if let sessionId {
            Task {
                try? await WorkoutAPIService.shared.logCardioDuration(
                    sessionId: sessionId,
                    exerciseName: name,
                    durationMinutes: recommendation.durationMinutes,
                    notes: "Intensity: \(recommendation.intensity)"
                )
            }
        } else {
            savePendingLog(
                PendingExerciseLog(
                    sessionTitle: sessionTitle.isEmpty ? title : sessionTitle,
                    exerciseName: name,
                    reps: 0,
                    weight: 0,
                    durationMinutes: recommendation.durationMinutes,
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
            return
        }
        isCompleting = true
        do {
            let summary = try await WorkoutAPIService.shared.completeSession(
                sessionId: sessionId,
                durationSeconds: workoutElapsed
            )
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
        }
    }

    private func addExercise(_ definition: ExerciseDefinition) {
        let newExercise = WorkoutExerciseSession(
            name: definition.name,
            sets: WorkoutSetEntry.batch(reps: "10", weight: "", count: 3),
            restSeconds: 60
        )
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
        let entry = WorkoutExerciseSession(
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
        exercises.append(entry)
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
        let sourceId = exercises[sourceIndex].id
        let targetId = exercises[targetIndex].id
        exerciseTags[sourceId] = tag
        exerciseTags[targetId] = tag
        exerciseTagLinks[sourceId] = targetId
        exerciseTagLinks[targetId] = sourceId
        pendingSupersetRestExerciseId = nil
        pendingTagType = nil
        showTagPicker = false
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
        logSetIfNeeded(
            exerciseName: exercises[index].name,
            setEntry: setEntry,
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

private struct WorkoutCompletionSheet: View {
    let summary: WorkoutSessionCompleteResponse
    let streakCount: Int
    let onDone: () -> Void

    @State private var step: CompletionStep
    @State private var animatedStreak = 0
    @State private var streakPulse = false

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

                if step == .pr {
                    prView
                } else {
                    congratsView
                }

                Spacer()
            }
        }
    }

    private var prView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(FitTheme.accent)

            Text("PR!")
                .font(FitFont.heading(size: 26))
                .foregroundColor(FitTheme.textPrimary)

            TabView {
                ForEach(summary.prs) { pr in
                    VStack(spacing: 8) {
                        Text(pr.exerciseName)
                            .font(FitFont.body(size: 18))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("\(Int(pr.value)) lb")
                            .font(FitFont.heading(size: 30))
                            .foregroundColor(FitTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 120)

            CompletionActionButton(title: "Continue") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    step = .congrats
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 20)
    }

    private var congratsView: some View {
        VStack(spacing: 14) {
            CoachCharacterView(size: 120, showBackground: false, pose: .celebration)
                .padding(.top, 6)

            Text("Workout complete")
                .font(FitFont.heading(size: 24))
                .foregroundColor(FitTheme.textPrimary)

            Text("Quick win, solid effort. Keep it rolling.")
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(FitTheme.accent)
                    Text("\(animatedStreak)")
                        .font(FitFont.heading(size: 28))
                        .foregroundColor(FitTheme.textPrimary)
                }
                .scaleEffect(streakPulse ? 1.08 : 1.0)

                Text("day streak")
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(.top, 6)

            Text("Duration · \(formatDuration(summary.durationSeconds))")
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)

            CompletionActionButton(title: "Done", action: onDone)
                .padding(.horizontal, 20)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
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
                .shadow(color: FitTheme.buttonShadow, radius: 10, x: 0, y: 6)
        }
    }
}

private struct PendingExerciseLog: Codable {
    let sessionTitle: String
    let exerciseName: String
    let reps: Int
    let weight: Double
    let durationMinutes: Int?
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
    let onMore: () -> Void
    let onTag: (ExerciseTag?) -> Void

    var body: some View {
        let completedSets = exercise.sets.filter { $0.isComplete }.count
        let isComplete = !exercise.sets.isEmpty && completedSets == exercise.sets.count

        return Button(action: onOpen) {
            HStack(spacing: 12) {
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

                    Text("\(completedSets)/\(exercise.sets.count) sets  •  \(exercise.sets.first?.reps ?? "10") reps")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }

                Spacer()

                if let supersetIndicator {
                    Image(systemName: supersetIndicator.systemImage)
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(ExerciseTag.superset.color)
                        .padding(6)
                        .background(ExerciseTag.superset.color.opacity(0.12))
                        .clipShape(Circle())
                }

                Button(action: onMore) {
                    Image(systemName: "ellipsis")
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(14)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Clear Tag") {
                onTag(nil)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "stopwatch.fill")
                        .foregroundColor(Color(red: 0.5, green: 0.75, blue: 1))
                        .padding(10)
                        .background(Color(red: 0.12, green: 0.2, blue: 0.3))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Recommended Cardio")
                            .font(FitFont.body(size: 20))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Based on your training level and goals")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }

                Spacer()

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

            Text("💡 Tap a row to select and customize your cardio")
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.12, blue: 0.2), FitTheme.cardBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(red: 0.2, green: 0.3, blue: 0.45), lineWidth: 1)
        )
    }
}

private struct CardioRow: View {
    let recommendation: CardioRecommendation
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.title)
                        .font(FitFont.body(size: 16))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(recommendation.intensity)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }

                Spacer()

                Text("\(recommendation.durationMinutes) min")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textPrimary)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(FitTheme.accent)
                        .font(FitFont.body(size: 14))
                }
            }
            .padding(12)
            .background(isSelected ? FitTheme.cardHighlight : FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendation.title)
                            .font(FitFont.heading(size: 22))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Customize your cardio")
                            .font(FitFont.body(size: 12))
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

                VStack(spacing: 14) {
                    HStack {
                        Text("Duration")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                        Spacer()
                        Text("\(durationMinutes) min")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textPrimary)
                    }

                    Stepper(value: $durationMinutes, in: 1...120, step: 1) {
                        Text("Adjust time")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    Text("Intensity")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Intensity", selection: $intensity) {
                        ForEach(intensityOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(16)
                .background(FitTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    if isRunning {
                        Text(timeString(from: remainingSeconds))
                            .font(FitFont.heading(size: 28))
                            .foregroundColor(FitTheme.textPrimary)
                    } else if elapsedSeconds > 0 {
                        Text("Completed \(timeString(from: elapsedSeconds))")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    HStack(spacing: 12) {
                        if isRunning {
                            Button(action: endAndSaveCardio) {
                                Text("End & Save")
                                    .font(FitFont.body(size: 14))
                                    .fontWeight(.semibold)
                                    .foregroundColor(FitTheme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(FitTheme.cardHighlight)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        } else {
                            Button(action: startCardio) {
                                Text(didComplete ? "Restart Cardio" : "Start Cardio")
                                    .font(FitFont.body(size: 14))
                                    .fontWeight(.semibold)
                                    .foregroundColor(FitTheme.buttonText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(FitTheme.primaryGradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .shadow(color: FitTheme.buttonShadow, radius: 10, x: 0, y: 6)
                            }
                        }

                        Button(action: saveCardio) {
                            Text("Save Cardio")
                                .font(FitFont.body(size: 14))
                                .fontWeight(.semibold)
                                .foregroundColor(FitTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(FitTheme.cardHighlight)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(isRunning)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .onDisappear {
            timerTask?.cancel()
            timerTask = nil
        }
        .onChange(of: durationMinutes) { newValue in
            guard !isRunning else { return }
            remainingSeconds = newValue * 60
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
    @Binding var restRemaining: Int
    @Binding var restActive: Bool
    let existingExerciseNames: Set<String>
    let onDeleteExercise: () -> Void
    let onCompleteSet: (Int, WorkoutSetEntry) -> Void
    let onShowHistory: () -> Void
    let onSkipRest: () -> Void
    let onAdjustRest: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showCoachChat = false
    @State private var showRestPicker = false
    @State private var showMoreSheet = false
    @State private var showReplacePicker = false
    @State private var showNotesEditor = false
    @State private var showDeleteAlert = false

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    actionPills

                    if !warmupIndices.isEmpty {
                        sectionTitle("Warm-up Sets")
                        ForEach(Array(warmupIndices.enumerated()), id: \.element) { index, setIndex in
                            WorkoutSetRow(
                                index: index + 1,
                                unit: exercise.unit,
                                setEntry: $exercise.sets[setIndex],
                                onComplete: { isComplete in
                                    guard isComplete else { return }
                                    onCompleteSet(exercise.restSeconds, exercise.sets[setIndex])
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
                            onComplete: { isComplete in
                                guard isComplete else { return }
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
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
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

                Button("Done") {
                    dismiss()
                }
                .font(FitFont.body(size: 16, weight: .semibold))
                .foregroundColor(FitTheme.buttonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(FitTheme.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: FitTheme.buttonShadow, radius: 12, x: 0, y: 8)
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 10)
        }
        .sheet(isPresented: $showRestPicker) {
            RestTimePickerSheet(restSeconds: $exercise.restSeconds)
        }
        .sheet(isPresented: $showReplacePicker) {
            ExercisePickerModal(
                title: "Replace Exercise",
                subtitle: "Search to swap this exercise.",
                onSearch: { query in
                    (try? await WorkoutAPIService.shared.searchExercises(query: query)) ?? []
                },
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
        .sheet(isPresented: $showNotesEditor) {
            ExerciseNotesSheet(notes: $exercise.notes)
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
        .sheet(isPresented: $showCoachChat) {
            CoachChatView(userId: userId)
        }
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
        .onChange(of: exercise.unit) { newValue in
            convertWeights(to: newValue)
        }
    }

    private func addSet() {
        let last = exercise.sets.last
        let reps = last?.reps ?? "10"
        let weight = last?.weight ?? ""
        exercise.sets.append(WorkoutSetEntry(reps: reps, weight: weight, isComplete: false, isWarmup: false))
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(FitFont.heading(size: 24))
                .foregroundColor(FitTheme.textPrimary)
            Text("Log your sets")
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)
        }
        .padding(.top, 12)
    }

    private var actionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ExerciseActionPill(
                    title: "\(formatRest(exercise.restSeconds)) rest",
                    systemImage: "timer",
                    action: { showRestPicker = true }
                )
                ExerciseActionPill(
                    title: "History",
                    systemImage: "chart.bar",
                    action: onShowHistory
                )
                ExerciseActionPill(
                    title: "Replace",
                    systemImage: "arrow.left.arrow.right",
                    action: { showReplacePicker = true }
                )
                ExerciseActionPill(
                    title: "More",
                    systemImage: "ellipsis",
                    action: { showMoreSheet = true }
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var setActions: some View {
        HStack(spacing: 10) {
            Button(action: addSet) {
                Label("Add Set", systemImage: "plus")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(FitTheme.cardHighlight)
                    .clipShape(Capsule())
            }

            Spacer()

            Button(action: dismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(FitTheme.cardHighlight)
                    .clipShape(Capsule())
            }
        }
    }

    private var warmupSetActions: some View {
        HStack(spacing: 10) {
            Button(action: addWarmupSet) {
                Label("Add Set", systemImage: "plus")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(FitTheme.cardHighlight)
                    .clipShape(Capsule())
            }

            Spacer()

            Button(action: dismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(FitTheme.cardHighlight)
                    .clipShape(Capsule())
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(FitFont.body(size: 12))
            .foregroundColor(FitTheme.textSecondary)
            .padding(.top, 6)
    }

    private var warmupIndices: [Int] {
        exercise.sets.indices.filter { exercise.sets[$0].isWarmup }
    }

    private var workingIndices: [Int] {
        exercise.sets.indices.filter { !exercise.sets[$0].isWarmup }
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
}

private struct ExerciseActionPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(FitFont.body(size: 12, weight: .semibold))
                Text(title)
                    .font(FitFont.body(size: 12, weight: .semibold))
            }
            .foregroundColor(FitTheme.textPrimary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(FitTheme.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RestTimePickerSheet: View {
    @Binding var restSeconds: Int
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
                    Text("Rest Time")
                        .font(FitFont.heading(size: 20))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("Scroll to set the default rest timer.")
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

                Button("Done") {
                    restSeconds = selection
                    dismiss()
                }
                .font(FitFont.body(size: 16, weight: .semibold))
                .foregroundColor(FitTheme.buttonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(FitTheme.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: 18))
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
                        action: onAddWarmup
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
    let onComplete: (Bool) -> Void
    let onDelete: () -> Void
    @FocusState private var focusedField: Field?

    private enum Field {
        case reps
        case weight
    }

    var body: some View {
        let isComplete = setEntry.isComplete
        let isWarmup = setEntry.isWarmup
        let isDropSet = setEntry.isDropSet
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isWarmup ? "Warm-up \(index)" : "Set \(index)")
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)
                if isDropSet {
                    Text("Drop Set")
                        .font(FitFont.body(size: 10, weight: .semibold))
                        .foregroundColor(FitTheme.accent)
                }
            }
            .frame(width: 88, alignment: .leading)

            setField(title: "Reps", value: $setEntry.reps, field: .reps)
            setField(title: "Weight (\(unit.label))", value: $setEntry.weight, field: .weight)

            Button(action: { setCompletion(!isComplete) }) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isComplete ? FitTheme.success : FitTheme.textSecondary)
                    .font(FitFont.body(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(rowBackground(isComplete: isComplete, isWarmup: isWarmup, isDropSet: isDropSet))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isComplete {
                Button("Undo") {
                    setCompletion(false)
                }
                .tint(FitTheme.cardHighlight)
            } else {
                Button("Log") {
                    setCompletion(true)
                }
                .tint(FitTheme.success)
            }

            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }

    private func rowBackground(isComplete: Bool, isWarmup: Bool, isDropSet: Bool) -> Color {
        if isComplete {
            return FitTheme.success.opacity(0.18)
        }
        if isDropSet {
            return FitTheme.accentMuted
        }
        if isWarmup {
            return FitTheme.accentSoft
        }
        return FitTheme.cardHighlight
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
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                        }
                    }
                }
        }
        .frame(width: 70)
    }

    private func setCompletion(_ value: Bool) {
        guard setEntry.isComplete != value else { return }
        setEntry.isComplete = value
        onComplete(value)
        if value {
            Haptics.light()
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
