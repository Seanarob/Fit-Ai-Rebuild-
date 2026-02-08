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
    @State private var editingGeneratedIndex: Int?
    @State private var templates: [WorkoutTemplate] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var templateSearch = ""
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var isTemplateActionsPresented = false
    @State private var isTemplatePreviewPresented = false
    @State private var previewTemplate: WorkoutTemplate?
    @State private var previewExercises: [WorkoutTemplateExercise] = []
    @State private var isPreviewLoading = false
    @State private var previewError: String?
    @State private var isExercisePickerPresented = false
    @State private var draftName = ""
    @State private var draftExercises: [WorkoutExerciseDraft] = []
    @State private var activeSession: SessionDraft?
    @State private var showActiveSession = false
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
    @State private var showRecoveryAlert = false
    @State private var recoveryInfo: (title: String, exerciseCount: Int, elapsed: Int, savedAt: Date)?
    @State private var coachPickTemplateId: String?
    @State private var coachPickTitle: String?
    @State private var coachPickExercises: [WorkoutExerciseSession] = []
    @State private var splitSnapshot = SplitSnapshot()
    @State private var selectedWeeklyDay: WeeklyDayDetail?
    @State private var weekOffset: Int = 0

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
                    WorkoutStreakBadge(goalOverride: splitSnapshot.daysPerWeek, goalLabel: "session")

                    weeklySplitHeader
                    workoutBuilderSection

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
        .task {
            await loadWorkouts()
            todaysWorkout = WorkoutCompletionStore.todaysCompletion()
            refreshSplitSnapshot()
            
            // Check for recoverable workout session
            if WorkoutSessionStore.hasRecoverableSession() {
                recoveryInfo = WorkoutSessionStore.getRecoveryInfo()
                showRecoveryAlert = true
            }
        }
        .onAppear {
            Task {
                await loadWorkouts()
            }
            refreshSplitSnapshot()
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
                selectedNames: Set(generatedExercises.map { $0.name }),
                onAdd: { exercise in
                    guard let index = generatedSwapIndex else { return }
                    let restSeconds = isCompoundExercise(exercise.name) ? 90 : 60
                    var replacement = WorkoutExerciseSession(
                        name: exercise.name,
                        sets: WorkoutSetEntry.batch(reps: "10", weight: "", count: 4),
                        restSeconds: restSeconds
                    )
                    replacement.warmupRestSeconds = min(60, replacement.restSeconds)
                    if generatedExercises.indices.contains(index) {
                        generatedExercises[index] = replacement
                    }
                    isGeneratedSwapPresented = false
                },
                onClose: { isGeneratedSwapPresented = false }
            )
            .presentationDetents([.large])
        }
        .sheet(
            isPresented: Binding(
                get: { editingGeneratedIndex != nil },
                set: { isPresented in
                    if !isPresented {
                        editingGeneratedIndex = nil
                    }
                }
            )
        ) {
            if let index = editingGeneratedIndex, generatedExercises.indices.contains(index) {
                GeneratedExerciseEditor(
                    exercise: $generatedExercises[index],
                    onClose: { editingGeneratedIndex = nil }
                )
                .presentationDetents([.medium, .large])
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $isTemplateActionsPresented) {
            if let template = selectedTemplate {
                WorkoutTemplateActionsSheet(
                    template: template,
                    onStart: {
                        Task { @MainActor in
                            await startSession(from: template)
                        }
                    },
                    onEdit: {
                        Task { @MainActor in
                            await loadTemplateForEditing(template)
                        }
                    },
                    onDuplicate: {
                        Task { @MainActor in
                            await duplicateTemplate(template)
                        }
                    },
                    onDelete: {
                        pendingDeleteTemplate = template
                        showDeleteAlert = true
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
            } else {
                Text("Loading...")
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .sheet(isPresented: $isTemplatePreviewPresented) {
            if let template = previewTemplate {
                WorkoutTemplatePreviewSheet(
                    template: template,
                    exercises: previewExercises,
                    isLoading: isPreviewLoading,
                    errorMessage: previewError,
                    onStart: {
                        isTemplatePreviewPresented = false
                        Task {
                            await startSessionFromPreview()
                        }
                    },
                    onClose: {
                        isTemplatePreviewPresented = false
                    }
                )
                .presentationDetents([.medium, .large])
            } else {
                Text("Loading...")
                    .foregroundColor(FitTheme.textSecondary)
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
        .fullScreenCover(isPresented: $showActiveSession) {
            Group {
                if let session = activeSession, !session.exercises.isEmpty {
                    WorkoutSessionView(
                        userId: userId,
                        title: session.title,
                        sessionId: session.sessionId,
                        exercises: session.exercises
                    )
                } else {
                    // Fallback view if session is invalid
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("Unable to load workout")
                            .font(FitFont.heading(size: 20))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Please try again")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                        Button("Dismiss") {
                            showActiveSession = false
                            activeSession = nil
                        }
                        .foregroundColor(FitTheme.accent)
                        .padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FitTheme.backgroundGradient.ignoresSafeArea())
                }
            }
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
        .alert("Resume Workout?", isPresented: $showRecoveryAlert) {
            Button("Resume") {
                recoverSavedSession()
            }
            Button("Discard", role: .destructive) {
                WorkoutSessionStore.clear()
                recoveryInfo = nil
            }
        } message: {
            if let info = recoveryInfo {
                let elapsed = formatRecoveryTime(info.elapsed)
                Text("You have an unfinished workout: \"\(info.title)\" with \(info.exerciseCount) exercises (\(elapsed) elapsed). Would you like to continue?")
            } else {
                Text("You have an unfinished workout. Would you like to continue?")
            }
        }
        .onChange(of: generatedExercises) { exercises in
            if exercises.isEmpty {
                generatedEstimatedMinutes = 0
                return
            }
            let estimate = estimateWorkoutMinutes(exercises)
            generatedEstimatedMinutes = clampedEstimateMinutes(
                estimate,
                targetMinutes: selectedDurationMinutes
            )
        }
        .onChange(of: intent) { newValue in
            guard let newValue else { return }
            Task {
                await handleIntent(newValue)
            }
        }
    }

    private var weeklySplitHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("Weekly Split")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer()

                Button(action: { }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(FitTheme.cardHighlight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            weeklySplitWeekView
        }
        .padding(.top, 4)
    }

    private var weeklySplitWeekView: some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                let palette = weeklyAccentPalette
                ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                    let label = splitLabel(for: date)
                    let status = weeklyDayStatus(for: date)
                    let dayNumber = Calendar.current.component(.day, from: date)
                    let detailId = dateKey(for: date)
                    let isSelected = selectedWeeklyDay?.id == detailId
                        || (selectedWeeklyDay == nil && Calendar.current.isDateInToday(date))
                    let accentColor = palette[index % palette.count]
                    WeeklySplitDayCell(
                        daySymbol: shortWeekdaySymbol(for: date),
                        dayNumber: dayNumber,
                        status: status,
                        isSelected: isSelected,
                        isTrainingDay: label != nil,
                        accentColor: accentColor,
                        action: {
                            let detail = weeklyDayDetail(for: date)
                            if selectedWeeklyDay?.id == detail.id {
                                selectedWeeklyDay = nil
                            } else {
                                selectedWeeklyDay = detail
                            }
                        }
                    )
                    .contextMenu {
                        Button("Edit Day") {
                            showTunePlanSheet = true
                        }
                        Button("Swap Workout") {
                            isSwapSheetPresented = true
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(FitTheme.cardBackground)
                    .shadow(color: FitTheme.shadow.opacity(0.35), radius: 10, x: 0, y: 6)
            )
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard abs(horizontal) > abs(vertical), abs(horizontal) > 40 else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if horizontal < 0 {
                                weekOffset += 1
                            } else {
                                weekOffset -= 1
                            }
                        }
                        selectedWeeklyDay = nil
                    }
            )

            if let day = selectedWeeklyDay {
                WeeklySplitInlineDetailCard(
                    day: day,
                    completion: WorkoutCompletionStore.completion(on: day.date),
                    onPrimaryAction: {
                        if day.isTrainingDay {
                            Task {
                                await startWeeklySplitSession(for: day.date)
                            }
                        } else {
                            mode = .generate
                            Task {
                                await generateWorkout()
                            }
                        }
                    },
                    onSwap: {
                        isSwapSheetPresented = true
                    },
                    onGenerate: {
                        mode = .generate
                        Task {
                            await generateWorkout()
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var workoutBuilderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            todaysTrainingCard

            Text("Workout Builder")
                .font(FitFont.body(size: 14, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)

            ModePicker(mode: $mode)

            switch mode {
            case .generate:
                generateSection
            case .saved:
                savedSection
            case .create:
                createSection
            }
        }
        .padding(.top, 8)
    }

    private var generateSection: some View {
        VStack(spacing: 18) {
            WorkoutHeroCard(onTap: { showTunePlanSheet = true }) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI Workout Builder")
                                .font(FitFont.heading(size: 22))
                                .foregroundColor(FitTheme.textPrimary)
                            Text("Tap to customize your workout plan")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        Spacer()
                        WorkoutIconBadge(symbol: "sparkles", accentColor: FitTheme.cardWorkoutAccent)
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

            if isGenerating {
                WorkoutGeneratingCard()
            }
            
            if !generatedExercises.isEmpty && !isGenerating {
                WorkoutCard(isAccented: true) {
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
                                ExerciseRow(
                                    name: exercise.name,
                                    detail: detail,
                                    badgeText: "\(index + 1)",
                                    onTap: { editingGeneratedIndex = index }
                                )
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
                            onPreview: {
                                presentTemplatePreview(template)
                            },
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
            withWarmupRest(WorkoutExerciseSession(
                name: "Bench Press",
                sets: [
                    WorkoutSetEntry(reps: "8", weight: "185", isComplete: false),
                    WorkoutSetEntry(reps: "8", weight: "185", isComplete: false),
                    WorkoutSetEntry(reps: "6", weight: "195", isComplete: false)
                ],
                restSeconds: 90
            )),
            withWarmupRest(WorkoutExerciseSession(
                name: "Incline Dumbbell Press",
                sets: [
                    WorkoutSetEntry(reps: "10", weight: "65", isComplete: false),
                    WorkoutSetEntry(reps: "10", weight: "65", isComplete: false),
                    WorkoutSetEntry(reps: "8", weight: "70", isComplete: false)
                ],
                restSeconds: 75
            )),
            withWarmupRest(WorkoutExerciseSession(
                name: "Cable Fly",
                sets: [
                    WorkoutSetEntry(reps: "12", weight: "40", isComplete: false),
                    WorkoutSetEntry(reps: "12", weight: "40", isComplete: false),
                    WorkoutSetEntry(reps: "12", weight: "40", isComplete: false)
                ],
                restSeconds: 60
            ))
        ]
    }

    private var defaultRecommendedExercises: [WorkoutExerciseSession] {
        sampleSessionExercises
    }

    private var spotlightExercises: [WorkoutExerciseSession] {
        if !coachPickExercises.isEmpty {
            return coachPickExercises
        }
        return generatedExercises.isEmpty ? defaultRecommendedExercises : generatedExercises
    }

    private var trainingPreviewExercises: [String] {
        let names = spotlightExercises.map { $0.name }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Array(names.prefix(3))
    }

    private var todaysTrainingCard: some View {
        let label = splitLabel(for: Date())
        let completion = todaysWorkout ?? WorkoutCompletionStore.completion(on: Date())
        let isCompleted = completion != nil
        let isCoachPick = coachPickTemplateId != nil && !coachPickExercises.isEmpty
        let titleText = coachPickTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = (titleText?.isEmpty == false ? titleText! : "Today's Training")
            .replacingOccurrences(of: "Coach's Pick: ", with: "")
            .replacingOccurrences(of: "Coaches Pick: ", with: "")
        let subtitle = isCoachPick ? "Coaches Pick" : (label ?? "Push Day")
        let statusText = isCompleted ? "Completed" : (isCoachPick ? "" : subtitle)

        let displayList: [String]
        if let completion, !completion.exercises.isEmpty {
            displayList = completion.exercises
        } else {
            displayList = trainingPreviewExercises
        }
        let previewList = Array(displayList.prefix(2))

        return WorkoutCard(isAccented: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: isCoachPick ? "sparkles" : "figure.run")
                                .font(.system(size: 14))
                                .foregroundColor(isCoachPick ? FitTheme.accent : FitTheme.cardWorkoutAccent)
                            Text(displayTitle)
                                .font(FitFont.body(size: 18))
                                .fontWeight(.semibold)
                                .foregroundColor(FitTheme.textPrimary)
                        }

                        HStack(spacing: 8) {
                            if !isCompleted {
                                Text("~\(selectedDurationMinutes) min")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)

                                Text("•")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            }

                            if !statusText.isEmpty {
                                Text(statusText)
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(isCompleted ? FitTheme.success : FitTheme.cardWorkoutAccent)
                            }

                            if isCoachPick {
                                WorkoutCoachPickPill()
                            }
                        }
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(previewList, id: \.self) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(FitTheme.cardWorkoutAccent)
                                .frame(width: 6, height: 6)
                            Text(item)
                                .font(FitFont.body(size: 14))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }

                    if displayList.count > previewList.count {
                        Text("+\(displayList.count - previewList.count) more exercises")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.cardWorkoutAccent)
                    }
                }

                if !isCompleted {
                    HStack(spacing: 12) {
                        ActionButton(title: "Start Workout", style: .primary) {
                            Task {
                                await startWeeklySplitSession(for: Date())
                            }
                        }
                        ActionButton(title: "Swap", style: .secondary) {
                            isSwapSheetPresented = true
                        }
                    }
                }
            }
        }
    }

    private let splitPreferencesKey = "fitai.onboarding.split.preferences"
    private let onboardingFormKey = "fitai.onboarding.form"

    private var weekDates: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        let today = Date()
        let baseWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let weekStart = calendar.date(byAdding: .day, value: weekOffset * 7, to: baseWeekStart) ?? baseWeekStart
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var splitDayRows: [String] {
        defaultSplitDayNames(for: splitSnapshot.daysPerWeek)
    }

    private var weeklyAccentPalette: [Color] {
        [
            FitTheme.accent, // streak purple
            Color(red: 0.10, green: 0.85, blue: 0.45), // bright green
            Color(red: 0.95, green: 0.36, blue: 0.22), // vivid orange
            Color(red: 0.10, green: 0.75, blue: 0.95), // bright cyan
            Color(red: 0.97, green: 0.22, blue: 0.62), // hot pink
            Color(red: 0.98, green: 0.76, blue: 0.20), // bright amber
            Color(red: 0.27, green: 0.52, blue: 1.00)  // electric blue
        ]
    }

    private var weekRangeLabel: String {
        guard let start = weekDates.first, let end = weekDates.last else { return "This Week" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func completionPreview(_ exercises: [String]) -> String {
        let trimmed = exercises.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !trimmed.isEmpty else { return "Session logged" }
        let preview = trimmed.prefix(3)
        let base = preview.joined(separator: " • ")
        if trimmed.count > 3 {
            return "\(base) +\(trimmed.count - 3) more"
        }
        return base
    }

    private func shortWeekdaySymbol(for date: Date) -> String {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols.isEmpty ? calendar.shortWeekdaySymbols : calendar.veryShortWeekdaySymbols
        let index = max(0, min(symbols.count - 1, calendar.component(.weekday, from: date) - 1))
        return symbols[index].uppercased()
    }

    private func weeklyDayStatus(for date: Date) -> WeeklyDayStatus {
        let label = splitLabel(for: date)
        guard label != nil else { return .rest }

        if Calendar.current.isDateInToday(date) {
            if todaysWorkout != nil || WorkoutCompletionStore.hasCompletion(on: date) {
                return .completed
            }
            return .today
        }

        if WorkoutCompletionStore.hasCompletion(on: date) {
            return .completed
        }

        return .upcoming
    }

    private func weeklyDayDetail(for date: Date) -> WeeklyDayDetail {
        let label = splitLabel(for: date)
        let status = weeklyDayStatus(for: date)
        let isTrainingDay = label != nil
        let estimatedMinutes = isTrainingDay ? max(30, selectedDurationMinutes) : 0
        let workoutName = label ?? "Rest"
        return WeeklyDayDetail(
            id: dateKey(for: date),
            date: date,
            workoutName: workoutName,
            focus: splitSnapshot.focus,
            estimatedMinutes: estimatedMinutes,
            status: status,
            isTrainingDay: isTrainingDay
        )
    }

    private func startWeeklySplitSession(for date: Date) async {
        let title = splitLabel(for: date) ?? "Today's Training"
        if let coachId = coachPickTemplateId, !coachPickExercises.isEmpty {
            await startSession(
                title: title,
                templateId: coachId,
                exercises: coachPickExercises
            )
        } else {
            await startSession(
                title: title,
                templateId: nil,
                exercises: spotlightExercises
            )
        }
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
        case .startCoachPick(let templateId):
            // Start a coach-generated workout
            do {
                let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: templateId)
                let exercises = detail.exercises.map { ex in
                    let session = WorkoutExerciseSession(
                        name: ex.name,
                        sets: WorkoutSetEntry.batch(
                            reps: "\(ex.reps ?? 10)",
                            weight: "",
                            count: ex.sets ?? 3
                        ),
                        restSeconds: ex.restSeconds ?? 60,
                        notes: ex.notes ?? ""
                    )
                    return withWarmupRest(session)
                }
                await startSession(
                    title: detail.template.title,
                    templateId: templateId,
                    exercises: exercises
                )
            } catch {
                await MainActor.run {
                    loadError = "Failed to load Coaches Pick workout."
                    Haptics.error()
                }
            }
        }
        await MainActor.run {
            self.intent = nil
        }
    }

    private func refreshSplitSnapshot() {
        let calendar = Calendar.current
        var mode: SplitCreationMode = .ai
        var daysPerWeek = 3
        var trainingDays: [String] = []
        var focus = "Strength"

        if let data = UserDefaults.standard.data(forKey: splitPreferencesKey),
           let decoded = try? JSONDecoder().decode(SplitSetupPreferences.self, from: data) {
            mode = SplitCreationMode(rawValue: decoded.mode) ?? .ai
            daysPerWeek = min(max(decoded.daysPerWeek, 2), 7)
            trainingDays = normalizedTrainingDays(decoded.trainingDays, targetCount: daysPerWeek)
        } else if let data = UserDefaults.standard.data(forKey: onboardingFormKey),
                  let form = try? JSONDecoder().decode(OnboardingForm.self, from: data) {
            daysPerWeek = min(max(form.workoutDaysPerWeek, 2), 7)
            trainingDays = normalizedTrainingDays([], targetCount: daysPerWeek)
            focus = focusForGoal(form.goal)
        } else {
            trainingDays = normalizedTrainingDays([], targetCount: daysPerWeek)
        }

        if let data = UserDefaults.standard.data(forKey: onboardingFormKey),
           let form = try? JSONDecoder().decode(OnboardingForm.self, from: data) {
            focus = focusForGoal(form.goal)
        }

        if trainingDays.isEmpty {
            let weekdays = calendar.weekdaySymbols
            trainingDays = weekdays.prefix(daysPerWeek).map { $0 }
        }

        let name = splitDisplayName(daysPerWeek: daysPerWeek, mode: mode)
        splitSnapshot = SplitSnapshot(
            mode: mode,
            daysPerWeek: daysPerWeek,
            trainingDays: trainingDays,
            focus: focus,
            name: name
        )
    }

    private func focusForGoal(_ goal: OnboardingForm.Goal?) -> String {
        switch goal {
        case .gainWeight:
            return "Hypertrophy"
        case .loseWeight, .loseWeightFast:
            return "Fat loss + muscle"
        case .maintain:
            return "Strength"
        case .none:
            return "Strength"
        }
    }

    private func splitDisplayName(daysPerWeek: Int, mode: SplitCreationMode) -> String {
        if mode == .custom {
            return "Custom Split"
        }
        switch daysPerWeek {
        case 2:
            return "Upper / Lower"
        case 3:
            return "Full Body"
        case 4:
            return "Upper / Lower"
        case 5:
            return "Hybrid Split"
        case 6:
            return "Push / Pull / Legs"
        default:
            return "Full Body"
        }
    }

    private func defaultSplitDayNames(for daysPerWeek: Int) -> [String] {
        switch daysPerWeek {
        case 2:
            return ["Upper", "Lower"]
        case 3:
            return ["Full Body A", "Full Body B", "Full Body C"]
        case 4:
            return ["Upper", "Lower", "Upper", "Lower"]
        case 5:
            return ["Push", "Pull", "Legs", "Upper", "Lower"]
        case 6:
            return ["Push", "Pull", "Legs", "Push", "Pull", "Legs"]
        case 7:
            return ["Full Body", "Full Body", "Full Body", "Full Body", "Full Body", "Full Body", "Full Body"]
        default:
            return ["Full Body"]
        }
    }

    private func splitLabel(for date: Date) -> String? {
        let weekday = weekdaySymbol(for: date)
        guard let index = splitSnapshot.trainingDays.firstIndex(of: weekday) else {
            return nil
        }
        let rows = splitDayRows
        return index < rows.count ? rows[index] : rows.last
    }

    private func weekdaySymbol(for date: Date) -> String {
        let calendar = Calendar.current
        let index = max(0, min(calendar.weekdaySymbols.count - 1, calendar.component(.weekday, from: date) - 1))
        return calendar.weekdaySymbols[index]
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func normalizedTrainingDays(_ days: [String], targetCount: Int) -> [String] {
        let availableDays = Calendar.current.weekdaySymbols
        let filtered = days.filter { availableDays.contains($0) }
        var ordered = availableDays.filter { filtered.contains($0) }

        if ordered.count > targetCount {
            ordered = Array(ordered.prefix(targetCount))
        }

        if ordered.count < targetCount {
            for day in availableDays where !ordered.contains(day) {
                ordered.append(day)
                if ordered.count == targetCount {
                    break
                }
            }
        }

        return ordered
    }

    private func presentTemplatePreview(_ template: WorkoutTemplate) {
        previewTemplate = template
        previewExercises = []
        previewError = nil
        isPreviewLoading = true
        isTemplatePreviewPresented = true
        Task {
            do {
                let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: template.id)
                await MainActor.run {
                    previewTemplate = detail.template
                    previewExercises = detail.exercises
                    isPreviewLoading = false
                }
            } catch {
                await MainActor.run {
                    previewExercises = []
                    previewError = "Unable to load workout preview."
                    isPreviewLoading = false
                }
            }
        }
    }

    private func startSession(from template: WorkoutTemplate) async {
        guard !userId.isEmpty else {
            await MainActor.run {
                loadError = "Missing user session. Please log in again."
                Haptics.error()
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: template.id)
            guard !detail.exercises.isEmpty else {
                await MainActor.run {
                    isLoading = false
                    showPlaceholderAlert(
                        title: "Empty workout",
                        message: "This workout template has no exercises. Please edit it to add exercises."
                    )
                }
                return
            }
            let exercises = sessionExercises(from: detail.exercises)
            await MainActor.run {
                isLoading = false
            }
            await startSession(title: template.title, templateId: template.id, exercises: exercises)
        } catch {
            await MainActor.run {
                isLoading = false
                loadError = "Unable to start workout. \(error.localizedDescription)"
                Haptics.error()
            }
        }
    }

    private func startSessionFromPreview() async {
        guard let template = previewTemplate else { return }
        if previewExercises.isEmpty {
            await startSession(from: template)
            return
        }
        let exercises = sessionExercises(from: previewExercises)
        await startSession(title: template.title, templateId: template.id, exercises: exercises)
    }

    private func startSession(
        title: String,
        templateId: String?,
        exercises: [WorkoutExerciseSession]
    ) async {
        let resolvedExercises = exercises.isEmpty ? defaultRecommendedExercises : exercises
        guard !resolvedExercises.isEmpty else {
            await MainActor.run {
                showPlaceholderAlert(
                    title: "No exercises",
                    message: "This workout doesn't have any exercises yet."
                )
            }
            return
        }

        await MainActor.run {
            activeSession = SessionDraft(
                sessionId: nil as String?,
                title: title,
                exercises: resolvedExercises
            )
            showActiveSession = true
        }

        guard !userId.isEmpty else { return }
        do {
            let sessionId = try await WorkoutAPIService.shared.startSession(
                userId: userId,
                templateId: templateId
            )
            await MainActor.run {
                guard showActiveSession else { return }
                activeSession = SessionDraft(
                    sessionId: sessionId,
                    title: title,
                    exercises: resolvedExercises
                )
            }
        } catch {
            await MainActor.run {
                // Clear any error - session still works locally
                loadError = nil
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
            await MainActor.run {
                draftName = ""
                draftExercises = []
                isSavingDraft = false
                mode = .saved
                Haptics.success()
                // Show success message
                showPlaceholderAlert(title: "Workout Saved!", message: "Your template has been saved. You can start it anytime from the Saved tab.")
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

    private func recoverSavedSession() {
        guard let savedSession = WorkoutSessionStore.load() else {
            recoveryInfo = nil
            return
        }
        
        let exercises = savedSession.exercises.map { $0.toWorkoutExerciseSession() }
        
        activeSession = SessionDraft(
            sessionId: savedSession.sessionId,
            title: savedSession.title,
            exercises: exercises
        )
        showActiveSession = true
        recoveryInfo = nil
    }
    
    private func formatRecoveryTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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
                Haptics.error()
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: template.id)
            await MainActor.run {
                isLoading = false
                editingTemplateId = template.id
                draftName = detail.template.title
                draftExercises = draftExercises(from: detail.exercises)
                mode = .create
                loadError = nil
                Haptics.light()
            }
        } catch {
            await MainActor.run {
                isLoading = false
                loadError = "Unable to load template. \(error.localizedDescription)"
                Haptics.error()
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
            let session = WorkoutExerciseSession(
                name: exercise.name,
                sets: WorkoutSetEntry.batch(
                    reps: repsText,
                    weight: "",
                    count: setCount
                ),
                restSeconds: restSeconds
            )
            return withWarmupRest(session)
        }
    }

    private struct ParsedGeneratedWorkout {
        let title: String
        let exercises: [WorkoutExerciseSession]
    }

    private struct GeneratedWorkoutPayload: Decodable {
        let title: String?
        let exercises: [GeneratedExercise]?
        
        init(title: String?, exercises: [GeneratedExercise]?) {
            self.title = title
            self.exercises = exercises
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            exercises = try container.decodeIfPresent([GeneratedExercise].self, forKey: .exercises)
        }
        
        enum CodingKeys: String, CodingKey {
            case title, exercises
        }
    }

    private struct GeneratedExercise: Decodable {
        let name: String?
        let exercise: String?
        let exerciseName: String?
        let sets: Int?
        let reps: String?
        let restSeconds: Int?
        let rest: Int?
        let notes: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            name = Self.decodeLossyString(from: container, keys: ["name"])
            exercise = Self.decodeLossyString(from: container, keys: ["exercise"])
            exerciseName = Self.decodeLossyString(
                from: container,
                keys: ["exercise_name", "exerciseName", "movement", "movement_name", "movementName"]
            )
            sets = Self.decodeLossyInt(from: container, keys: ["sets", "set_count", "setCount"])
            reps = Self.decodeLossyString(
                from: container,
                keys: ["reps", "rep_range", "repRange", "repetitions", "rep_count", "repCount"]
            )
            restSeconds = Self.decodeLossyInt(
                from: container,
                keys: ["rest_seconds", "restSeconds", "rest_time_seconds", "restTimeSeconds", "rest_time", "restTime", "rest"]
            )
            rest = Self.decodeLossyInt(from: container, keys: ["rest", "rest_seconds", "restSeconds"])
            notes = Self.decodeLossyString(from: container, keys: ["notes", "note", "coaching_cues", "cues"])
        }

        private struct DynamicCodingKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil

            init?(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue: Int) {
                return nil
            }
        }

        private static func decodeLossyInt(
            from container: KeyedDecodingContainer<DynamicCodingKey>,
            keys: [String]
        ) -> Int? {
            for key in keys {
                guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                if let value = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
                    return value
                }
                if let value = try? container.decodeIfPresent(String.self, forKey: codingKey) {
                    if let number = firstNumber(in: value) {
                        return number
                    }
                }
            }
            return nil
        }

        private static func decodeLossyString(
            from container: KeyedDecodingContainer<DynamicCodingKey>,
            keys: [String]
        ) -> String? {
            for key in keys {
                guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                if let value = try? container.decodeIfPresent(String.self, forKey: codingKey) {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
                if let value = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
                    return "\(value)"
                }
            }
            return nil
        }

        private static func firstNumber(in value: String) -> Int? {
            let parts = value.split { !$0.isNumber }
            guard let first = parts.first else { return nil }
            return Int(first)
        }
    }

    private func parseGeneratedWorkout(_ text: String) -> ParsedGeneratedWorkout {
        if let payload = decodeGeneratedWorkout(from: text) {
            let exercises = payload.exercises.map { exercisesFromGenerated($0) } ?? []
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
        let candidates = extractJSONCandidates(from: text)
        for candidate in candidates {
            if let payload = decodeGeneratedWorkoutCandidate(candidate) {
                return payload
            }
        }
        return nil
    }

    private func decodeGeneratedWorkoutCandidate(_ candidate: String) -> GeneratedWorkoutPayload? {
        let sanitized = sanitizeJSONString(candidate)
        guard let data = sanitized.data(using: .utf8) else { return nil }
        if let payload = decodeGeneratedWorkout(from: data) {
            return payload
        }
        if let object = try? JSONSerialization.jsonObject(with: data, options: []) {
            return extractGeneratedPayload(from: object)
        }
        return nil
    }

    private func decodeGeneratedWorkout(from data: Data) -> GeneratedWorkoutPayload? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let payload = try? decoder.decode(GeneratedWorkoutPayload.self, from: data) {
            if payload.exercises != nil || payload.title != nil {
                return payload
            }
        }

        if let exercises = try? decoder.decode([GeneratedExercise].self, from: data) {
            return GeneratedWorkoutPayload(title: nil as String?, exercises: exercises)
        }

        return nil
    }

    private func extractGeneratedPayload(from object: Any) -> GeneratedWorkoutPayload? {
        if let payload = payloadFromJSON(object) {
            return payload
        }
        return nil
    }

    private func payloadFromJSON(_ object: Any) -> GeneratedWorkoutPayload? {
        if let dict = object as? [String: Any] {
            if let payload = payloadFromDictionary(dict) {
                return payload
            }
            let nestedKeys = ["workout", "template", "plan", "result", "data"]
            for key in nestedKeys {
                if let nested = dict[key], let payload = payloadFromJSON(nested) {
                    return payload
                }
            }
            return nil
        }
        if let array = object as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array, options: []) {
            return decodeGeneratedWorkout(from: data)
        }
        if let string = object as? String {
            return decodeGeneratedWorkout(from: string)
        }
        return nil
    }

    private func payloadFromDictionary(_ dict: [String: Any]) -> GeneratedWorkoutPayload? {
        guard dict["exercises"] != nil || dict["title"] != nil else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else {
            return nil
        }
        return decodeGeneratedWorkout(from: data)
    }

    private func extractJSONCandidates(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []

        let fencePattern = "```(?:json)?\\s*([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: fencePattern, options: []) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            regex.enumerateMatches(in: trimmed, options: [], range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let captureRange = Range(match.range(at: 1), in: trimmed) else {
                    return
                }
                let candidate = trimmed[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    candidates.append(candidate)
                }
            }
        }

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            candidates.append(trimmed)
        }

        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}") {
            candidates.append(String(trimmed[firstBrace...lastBrace]))
        }

        if let firstBracket = trimmed.firstIndex(of: "["),
           let lastBracket = trimmed.lastIndex(of: "]") {
            candidates.append(String(trimmed[firstBracket...lastBracket]))
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return false }
            if seen.contains(normalized) {
                return false
            }
            seen.insert(normalized)
            return true
        }
    }

    private func sanitizeJSONString(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #",\s*([}\]])"#,
                with: "$1",
                options: .regularExpression
            )
    }

    private func exercisesFromGenerated(_ exercises: [GeneratedExercise]) -> [WorkoutExerciseSession] {
        exercises.compactMap { item in
            let name = item.name ?? item.exercise ?? ""
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }
            let lowerName = trimmedName.lowercased()
            // Filter out placeholder names and JSON field names that leak through malformed AI responses
            let invalidNames: Set<String> = [
                "rest_seconds", "rest", "reps", "sets", "name", "exercise", "exercises",
                "notes", "title", "exercise_name", "exercisename", "tempo", "duration",
                "weight", "muscle_groups", "equipment", "workout", "template"
            ]
            if invalidNames.contains(lowerName) || lowerName.hasPrefix("\"") || lowerName.hasSuffix("\"") {
                return nil
            }
            let sets = normalizedSetCount(item.sets)
            let repsText = normalizedRepsText(item.reps)
            let restSeconds = normalizedRestSeconds(item.restSeconds ?? item.rest)
            let session = WorkoutExerciseSession(
                name: trimmedName,
                sets: WorkoutSetEntry.batch(reps: repsText, weight: "", count: sets),
                restSeconds: restSeconds
            )
            return withWarmupRest(session)
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
            if let compound = Self.exerciseLibrary[group]?.compound.first {
                exercises.append(makeSessionExercise(from: compound, sets: config.defaultSets))
            }
        }

        if exercises.count < config.minExercises {
            for group in selected {
                guard exercises.count < config.minExercises else { break }
                if let isolation = Self.exerciseLibrary[group]?.isolation.first {
                    exercises.append(makeSessionExercise(from: isolation, sets: config.defaultSets))
                }
            }
        }

        let allExtras = Self.exerciseLibrary.values.flatMap { $0.compound + $0.isolation }
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
            if let seed = Self.exerciseLibrary[group]?.compound.first {
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

    private func clampedEstimateMinutes(_ estimate: Int, targetMinutes: Int) -> Int {
        guard targetMinutes > 0 else { return max(estimate, 0) }
        let lower = Int(Double(targetMinutes) * 0.9)
        let upper = Int(Double(targetMinutes) * 1.1)
        return min(max(estimate, lower), upper)
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

    private static let exerciseLibrary: [String: ExercisePool] = [
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
            "quads": ExercisePool(
                compound: [
                    ExerciseSeed(name: "Back Squat", restSeconds: 120),
                    ExerciseSeed(name: "Front Squat", restSeconds: 120),
                    ExerciseSeed(name: "Leg Press", restSeconds: 90),
                    ExerciseSeed(name: "Hack Squat", restSeconds: 90)
                ],
                isolation: [
                    ExerciseSeed(name: "Leg Extension", restSeconds: 60),
                    ExerciseSeed(name: "Sissy Squat", restSeconds: 60),
                    ExerciseSeed(name: "Walking Lunge", restSeconds: 60)
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

    private func makeSessionExercise(from seed: ExerciseSeed, sets: Int) -> WorkoutExerciseSession {
        var session = WorkoutExerciseSession(
            name: seed.name,
            sets: WorkoutSetEntry.batch(reps: "10", weight: "", count: max(sets, 1)),
            restSeconds: normalizedRestSeconds(seed.restSeconds)
        )
        session.warmupRestSeconds = min(60, session.restSeconds)
        return session
    }

    private func normalizedSetCount(_ value: Int?) -> Int {
        let sets = value ?? 3
        return min(max(sets, 1), 6)
    }

    private func normalizedRepsText(_ value: Int?) -> String {
        if let value {
            return normalizedRepsText("\(value)")
        }
        return "10"
    }

    private func normalizedRepsText(_ value: String?) -> String {
        guard let value else { return "10" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "10" }
        if let match = regexMatch(#"(\d+\s*-\s*\d+)"#, in: trimmed, captureCount: 1) {
            return match.captures[0].replacingOccurrences(of: " ", with: "")
        }
        if let match = regexMatch(#"(\d+)"#, in: trimmed, captureCount: 1) {
            return match.captures[0]
        }
        return "10"
    }

    private func normalizedRestSeconds(_ value: Int?) -> Int {
        let rest = value ?? 90
        return min(max(rest, 30), 150)
    }

    private func withWarmupRest(_ session: WorkoutExerciseSession) -> WorkoutExerciseSession {
        var updated = session
        updated.warmupRestSeconds = min(60, updated.restSeconds)
        return updated
    }

    private func ensureSetCount(_ exercise: WorkoutExerciseSession, minSets: Int, maxSets: Int) -> WorkoutExerciseSession {
        let sets = min(max(exercise.sets.count, minSets), maxSets)
        if sets == exercise.sets.count {
            return exercise
        }
        var updated = WorkoutExerciseSession(
            name: exercise.name,
            sets: WorkoutSetEntry.batch(
                reps: exercise.sets.first?.reps ?? "10",
                weight: exercise.sets.first?.weight ?? "",
                count: sets
            ),
            restSeconds: exercise.restSeconds
        )
        updated.warmupRestSeconds = exercise.warmupRestSeconds
        return updated
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
            if let pool = Self.exerciseLibrary[group] {
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
        guard let pool = Self.exerciseLibrary[group] else { return false }
        let matches = (pool.compound + pool.isolation).map { $0.name.lowercased() }
        return matches.contains(name.lowercased())
    }

    private func parseExerciseLine(_ line: String) -> WorkoutExerciseSession? {
        let cleaned = stripBulletPrefix(line)
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower == "{" || lower == "}" || lower == "[" || lower == "]" {
            return nil
        }
        let jsonKeys = [
            "exercises", "exercise", "name", "notes", "sets", "reps", "rest", "rest_seconds", "title"
        ]
        if let separator = trimmed.firstIndex(of: ":") {
            let keyCandidate = trimmed[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .lowercased()
            if jsonKeys.contains(keyCandidate) {
                return nil
            }
        }
        let lowerKey = lower.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if jsonKeys.contains(lowerKey) {
            return nil
        }
        if lower.contains("rest_seconds") || lower.hasPrefix("rest:") || lower.hasPrefix("reps:")
            || lower.hasPrefix("sets:") || lower.hasPrefix("rest seconds") {
            return nil
        }

        let parsed = extractSetReps(from: trimmed)
        let restSeconds = normalizedRestSeconds(extractRest(from: trimmed))

        var name = trimmed
        if let range = firstSeparatorRange(in: trimmed) {
            name = String(trimmed[..<range.lowerBound])
        } else if let matchRange = parsed.matchRange, let range = Range(matchRange, in: trimmed) {
            name = trimmed.replacingCharacters(in: range, with: "")
        }

        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let setCount = normalizedSetCount(parsed.sets)
        let repsText = parsed.repsText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "10"

        let session = WorkoutExerciseSession(
            name: name,
            sets: WorkoutSetEntry.batch(reps: repsText, weight: "", count: setCount),
            restSeconds: restSeconds
        )
        return withWarmupRest(session)
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
            let clampedEstimate = clampedEstimateMinutes(
                estimate,
                targetMinutes: selectedDurationMinutes
            )
            await MainActor.run {
                generatedPreview = result.isEmpty ? "Workout generated." : result
                generatedTitle = parsed.exercises.isEmpty ? "Quick Build" : parsed.title
                generatedExercises = adjustedExercises
                generatedEstimatedMinutes = clampedEstimate
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
            let clampedEstimate = clampedEstimateMinutes(
                estimate,
                targetMinutes: selectedDurationMinutes
            )
            await MainActor.run {
                generatedTitle = "Quick Build"
                generatedExercises = fallback
                generatedEstimatedMinutes = clampedEstimate
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
            await loadCoachPickWorkout(from: templates)
        } catch {
            await MainActor.run {
                self.loadError = "Unable to load workouts."
                self.isLoading = false
            }
            await MainActor.run {
                coachPickTemplateId = nil
                coachPickTitle = nil
                coachPickExercises = []
            }
        }
    }

    private func loadCoachPickWorkout(from templates: [WorkoutTemplate]) async {
        guard let coachTemplate = templates.first(where: { $0.mode == "coach" }) else {
            await MainActor.run {
                coachPickTemplateId = nil
                coachPickTitle = nil
                coachPickExercises = []
            }
            return
        }
        do {
            let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: coachTemplate.id)
            let exercises = sessionExercises(from: detail.exercises)
            await MainActor.run {
                coachPickTemplateId = coachTemplate.id
                coachPickTitle = coachTemplate.title
                coachPickExercises = exercises
            }
        } catch {
            await MainActor.run {
                coachPickTemplateId = nil
                coachPickTitle = nil
                coachPickExercises = []
            }
        }
    }

    private func showPlaceholderAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
private struct CoachPickBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text("COACHES PICK")
                .font(FitFont.body(size: 10, weight: .bold))
                .tracking(0.6)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [FitTheme.cardCoachAccent, FitTheme.cardCoachAccent.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: FitTheme.cardCoachAccent.opacity(0.25), radius: 6, x: 0, y: 4)
    }
}

private struct WorkoutHeroCard<Content: View>: View {
    var onTap: (() -> Void)?
    @ViewBuilder let content: Content
    
    init(onTap: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.onTap = onTap
        self.content = content()
    }

    var body: some View {
        Group {
            if let onTap = onTap {
                Button(action: onTap) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }
    
    private var cardContent: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(FitTheme.cardWorkout)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(FitTheme.cardWorkoutAccent.opacity(0.1))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(FitTheme.cardWorkoutAccent.opacity(0.3), lineWidth: 1.5)
            )
            .shadow(color: FitTheme.cardWorkoutAccent.opacity(0.15), radius: 18, x: 0, y: 10)
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
    var accentColor: Color = FitTheme.accent

    var body: some View {
        Image(systemName: symbol)
            .font(FitFont.body(size: 14, weight: .bold))
            .foregroundColor(FitTheme.buttonText)
            .padding(10)
            .background(accentColor)
            .clipShape(Circle())
            .shadow(color: accentColor.opacity(0.4), radius: 10, x: 0, y: 6)
    }
}

private struct SplitSnapshot {
    var mode: SplitCreationMode = .ai
    var daysPerWeek: Int = 3
    var trainingDays: [String] = []
    var focus: String = "Strength"
    var name: String = "Full Body"
}

private enum WeeklyDayStatus {
    case completed
    case today
    case upcoming
    case rest

    var label: String {
        switch self {
        case .completed:
            return "Completed"
        case .today:
            return "Today"
        case .upcoming:
            return "Upcoming"
        case .rest:
            return "Rest"
        }
    }
}

private struct WeeklyDayDetail: Identifiable {
    let id: String
    let date: Date
    let workoutName: String
    let focus: String
    let estimatedMinutes: Int
    let status: WeeklyDayStatus
    let isTrainingDay: Bool
}

private struct WeeklySplitDayCell: View {
    let daySymbol: String
    let dayNumber: Int
    let status: WeeklyDayStatus
    let isSelected: Bool
    let isTrainingDay: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Text(daySymbol)
                        .font(FitFont.body(size: 10, weight: .semibold))
                        .foregroundColor(topTextColor)
                    Text("\(dayNumber)")
                        .font(FitFont.body(size: 18, weight: .bold))
                        .foregroundColor(mainTextColor)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(borderColor, lineWidth: isSelected ? 0 : 1)
                )
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowOffsetY)

                if status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(FitTheme.textOnAccent)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        if isSelected, isTrainingDay {
            return accentColor
        }
        if !isTrainingDay {
            return isSelected ? FitTheme.cardHighlight.opacity(0.8) : FitTheme.cardHighlight
        }
        switch status {
        case .completed:
            return accentColor
        case .today:
            return accentColor.opacity(0.28)
        case .upcoming:
            return accentColor.opacity(0.18)
        case .rest:
            return FitTheme.cardHighlight
        }
    }

    private var borderColor: Color {
        if isSelected, isTrainingDay {
            return accentColor
        }
        if isSelected, !isTrainingDay {
            return FitTheme.cardStroke.opacity(0.7)
        }
        switch status {
        case .today:
            return accentColor
        case .upcoming:
            return accentColor.opacity(0.5)
        case .rest:
            return FitTheme.cardStroke.opacity(0.4)
        case .completed:
            return accentColor
        }
    }

    private var shadowColor: Color {
        isSelected ? FitTheme.shadow.opacity(0.45) : FitTheme.shadow.opacity(0.25)
    }

    private var shadowRadius: CGFloat {
        isSelected ? 10 : 6
    }

    private var shadowOffsetY: CGFloat {
        isSelected ? 8 : 4
    }

    private var topTextColor: Color {
        if isSelected, isTrainingDay { return FitTheme.textOnAccent.opacity(0.9) }
        return FitTheme.textSecondary
    }

    private var mainTextColor: Color {
        if isSelected, isTrainingDay { return FitTheme.textOnAccent }
        return FitTheme.textPrimary
    }
}

private struct WeeklySplitInlineDetailCard: View {
    let day: WeeklyDayDetail
    let completion: WorkoutCompletion?
    let onPrimaryAction: () -> Void
    let onSwap: () -> Void
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayHeader)
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                    Text(dayTitle)
                        .font(FitFont.heading(size: 18, weight: .bold))
                        .foregroundColor(FitTheme.textPrimary)
                }
                Spacer()
                statusPill
            }

            if let completion, !completion.exercises.isEmpty {
                Text("Completed: \(completionSummary(completion.exercises))")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            } else if day.isTrainingDay {
                Text("Planned: \(day.workoutName)")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            } else {
                Text("Rest day. Generate a workout if you want to train.")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }

            HStack(spacing: 10) {
                detailPill(title: "Est. time", value: day.estimatedMinutes > 0 ? "\(day.estimatedMinutes) min" : "Rest")
                detailPill(title: "Focus", value: day.focus)
            }

            ActionButton(title: primaryButtonTitle, style: .primary) {
                onPrimaryAction()
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                ActionButton(title: "Swap", style: .secondary) {
                    onSwap()
                }
                .frame(maxWidth: .infinity)

                if shouldShowGenerateSecondary {
                    ActionButton(title: "Generate", style: .secondary) {
                        onGenerate()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FitTheme.cardWorkout)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
        )
    }

    private var dayTitle: String {
        day.isTrainingDay ? day.workoutName : "Rest"
    }

    private var dayHeader: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: day.date)
    }

    private var primaryButtonTitle: String {
        if day.isTrainingDay, completion == nil {
            return "Start workout"
        }
        if completion != nil {
            return "Repeat workout"
        }
        return "Generate workout"
    }

    private var shouldShowGenerateSecondary: Bool {
        day.isTrainingDay
    }

    @ViewBuilder
    private var statusPill: some View {
        Text(day.status.label)
            .font(FitFont.body(size: 10, weight: .semibold))
            .foregroundColor(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch day.status {
        case .completed:
            return FitTheme.success
        case .today:
            return FitTheme.accent
        case .upcoming:
            return FitTheme.textSecondary
        case .rest:
            return FitTheme.textSecondary
        }
    }

    private func completionSummary(_ exercises: [String]) -> String {
        let trimmed = exercises.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !trimmed.isEmpty else { return "Session logged" }
        let preview = trimmed.prefix(3)
        let base = preview.joined(separator: " • ")
        if trimmed.count > 3 {
            return "\(base) +\(trimmed.count - 3) more"
        }
        return base
    }

    private func detailPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(FitFont.body(size: 9, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)
            Text(value)
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct WeeklySplitDetailSheet: View {
    let day: WeeklyDayDetail
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(weekdayLabel)
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(FitTheme.textPrimary)
                Text(day.workoutName)
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
            }

            HStack(spacing: 12) {
                detailPill(title: "Est. time", value: day.estimatedMinutes > 0 ? "\(day.estimatedMinutes) min" : "Rest")
                detailPill(title: "Focus", value: day.focus)
            }

            Button(action: onStart) {
                Text(day.isTrainingDay ? "Start workout" : "No workout scheduled")
                    .font(FitFont.body(size: 15, weight: .semibold))
                    .foregroundColor(FitTheme.buttonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(!day.isTrainingDay)
            .opacity(day.isTrainingDay ? 1.0 : 0.4)

            Spacer()
        }
        .padding(24)
    }

    private var weekdayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: day.date)
    }

    private func detailPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FitFont.body(size: 11, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)
            Text(value)
                .font(FitFont.body(size: 14, weight: .semibold))
                .foregroundColor(FitTheme.textPrimary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FitTheme.cardStroke.opacity(0.7), lineWidth: 1)
        )
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
                        FitTheme.cardWorkoutAccent
                    } else {
                        FitTheme.cardWorkout
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
                        FitTheme.cardWorkoutAccent
                    } else {
                        FitTheme.cardWorkout
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FitTheme.cardWorkoutAccent.opacity(0.3), lineWidth: isSelected ? 0 : 1)
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

private struct GeneratedExerciseEditor: View {
    @Binding var exercise: WorkoutExerciseSession
    let onClose: () -> Void

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                header

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(exercise.sets.indices, id: \.self) { index in
                            GeneratedSetRow(
                                index: index + 1,
                                setEntry: $exercise.sets[index],
                                canRemove: exercise.sets.count > 1,
                                onRemove: { removeSet(at: index) }
                            )
                        }

                        ActionButton(title: "Add set", style: .secondary) {
                            addSet()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(FitTheme.textPrimary)
                Text("Adjust reps and weights")
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
    }

    private func addSet() {
        let last = exercise.sets.last
        let entry = WorkoutSetEntry(
            reps: last?.reps ?? "10",
            weight: last?.weight ?? "",
            isComplete: false
        )
        exercise.sets.append(entry)
    }

    private func removeSet(at index: Int) {
        guard exercise.sets.count > 1 else { return }
        exercise.sets.remove(at: index)
    }
}

private struct GeneratedSetRow: View {
    let index: Int
    @Binding var setEntry: WorkoutSetEntry
    let canRemove: Bool
    let onRemove: () -> Void
    @FocusState private var focusedField: Field?

    private enum Field {
        case reps
        case weight
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Set \(index)")
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(FitTheme.textSecondary)
                .frame(width: 50, alignment: .leading)

            setField(title: "Reps", value: $setEntry.reps, field: .reps)
            setField(title: "Weight", value: $setEntry.weight, field: .weight)

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(FitTheme.textSecondary)
                        .font(FitFont.body(size: 16))
                }
            }
        }
        .padding(12)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(FitTheme.cardStroke.opacity(0.5), lineWidth: 1)
        )
    }

    private func setField(
        title: String,
        value: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(FitFont.body(size: 10))
                .foregroundColor(FitTheme.textSecondary)
            TextField("0", text: value)
                .keyboardType(field == .reps ? .numberPad : .decimalPad)
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
}

private struct WorkoutPlanCard: View {
    let title: String
    let subtitle: String
    let detail: String
    let onPreview: () -> Void
    let onStart: () -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onPreview) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
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

private struct WorkoutTemplatePreviewSheet: View {
    let template: WorkoutTemplate
    let exercises: [WorkoutTemplateExercise]
    let isLoading: Bool
    let errorMessage: String?
    let onStart: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.title)
                            .font(FitFont.heading(size: 22))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Workout preview")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(FitFont.body(size: 12, weight: .bold))
                            .foregroundColor(FitTheme.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(FitTheme.cardHighlight)
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 12)

                HStack(spacing: 10) {
                    SummaryPill(title: "Exercises", value: "\(exercises.count)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SummaryPill(title: "Mode", value: template.mode.uppercased())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(FitTheme.accent)
                        Text("Loading preview...")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(FitTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                } else if let errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(FitTheme.cardReminderAccent)
                        Text(errorMessage)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FitTheme.cardReminder)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else if exercises.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 24))
                            .foregroundColor(FitTheme.textSecondary.opacity(0.6))
                        Text("No exercises in this template")
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Edit the template to add exercises.")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(FitTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(exercises) { exercise in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(exercise.name)
                                        .font(FitFont.body(size: 14, weight: .semibold))
                                        .foregroundColor(FitTheme.textPrimary)
                                    Text(exerciseDetail(for: exercise))
                                        .font(FitFont.body(size: 12))
                                        .foregroundColor(FitTheme.textSecondary)
                                    if let notes = exercise.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(FitFont.body(size: 12))
                                            .foregroundColor(FitTheme.textSecondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(FitTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                ActionButton(title: "Start Workout", style: .primary, action: onStart)
                    .frame(maxWidth: .infinity)
                    .disabled(isLoading || exercises.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func exerciseDetail(for exercise: WorkoutTemplateExercise) -> String {
        var parts: [String] = []
        if let sets = exercise.sets, sets > 0 {
            parts.append("\(sets) sets")
        }
        if let reps = exercise.reps, reps > 0 {
            parts.append("\(reps) reps")
        }
        if let rest = exercise.restSeconds, rest > 0 {
            parts.append("Rest \(rest)s")
        }
        if parts.isEmpty {
            parts.append("Details unavailable")
        }
        if let muscle = exercise.muscleGroups.first, !muscle.isEmpty {
            parts.append(muscle)
        }
        if let equipment = exercise.equipment.first, !equipment.isEmpty {
            parts.append(equipment)
        }
        return parts.joined(separator: " · ")
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
                .tint(FitTheme.textPrimary)
                Stepper(value: $exercise.reps, in: 1...20) {
                    Text("Reps \(exercise.reps)")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                .tint(FitTheme.textPrimary)
            }

            Stepper(value: $exercise.restSeconds, in: 30...240, step: 15) {
                Text("Rest \(exercise.restSeconds)s")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .tint(FitTheme.textPrimary)
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

private struct WorkoutGeneratingCard: View {
    @State private var animationPhase = 0
    @State private var iconScale: CGFloat = 1.0
    
    private let loadingMessages = [
        "Analyzing your preferences...",
        "Building your workout...",
        "Selecting exercises...",
        "Optimizing for your goals...",
        "Almost ready..."
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(FitTheme.cardWorkoutAccent.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .scaleEffect(iconScale)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(FitTheme.cardWorkoutAccent)
                    .scaleEffect(iconScale)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    iconScale = 1.15
                }
            }
            
            VStack(spacing: 8) {
                Text("Generating Your Workout")
                    .font(FitFont.heading(size: 20))
                    .foregroundColor(FitTheme.textPrimary)
                
                Text(loadingMessages[animationPhase % loadingMessages.count])
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                    .animation(.easeInOut(duration: 0.3), value: animationPhase)
            }
            
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index <= animationPhase % 5 ? FitTheme.cardWorkoutAccent : FitTheme.cardWorkoutAccent.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2).delay(Double(index) * 0.1), value: animationPhase)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(FitTheme.cardWorkout)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardWorkoutAccent.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: FitTheme.cardWorkoutAccent.opacity(0.15), radius: 18, x: 0, y: 10)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                withAnimation {
                    animationPhase += 1
                }
            }
        }
    }
}

private struct WorkoutCard<Content: View>: View {
    var isAccented: Bool = false
    @ViewBuilder let content: Content
    
    init(isAccented: Bool = false, @ViewBuilder content: () -> Content) {
        self.isAccented = isAccented
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isAccented ? FitTheme.cardWorkout : FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isAccented ? FitTheme.cardWorkoutAccent.opacity(0.3) : FitTheme.cardStroke.opacity(0.6), lineWidth: isAccented ? 1.5 : 1)
            )
            .shadow(color: isAccented ? FitTheme.cardWorkoutAccent.opacity(0.15) : FitTheme.shadow, radius: 18, x: 0, y: 10)
    }
}

private struct WorkoutCoachPickPill: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text("COACHES PICK")
                .font(FitFont.body(size: 10, weight: .bold))
                .tracking(0.6)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [FitTheme.cardCoachAccent, FitTheme.cardCoachAccent.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: FitTheme.cardCoachAccent.opacity(0.25), radius: 6, x: 0, y: 4)
    }
}

private enum MuscleGroup: String, CaseIterable, Identifiable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case arms
    case quads
    case hamstrings
    case glutes
    case calves
    case core
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
    let id: UUID
    let sessionId: String?
    let title: String
    let exercises: [WorkoutExerciseSession]
    
    // Explicit initializer - prevents memberwise initializer and Codable synthesis
    init(sessionId: String?, title: String, exercises: [WorkoutExerciseSession]) {
        self.id = UUID()
        self.sessionId = sessionId
        self.title = title
        self.exercises = exercises
    }
}

#Preview {
    WorkoutView(userId: "demo-user")
}
