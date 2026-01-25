import Foundation
import SwiftUI

struct WorkoutView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case generate = "Generate"
        case saved = "Saved"
        case create = "Create"

        var id: String { rawValue }
    }

    @Binding private var intent: WorkoutTabIntent?
    @State private var mode: Mode = .generate
    @State private var selectedMuscleGroups: Set<String> = [
        MuscleGroup.chest.rawValue,
        MuscleGroup.back.rawValue
    ]
    @State private var selectedEquipment: Set<String> = []
    @State private var selectedDurationMinutes = 45
    @State private var generatedPreview = ""
    @State private var generatedTitle = "AI Generated Workout"
    @State private var generatedExercises: [WorkoutExerciseSession] = []
    @State private var generatedEstimatedMinutes = 0
    @State private var isGenerating = false
    @State private var isGeneratedSwapPresented = false
    @State private var generatedSwapIndex: Int?
    @State private var templates: [WorkoutTemplate] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var templateSearch = ""
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var isTemplateActionsPresented = false
    @State private var isExercisePickerPresented = false
    @State private var draftName = ""
    @State private var draftExercises: [WorkoutExerciseDraft] = []
    @State private var activeSession: SessionDraft?
    @State private var isSavingDraft = false
    @State private var editingTemplateId: String?
    @State private var pendingDeleteTemplate: WorkoutTemplate?
    @State private var isSwapSheetPresented = false
    @State private var showDeleteAlert = false
    @State private var showNewTemplateAlert = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showTunePlanSheet = false
    @State private var todaysWorkout: WorkoutCompletion?

    let userId: String

    init(userId: String, intent: Binding<WorkoutTabIntent?> = .constant(nil)) {
        self.userId = userId
        _intent = intent
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WorkoutStreakHeader(streakCount: WorkoutStreakStore.current())

                    WorkoutSpotlightCard(
                        title: "Today's Training",
                        subtitle: spotlightSubtitle,
                        durationMinutes: estimateWorkoutMinutes(spotlightExercises),
                        exercises: spotlightExercises.map { $0.name },
                        completedExercises: todaysWorkout?.exercises ?? [],
                        isCompleted: todaysWorkout != nil,
                        onStart: {
                            Task {
                                await startSession(
                                    title: "Today's Training",
                                    templateId: nil,
                                    exercises: spotlightExercises
                                )
                            }
                        },
                        onSwap: {
                            isSwapSheetPresented = true
                        }
                    )

                    ModePicker(mode: $mode)

                    switch mode {
                    case .generate:
                        generateSection
                    case .saved:
                        savedSection
                    case .create:
                        createSection
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
        }
        .task {
            await loadWorkouts()
            todaysWorkout = WorkoutCompletionStore.todaysCompletion()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIWorkoutCompleted)) { notification in
            if let completion = notification.userInfo?["completion"] as? WorkoutCompletion {
                todaysWorkout = completion
            } else {
                todaysWorkout = WorkoutCompletionStore.todaysCompletion()
            }
        }
        .sheet(isPresented: $isExercisePickerPresented) {
            ExercisePickerModal(
                onSearch: { query in
                    await searchExercises(query: query)
                },
                selectedNames: Set(draftExercises.map { $0.name }),
                onAdd: { exercise in
                    let newExercise = WorkoutExerciseDraft(
                        name: exercise.name,
                        muscleGroup: exercise.muscleGroups.first ?? "General",
                        equipment: exercise.equipment.first ?? "Bodyweight",
                        sets: 3,
                        reps: 10,
                        restSeconds: 90,
                        notes: ""
                    )
                    draftExercises.append(newExercise)
                },
                onClose: { isExercisePickerPresented = false }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isGeneratedSwapPresented) {
            ExercisePickerModal(
                onSearch: { query in
                    await searchExercises(query: query)
                },
                selectedNames: Set(generatedExercises.map { $0.name }),
                onAdd: { exercise in
                    guard let index = generatedSwapIndex else { return }
                    let restSeconds = isCompoundExercise(exercise.name) ? 90 : 60
                    let replacement = WorkoutExerciseSession(
                        name: exercise.name,
                        sets: WorkoutSetEntry.batch(reps: "10", weight: "", count: 4),
                        restSeconds: restSeconds
                    )
                    if generatedExercises.indices.contains(index) {
                        generatedExercises[index] = replacement
                    }
                    isGeneratedSwapPresented = false
                },
                onClose: { isGeneratedSwapPresented = false }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isTemplateActionsPresented) {
            if let template = selectedTemplate {
                WorkoutTemplateActionsSheet(
                    template: template,
                    onStart: {
                        Task {
                            await startSession(from: template)
                        }
                        isTemplateActionsPresented = false
                    },
                    onEdit: {
                        Task {
                            await loadTemplateForEditing(template)
                        }
                        isTemplateActionsPresented = false
                    },
                    onDuplicate: {
                        Task {
                            await duplicateTemplate(template)
                        }
                        isTemplateActionsPresented = false
                    },
                    onDelete: {
                        pendingDeleteTemplate = template
                        showDeleteAlert = true
                        isTemplateActionsPresented = false
                    }
                )
                .presentationDetents([.medium])
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showTunePlanSheet) {
            WorkoutTunePlanSheet(
                selectedMuscleGroups: $selectedMuscleGroups,
                selectedEquipment: $selectedEquipment,
                selectedDurationMinutes: $selectedDurationMinutes
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(item: $activeSession) { session in
            WorkoutSessionView(
                userId: userId,
                title: session.title,
                sessionId: session.sessionId,
                exercises: session.exercises
            )
        }
        .sheet(isPresented: $isSwapSheetPresented) {
            WorkoutSwapSheet(
                templates: templates,
                onSelect: { template in
                    Task {
                        await startSession(from: template)
                    }
                    isSwapSheetPresented = false
                },
                onClose: { isSwapSheetPresented = false }
            )
        }
        .alert("Delete workout?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let template = pendingDeleteTemplate {
                    Task {
                        await deleteTemplate(template)
                    }
                }
                pendingDeleteTemplate = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteTemplate = nil
            }
        } message: {
            Text("This removes the saved template.")
        }
        .alert("Start a new template?", isPresented: $showNewTemplateAlert) {
            Button("Reset", role: .destructive) {
                resetDraftState()
                mode = .create
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear the current draft.")
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onChange(of: intent) { newValue in
            guard let newValue else { return }
            Task {
                await handleIntent(newValue)
            }
        }
    }

    private var generateSection: some View {
        VStack(spacing: 18) {
            WorkoutHeroCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI Workout Builder")
                                .font(FitFont.heading(size: 22))
                                .foregroundColor(FitTheme.textPrimary)
                            Text("Build a plan around your focus, equipment, and time.")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        Spacer()
                        WorkoutIconBadge(symbol: "sparkles")
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        SummaryPill(title: "Focus", value: "\(max(selectedMuscleGroups.count, 1)) groups")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SummaryPill(title: "Equipment", value: selectedEquipment.isEmpty ? "Any" : "\(selectedEquipment.count) items")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SummaryPill(title: "Target time", value: "\(selectedDurationMinutes) min")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 12) {
                        ActionButton(title: "Edit Plan", style: .secondary) {
                            showTunePlanSheet = true
                        }
                        .frame(maxWidth: .infinity)

                        ActionButton(
                            title: isGenerating ? "Generating..." : "Generate Workout",
                            style: .primary
                        ) {
                            Task {
                                await generateWorkout()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            if !generatedExercises.isEmpty {
                WorkoutCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(generatedTitle)
                                    .font(FitFont.body(size: 17, weight: .semibold))
                                    .foregroundColor(FitTheme.textPrimary)
                                Text("Est. \(generatedEstimatedMinutes) min")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                            Spacer()
                            SummaryPill(title: "Status", value: "Ready")
                        }

                        VStack(spacing: 10) {
                            ForEach(generatedExercises.indices, id: \.self) { index in
                                let exercise = generatedExercises[index]
                                let repsText = exercise.sets.first?.reps ?? ""
                                let detail = repsText.isEmpty
                                    ? "\(exercise.sets.count) sets"
                                    : "\(exercise.sets.count) x \(repsText)"
                                ExerciseRow(name: exercise.name, detail: detail, badgeText: "\(index + 1)")
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            generatedExercises.remove(at: index)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }

                                        Button {
                                            generatedSwapIndex = index
                                            isGeneratedSwapPresented = true
                                        } label: {
                                            Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                                        }
                                        .tint(FitTheme.cardHighlight)
                                    }
                                    .contextMenu {
                                        Button("Swap") {
                                            generatedSwapIndex = index
                                            isGeneratedSwapPresented = true
                                        }
                                        Button("Delete", role: .destructive) {
                                            generatedExercises.remove(at: index)
                                        }
                                    }
                            }
                        }

                        ActionButton(title: "Start Generated Workout", style: .primary) {
                            Task {
                                await startSession(
                                    title: generatedTitle,
                                    templateId: nil,
                                    exercises: generatedExercises
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else if !generatedPreview.isEmpty {
                WorkoutCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Generator notes", subtitle: "Latest preview")
                        Text(generatedPreview)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                            .lineLimit(4)
                    }
                }
            }
        }
    }

    private var savedSection: some View {
        VStack(spacing: 18) {
            WorkoutCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        SectionHeader(title: "Saved workouts", subtitle: "Templates ready to start.")
                        Spacer()
                        PillButton(
                            title: "New template",
                            icon: "plus"
                        ) {
                            if hasDraftChanges {
                                showNewTemplateAlert = true
                            } else {
                                resetDraftState()
                                mode = .create
                            }
                        }
                    }

                    SearchBar(text: $templateSearch, placeholder: "Search saved workouts")

                    HStack(spacing: 10) {
                        SummaryPill(title: "Total", value: "\(templates.count)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SummaryPill(title: "Mode", value: "Manual/AI")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if isLoading {
                WorkoutCard {
                    Text("Loading templates...")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }
            } else if templates.isEmpty {
                WorkoutCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No templates yet.")
                            .font(FitFont.body(size: 15, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Generate or build your first workout to save it here.")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredTemplates) { template in
                        WorkoutPlanCard(
                            title: template.title,
                            subtitle: template.mode.uppercased(),
                            detail: template.description ?? "Saved workout template",
                            onStart: {
                                Task {
                                    await startSession(from: template)
                                }
                            },
                            onMore: {
                                selectedTemplate = template
                                isTemplateActionsPresented = true
                            }
                        )
                    }
                }
            }
        }
    }

    private var createSection: some View {
        VStack(spacing: 18) {
            WorkoutCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        SectionHeader(title: "Template builder", subtitle: "Craft a workout from scratch.")
                        Spacer()
                        if editingTemplateId != nil {
                            PillButton(title: "Cancel edit", icon: "xmark") {
                                resetDraftState()
                                mode = .saved
                            }
                        }
                        PillButton(title: "New template", icon: "plus") {
                            if hasDraftChanges {
                                showNewTemplateAlert = true
                            } else {
                                resetDraftState()
                                mode = .create
                            }
                        }
                    }

                    BuilderStepHeader(step: 1, title: "Name your workout", subtitle: "Shown on saved templates.")
                    TextField("Workout name", text: $draftName)
                        .font(FitFont.body(size: 15))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(12)
                        .background(FitTheme.cardHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    Divider().background(FitTheme.cardStroke)

                    BuilderStepHeader(step: 2, title: "Add exercises", subtitle: "Sets, reps, rest, and notes.")
                    if draftExercises.isEmpty {
                        Text("Add exercises to start building your session.")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    } else {
                        ForEach(draftExercises.indices, id: \.self) { index in
                            DraftExerciseEditorRow(
                                exercise: $draftExercises[index],
                                onRemove: {
                                    let id = draftExercises[index].id
                                    draftExercises.removeAll { $0.id == id }
                                }
                            )
                        }
                    }

                    ActionButton(title: "Add Exercise", style: .secondary) {
                        isExercisePickerPresented = true
                    }
                    .frame(maxWidth: .infinity)

                    Divider().background(FitTheme.cardStroke)

                    BuilderStepHeader(step: 3, title: "Save template", subtitle: "Ready to start lifting?")
                    ActionButton(title: saveTemplateButtonTitle, style: .primary) {
                        Task {
                            if isEditingTemplate {
                                await updateDraftTemplate()
                            } else {
                                await saveDraftTemplate()
                            }
                        }
                    }
                    .disabled(isSavingDraft)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var filteredTemplates: [WorkoutTemplate] {
        let trimmed = templateSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return templates
        }
        return templates.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var isEditingTemplate: Bool {
        editingTemplateId != nil
    }

    private var saveTemplateButtonTitle: String {
        if isSavingDraft {
            return isEditingTemplate ? "Updating…" : "Saving…"
        }
        return isEditingTemplate ? "Update Template" : "Save Template"
    }

    private var sampleSessionExercises: [WorkoutExerciseSession] {
        [
            WorkoutExerciseSession(
                name: "Bench Press",
                sets: [
                    WorkoutSetEntry(reps: "8", weight: "185", isComplete: false),
                    WorkoutSetEntry(reps: "8", weight: "185", isComplete: false),
                    WorkoutSetEntry(reps: "6", weight: "195", isComplete: false)
                ],
                restSeconds: 90
            ),
            WorkoutExerciseSession(
                name: "Incline Dumbbell Press",
                sets: [
                    WorkoutSetEntry(reps: "10", weight: "65", isComplete: false),
                    WorkoutSetEntry(reps: "10", weight: "65", isComplete: false),
                    WorkoutSetEntry(reps: "8", weight: "70", isComplete: false)
                ],
                restSeconds: 75
            ),
            WorkoutExerciseSession(
                name: "Cable Fly",
                sets: [
                    WorkoutSetEntry(reps: "12", weight: "40", isComplete: false),
                    WorkoutSetEntry(reps: "12", weight: "40", isComplete: false),
                    WorkoutSetEntry(reps: "12", weight: "40", isComplete: false)
                ],
                restSeconds: 60
            )
        ]
    }

    private var defaultRecommendedExercises: [WorkoutExerciseSession] {
        sampleSessionExercises
    }

    private var spotlightExercises: [WorkoutExerciseSession] {
        generatedExercises.isEmpty ? defaultRecommendedExercises : generatedExercises
    }

    private var spotlightSubtitle: String {
        generatedExercises.isEmpty ? "Upper Strength" : generatedTitle
    }

    private func handleIntent(_ intent: WorkoutTabIntent) async {
        switch intent {
        case .startRecommended:
            await startSession(
                title: "Today's Training",
                templateId: nil,
                exercises: spotlightExercises
            )
        case .swapSaved:
            await MainActor.run {
                mode = .saved
                isSwapSheetPresented = true
            }
            if templates.isEmpty {
                await loadWorkouts()
            }
        }
        await MainActor.run {
            self.intent = nil
        }
    }

    private func startSession(from template: WorkoutTemplate) async {
        guard !userId.isEmpty else {
            await MainActor.run {
                loadError = "Missing user session. Please log in again."
            }
            return
        }
        do {
            let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: template.id)
            guard !detail.exercises.isEmpty else {
                await MainActor.run {
                    showPlaceholderAlert(
                        title: "Empty workout",
                        message: "This workout template has no exercises. Please edit it to add exercises."
                    )
                }
                return
            }
            let exercises = sessionExercises(from: detail.exercises)
            await startSession(title: template.title, templateId: template.id, exercises: exercises)
        } catch {
            await MainActor.run {
                loadError = "Unable to start workout. \(error.localizedDescription)"
            }
        }
    }

    private func startSession(
        title: String,
        templateId: String?,
        exercises: [WorkoutExerciseSession]
    ) async {
        guard !exercises.isEmpty else {
            await MainActor.run {
                showPlaceholderAlert(
                    title: "No exercises",
                    message: "This workout doesn't have any exercises yet."
                )
            }
            return
        }

        guard !userId.isEmpty else {
            await MainActor.run {
                activeSession = SessionDraft(
                    sessionId: nil,
                    title: title,
                    exercises: exercises
                )
            }
            return
        }
        do {
            let sessionId = try await WorkoutAPIService.shared.startSession(
                userId: userId,
                templateId: templateId
            )
            await MainActor.run {
                activeSession = SessionDraft(
                    sessionId: sessionId,
                    title: title,
                    exercises: exercises
                )
            }
        } catch {
            await MainActor.run {
                activeSession = SessionDraft(
                    sessionId: nil,
                    title: title,
                    exercises: exercises
                )
                loadError = "Unable to connect to the server. Session started locally."
            }
        }
    }

    private func saveDraftTemplate() async {
        guard !userId.isEmpty else {
            await MainActor.run {
                loadError = "Missing user session. Please log in again."
            }
            return
        }
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            await MainActor.run {
                loadError = "Add a workout name."
            }
            return
        }
        guard !draftExercises.isEmpty else {
            await MainActor.run {
                loadError = "Add at least one exercise."
            }
            return
        }

        await MainActor.run {
            isSavingDraft = true
            loadError = nil
        }
        do {
            let inputs = draftExercises.map {
                WorkoutExerciseInput(
                    name: $0.name,
                    muscleGroups: [$0.muscleGroup],
                    equipment: [$0.equipment],
                    sets: $0.sets,
                    reps: $0.reps,
                    restSeconds: $0.restSeconds,
                    notes: $0.notes.isEmpty ? nil : $0.notes
                )
            }
            let templateId = try await WorkoutAPIService.shared.createTemplate(
                userId: userId,
                title: trimmedName,
                description: nil,
                mode: "manual",
                exercises: inputs
            )
            await MainActor.run {
                let newTemplate = WorkoutTemplate(
                    id: templateId,
                    title: trimmedName,
                    description: nil,
                    mode: "manual",
                    createdAt: nil
                )
                templates.removeAll { $0.id == templateId }
                templates.insert(newTemplate, at: 0)
            }
            await loadWorkouts()
            let exercises = draftExercises.map { exercise in
                let repsValue = exercise.reps > 0 ? "\(exercise.reps)" : ""
                return WorkoutExerciseSession(
                    name: exercise.name,
                    sets: WorkoutSetEntry.batch(reps: repsValue, weight: "", count: max(exercise.sets, 1)),
                    restSeconds: exercise.restSeconds
                )
            }
            await startSession(title: trimmedName, templateId: templateId, exercises: exercises)
            await MainActor.run {
                draftName = ""
                draftExercises = []
                isSavingDraft = false
                Haptics.success()
            }
        } catch {
            await MainActor.run {
                loadError = "Unable to save workout."
                isSavingDraft = false
            }
        }
    }

    private func updateDraftTemplate() async {
        guard !userId.isEmpty else {
            await MainActor.run {
                loadError = "Missing user session. Please log in again."
            }
            return
        }
        guard let templateId = editingTemplateId else { return }
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            await MainActor.run {
                loadError = "Add a workout name."
            }
            return
        }
        guard !draftExercises.isEmpty else {
            await MainActor.run {
                loadError = "Add at least one exercise."
            }
            return
        }

        await MainActor.run {
            isSavingDraft = true
            loadError = nil
        }

        do {
            let inputs = draftExercises.map {
                WorkoutExerciseInput(
                    name: $0.name,
                    muscleGroups: [$0.muscleGroup],
                    equipment: [$0.equipment],
                    sets: $0.sets,
                    reps: $0.reps,
                    restSeconds: $0.restSeconds,
                    notes: $0.notes.isEmpty ? nil : $0.notes
                )
            }
            _ = try await WorkoutAPIService.shared.updateTemplate(
                templateId: templateId,
                title: trimmedName,
                description: nil,
                mode: "manual",
                exercises: inputs
            )
            await MainActor.run {
                if let index = templates.firstIndex(where: { $0.id == templateId }) {
                    let updated = WorkoutTemplate(
                        id: templateId,
                        title: trimmedName,
                        description: nil,
                        mode: "manual",
                        createdAt: templates[index].createdAt
                    )
                    templates[index] = updated
                }
            }
            await loadWorkouts()
            await MainActor.run {
                editingTemplateId = nil
                draftName = ""
                draftExercises = []
                mode = .saved
                isSavingDraft = false
                Haptics.success()
            }
        } catch {
            await MainActor.run {
                loadError = "Unable to update workout."
                isSavingDraft = false
            }
        }
    }

    private func resetDraftState() {
        editingTemplateId = nil
        draftName = ""
        draftExercises = []
        loadError = nil
    }

    private var hasDraftChanges: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !draftExercises.isEmpty ||
        editingTemplateId != nil
    }

    private func loadTemplateForEditing(_ template: WorkoutTemplate) async {
        guard !userId.isEmpty else {
            await MainActor.run {
                loadError = "Missing user session. Please log in again."
            }
            return
        }
        do {
            let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: template.id)
            await MainActor.run {
                editingTemplateId = template.id
                draftName = detail.template.title
                draftExercises = draftExercises(from: detail.exercises)
                mode = .create
                loadError = nil
            }
        } catch {
            await MainActor.run {
                loadError = "Unable to load template. \(error.localizedDescription)"
            }
        }
    }

    private func duplicateTemplate(_ template: WorkoutTemplate) async {
        guard !userId.isEmpty else {
            await MainActor.run {
                loadError = "Missing user session. Please log in again."
            }
            return
        }
        do {
            _ = try await WorkoutAPIService.shared.duplicateTemplate(
                templateId: template.id,
                userId: userId
            )
            await loadWorkouts()
        } catch {
            await MainActor.run {
                loadError = "Unable to duplicate workout."
            }
        }
    }

    private func deleteTemplate(_ template: WorkoutTemplate) async {
        do {
            try await WorkoutAPIService.shared.deleteTemplate(templateId: template.id)
            await loadWorkouts()
        } catch {
            await MainActor.run {
                loadError = "Unable to delete workout."
            }
        }
    }

    private func searchExercises(query: String) async -> [ExerciseDefinition] {
        do {
            return try await WorkoutAPIService.shared.searchExercises(query: query)
        } catch {
            return []
        }
    }

    private func draftExercises(from exercises: [WorkoutTemplateExercise]) -> [WorkoutExerciseDraft] {
        let sorted = exercises.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        return sorted.map {
            WorkoutExerciseDraft(
                name: $0.name,
                muscleGroup: $0.muscleGroups.first ?? "General",
                equipment: $0.equipment.first ?? "Bodyweight",
                sets: $0.sets ?? 3,
                reps: $0.reps ?? 10,
                restSeconds: $0.restSeconds ?? 60,
                notes: $0.notes ?? ""
            )
        }
    }

    private func sessionExercises(from exercises: [WorkoutTemplateExercise]) -> [WorkoutExerciseSession] {
        let sorted = exercises.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        return sorted.map { exercise in
            let setCount = normalizedSetCount(exercise.sets)
            let repsText = normalizedRepsText(exercise.reps)
            let restSeconds = normalizedRestSeconds(exercise.restSeconds)
            return WorkoutExerciseSession(
                name: exercise.name,
                sets: WorkoutSetEntry.batch(
                    reps: repsText,
                    weight: "",
                    count: setCount
                ),
                restSeconds: restSeconds
            )
        }
    }

    private struct ParsedGeneratedWorkout {
        let title: String
        let exercises: [WorkoutExerciseSession]
    }

    private struct GeneratedWorkoutPayload: Decodable {
        let title: String?
        let exercises: [GeneratedExercise]?
    }

    private struct GeneratedExercise: Decodable {
        let name: String?
        let exercise: String?
        let sets: Int?
        let reps: Int?
        let restSeconds: Int?
        let rest: Int?
        let notes: String?
    }

    private func parseGeneratedWorkout(_ text: String) -> ParsedGeneratedWorkout {
        if let payload = decodeGeneratedWorkout(from: text) {
            let exercises = payload.exercises.flatMap { exercisesFromGenerated($0) } ?? []
            if !exercises.isEmpty {
                return ParsedGeneratedWorkout(
                    title: payload.title ?? "AI Generated Workout",
                    exercises: exercises
                )
            }
        }

        let exercises = parseExercisesFromText(text)
        return ParsedGeneratedWorkout(
            title: "AI Generated Workout",
            exercises: exercises
        )
    }

    private func decodeGeneratedWorkout(from text: String) -> GeneratedWorkoutPayload? {
        guard let data = extractJSONData(from: text) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let payload = try? decoder.decode(GeneratedWorkoutPayload.self, from: data) {
            if payload.exercises != nil || payload.title != nil {
                return payload
            }
        }

        if let exercises = try? decoder.decode([GeneratedExercise].self, from: data) {
            return GeneratedWorkoutPayload(title: nil, exercises: exercises)
        }

        return nil
    }

    private func extractJSONData(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return trimmed.data(using: .utf8)
        }

        guard let firstBrace = trimmed.firstIndex(of: "{"),
              let lastBrace = trimmed.lastIndex(of: "}") else {
            return nil
        }

        let jsonSubstring = trimmed[firstBrace...lastBrace]
        return String(jsonSubstring).data(using: .utf8)
    }

    private func exercisesFromGenerated(_ exercises: [GeneratedExercise]) -> [WorkoutExerciseSession] {
        exercises.compactMap { item in
            let name = item.name ?? item.exercise ?? ""
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }
            let lowerName = trimmedName.lowercased()
            if lowerName == "rest_seconds" || lowerName == "rest" || lowerName == "reps" || lowerName == "sets" {
                return nil
            }
            let sets = normalizedSetCount(item.sets)
            let repsText = normalizedRepsText(item.reps)
            let restSeconds = normalizedRestSeconds(item.restSeconds ?? item.rest)
            return WorkoutExerciseSession(
                name: trimmedName,
                sets: WorkoutSetEntry.batch(reps: repsText, weight: "", count: sets),
                restSeconds: restSeconds
            )
        }
    }

    private func parseExercisesFromText(_ text: String) -> [WorkoutExerciseSession] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        return lines.compactMap { parseExerciseLine($0) }
    }

    private func fallbackGeneratedExercises() -> [WorkoutExerciseSession] {
        let config = durationConfig(for: selectedDurationMinutes)
        let selected = selectedMuscleGroups.isEmpty
            ? MuscleGroup.allCases.map(\.rawValue)
            : Array(selectedMuscleGroups)

        var exercises: [WorkoutExerciseSession] = []
        for group in selected {
            if let compound = exerciseLibrary[group]?.compound.first {
                exercises.append(makeSessionExercise(from: compound, sets: config.defaultSets))
            }
        }

        if exercises.count < config.minExercises {
            for group in selected {
                guard exercises.count < config.minExercises else { break }
                if let isolation = exerciseLibrary[group]?.isolation.first {
                    exercises.append(makeSessionExercise(from: isolation, sets: config.defaultSets))
                }
            }
        }

        let allExtras = exerciseLibrary.values.flatMap { $0.compound + $0.isolation }
        var extraIndex = 0
        while exercises.count < config.minExercises && extraIndex < allExtras.count {
            exercises.append(makeSessionExercise(from: allExtras[extraIndex], sets: config.defaultSets))
            extraIndex += 1
        }

        return exercises
    }

    private func adjustExercisesToDuration(
        _ initial: [WorkoutExerciseSession],
        targetMinutes: Int
    ) -> [WorkoutExerciseSession] {
        let config = durationConfig(for: targetMinutes)
        let selected = selectedMuscleGroups.isEmpty
            ? MuscleGroup.allCases.map(\.rawValue)
            : Array(selectedMuscleGroups)

        let matched = initial.filter { exercise in
            selected.contains { isExerciseInGroup(exercise.name, group: $0) }
        }

        var exercises = (matched.isEmpty ? initial : matched).map { exercise in
            ensureSetCount(
                exercise,
                minSets: config.minSets,
                maxSets: config.maxSets
            )
        }
        exercises = reorderExercises(exercises)
        for group in selected {
            guard !exercises.contains(where: { isExerciseInGroup($0.name, group: group) }) else { continue }
            if let seed = exerciseLibrary[group]?.compound.first {
                exercises.append(makeSessionExercise(from: seed, sets: config.defaultSets))
            }
        }
        exercises = reorderExercises(exercises)

        let targetMin = Int(Double(targetMinutes) * 0.9)
        let targetMax = Int(Double(targetMinutes) * 1.1)

        func estimated() -> Int {
            estimateWorkoutMinutes(exercises)
        }

        var guardCount = 0
        while estimated() < targetMin && guardCount < 20 {
            guardCount += 1
            if exercises.count < config.maxExercises, let next = nextSupplementExercise(avoiding: exercises) {
                exercises.append(next)
                exercises = reorderExercises(exercises)
                continue
            }

            if let index = exercises.firstIndex(where: { isCompoundExercise($0.name) && $0.sets.count < config.maxSets }) {
                exercises[index] = incrementSets(exercises[index])
            } else if let index = exercises.firstIndex(where: { $0.sets.count < config.maxSets }) {
                exercises[index] = incrementSets(exercises[index])
            } else {
                break
            }
        }

        guardCount = 0
        while estimated() > targetMax && guardCount < 20 {
            guardCount += 1
            if let index = exercises.lastIndex(where: { !isCompoundExercise($0.name) && $0.sets.count > config.minSets }) {
                exercises[index] = decrementSets(exercises[index])
                continue
            }
            if exercises.count > config.minExercises,
               let index = exercises.lastIndex(where: { !isCompoundExercise($0.name) }) {
                exercises.remove(at: index)
                continue
            }
            if let index = exercises.lastIndex(where: { $0.sets.count > config.minSets }) {
                exercises[index] = decrementSets(exercises[index])
            } else {
                break
            }
        }

        if exercises.count < 4 {
            while exercises.count < 4, let next = nextSupplementExercise(avoiding: exercises) {
                exercises.append(next)
            }
        }

        return exercises
    }

    private func estimateWorkoutMinutes(_ exercises: [WorkoutExerciseSession]) -> Int {
        guard !exercises.isEmpty else { return 0 }
        let warmupSeconds = 5 * 60
        let perSetSeconds = 45
        let transitionSeconds = 35

        var totalSeconds = warmupSeconds
        for (index, exercise) in exercises.enumerated() {
            let sets = max(exercise.sets.count, 1)
            let restSeconds = normalizedRestSeconds(exercise.restSeconds)
            totalSeconds += sets * perSetSeconds
            if sets > 1 {
                totalSeconds += (sets - 1) * restSeconds
            }
            if index < exercises.count - 1 {
                totalSeconds += transitionSeconds
            }
        }
        return Int(round(Double(totalSeconds) / 60.0))
    }

    private struct DurationConfig {
        let minExercises: Int
        let maxExercises: Int
        let minSets: Int
        let maxSets: Int
        let defaultSets: Int
    }

    private func durationConfig(for minutes: Int) -> DurationConfig {
        switch minutes {
        case 20:
            return DurationConfig(minExercises: 4, maxExercises: 5, minSets: 2, maxSets: 3, defaultSets: 3)
        case 30:
            return DurationConfig(minExercises: 5, maxExercises: 6, minSets: 3, maxSets: 3, defaultSets: 3)
        case 45:
            return DurationConfig(minExercises: 6, maxExercises: 8, minSets: 3, maxSets: 4, defaultSets: 4)
        case 60:
            return DurationConfig(minExercises: 7, maxExercises: 9, minSets: 3, maxSets: 4, defaultSets: 4)
        case 75:
            return DurationConfig(minExercises: 8, maxExercises: 10, minSets: 4, maxSets: 4, defaultSets: 4)
        default:
            return DurationConfig(minExercises: 9, maxExercises: 12, minSets: 4, maxSets: 5, defaultSets: 4)
        }
    }

    private struct ExercisePool {
        let compound: [ExerciseSeed]
        let isolation: [ExerciseSeed]
    }

    private struct ExerciseSeed {
        let name: String
        let restSeconds: Int
    }

    private var exerciseLibrary: [String: ExercisePool] {
        [
            "chest": ExercisePool(
                compound: [
                    ExerciseSeed(name: "Bench Press", restSeconds: 90),
                    ExerciseSeed(name: "Incline Dumbbell Press", restSeconds: 75)
                ],
                isolation: [
                    ExerciseSeed(name: "Cable Fly", restSeconds: 60),
                    ExerciseSeed(name: "Pec Deck", restSeconds: 60)
                ]
            ),
            "back": ExercisePool(
                compound: [
                    ExerciseSeed(name: "Lat Pulldown", restSeconds: 75),
                    ExerciseSeed(name: "Seated Row", restSeconds: 75)
                ],
                isolation: [
                    ExerciseSeed(name: "Straight-Arm Pulldown", restSeconds: 60)
                ]
            ),
            "shoulders": ExercisePool(
                compound: [
                    ExerciseSeed(name: "Overhead Press", restSeconds: 90)
                ],
                isolation: [
                    ExerciseSeed(name: "Lateral Raise", restSeconds: 60),
                    ExerciseSeed(name: "Rear Delt Fly", restSeconds: 60)
                ]
            ),
            "arms": ExercisePool(
                compound: [
                    ExerciseSeed(name: "Close-Grip Bench Press", restSeconds: 90),
                    ExerciseSeed(name: "Chin Up", restSeconds: 90)
                ],
                isolation: [
                    ExerciseSeed(name: "Bicep Curl", restSeconds: 60),
                    ExerciseSeed(name: "Tricep Pushdown", restSeconds: 60)
                ]
            ),
            "legs": ExercisePool(
                compound: [
                    ExerciseSeed(name: "Back Squat", restSeconds: 120),
                    ExerciseSeed(name: "Leg Press", restSeconds: 90)
                ],
                isolation: [
                    ExerciseSeed(name: "Leg Extension", restSeconds: 60),
                    ExerciseSeed(name: "Leg Curl", restSeconds: 60)
                ]
            ),
            "core": ExercisePool(
                compound: [
                    ExerciseSeed(name: "Hanging Leg Raise", restSeconds: 60)
                ],
                isolation: [
                    ExerciseSeed(name: "Plank", restSeconds: 45),
                    ExerciseSeed(name: "Cable Crunch", restSeconds: 45)
                ]
            ),
            "glutes": ExercisePool(
                compound: [
                    ExerciseSeed(name: "Hip Thrust", restSeconds: 90),
                    ExerciseSeed(name: "Romanian Deadlift", restSeconds: 120)
                ],
                isolation: [
                    ExerciseSeed(name: "Glute Bridge", restSeconds: 60),
                    ExerciseSeed(name: "Cable Kickback", restSeconds: 60)
                ]
            ),
            "hamstrings": ExercisePool(
                compound: [
                    ExerciseSeed(name: "Romanian Deadlift", restSeconds: 120),
                    ExerciseSeed(name: "Good Morning", restSeconds: 120)
                ],
                isolation: [
                    ExerciseSeed(name: "Leg Curl", restSeconds: 60),
                    ExerciseSeed(name: "Nordic Curl", restSeconds: 90)
                ]
            ),
            "calves": ExercisePool(
                compound: [
                    ExerciseSeed(name: "Standing Calf Raise", restSeconds: 60)
                ],
                isolation: [
                    ExerciseSeed(name: "Seated Calf Raise", restSeconds: 60)
                ]
            ),
            "forearms": ExercisePool(
                compound: [
                    ExerciseSeed(name: "Farmer Carry", restSeconds: 90)
                ],
                isolation: [
                    ExerciseSeed(name: "Wrist Curl", restSeconds: 45),
                    ExerciseSeed(name: "Reverse Wrist Curl", restSeconds: 45)
                ]
            )
        ]
    }

    private func makeSessionExercise(from seed: ExerciseSeed, sets: Int) -> WorkoutExerciseSession {
        WorkoutExerciseSession(
            name: seed.name,
            sets: WorkoutSetEntry.batch(reps: "10", weight: "", count: max(sets, 1)),
            restSeconds: normalizedRestSeconds(seed.restSeconds)
        )
    }

    private func normalizedSetCount(_ value: Int?) -> Int {
        let sets = value ?? 3
        return min(max(sets, 1), 6)
    }

    private func normalizedRepsText(_ value: Int?) -> String {
        let reps = value ?? 0
        if reps > 0 {
            return "\(reps)"
        }
        return "10"
    }

    private func normalizedRestSeconds(_ value: Int?) -> Int {
        let rest = value ?? 90
        return min(max(rest, 30), 150)
    }

    private func ensureSetCount(_ exercise: WorkoutExerciseSession, minSets: Int, maxSets: Int) -> WorkoutExerciseSession {
        let sets = min(max(exercise.sets.count, minSets), maxSets)
        if sets == exercise.sets.count {
            return exercise
        }
        return WorkoutExerciseSession(
            name: exercise.name,
            sets: WorkoutSetEntry.batch(
                reps: exercise.sets.first?.reps ?? "10",
                weight: exercise.sets.first?.weight ?? "",
                count: sets
            ),
            restSeconds: exercise.restSeconds
        )
    }

    private func incrementSets(_ exercise: WorkoutExerciseSession) -> WorkoutExerciseSession {
        var updated = exercise
        let last = updated.sets.last
        updated.sets.append(
            WorkoutSetEntry(
                reps: last?.reps ?? "10",
                weight: last?.weight ?? "",
                isComplete: false
            )
        )
        return updated
    }

    private func decrementSets(_ exercise: WorkoutExerciseSession) -> WorkoutExerciseSession {
        var updated = exercise
        if updated.sets.count > 1 {
            updated.sets.removeLast()
        }
        return updated
    }

    private func reorderExercises(_ exercises: [WorkoutExerciseSession]) -> [WorkoutExerciseSession] {
        exercises.sorted { lhs, rhs in
            let leftCompound = isCompoundExercise(lhs.name)
            let rightCompound = isCompoundExercise(rhs.name)
            if leftCompound != rightCompound {
                return leftCompound && !rightCompound
            }
            return lhs.name < rhs.name
        }
    }

    private func nextSupplementExercise(avoiding existing: [WorkoutExerciseSession]) -> WorkoutExerciseSession? {
        let existingNames = Set(existing.map { $0.name })
        let selected = selectedMuscleGroups.isEmpty
            ? MuscleGroup.allCases.map(\.rawValue)
            : Array(selectedMuscleGroups)

        for group in selected {
            if let pool = exerciseLibrary[group] {
                for seed in pool.isolation + pool.compound {
                    if !existingNames.contains(seed.name) {
                        let config = durationConfig(for: selectedDurationMinutes)
                        return makeSessionExercise(from: seed, sets: config.defaultSets)
                    }
                }
            }
        }
        return nil
    }

    private func isCompoundExercise(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let keywords = [
            "press", "squat", "deadlift", "row", "pull", "bench",
            "lunge", "clean", "snatch", "chin", "dip", "overhead"
        ]
        return keywords.contains { lowered.contains($0) }
    }

    private func isExerciseInGroup(_ name: String, group: String) -> Bool {
        guard let pool = exerciseLibrary[group] else { return false }
        let matches = (pool.compound + pool.isolation).map { $0.name.lowercased() }
        return matches.contains(name.lowercased())
    }

    private func parseExerciseLine(_ line: String) -> WorkoutExerciseSession? {
        let cleaned = stripBulletPrefix(line)
        guard !cleaned.isEmpty else { return nil }
        let lower = cleaned.lowercased()
        if lower.contains("rest_seconds") || lower.hasPrefix("rest:") || lower.hasPrefix("reps:")
            || lower.hasPrefix("sets:") || lower.hasPrefix("rest seconds") {
            return nil
        }

        let parsed = extractSetReps(from: cleaned)
        let restSeconds = normalizedRestSeconds(extractRest(from: cleaned))

        var name = cleaned
        if let range = firstSeparatorRange(in: cleaned) {
            name = String(cleaned[..<range.lowerBound])
        } else if let matchRange = parsed.matchRange, let range = Range(matchRange, in: cleaned) {
            name = cleaned.replacingCharacters(in: range, with: "")
        }

        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let setCount = normalizedSetCount(parsed.sets)
        let repsText = parsed.repsText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "10"

        return WorkoutExerciseSession(
            name: name,
            sets: WorkoutSetEntry.batch(reps: repsText, weight: "", count: setCount),
            restSeconds: restSeconds
        )
    }

    private func stripBulletPrefix(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        if first == "-" || first == "•" || first == "*" {
            return trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func firstSeparatorRange(in line: String) -> Range<String.Index>? {
        let separators = [" - ", " – ", " — ", ": "]
        return separators.compactMap { line.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
    }

    private struct ParsedSetReps {
        let sets: Int?
        let repsText: String?
        let matchRange: NSRange?
    }

    private func extractSetReps(from line: String) -> ParsedSetReps {
        let patterns = [
            #"(?i)(\d+)\s*(?:x|×|\*)\s*(\d+)"#,
            #"(?i)(\d+)\s*sets?\s*(?:x|of)?\s*(\d+)"#
        ]

        for pattern in patterns {
            if let match = regexMatch(pattern, in: line, captureCount: 2) {
                let sets = Int(match.captures[0])
                let repsText = match.captures[1]
                return ParsedSetReps(sets: sets, repsText: repsText, matchRange: match.range)
            }
        }

        return ParsedSetReps(sets: nil, repsText: nil, matchRange: nil)
    }

    private func extractRest(from line: String) -> Int? {
        let patterns = [
            #"(?i)rest\s*(\d+)"#,
            #"(?i)(\d+)\s*(?:sec|secs|s)\s*rest"#
        ]

        for pattern in patterns {
            if let match = regexMatch(pattern, in: line, captureCount: 1) {
                return Int(match.captures[0])
            }
        }

        return nil
    }

    private struct RegexMatch {
        let range: NSRange
        let captures: [String]
    }

    private func regexMatch(_ pattern: String, in text: String, captureCount: Int) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }

        var captures: [String] = []
        for index in 1...captureCount {
            if let range = Range(match.range(at: index), in: text) {
                captures.append(String(text[range]))
            }
        }

        return RegexMatch(range: match.range, captures: captures)
    }

    private func generateWorkout() async {
        guard !userId.isEmpty else { return }
        guard !selectedMuscleGroups.isEmpty else {
            await MainActor.run {
                loadError = "Pick at least one muscle group."
            }
            return
        }
        await MainActor.run {
            isGenerating = true
            loadError = nil
            generatedPreview = ""
            generatedExercises = []
            generatedTitle = "AI Generated Workout"
            generatedEstimatedMinutes = 0
        }
        do {
            let result = try await WorkoutAPIService.shared.generateWorkout(
                userId: userId,
                muscleGroups: selectedMuscleGroups.sorted(),
                workoutType: nil,
                equipment: selectedEquipment.sorted(),
                durationMinutes: selectedDurationMinutes
            )
            let parsed = parseGeneratedWorkout(result)
            let baseExercises = parsed.exercises.isEmpty ? fallbackGeneratedExercises() : parsed.exercises
            let adjustedExercises = adjustExercisesToDuration(
                baseExercises,
                targetMinutes: selectedDurationMinutes
            )
            let estimate = estimateWorkoutMinutes(adjustedExercises)
            await MainActor.run {
                generatedPreview = result.isEmpty ? "Workout generated." : result
                generatedTitle = parsed.exercises.isEmpty ? "Quick Build" : parsed.title
                generatedExercises = adjustedExercises
                generatedEstimatedMinutes = estimate
                if generatedExercises.isEmpty && !result.isEmpty {
                    loadError = "Generated workout couldn't be parsed."
                }
                isGenerating = false
            }
        } catch {
            let fallback = adjustExercisesToDuration(
                fallbackGeneratedExercises(),
                targetMinutes: selectedDurationMinutes
            )
            let estimate = estimateWorkoutMinutes(fallback)
            await MainActor.run {
                generatedTitle = "Quick Build"
                generatedExercises = fallback
                generatedEstimatedMinutes = estimate
                loadError = "Server unavailable. Using quick build."
                isGenerating = false
            }
        }
    }

    private func loadWorkouts() async {
        guard !userId.isEmpty else { return }
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            let templates = try await WorkoutAPIService.shared.fetchTemplates(userId: userId)
            await MainActor.run {
                self.templates = templates
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = "Unable to load workouts."
                self.isLoading = false
            }
        }
    }

    private func showPlaceholderAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

private struct WorkoutStreakHeader: View {
    let streakCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(FitFont.body(size: 18, weight: .semibold))
                .foregroundColor(FitTheme.accent)
                .frame(width: 40, height: 40)
                .background(FitTheme.cardBackground)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Workout streak")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
                Text("\(max(streakCount, 0)) days")
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(FitTheme.textPrimary)
            }

            Spacer()
        }
        .padding(16)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: FitTheme.shadow.opacity(0.8), radius: 12, x: 0, y: 8)
    }
}

private struct WorkoutStatCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(FitFont.body(size: 13, weight: .semibold))
                .foregroundColor(accent)

            Text(value)
                .font(FitFont.heading(size: 18, weight: .bold))
                .foregroundColor(FitTheme.textPrimary)

            Text(title)
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)

            Text(detail)
                .font(FitFont.body(size: 11))
                .foregroundColor(FitTheme.textSecondary)
        }
        .padding(12)
        .frame(width: 150, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(FitTheme.cardBackground)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accent.opacity(0.08))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: FitTheme.shadow.opacity(0.8), radius: 12, x: 0, y: 8)
    }
}

private struct WorkoutSpotlightCard: View {
    let title: String
    let subtitle: String
    let durationMinutes: Int
    let exercises: [String]
    let completedExercises: [String]
    let isCompleted: Bool
    let onStart: () -> Void
    let onSwap: () -> Void

    private var previewExercises: [String] {
        Array((displayExercises).prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(FitFont.heading(size: 22))
                        .foregroundColor(FitTheme.textPrimary)
                    if isCompleted {
                        Text("Completed today")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.success)
                    } else {
                        Text(subtitle)
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                Spacer()
                WorkoutIconBadge(symbol: isCompleted ? "checkmark.seal.fill" : "bolt.fill")
            }

            if !isCompleted {
                HStack(spacing: 8) {
                    SummaryPill(title: "Duration", value: "\(durationMinutes) min")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SummaryPill(title: "Style", value: "Strength")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(previewExercises, id: \.self) { name in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(FitTheme.accent)
                            .frame(width: 6, height: 6)
                        Text(name)
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                if displayExercises.count > previewExercises.count {
                    Text("+\(displayExercises.count - previewExercises.count) more")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }

            if !isCompleted {
                HStack(spacing: 12) {
                    ActionButton(title: "Start Session", style: .primary, action: onStart)
                        .frame(maxWidth: .infinity)
                    ActionButton(title: "Swap", style: .secondary, action: onSwap)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(FitTheme.cardBackground)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(FitTheme.primaryGradient.opacity(0.12))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: FitTheme.shadow, radius: 18, x: 0, y: 10)
    }

    private var displayExercises: [String] {
        if isCompleted, !completedExercises.isEmpty {
            return completedExercises
        }
        return exercises
    }
}

private struct WorkoutHeroCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(FitTheme.cardBackground)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(FitTheme.primaryGradient.opacity(0.12))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: FitTheme.shadow, radius: 18, x: 0, y: 10)
    }
}

private struct WorkoutTunePlanSheet: View {
    @Binding var selectedMuscleGroups: Set<String>
    @Binding var selectedEquipment: Set<String>
    @Binding var selectedDurationMinutes: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Tune the plan")
                            .font(FitFont.heading(size: 22))
                            .foregroundColor(FitTheme.textPrimary)
                        Spacer()
                        Button("Done") {
                            dismiss()
                        }
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.accent)
                    }
                    .padding(.top, 12)

                    FieldLabel(title: "Muscle focus")
                    MuscleGroupGrid(
                        selections: $selectedMuscleGroups,
                        options: MuscleGroup.allCases
                    )

                    FieldLabel(title: "Available equipment")
                    EquipmentGrid(
                        selections: $selectedEquipment,
                        options: WorkoutEquipment.allCases
                    )

                    FieldLabel(title: "Target duration")
                    DurationSelector(
                        selectedMinutes: $selectedDurationMinutes,
                        options: [20, 30, 45, 60, 75, 90]
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct WorkoutIconBadge: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(FitFont.body(size: 14, weight: .bold))
            .foregroundColor(FitTheme.buttonText)
            .padding(10)
            .background(FitTheme.primaryGradient)
            .clipShape(Circle())
            .shadow(color: FitTheme.buttonShadow, radius: 10, x: 0, y: 6)
    }
}

private struct ModePicker: View {
    @Binding var mode: WorkoutView.Mode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WorkoutView.Mode.allCases) { option in
                let isSelected = option == mode
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = option
                    }
                }) {
                    Text(option.rawValue)
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if isSelected {
                                    FitTheme.primaryGradient
                                } else {
                                    Color.clear
                                }
                            }
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(FitTheme.cardBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(FitTheme.cardStroke.opacity(0.7), lineWidth: 1)
        )
    }
}

private struct MuscleGroupGrid: View {
    @Binding var selections: Set<String>
    let options: [MuscleGroup]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
            ForEach(options) { option in
                let isSelected = selections.contains(option.rawValue)
                SelectableChip(title: option.title, isSelected: isSelected) {
                    if isSelected {
                        selections.remove(option.rawValue)
                    } else {
                        selections.insert(option.rawValue)
                    }
                }
            }
        }
    }
}

private struct EquipmentGrid: View {
    @Binding var selections: Set<String>
    let options: [WorkoutEquipment]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
            ForEach(options) { option in
                let isSelected = selections.contains(option.rawValue)
                SelectableChip(title: option.title, isSelected: isSelected) {
                    if isSelected {
                        selections.remove(option.rawValue)
                    } else {
                        selections.insert(option.rawValue)
                    }
                }
            }
        }
    }
}

private struct DurationSelector: View {
    @Binding var selectedMinutes: Int
    let options: [Int]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 10)], spacing: 10) {
            ForEach(options, id: \.self) { value in
                let isSelected = selectedMinutes == value
                DurationChip(minutes: value, isSelected: isSelected) {
                    selectedMinutes = value
                }
            }
        }
    }
}

private struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(FitFont.body(size: 11, weight: .bold))
                }
                Text(title)
            }
            .font(FitFont.body(size: 13, weight: .semibold))
            .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textPrimary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isSelected {
                        FitTheme.primaryGradient
                    } else {
                        FitTheme.cardBackground
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DurationChip: View {
    let minutes: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(minutes)")
                    .font(FitFont.body(size: 14, weight: .semibold))
                Text("min")
                    .font(FitFont.body(size: 10))
            }
            .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isSelected {
                        FitTheme.primaryGradient
                    } else {
                        FitTheme.cardBackground
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
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

private struct FieldLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(FitFont.body(size: 11, weight: .semibold))
            .foregroundColor(FitTheme.textSecondary)
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(FitFont.body(size: 10))
                .foregroundColor(FitTheme.textSecondary)
            Text(value)
                .font(FitFont.body(size: 13, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PillButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(FitFont.body(size: 12, weight: .semibold))
            .foregroundColor(FitTheme.textPrimary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(FitTheme.cardHighlight)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BuilderStepHeader: View {
    let step: Int
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(step)")
                .font(FitFont.body(size: 12, weight: .bold))
                .foregroundColor(FitTheme.buttonText)
                .frame(width: 24, height: 24)
                .background(FitTheme.accent)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                Text(subtitle)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }
}

private struct ExerciseRow: View {
    let name: String
    let detail: String
    let badgeText: String?
    let onTap: (() -> Void)?

    init(name: String, detail: String, badgeText: String? = nil, onTap: (() -> Void)? = nil) {
        self.name = name
        self.detail = detail
        self.badgeText = badgeText
        self.onTap = onTap
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(FitTheme.cardBackground)
                    .frame(width: 34, height: 34)
                Text(badgeText ?? String(name.prefix(1)))
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(FitFont.body(size: 15, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                Text(detail)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)
        }
        .padding(12)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct WorkoutPlanCard: View {
    let title: String
    let subtitle: String
    let detail: String
    let onStart: () -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                Text(subtitle)
                    .font(FitFont.body(size: 11, weight: .semibold))
                    .foregroundColor(FitTheme.accent)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(FitTheme.accentSoft)
                    .clipShape(Capsule())
                Text(detail)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(spacing: 10) {
                Button(action: onMore) {
                    Image(systemName: "ellipsis")
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(FitTheme.cardBackground)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
                        )
                }
                ActionButton(title: "Start", style: .secondary, action: onStart)
            }
        }
        .padding(14)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: FitTheme.shadow, radius: 12, x: 0, y: 8)
    }
}

private struct WorkoutSwapSheet: View {
    let templates: [WorkoutTemplate]
    let onSelect: (WorkoutTemplate) -> Void
    let onClose: () -> Void

    @State private var searchText = ""

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Swap Workout")
                            .font(FitFont.heading(size: 22))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Pick a saved workout to swap in.")
                            .font(FitFont.body(size: 12))
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

                SearchBar(text: $searchText, placeholder: "Search saved workouts")
                    .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 12) {
                        if filteredTemplates.isEmpty {
                            Text("No saved workouts found.")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                        } else {
                            ForEach(filteredTemplates) { template in
                                WorkoutSwapRow(template: template) {
                                    onSelect(template)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var filteredTemplates: [WorkoutTemplate] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return templates
        }
        return templates.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
}

private struct WorkoutSwapRow: View {
    let template: WorkoutTemplate
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(template.description ?? "Saved workout template")
                        .font(FitFont.body(size: 11))
                        .foregroundColor(FitTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(12)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DraftExerciseEditorRow: View {
    @Binding var exercise: WorkoutExerciseDraft
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(FitFont.body(size: 15, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("\(exercise.muscleGroup) · \(exercise.equipment)")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(FitTheme.textSecondary)
                        .font(FitFont.body(size: 16))
                }
            }

            HStack(spacing: 12) {
                Stepper(value: $exercise.sets, in: 1...10) {
                    Text("Sets \(exercise.sets)")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                Stepper(value: $exercise.reps, in: 1...20) {
                    Text("Reps \(exercise.reps)")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }

            Stepper(value: $exercise.restSeconds, in: 30...240, step: 15) {
                Text("Rest \(exercise.restSeconds)s")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .padding(14)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
        )
    }
}

private struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(FitTheme.textSecondary)
            TextField(placeholder, text: $text)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textPrimary)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(FitTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
        )
    }
}

private struct ActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FitFont.body(size: 14))
                .fontWeight(.semibold)
                .foregroundColor(style == .primary ? FitTheme.buttonText : FitTheme.textPrimary)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
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

private struct WorkoutCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: FitTheme.shadow, radius: 18, x: 0, y: 10)
    }
}

private enum MuscleGroup: String, CaseIterable, Identifiable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case arms
    case legs
    case core
    case glutes
    case hamstrings
    case calves
    case forearms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .biceps:
            return "Bicep"
        case .triceps:
            return "Tricep"
        default:
            return rawValue.capitalized
        }
    }
}

private enum WorkoutEquipment: String, CaseIterable, Identifiable {
    case bodyweight = "Bodyweight"
    case fullGym = "Full Gym"
    case dumbbells = "Dumbbells"
    case barbell = "Barbell"
    case bands = "Bands"
    case machine = "Machine"
    case kettlebell = "Kettlebell"

    var id: String { rawValue }

    var title: String { rawValue }
}

private struct SessionDraft: Identifiable {
    let id = UUID()
    let sessionId: String?
    let title: String
    let exercises: [WorkoutExerciseSession]
}

#Preview {
    WorkoutView(userId: "demo-user")
}
