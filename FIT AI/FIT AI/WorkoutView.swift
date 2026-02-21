import Foundation
import SwiftUI

struct WorkoutView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case generate = "Generate"
        case saved = "Saved"
        case create = "Create"

        var id: String { rawValue }
    }

    private enum SwapDestination {
        case generate
        case create
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
    @State private var showSwapGeneratePlanSheet = false
    @State private var pendingSwapDestination: SwapDestination?
    @State private var workoutBuilderScrollTrigger = 0
    @State private var spotlightCreateBuilder = false
    @State private var showSplitEditorSheet = false
    @State private var showWorkoutWelcome = false
    @State private var hasSplitPreferences = false
    @State private var todaysWorkout: WorkoutCompletion?
    @State private var showRecoveryAlert = false
    @State private var recoveryInfo: (title: String, exerciseCount: Int, elapsed: Int, savedAt: Date)?
    @State private var coachPickTemplateId: String?
    @State private var coachPickTitle: String?
    @State private var coachPickExercises: [WorkoutExerciseSession] = []
    @State private var splitSnapshot = SplitSnapshot()
    @State private var splitPlanExerciseCache: [String: [String]] = [:]
    @State private var splitGenerationTask: Task<Void, Never>?
    @State private var isGeneratingSplitWorkouts = false
    @State private var todaysTrainingSnapshot: TodayTrainingSnapshot?
    @State private var isTodaysTrainingExpanded = false
    @State private var selectedWeeklyDay: WeeklyDayDetail?
    @State private var weekOffset: Int = 0

    let userId: String
    @EnvironmentObject private var guidedTour: GuidedTourCoordinator

    init(userId: String, intent: Binding<WorkoutTabIntent?> = .constant(nil)) {
        self.userId = userId
        _intent = intent
    }

    var body: some View {
        let base = AnyView(
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            WorkoutStreakBadge(goalOverride: splitSnapshot.daysPerWeek, goalLabel: "session")

                            weeklySplitHeader
                                .tourTarget(.workoutWeeklySplit)
                                .id(GuidedTourTargetID.workoutWeeklySplit)
                            workoutBuilderSection
                                .tourTarget(.workoutBuilder)
                                .id(GuidedTourTargetID.workoutBuilder)

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
                    .onChange(of: workoutBuilderScrollTrigger) { _ in
                        DispatchQueue.main.async {
                            withAnimation(MotionTokens.springSoft) {
                                proxy.scrollTo(GuidedTourTargetID.workoutBuilder, anchor: .center)
                            }
                        }
                    }
                }

                if isGenerating {
                    WorkoutGeneratingFullscreenOverlay()
                        .zIndex(10)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 1.02)),
                                removal: .opacity
                            )
                        )
                }
            }
        )

        let lifecycle = AnyView(
            base
                .task {
                    await loadWorkouts()
                    todaysWorkout = WorkoutCompletionStore.todaysCompletion()
                    todaysTrainingSnapshot = TodayTrainingStore.todaysTraining()
                    refreshSplitSnapshot()
                    await preloadSplitPlanExerciseNamesIfNeeded()
                    
                    // Check for recoverable workout session
                    if WorkoutSessionStore.hasRecoverableSession() {
                        recoveryInfo = WorkoutSessionStore.getRecoveryInfo()
                        showRecoveryAlert = true
                    }
                }
                .onAppear {
                    Task {
                        await loadWorkouts()
                        await preloadSplitPlanExerciseNamesIfNeeded()
                    }
                    todaysTrainingSnapshot = TodayTrainingStore.todaysTraining()
                    refreshSplitSnapshot()
                }
                .onReceive(NotificationCenter.default.publisher(for: .fitAIWorkoutCompleted)) { notification in
                    if let completion = notification.userInfo?["completion"] as? WorkoutCompletion {
                        todaysWorkout = completion
                    } else {
                        todaysWorkout = WorkoutCompletionStore.todaysCompletion()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .fitAITodayTrainingUpdated)) { _ in
                    todaysTrainingSnapshot = TodayTrainingStore.todaysTraining()
                }
                .onReceive(NotificationCenter.default.publisher(for: .fitAISplitUpdated)) { _ in
                    refreshSplitSnapshot()
                    Task {
                        await preloadSplitPlanExerciseNamesIfNeeded()
                    }
                }
                .onDisappear {
                    splitGenerationTask?.cancel()
                    splitGenerationTask = nil
                }
        )

        let withModals = AnyView(
            lifecycle
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
                .sheet(isPresented: $showSwapGeneratePlanSheet) {
                    WorkoutTunePlanSheet(
                        selectedMuscleGroups: $selectedMuscleGroups,
                        selectedEquipment: $selectedEquipment,
                        selectedDurationMinutes: $selectedDurationMinutes,
                        onGenerate: {
                            await generateWorkout()
                        }
                    )
                    .presentationDetents([.large])
                }
                .fullScreenCover(isPresented: $showSplitEditorSheet) {
                    SplitSetupFlowView(
                        currentMode: splitSnapshot.mode,
                        currentDaysPerWeek: splitSnapshot.daysPerWeek,
                        currentTrainingDays: splitSnapshot.trainingDays,
                        currentSplitType: splitSnapshot.splitType,
                        currentDayPlans: splitSnapshot.dayPlans,
                        currentFocus: splitSnapshot.focus,
                        templates: visibleTemplates,
                        isEditing: hasSplitPreferences,
                        onSave: { mode, daysPerWeek, trainingDays, splitType, dayPlans, focus in
                            applySplitPreferences(
                                mode: mode,
                                daysPerWeek: daysPerWeek,
                                trainingDays: trainingDays,
                                splitType: splitType,
                                dayPlans: dayPlans,
                                focus: focus
                            )
                        }
                    )
                }
                .fullScreenCover(isPresented: $showWorkoutWelcome) {
                    WorkoutWelcomeView(
                        onGetStarted: {
                            showWorkoutWelcome = false
                            UserDefaults.standard.set(true, forKey: hasSeenWorkoutWelcomeKey)
                            // Small delay to allow modal to dismiss before showing split editor
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showSplitEditorSheet = true
                            }
                        },
                        onDismiss: {
                            showWorkoutWelcome = false
                            UserDefaults.standard.set(true, forKey: hasSeenWorkoutWelcomeKey)
                        }
                    )
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
                        onGenerate: {
                            pendingSwapDestination = .generate
                            isSwapSheetPresented = false
                        },
                        onCreate: {
                            pendingSwapDestination = .create
                            isSwapSheetPresented = false
                        },
                        onClose: { isSwapSheetPresented = false }
                    )
                }
        )

        return AnyView(
            withModals
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
                .onChange(of: isSwapSheetPresented) { isPresented in
                    guard !isPresented else { return }
                    guard let destination = pendingSwapDestination else { return }
                    pendingSwapDestination = nil
                    routeFromSwap(destination)
                }
        )
    }

    private func scrollToGuidedTourTarget(using proxy: ScrollViewProxy) {
        guard let step = guidedTour.currentStep else { return }
        guard step.screen == .workout else { return }
        guard let target = step.target else { return }

        let anchor: UnitPoint
        switch target {
        case .workoutWeeklySplit:
            anchor = .top
        case .workoutBuilder:
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

    private func routeFromSwap(_ destination: SwapDestination) {
        switch destination {
        case .generate:
            withAnimation(MotionTokens.springSoft) {
                mode = .generate
            }
            workoutBuilderScrollTrigger += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showSwapGeneratePlanSheet = true
            }
        case .create:
            withAnimation(MotionTokens.springSoft) {
                mode = .create
            }
            workoutBuilderScrollTrigger += 1
            spotlightCreateBuilder = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.35)) {
                    spotlightCreateBuilder = false
                }
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

                Button(action: { guidedTour.startScreenTour(.workout) }) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(FitTheme.cardHighlight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                if hasSplitPreferences {
                    Button(action: { showSplitEditorSheet = true }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(FitTheme.cardHighlight)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { showSplitEditorSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Set up")
                                .font(FitFont.body(size: 12, weight: .semibold))
                        }
                        .foregroundColor(FitTheme.buttonText)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(FitTheme.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if hasSplitPreferences {
                weeklySplitWeekView
                if isGeneratingSplitWorkouts {
                    Text("Generating your weekly workouts...")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            } else {
                weeklySplitSetupCard
            }
        }
        .padding(.top, 4)
    }

    private var weeklySplitWeekView: some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                let plannedColor = FitTheme.cardWorkoutAccent
                ForEach(Array(weekDates.enumerated()), id: \.element) { _, date in
                    let label = splitLabel(for: date)
                    let status = weeklyDayStatus(for: date)
                    let dayNumber = Calendar.current.component(.day, from: date)
                    let detailId = dateKey(for: date)
                    let isSelected = selectedWeeklyDay?.id == detailId
                        || (selectedWeeklyDay == nil && Calendar.current.isDateInToday(date))
                    WeeklySplitDayCell(
                        daySymbol: shortWeekdaySymbol(for: date),
                        dayNumber: dayNumber,
                        status: status,
                        isSelected: isSelected,
                        isTrainingDay: label != nil,
                        accentColor: plannedColor,
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

        }
        .frame(maxWidth: .infinity)
    }

    private var weeklySplitSetupCard: some View {
        WorkoutCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(FitTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set up weekly split")
                            .font(FitFont.heading(size: 18))
                            .foregroundColor(FitTheme.textPrimary)
                        Text("Answer a few questions to plan your workouts.")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    Spacer()
                }

                ActionButton(title: "Set up", style: .primary) {
                    showSplitEditorSheet = true
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
                        .disabled(isGenerating)
                    }
                }
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
                        SummaryPill(title: "Total", value: "\(visibleTemplates.count)")
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
            if spotlightCreateBuilder {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Create builder ready")
                        .font(FitFont.body(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(FitTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(FitTheme.accentSoft.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            WorkoutCard(isAccented: spotlightCreateBuilder) {
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

                    BuilderStepHeader(step: 3, title: "Start workout", subtitle: "Start now, save later if you want.")
                    ActionButton(title: "Start Workout", style: .primary) {
                        Task {
                            await startDraftSession()
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Divider().background(FitTheme.cardStroke)

                    BuilderStepHeader(step: 4, title: "Save template", subtitle: "Save it for next time.")
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
            return visibleTemplates
        }
        return visibleTemplates.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var visibleTemplates: [WorkoutTemplate] {
        templates.filter { $0.mode != splitGeneratedTemplateMode }
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
        if let snapshot = todaysTrainingSnapshot, !snapshot.exercises.isEmpty {
            return Array(snapshot.exercises.prefix(3))
        }
        let names = spotlightExercises.map { $0.name }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Array(names.prefix(3))
    }

    @ViewBuilder
    private var todaysTrainingCard: some View {
        let selectedDate = selectedWeeklyDay?.date ?? Date()
        let selectedDay = weeklyDayDetail(for: selectedDate)
        let label = splitLabel(for: selectedDate)
        let isTrainingDay = selectedDay.isTrainingDay
        let isViewingToday = Calendar.current.isDateInToday(selectedDate)
        let daySnapshot = isViewingToday ? todaysTrainingSnapshot : nil
        let hasOverrideTraining = daySnapshot != nil

        if hasSplitPreferences && !isTrainingDay && !hasOverrideTraining {
            noTrainingCard(for: selectedDate)
        } else {
            let completion = workoutCompletion(for: selectedDate)
            let isCompleted = completion != nil
            let snapshotIsCoach = daySnapshot?.source == .coach
            let snapshotTemplateMatchesCoach = daySnapshot?.templateId == coachPickTemplateId
            let completionMatchesCoach = completionMatchesCoachPick(completion)
            let isCoachPick = snapshotIsCoach && (snapshotTemplateMatchesCoach || completionMatchesCoach)
            let snapshotTitle = daySnapshot?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleText = snapshotTitle?.isEmpty == false ? snapshotTitle : nil
            let splitTitle = selectedDay.workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = Calendar.current.isDateInToday(selectedDate)
                ? "Today's Training"
                : "\(weekdayDisplayName(for: selectedDate)) Training"
            let baseNonCoachTitle = splitTitle.isEmpty ? (titleText ?? fallbackTitle) : splitTitle
            let nonCoachTitle = baseNonCoachTitle.lowercased().contains("workout")
                ? baseNonCoachTitle
                : "\(baseNonCoachTitle) Workout"
            let cleanedCoachTitle = (titleText ?? fallbackTitle)
                .replacingOccurrences(of: "Coach's Pick: ", with: "")
                .replacingOccurrences(of: "Coaches Pick: ", with: "")
            let displayTitle = isCoachPick ? cleanedCoachTitle : nonCoachTitle
            let subtitle = isCoachPick
                ? "Coaches Pick"
                : trainingCardSubtitle(for: selectedDate, detail: selectedDay, fallbackLabel: label)
            let statusText = isCompleted ? "Completed" : (isCoachPick ? "" : subtitle)

            let displayList: [String] = {
                if let completion, !completion.exercises.isEmpty {
                    return completion.exercises
                }
                if let snapshot = daySnapshot, !snapshot.exercises.isEmpty {
                    return snapshot.exercises
                }
                let planned = plannedExerciseNames(for: selectedDate)
                if !planned.isEmpty {
                    return planned
                }
                if isViewingToday {
                    return trainingPreviewExercises
                }
                return [selectedDay.workoutName]
            }()
            let previewList = isTodaysTrainingExpanded ? displayList : Array(displayList.prefix(2))
            let estimatedMinutes = selectedDay.estimatedMinutes > 0
                ? selectedDay.estimatedMinutes
                : selectedDurationMinutes

            WorkoutCard(isAccented: true) {
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
                                    Text("~\(estimatedMinutes) min")
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

                        if !isTodaysTrainingExpanded && displayList.count > previewList.count {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isTodaysTrainingExpanded = true
                                }
                            } label: {
                                Text("+\(displayList.count - previewList.count) more exercises")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.cardWorkoutAccent)
                            }
                            .buttonStyle(.plain)
                        } else if isTodaysTrainingExpanded && displayList.count > 2 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isTodaysTrainingExpanded = false
                                }
                            } label: {
                                Text("Show less")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !isCompleted {
                        HStack(spacing: 12) {
                            ActionButton(title: "Start Workout", style: .primary) {
                                Task {
                                    await startWeeklySplitSession(for: selectedDate)
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
    }

    private func noTrainingCard(for date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let nextDetail = nextTrainingDayDetail(after: date)
        return WorkoutCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "zzz")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                    Text(isToday ? "No training today" : "No training on \(weekdayDisplayName(for: date))")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                }

                if let nextDetail {
                    Text("Next training: \(nextDetail.dayName) — \(nextDetail.workoutName)")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                } else {
                    Text("Next training scheduled soon.")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
        }
    }

    private let splitPreferencesKey = "fitai.onboarding.split.preferences"
    private let onboardingFormKey = "fitai.onboarding.form"
    private let hasSeenWorkoutWelcomeKey = "fitai.workout.hasSeenWelcome"
    private let splitGeneratedTemplateMode = "split_ai"

    private var weekDates: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        let today = Date()
        let baseWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let weekStart = calendar.date(byAdding: .day, value: weekOffset * 7, to: baseWeekStart) ?? baseWeekStart
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var splitDayRows: [String] {
        defaultSplitDayNames(for: splitSnapshot.daysPerWeek, splitType: splitSnapshot.splitType)
    }

    private var weekRangeLabel: String {
        guard let start = weekDates.first, let end = weekDates.last else { return "This Week" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func nextTrainingDayDetail(after date: Date) -> (dayName: String, workoutName: String)? {
        let calendar = Calendar.current
        let symbols = calendar.weekdaySymbols
        for offset in 1...14 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            guard let label = splitLabel(for: candidate) else { continue }
            let plan = planForDate(candidate)
            let workoutName = plannedWorkoutName(plan: plan, fallback: label)
            let index = max(0, min(symbols.count - 1, calendar.component(.weekday, from: candidate) - 1))
            let dayName = symbols[index]
            return (dayName, workoutName)
        }
        return nil
    }

    private func workoutCompletion(for date: Date) -> WorkoutCompletion? {
        if Calendar.current.isDateInToday(date) {
            return todaysWorkout ?? WorkoutCompletionStore.completion(on: date)
        }
        return WorkoutCompletionStore.completion(on: date)
    }

    private func trainingCardSubtitle(
        for date: Date,
        detail: WeeklyDayDetail,
        fallbackLabel: String?
    ) -> String {
        if Calendar.current.isDateInToday(date) {
            return fallbackLabel ?? "Today's Training"
        }
        switch detail.status {
        case .completed:
            return "Completed"
        case .today:
            return "Today"
        case .upcoming:
            return weekdayDisplayName(for: date)
        case .rest:
            return "Rest"
        }
    }

    private func plannedExerciseNames(for date: Date) -> [String] {
        guard let plan = planForDate(date) else { return [] }

        let resolvedNames = resolvedExerciseNames(for: plan)
        if !resolvedNames.isEmpty {
            return resolvedNames
        }

        if let customExercises = plan.customExercises, !customExercises.isEmpty {
            return customExercises
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if let title = cleanedPlanText(plan.templateTitle, source: plan.source) {
            return [title]
        }

        if let focus = cleanedPlanText(plan.focus, source: plan.source) {
            return [focus]
        }

        return []
    }

    private func resolvedExerciseNames(for plan: SplitDayPlan) -> [String] {
        if let stored = plan.exerciseNames {
            let normalized = normalizedExerciseNames(stored)
            if !normalized.isEmpty {
                return normalized
            }
        }

        if let templateId = plan.templateId,
           let cached = splitPlanExerciseCache[templateId] {
            let normalized = normalizedExerciseNames(cached)
            if !normalized.isEmpty {
                return normalized
            }
        }

        return []
    }

    private func weekdayDisplayName(for date: Date) -> String {
        let calendar = Calendar.current
        let symbols = calendar.weekdaySymbols
        let index = max(0, min(symbols.count - 1, calendar.component(.weekday, from: date) - 1))
        return symbols[index]
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

    private func completionMatchesCoachPick(_ completion: WorkoutCompletion?) -> Bool {
        guard let completion, !completion.exercises.isEmpty, !coachPickExercises.isEmpty else { return false }
        let completed = Set(completion.exercises.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let coach = Set(coachPickExercises.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        guard !completed.isEmpty, !coach.isEmpty else { return false }
        let overlap = completed.intersection(coach).count
        let ratio = Double(overlap) / Double(completed.count)
        return overlap >= 2 && ratio >= 0.5
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
        let plan = planForDate(date)
        let label = splitLabel(for: date)
        let status = weeklyDayStatus(for: date)
        let isTrainingDay = label != nil
        let estimatedMinutes = plan?.durationMinutes ?? (isTrainingDay ? max(30, selectedDurationMinutes) : 0)
        let workoutName = plannedWorkoutName(plan: plan, fallback: label ?? "Rest")
        let focus = plannedFocus(plan: plan) ?? label ?? splitSnapshot.focus
        return WeeklyDayDetail(
            id: dateKey(for: date),
            date: date,
            workoutName: workoutName,
            focus: focus,
            estimatedMinutes: estimatedMinutes,
            status: status,
            isTrainingDay: isTrainingDay
        )
    }

    private func planForDate(_ date: Date) -> SplitDayPlan? {
        let weekday = weekdaySymbol(for: date)
        return splitSnapshot.dayPlans[weekday]
    }

    private func plannedWorkoutName(plan: SplitDayPlan?, fallback: String) -> String {
        guard let plan else { return fallback }
        if let title = cleanedPlanText(plan.templateTitle, source: plan.source) {
            return title
        }
        if let focus = cleanedPlanText(plan.focus, source: plan.source) {
            return focus
        }
        if plan.source == .ai, fallback != "Rest" {
            return fallback
        }
        switch plan.source {
        case .saved:
            return "Saved workout"
        case .create:
            return "Custom workout"
        case .ai:
            return "AI workout"
        }
    }

    private func plannedFocus(plan: SplitDayPlan?) -> String? {
        guard let plan else { return nil }
        return cleanedPlanText(plan.focus, source: plan.source)
    }

    private func cleanedPlanText(_ text: String?, source: SplitPlanSource) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if source == .ai, trimmed.caseInsensitiveCompare("AI workout") == .orderedSame {
            return nil
        }
        return trimmed
    }

    private func startWeeklySplitSession(for date: Date) async {
        let trainingLabel = splitLabel(for: date)
        let fallbackTitle = trainingLabel ?? "Today's Training"
        if let plan = planForDate(date) {
            switch plan.source {
            case .saved:
                if let templateId = plan.templateId {
                    _ = await startSessionFromTemplateId(
                        templateId,
                        titleOverride: plannedWorkoutName(plan: plan, fallback: fallbackTitle)
                    )
                    return
                }
            case .ai:
                if let templateId = plan.templateId {
                    let startedFromTemplate = await startSessionFromTemplateId(
                        templateId,
                        titleOverride: plannedWorkoutName(plan: plan, fallback: fallbackTitle)
                    )
                    if startedFromTemplate {
                        return
                    }
                }
                await startGeneratedPlan(plan, fallbackTitle: fallbackTitle)
                return
            case .create:
                if let customExercises = plan.customExercises, !customExercises.isEmpty {
                    let exercises = sessionExercises(from: customExercises)
                    let title = plannedWorkoutName(plan: plan, fallback: fallbackTitle)
                    await startSession(title: title, templateId: nil, exercises: exercises)
                    return
                }
                await MainActor.run {
                    mode = .create
                    draftName = plannedFocus(plan: plan) ?? fallbackTitle
                }
                return
            }
        }

        if let trainingLabel {
            let inferredMuscles = muscleGroupsForSplitLabel(trainingLabel)
            let inferredPlan = SplitDayPlan(
                weekday: weekdaySymbol(for: date),
                focus: trainingLabel,
                source: .ai,
                muscleGroups: inferredMuscles,
                equipment: [],
                durationMinutes: selectedDurationMinutes,
                customExercises: nil
            )
            await startGeneratedPlan(inferredPlan, fallbackTitle: fallbackTitle)
            return
        }

        let title = fallbackTitle
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

    private func startGeneratedPlan(_ plan: SplitDayPlan, fallbackTitle: String) async {
        let resolvedMuscleGroups = resolvedAIMuscleGroups(plan: plan, fallbackTitle: fallbackTitle)
        await MainActor.run {
            mode = .generate
            selectedMuscleGroups = Set(resolvedMuscleGroups)
            if !plan.equipment.isEmpty {
                selectedEquipment = Set(plan.equipment)
            }
            if let duration = plan.durationMinutes {
                selectedDurationMinutes = duration
            }
        }

        await generateWorkout()

        let (exercises, generatedTitleValue) = await MainActor.run {
            (generatedExercises, generatedTitle)
        }

        guard !exercises.isEmpty else { return }
        let title = plannedWorkoutName(plan: plan, fallback: generatedTitleValue.isEmpty ? fallbackTitle : generatedTitleValue)
        await startSession(title: title, templateId: nil, exercises: exercises)
    }

    private func resolvedAIMuscleGroups(plan: SplitDayPlan?, fallbackTitle: String) -> [String] {
        let explicit = normalizedUniqueStrings(plan?.muscleGroups ?? [])
        if !explicit.isEmpty {
            var expanded: [String] = []
            for value in explicit {
                let inferred = muscleGroupsForSplitLabel(value)
                if inferred.isEmpty {
                    expanded.append(value)
                } else {
                    expanded.append(contentsOf: inferred)
                }
            }
            let normalizedExpanded = normalizedUniqueStrings(expanded)
            if !normalizedExpanded.isEmpty {
                return normalizedExpanded
            }
        }

        let focusCandidates = [
            plan?.focus,
            plan?.templateTitle,
            fallbackTitle
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in focusCandidates {
            let inferred = muscleGroupsForSplitLabel(candidate)
            if !inferred.isEmpty {
                return inferred
            }
        }

        return defaultFullBodyMuscleGroups()
    }

    private func muscleGroupsForSplitLabel(_ label: String) -> [String] {
        let normalized = label.lowercased()
        var groups = Set<MuscleGroup>()

        func add(_ values: [MuscleGroup]) {
            for value in values {
                groups.insert(value)
            }
        }

        if normalized.contains("full body") {
            add(defaultFullBodyGroupCases())
        }
        if normalized.contains("push") {
            add([.chest, .shoulders, .triceps])
        }
        if normalized.contains("pull") {
            add([.back, .biceps, .forearms])
        }
        if normalized.contains("upper") {
            add([.chest, .back, .shoulders, .biceps, .triceps])
        }
        if normalized.contains("lower") || normalized.contains("leg") {
            add([.quads, .hamstrings, .glutes, .calves])
        }

        if normalized.contains("chest") {
            add([.chest])
        }
        if normalized.contains("back") {
            add([.back])
        }
        if normalized.contains("shoulder") || normalized.contains("delt") {
            add([.shoulders])
        }
        if normalized.contains("arm") {
            add([.arms, .biceps, .triceps, .forearms])
        }
        if normalized.contains("bicep") {
            add([.biceps])
        }
        if normalized.contains("tricep") {
            add([.triceps])
        }
        if normalized.contains("quad") {
            add([.quads])
        }
        if normalized.contains("hamstring") {
            add([.hamstrings])
        }
        if normalized.contains("glute") {
            add([.glutes])
        }
        if normalized.contains("calf") {
            add([.calves])
        }
        if normalized.contains("core") || normalized.contains("ab") {
            add([.core])
        }

        guard !groups.isEmpty else { return [] }
        return MuscleGroup.allCases
            .filter { groups.contains($0) }
            .map(\.rawValue)
    }

    private func defaultFullBodyGroupCases() -> [MuscleGroup] {
        [.chest, .back, .shoulders, .arms, .quads, .hamstrings, .glutes, .core]
    }

    private func defaultFullBodyMuscleGroups() -> [String] {
        defaultFullBodyGroupCases().map(\.rawValue)
    }

    private func normalizedUniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }

        return result
    }

    private func normalizedExerciseNames(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                names.append(trimmed)
            }
        }
        return names
    }

    @discardableResult
    private func startSessionFromTemplateId(_ templateId: String, titleOverride: String?) async -> Bool {
        guard !userId.isEmpty else {
            await MainActor.run {
                loadError = "Missing user session. Please log in again."
                Haptics.error()
            }
            return false
        }

        await MainActor.run {
            isLoading = true
        }

        do {
            let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: templateId)
            let exercises = sessionExercises(from: detail.exercises)
            let title = {
                let trimmed = titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? detail.template.title : trimmed
            }()
            await MainActor.run {
                isLoading = false
            }
            await startSession(title: title, templateId: templateId, exercises: exercises)
            return true
        } catch {
            await MainActor.run {
                isLoading = false
                loadError = "Unable to start workout. \(error.localizedDescription)"
                Haptics.error()
            }
            return false
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

    private func refreshSplitSnapshot(scheduleGeneration: Bool = true) {
        let loaded = SplitSchedule.loadSnapshot()
        splitSnapshot = loaded.snapshot
        hasSplitPreferences = loaded.hasPreferences
        
        // Show welcome modal if user hasn't seen it and doesn't have split preferences
        let hasSeenWelcome = UserDefaults.standard.bool(forKey: hasSeenWorkoutWelcomeKey)
        if !hasSeenWelcome && !loaded.hasPreferences {
            showWorkoutWelcome = true
        }

        if scheduleGeneration {
            scheduleSplitPlanGenerationIfNeeded(snapshot: loaded.snapshot, hasPreferences: loaded.hasPreferences)
        }

        Task {
            await preloadSplitPlanExerciseNamesIfNeeded()
        }
    }

    private func scheduleSplitPlanGenerationIfNeeded(snapshot: SplitSnapshot, hasPreferences: Bool) {
        guard hasPreferences else {
            splitGenerationTask?.cancel()
            splitGenerationTask = nil
            isGeneratingSplitWorkouts = false
            return
        }

        let trainingDays = normalizedTrainingDays(snapshot.trainingDays, targetCount: snapshot.daysPerWeek)
        let normalizedPlans = preparedSplitDayPlans(
            mode: snapshot.mode,
            daysPerWeek: snapshot.daysPerWeek,
            trainingDays: trainingDays,
            splitType: snapshot.splitType,
            dayPlans: snapshot.dayPlans,
            focus: snapshot.focus
        )
        scheduleSplitPlanGeneration(for: normalizedPlans, trainingDays: trainingDays)
    }

    private func applySplitPreferences(
        mode: SplitCreationMode,
        daysPerWeek: Int,
        trainingDays: [String],
        splitType: SplitType,
        dayPlans: [String: SplitDayPlan],
        focus: String
    ) {
        let clampedDays = min(max(daysPerWeek, 2), 7)
        let normalizedDays = normalizedTrainingDays(trainingDays, targetCount: clampedDays)
        let normalizedPlans = preparedSplitDayPlans(
            mode: mode,
            daysPerWeek: clampedDays,
            trainingDays: normalizedDays,
            splitType: splitType,
            dayPlans: dayPlans,
            focus: focus
        )
        let preferences = SplitSetupPreferences(
            mode: mode.rawValue,
            daysPerWeek: clampedDays,
            trainingDays: normalizedDays,
            splitType: splitType,
            dayPlans: normalizedPlans,
            focus: focus,
            isUserConfigured: true
        )
        saveSplitPreferences(preferences)

        if let data = UserDefaults.standard.data(forKey: onboardingFormKey),
           var form = try? JSONDecoder().decode(OnboardingForm.self, from: data) {
            form.workoutDaysPerWeek = clampedDays
            form.trainingDaysOfWeek = normalizedDays
            if let encodedForm = try? JSONEncoder().encode(form) {
                UserDefaults.standard.set(encodedForm, forKey: onboardingFormKey)
            }
        }

        refreshSplitSnapshot()
        hasSplitPreferences = true
        selectedWeeklyDay = nil

        PostHogAnalytics.featureUsed(
            .splitSetup,
            action: "save",
            properties: [
                "mode": mode.rawValue,
                "days_per_week": clampedDays,
                "split_type": splitType.rawValue,
                "has_focus": !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ]
        )
    }

    private func preparedSplitDayPlans(
        mode: SplitCreationMode,
        daysPerWeek: Int,
        trainingDays: [String],
        splitType: SplitType,
        dayPlans: [String: SplitDayPlan],
        focus: String
    ) -> [String: SplitDayPlan] {
        let validWeekdays = Set(Calendar.current.weekdaySymbols)
        let selectedDays = Set(trainingDays)
        let filteredPlans = dayPlans.filter { validWeekdays.contains($0.key) && selectedDays.contains($0.key) }

        if mode != .ai {
            return filteredPlans.mapValues { plan in
                var updated = plan
                if plan.source == .create {
                    let names = normalizedExerciseNames((plan.customExercises ?? []).map(\.name))
                    updated.exerciseNames = names.isEmpty ? nil : names
                }
                return updated
            }
        }

        let fallbackFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Strength"
            : focus.trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = defaultSplitDayNames(for: daysPerWeek, splitType: splitType)
        var aiPlans: [String: SplitDayPlan] = [:]

        for (index, day) in trainingDays.enumerated() {
            let label = index < labels.count ? labels[index] : fallbackFocus
            let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackFocus : label

            if var existing = filteredPlans[day],
               existing.source == .ai,
               let existingTemplateId = existing.templateId,
               !existingTemplateId.isEmpty {
                let existingFocus = existing.focus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if existingFocus == cleanLabel.lowercased() {
                    if existing.muscleGroups.isEmpty {
                        existing.muscleGroups = resolvedAIMuscleGroups(plan: existing, fallbackTitle: cleanLabel)
                    }
                    if existing.durationMinutes == nil {
                        existing.durationMinutes = 45
                    }
                    aiPlans[day] = existing
                    continue
                }
            }

            aiPlans[day] = SplitDayPlan(
                weekday: day,
                focus: cleanLabel,
                source: .ai,
                templateId: nil,
                templateTitle: nil,
                muscleGroups: resolvedAIMuscleGroups(plan: nil, fallbackTitle: cleanLabel),
                equipment: [],
                durationMinutes: 45,
                customExercises: nil,
                exerciseNames: nil
            )
        }

        return aiPlans
    }

    private func scheduleSplitPlanGeneration(for plans: [String: SplitDayPlan], trainingDays: [String]) {
        splitGenerationTask?.cancel()
        splitGenerationTask = nil

        let hasWork = trainingDays.contains { day in
            guard let plan = plans[day] else { return false }
            switch plan.source {
            case .ai:
                if let templateId = plan.templateId, !templateId.isEmpty {
                    return (plan.exerciseNames ?? []).isEmpty
                }
                return true
            case .saved:
                guard let templateId = plan.templateId, !templateId.isEmpty else { return false }
                return (plan.exerciseNames ?? []).isEmpty
            case .create:
                return (plan.exerciseNames ?? []).isEmpty
            }
        }

        guard hasWork else {
            isGeneratingSplitWorkouts = false
            return
        }

        splitGenerationTask = Task {
            await MainActor.run {
                isGeneratingSplitWorkouts = true
            }

            var updatedPlans = plans
            var didUpdate = false
            var firstError: String?

            for day in trainingDays {
                if Task.isCancelled {
                    await MainActor.run {
                        isGeneratingSplitWorkouts = false
                    }
                    return
                }
                guard let plan = updatedPlans[day] else { continue }
                let fallback = plan.focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Training"
                    : plan.focus
                do {
                    let resolved = try await resolveSplitPlanForPersistence(plan, fallbackTitle: fallback)
                    updatedPlans[day] = resolved
                    didUpdate = true
                } catch {
                    if firstError == nil {
                        firstError = error.localizedDescription
                    }
                }
            }

            if Task.isCancelled {
                await MainActor.run {
                    isGeneratingSplitWorkouts = false
                }
                return
            }

            if didUpdate {
                await MainActor.run {
                    persistUpdatedSplitPlans(updatedPlans, trainingDays: trainingDays)
                }
                await loadWorkouts()
                await preloadSplitPlanExerciseNamesIfNeeded()
            }

            await MainActor.run {
                isGeneratingSplitWorkouts = false
                if let firstError {
                    loadError = "Some split workouts could not be generated. \(firstError)"
                }
            }
        }
    }

    private func resolveSplitPlanForPersistence(
        _ plan: SplitDayPlan,
        fallbackTitle: String
    ) async throws -> SplitDayPlan {
        switch plan.source {
        case .create:
            var updated = plan
            let names = normalizedExerciseNames((plan.customExercises ?? []).map(\.name))
            updated.exerciseNames = names.isEmpty ? nil : names
            return updated
        case .saved:
            guard let templateId = plan.templateId, !templateId.isEmpty else { return plan }
            if !(plan.exerciseNames ?? []).isEmpty {
                return plan
            }
            let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: templateId)
            let exerciseNames = normalizedExerciseNames(detail.exercises.map(\.name))
            await MainActor.run {
                splitPlanExerciseCache[templateId] = exerciseNames
            }
            var updated = plan
            updated.templateTitle = detail.template.title
            updated.exerciseNames = exerciseNames.isEmpty ? nil : exerciseNames
            return updated
        case .ai:
            if let templateId = plan.templateId, !templateId.isEmpty {
                if !(plan.exerciseNames ?? []).isEmpty {
                    return plan
                }
                let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: templateId)
                let exerciseNames = normalizedExerciseNames(detail.exercises.map(\.name))
                await MainActor.run {
                    splitPlanExerciseCache[templateId] = exerciseNames
                }
                var updated = plan
                updated.templateTitle = detail.template.title
                updated.exerciseNames = exerciseNames.isEmpty ? nil : exerciseNames
                return updated
            }
            return try await generateTemplateForSplitPlan(plan, fallbackTitle: fallbackTitle)
        }
    }

    private func generateTemplateForSplitPlan(
        _ plan: SplitDayPlan,
        fallbackTitle: String
    ) async throws -> SplitDayPlan {
        guard !userId.isEmpty else {
            throw NSError(
                domain: "WorkoutView.SplitGeneration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing user session."]
            )
        }

        let resolvedMuscleGroups = resolvedAIMuscleGroups(plan: plan, fallbackTitle: fallbackTitle)
        let duration = max(20, plan.durationMinutes ?? 45)
        let result = try await WorkoutAPIService.shared.generateWorkout(
            userId: userId,
            muscleGroups: resolvedMuscleGroups,
            workoutType: fallbackTitle,
            equipment: plan.equipment.isEmpty ? nil : plan.equipment,
            durationMinutes: duration
        )
        let parsed = parseGeneratedWorkout(result)
        let fallbackExercises = fallbackSplitExercises(
            muscleGroups: resolvedMuscleGroups,
            durationMinutes: duration
        )
        let generatedExercises = parsed.exercises.isEmpty ? fallbackExercises : parsed.exercises
        let exerciseNames = normalizedExerciseNames(generatedExercises.map(\.name))
        guard !generatedExercises.isEmpty else {
            throw NSError(
                domain: "WorkoutView.SplitGeneration",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Generated split workout had no exercises."]
            )
        }

        let rawTitle = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String
        if rawTitle.isEmpty || rawTitle.caseInsensitiveCompare("AI Generated Workout") == .orderedSame {
            resolvedTitle = fallbackTitle
        } else {
            resolvedTitle = rawTitle
        }

        let inputs = splitTemplateInputs(
            from: generatedExercises,
            muscleGroups: resolvedMuscleGroups,
            equipment: plan.equipment
        )
        let templateId = try await WorkoutAPIService.shared.createTemplate(
            userId: userId,
            title: resolvedTitle,
            description: "Auto-generated for your weekly split",
            mode: splitGeneratedTemplateMode,
            exercises: inputs
        )

        await MainActor.run {
            splitPlanExerciseCache[templateId] = exerciseNames
        }

        var updated = plan
        updated.templateId = templateId
        updated.templateTitle = resolvedTitle
        updated.muscleGroups = resolvedMuscleGroups
        updated.durationMinutes = duration
        updated.exerciseNames = exerciseNames.isEmpty ? nil : exerciseNames
        return updated
    }

    private func fallbackSplitExercises(
        muscleGroups: [String],
        durationMinutes: Int
    ) -> [WorkoutExerciseSession] {
        let groups = muscleGroups.isEmpty ? defaultFullBodyMuscleGroups() : muscleGroups
        let config = durationConfig(for: durationMinutes)
        var exercises: [WorkoutExerciseSession] = []

        for group in groups {
            if let pool = Self.exerciseLibrary[group],
               let seed = pool.compound.first ?? pool.isolation.first {
                exercises.append(makeSessionExercise(from: seed, sets: config.defaultSets))
            }
        }

        if exercises.isEmpty {
            let fallbackSeeds = [
                ExerciseSeed(name: "Bench Press", restSeconds: 90),
                ExerciseSeed(name: "Lat Pulldown", restSeconds: 75),
                ExerciseSeed(name: "Back Squat", restSeconds: 120),
                ExerciseSeed(name: "Overhead Press", restSeconds: 90),
                ExerciseSeed(name: "Romanian Deadlift", restSeconds: 120),
                ExerciseSeed(name: "Cable Crunch", restSeconds: 45)
            ]
            exercises = fallbackSeeds.map { makeSessionExercise(from: $0, sets: config.defaultSets) }
        }

        return exercises
    }

    private func splitTemplateInputs(
        from exercises: [WorkoutExerciseSession],
        muscleGroups: [String],
        equipment: [String]
    ) -> [WorkoutExerciseInput] {
        let resolvedMuscles = muscleGroups.isEmpty ? defaultFullBodyMuscleGroups() : muscleGroups
        return exercises.map { exercise in
            let repsValue = parseRepsValue(from: exercise.sets.first?.reps)
            let notes = exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkoutExerciseInput(
                name: exercise.name,
                muscleGroups: resolvedMuscles,
                equipment: equipment,
                sets: max(exercise.sets.count, 1),
                reps: repsValue,
                restSeconds: normalizedRestSeconds(exercise.restSeconds),
                notes: notes.isEmpty ? nil : notes
            )
        }
    }

    private func parseRepsValue(from text: String?) -> Int {
        guard let text else { return 10 }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 10 }
        if let match = regexMatch(#"(\d+)"#, in: trimmed, captureCount: 1),
           let value = Int(match.captures[0]) {
            return min(max(value, 1), 50)
        }
        return 10
    }

    private func persistUpdatedSplitPlans(_ updatedPlans: [String: SplitDayPlan], trainingDays: [String]) {
        guard var preferences = loadSplitPreferences() else { return }
        let validDays = Set(trainingDays)
        var mergedPlans = (preferences.dayPlans ?? [:]).filter { validDays.contains($0.key) }
        for day in trainingDays {
            if let updated = updatedPlans[day] {
                mergedPlans[day] = updated
            }
        }
        preferences.dayPlans = mergedPlans
        saveSplitPreferences(preferences)
        refreshSplitSnapshot(scheduleGeneration: false)
        hasSplitPreferences = true
        selectedWeeklyDay = nil
        NotificationCenter.default.post(name: .fitAISplitUpdated, object: nil)
    }

    private func loadSplitPreferences() -> SplitSetupPreferences? {
        guard let data = UserDefaults.standard.data(forKey: splitPreferencesKey),
              let decoded = try? JSONDecoder().decode(SplitSetupPreferences.self, from: data) else {
            return nil
        }
        return decoded
    }

    private func saveSplitPreferences(_ preferences: SplitSetupPreferences) {
        if let encoded = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(encoded, forKey: splitPreferencesKey)
        }
    }

    private func preloadSplitPlanExerciseNamesIfNeeded() async {
        guard !userId.isEmpty else { return }
        let plans = await MainActor.run { splitSnapshot.dayPlans }
        let templateIds = Set(plans.values.compactMap { plan -> String? in
            guard let templateId = plan.templateId, !templateId.isEmpty else { return nil }
            return templateId
        })
        guard !templateIds.isEmpty else { return }

        var fetched: [String: [String]] = [:]
        for templateId in templateIds {
            if Task.isCancelled { return }
            let alreadyCached = await MainActor.run { splitPlanExerciseCache[templateId] != nil }
            if alreadyCached {
                continue
            }
            do {
                let detail = try await WorkoutAPIService.shared.fetchTemplateDetail(templateId: templateId)
                let names = normalizedExerciseNames(detail.exercises.map(\.name))
                if !names.isEmpty {
                    fetched[templateId] = names
                }
            } catch {
                continue
            }
        }

        guard !fetched.isEmpty else { return }
        await MainActor.run {
            splitPlanExerciseCache.merge(fetched) { _, new in new }
        }
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

    private func splitDisplayName(daysPerWeek: Int, mode: SplitCreationMode, splitType: SplitType) -> String {
        if mode == .custom {
            return "Custom Split"
        }
        let resolved = resolvedSplitType(splitType, daysPerWeek: daysPerWeek)
        return resolved.title
    }

    private func defaultSplitDayNames(for daysPerWeek: Int, splitType: SplitType) -> [String] {
        let clamped = min(max(daysPerWeek, 2), 7)
        if splitType == .smart {
            switch clamped {
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
        return splitType.dayLabels(for: clamped)
    }

    private func resolvedSplitType(_ splitType: SplitType, daysPerWeek: Int) -> SplitType {
        let clamped = min(max(daysPerWeek, 2), 7)
        guard splitType == .smart else { return splitType }
        switch clamped {
        case 2:
            return .upperLower
        case 3:
            return .fullBody
        case 4:
            return .upperLower
        case 5:
            return .hybrid
        case 6:
            return .pushPullLegs
        default:
            return .fullBody
        }
    }

    private func splitLabel(for date: Date) -> String? {
        let weekday = weekdaySymbol(for: date)
        if let plan = splitSnapshot.dayPlans[weekday] {
            if let focus = cleanedPlanText(plan.focus, source: plan.source) {
                return focus
            }
            if let title = cleanedPlanText(plan.templateTitle, source: plan.source) {
                return title
            }
        }
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

        let source: TodayTrainingSource = {
            if let templateId, templateId == coachPickTemplateId {
                return .coach
            }
            if templateId != nil {
                return .saved
            }
            return .custom
        }()

        var analyticsProps: [String: Any] = [
            "source": source.rawValue,
            "exercise_count": resolvedExercises.count,
            "has_template": templateId != nil
        ]
        if let templateId {
            analyticsProps["template_id"] = templateId
        }
        PostHogAnalytics.featureUsed(.workoutTracking, action: "start", properties: analyticsProps)

        TodayTrainingStore.save(
            title: title,
            exercises: resolvedExercises.map { $0.name },
            source: source,
            templateId: templateId
        )

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

    private func startDraftSession() async {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draftExercises.isEmpty else {
            await MainActor.run {
                loadError = "Add at least one exercise."
            }
            return
        }

        await MainActor.run {
            loadError = nil
        }

        let title = trimmedName.isEmpty ? "Custom workout" : trimmedName
        let exercises = sessionExercises(from: draftExercises)
        await startSession(title: title, templateId: nil, exercises: exercises)
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
            TodayTrainingStore.save(
                title: trimmedName,
                exercises: draftExercises.map { $0.name },
                source: .custom,
                templateId: templateId
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

    private func sessionExercises(from exercises: [WorkoutExerciseDraft]) -> [WorkoutExerciseSession] {
        exercises.map { exercise in
            let setCount = normalizedSetCount(exercise.sets)
            let repsText = normalizedRepsText(exercise.reps)
            let restSeconds = normalizedRestSeconds(exercise.restSeconds)
            var session = WorkoutExerciseSession(
                name: exercise.name,
                sets: WorkoutSetEntry.batch(
                    reps: repsText,
                    weight: "",
                    count: setCount
                ),
                restSeconds: restSeconds
            )
            session.notes = exercise.notes
            return withWarmupRest(session)
        }
    }

    private func sessionExercises(from exercises: [SplitPlanExercise]) -> [WorkoutExerciseSession] {
        exercises.map { exercise in
            let setCount = max(1, exercise.sets)
            let repsText = "\(max(1, exercise.reps))"
            let restSeconds = normalizedRestSeconds(exercise.restSeconds)
            var session = WorkoutExerciseSession(
                name: exercise.name,
                sets: WorkoutSetEntry.batch(
                    reps: repsText,
                    weight: "",
                    count: setCount
                ),
                restSeconds: restSeconds
            )
            session.notes = exercise.notes ?? ""
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

    @discardableResult
    private func generateWorkout() async -> Bool {
        guard !userId.isEmpty else { return false }
        guard !selectedMuscleGroups.isEmpty else {
            await MainActor.run {
                loadError = "Pick at least one muscle group."
            }
            return false
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
            let resolvedTitle = parsed.exercises.isEmpty ? "Quick Build" : parsed.title
            await MainActor.run {
                generatedPreview = result.isEmpty ? "Workout generated." : result
                generatedTitle = resolvedTitle
                generatedExercises = adjustedExercises
                generatedEstimatedMinutes = clampedEstimate
                if generatedExercises.isEmpty && !result.isEmpty {
                    loadError = "Generated workout couldn't be parsed."
                }
                isGenerating = false
            }
            if !adjustedExercises.isEmpty {
                TodayTrainingStore.save(
                    title: resolvedTitle,
                    exercises: adjustedExercises.map { $0.name },
                    source: .generated
                )
            }
            PostHogAnalytics.featureUsed(
                .workoutGeneration,
                action: "generate",
                properties: [
                    "result": adjustedExercises.isEmpty ? "empty" : "success",
                    "duration_minutes": selectedDurationMinutes,
                    "muscle_groups_count": selectedMuscleGroups.count,
                    "equipment_count": selectedEquipment.count,
                    "exercise_count": adjustedExercises.count,
                    "server_used": true
                ]
            )
            return !adjustedExercises.isEmpty
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
            if !fallback.isEmpty {
                TodayTrainingStore.save(
                    title: "Quick Build",
                    exercises: fallback.map { $0.name },
                    source: .generated
                )
            }
            PostHogAnalytics.featureUsed(
                .workoutGeneration,
                action: "generate",
                properties: [
                    "result": fallback.isEmpty ? "failure" : "fallback",
                    "duration_minutes": selectedDurationMinutes,
                    "muscle_groups_count": selectedMuscleGroups.count,
                    "equipment_count": selectedEquipment.count,
                    "exercise_count": fallback.count,
                    "server_used": false
                ]
            )
            return !fallback.isEmpty
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
            let createdAt = TodayTrainingStore.parseDate(coachTemplate.createdAt)
            if let createdAt, Calendar.current.isDateInToday(createdAt) {
                let existing = TodayTrainingStore.todaysTraining()
                let shouldSaveCoachSnapshot = existing == nil || existing?.source == .coach
                if shouldSaveCoachSnapshot {
                    TodayTrainingStore.save(
                        title: coachTemplate.title,
                        exercises: detail.exercises.map { $0.name },
                        source: .coach,
                        templateId: coachTemplate.id,
                        createdAt: createdAt
                    )
                }
            }
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
    private enum GenerationAlert: Identifiable {
        case success
        case failure

        var id: String {
            switch self {
            case .success:
                return "success"
            case .failure:
                return "failure"
            }
        }
    }

    @Binding var selectedMuscleGroups: Set<String>
    @Binding var selectedEquipment: Set<String>
    @Binding var selectedDurationMinutes: Int
    let onGenerate: (() async -> Bool)?

    @State private var isGenerating = false
    @State private var spinnerRotation = 0.0
    @State private var pulseOuterRing = false
    @State private var generationAlert: GenerationAlert?

    @Environment(\.dismiss) private var dismiss

    init(
        selectedMuscleGroups: Binding<Set<String>>,
        selectedEquipment: Binding<Set<String>>,
        selectedDurationMinutes: Binding<Int>,
        onGenerate: (() async -> Bool)? = nil
    ) {
        _selectedMuscleGroups = selectedMuscleGroups
        _selectedEquipment = selectedEquipment
        _selectedDurationMinutes = selectedDurationMinutes
        self.onGenerate = onGenerate
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(showsGenerateAction ? "Generate workout" : "Tune the plan")
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

                    if showsGenerateAction {
                        Text("Your custom workout will appear in the Workout Builder once generated.")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }

            if isGenerating {
                generationOverlay
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsGenerateAction {
                ActionButton(
                    title: isGenerating ? "Generating..." : "Generate Workout",
                    style: .primary
                ) {
                    Task {
                        await runGeneration()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
                .disabled(isGenerating || selectedMuscleGroups.isEmpty)
            }
        }
        .alert(item: $generationAlert) { alert in
            switch alert {
            case .success:
                return Alert(
                    title: Text("Workout generated"),
                    message: Text("Your workout has been completely generated."),
                    dismissButton: .default(Text("Done")) {
                        dismiss()
                    }
                )
            case .failure:
                return Alert(
                    title: Text("Generation failed"),
                    message: Text("Unable to generate your workout right now. Please try again."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var showsGenerateAction: Bool {
        onGenerate != nil
    }

    private var generationOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(FitTheme.cardWorkoutAccent.opacity(0.14))
                        .frame(width: 118, height: 118)
                        .scaleEffect(pulseOuterRing ? 1.08 : 0.94)

                    Circle()
                        .trim(from: 0.18, to: 0.92)
                        .stroke(
                            FitTheme.primaryGradient,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 84, height: 84)
                        .rotationEffect(.degrees(spinnerRotation))

                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(FitTheme.cardWorkoutAccent)
                }

                Text("Building your workout")
                    .font(FitFont.heading(size: 19))
                    .foregroundColor(FitTheme.textPrimary)
                Text("This only takes a few seconds.")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 26)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(FitTheme.cardStroke.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: FitTheme.shadow.opacity(0.45), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 20)
        }
        .transition(.opacity)
    }

    private func runGeneration() async {
        guard let onGenerate else {
            dismiss()
            return
        }

        Haptics.medium()
        withAnimation(.easeInOut(duration: 0.2)) {
            isGenerating = true
        }
        spinnerRotation = 0
        pulseOuterRing = false

        withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
            spinnerRotation = 360
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseOuterRing = true
        }

        let success = await onGenerate()

        withAnimation(.easeInOut(duration: 0.2)) {
            isGenerating = false
        }
        spinnerRotation = 0
        pulseOuterRing = false

        if success {
            Haptics.success()
            generationAlert = .success
        } else {
            Haptics.error()
            generationAlert = .failure
        }
    }
}

private struct SplitSetupFlowView: View {
    private enum Step: Hashable {
        case intro
        case mode
        case splitStyle
        case daysPerWeek
        case trainingDays
        case focus
        case weekPlanner
        case overview
        case planDay(String)
    }

    @State private var path: [Step] = []
    @State private var mode: SplitCreationMode
    @State private var daysPerWeek: Int
    @State private var trainingDays: [String]
    @State private var splitType: SplitType
    @State private var dayPlans: [String: SplitDayPlan]
    @State private var focus: String

    let templates: [WorkoutTemplate]
    let isEditing: Bool
    let onSave: (SplitCreationMode, Int, [String], SplitType, [String: SplitDayPlan], String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let weekdaySymbols = Calendar.current.weekdaySymbols
    private let shortWeekdaySymbols = Calendar.current.shortWeekdaySymbols

    init(
        currentMode: SplitCreationMode,
        currentDaysPerWeek: Int,
        currentTrainingDays: [String],
        currentSplitType: SplitType,
        currentDayPlans: [String: SplitDayPlan],
        currentFocus: String,
        templates: [WorkoutTemplate],
        isEditing: Bool,
        onSave: @escaping (SplitCreationMode, Int, [String], SplitType, [String: SplitDayPlan], String) -> Void
    ) {
        _mode = State(initialValue: currentMode)
        _daysPerWeek = State(initialValue: currentDaysPerWeek)
        _trainingDays = State(initialValue: currentTrainingDays)
        _splitType = State(initialValue: currentSplitType)
        _dayPlans = State(initialValue: currentDayPlans)
        _focus = State(initialValue: currentFocus)
        self.templates = templates
        self.isEditing = isEditing
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack(path: $path) {
            introStep
                .navigationBarHidden(true)
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .intro:
                        introStep
                    case .mode:
                        modeStep
                    case .splitStyle:
                        splitStyleStep
                    case .daysPerWeek:
                        daysPerWeekStep
                    case .trainingDays:
                        trainingDaysStep
                    case .focus:
                        focusStep
                    case .weekPlanner:
                        weekPlannerStep
                    case .overview:
                        overviewStep
                    case .planDay(let day):
                        planDayStep(day)
                    }
                }
        }
    }

    private var introStep: some View {
        stepLayout(
            currentStep: .intro,
            title: isEditing ? "Update your weekly workouts" : "Set up your weekly workouts",
            subtitle: "Answer a few questions to plan the week.",
            showsBack: false,
            primaryTitle: "Get started",
            primaryAction: {
                Haptics.light()
                withAnimation(MotionTokens.springBase) {
                    path.append(.mode)
                }
            },
            showsSummary: false
        ) {
            WorkoutCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What you'll set up")
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                    Label("Choose AI or build your own", systemImage: "sparkles")
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Label("Pick your training days", systemImage: "calendar")
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Label("Plan each workout", systemImage: "dumbbell")
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                }
            }

            WorkoutCard(isAccented: true) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview your week")
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                    HStack(spacing: 6) {
                        ForEach(weekdaySymbols.indices, id: \.self) { index in
                            let day = weekdaySymbols[index]
                            let shortLabel = index < shortWeekdaySymbols.count
                                ? shortWeekdaySymbols[index]
                                : String(day.prefix(3))
                            MiniDayPill(
                                title: shortLabel,
                                isActive: trainingDays.contains(day)
                            )
                        }
                    }
                    Text("We'll balance training and recovery so your plan feels sustainable.")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
        }
    }

    private var modeStep: some View {
        stepLayout(
            currentStep: .mode,
            title: "How do you want to build your split?",
            subtitle: "Pick the setup style that fits you best.",
            primaryTitle: "Continue",
            primaryAction: continueFromMode,
            showsSummary: false
        ) {
            VStack(spacing: 12) {
                ForEach(SplitCreationMode.allCases) { option in
                    SplitModeCard(
                        mode: option,
                        isSelected: mode == option,
                        action: {
                            Haptics.selection()
                            withAnimation(MotionTokens.springQuick) {
                                mode = option
                            }
                        }
                    )
                }
            }
        }
    }

    private var splitStyleStep: some View {
        stepLayout(
            currentStep: .splitStyle,
            title: "Choose a split style",
            subtitle: "We’ll match the split to your training days.",
            primaryTitle: "Continue",
            primaryAction: {
                Haptics.light()
                withAnimation(MotionTokens.springBase) {
                    path.append(.daysPerWeek)
                }
            },
            showsSummary: true
        ) {
            VStack(spacing: 12) {
                ForEach(splitStyleOptions) { option in
                    SplitTypeCard(
                        splitType: option,
                        isSelected: splitType == option,
                        exampleDays: splitTypeExampleDays(option),
                        action: {
                            Haptics.selection()
                            withAnimation(MotionTokens.springQuick) {
                                splitType = option
                            }
                        }
                    )
                }
            }
        }
    }

    private var daysPerWeekStep: some View {
        stepLayout(
            currentStep: .daysPerWeek,
            title: "Training days per week",
            subtitle: "How many days do you want to train?",
            primaryTitle: "Continue",
            primaryAction: {
                Haptics.light()
                withAnimation(MotionTokens.springBase) {
                    path.append(.trainingDays)
                }
            },
            showsSummary: true
        ) {
            HStack(spacing: 8) {
                ForEach(2...7, id: \.self) { dayCount in
                    Button {
                        setDaysPerWeek(dayCount)
                    } label: {
                        Text("\(dayCount)")
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(daysPerWeek == dayCount ? FitTheme.buttonText : FitTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(daysPerWeek == dayCount ? FitTheme.accent : FitTheme.cardBackground)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(daysPerWeek == dayCount ? Color.clear : FitTheme.cardStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var trainingDaysStep: some View {
        stepLayout(
            currentStep: .trainingDays,
            title: "Pick your training days",
            subtitle: "Select \(daysPerWeek) days so we can schedule rest days.",
            primaryTitle: "Continue",
            isPrimaryDisabled: trainingDays.count != daysPerWeek,
            primaryAction: continueFromTrainingDays,
            showsSummary: true
        ) {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    let day = weekdaySymbols[index]
                    let shortLabel = index < shortWeekdaySymbols.count
                        ? shortWeekdaySymbols[index]
                        : String(day.prefix(3))
                    SplitDayChip(
                        title: shortLabel,
                        isSelected: trainingDays.contains(day),
                        action: { toggleTrainingDay(day) }
                    )
                }
            }

            Text("Select \(daysPerWeek) days. Tap a selected day to free a slot.")
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private var focusStep: some View {
        stepLayout(
            currentStep: .focus,
            title: "Training focus",
            subtitle: "Choose the goal that matters most right now.",
            primaryTitle: "Continue",
            primaryAction: {
                Haptics.light()
                withAnimation(MotionTokens.springBase) {
                    path.append(.overview)
                }
            },
            showsSummary: true
        ) {
            VStack(spacing: 12) {
                ForEach(focusOptions, id: \.self) { option in
                    let isSelected = focus == option
                    Button(action: {
                        Haptics.selection()
                        withAnimation(MotionTokens.springQuick) {
                            focus = option
                        }
                    }) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option)
                                    .font(FitFont.body(size: 15, weight: .semibold))
                                    .foregroundColor(FitTheme.textPrimary)
                                Text(focusSubtitle(for: option))
                                    .font(FitFont.body(size: 11))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(FitTheme.accent)
                            }
                        }
                        .padding(14)
                        .background(isSelected ? FitTheme.accent.opacity(0.12) : FitTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? FitTheme.accent : FitTheme.cardStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var weekPlannerStep: some View {
        stepLayout(
            currentStep: .weekPlanner,
            title: "Plan your week",
            subtitle: "Choose a workout focus and source for each training day.",
            primaryTitle: "Continue",
            isPrimaryDisabled: trainingDays.count != daysPerWeek,
            primaryAction: {
                Haptics.light()
                withAnimation(MotionTokens.springBase) {
                    path.append(.overview)
                }
            },
            showsSummary: true
        ) {
            VStack(spacing: 12) {
                ForEach(trainingDays, id: \.self) { day in
                    PlanDayRow(
                        dayLabel: shortLabel(for: day),
                        plan: dayPlans[day],
                        action: { path.append(.planDay(day)) }
                    )
                }
            }
        }
    }

    private var overviewStep: some View {
        stepLayout(
            currentStep: .overview,
            title: "Weekly overview",
            subtitle: "Review your plan before saving.",
            primaryTitle: isEditing ? "Save changes" : "Save split",
            isPrimaryDisabled: trainingDays.count != daysPerWeek,
            primaryAction: saveChanges,
            showsSummary: false
        ) {
            WorkoutCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Split summary")
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)

                    Text(mode == .custom ? "Custom Split" : resolvedSelectedSplitType.title)
                        .font(FitFont.heading(size: 20))
                        .foregroundColor(FitTheme.textPrimary)

                    HStack(spacing: 10) {
                        SummaryPill(title: "Days", value: "\(daysPerWeek) / week")
                        SummaryPill(title: "Mode", value: mode.title)
                        SummaryPill(title: "Focus", value: focus)
                    }

                    Text(trainingDaysSummary)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }

            if mode == .custom {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Planned workouts")
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)

                    ForEach(trainingDays, id: \.self) { day in
                        PlanDayRow(
                            dayLabel: shortLabel(for: day),
                            plan: dayPlans[day],
                            action: { path.append(.planDay(day)) }
                        )
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Split preview")
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)

                    ForEach(Array(trainingDays.enumerated()), id: \.offset) { index, day in
                        let label = previewDayLabels.indices.contains(index) ? previewDayLabels[index] : "Training"
                        HStack(spacing: 12) {
                            Text(shortLabel(for: day))
                                .font(FitFont.body(size: 14, weight: .semibold))
                                .foregroundColor(FitTheme.textPrimary)
                                .frame(width: 40, alignment: .leading)
                            Text(label)
                                .font(FitFont.body(size: 14))
                                .foregroundColor(FitTheme.textSecondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(FitTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(FitTheme.cardStroke.opacity(0.8), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func planDayStep(_ day: String) -> some View {
        WeeklyPlanEditorSheet(
            weekday: day,
            shortLabel: shortLabel(for: day),
            existingPlan: dayPlans[day],
            templates: templates,
            showsCloseButton: false,
            onSave: { updatedPlan in
                dayPlans[day] = updatedPlan
            },
            onClear: {
                dayPlans.removeValue(forKey: day)
            }
        )
    }

    private func stepLayout<Content: View>(
        currentStep: Step,
        title: String,
        subtitle: String? = nil,
        showsBack: Bool = true,
        primaryTitle: String,
        isPrimaryDisabled: Bool = false,
        primaryAction: @escaping () -> Void,
        showsSummary: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        if showsBack {
                            Button(action: {
                                guard !path.isEmpty else { return }
                                Haptics.light()
                                withAnimation(MotionTokens.springBase) {
                                    path.removeLast()
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(FitTheme.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(FitTheme.cardHighlight)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Spacer().frame(width: 34)
                        }

                        Spacer()

                        Button("Close") {
                            Haptics.light()
                            dismiss()
                        }
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.accent)
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(progressLabel(for: currentStep))
                            .font(FitFont.body(size: 11, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)

                        progressBar(value: progressValue(for: currentStep))
                    }

                    Text(title)
                        .font(FitFont.heading(size: 24))
                        .foregroundColor(FitTheme.textPrimary)

                    if let subtitle {
                        Text(subtitle)
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    if showsSummary {
                        splitSetupSummaryCard
                    }

                    content()

                    ActionButton(title: primaryTitle, style: .primary) {
                        primaryAction()
                    }
                    .disabled(isPrimaryDisabled)
                    .opacity(isPrimaryDisabled ? 0.6 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
    }

    private func continueFromMode() {
        Haptics.light()
        if mode == .ai {
            withAnimation(MotionTokens.springBase) {
                path.append(.splitStyle)
            }
        } else {
            withAnimation(MotionTokens.springBase) {
                path.append(.daysPerWeek)
            }
        }
    }

    private func continueFromTrainingDays() {
        Haptics.light()
        if mode == .ai {
            withAnimation(MotionTokens.springBase) {
                path.append(.focus)
            }
        } else {
            withAnimation(MotionTokens.springBase) {
                path.append(.weekPlanner)
            }
        }
    }

    private func saveChanges() {
        let normalized = normalizedTrainingDays(trainingDays, targetCount: daysPerWeek)
        let cleanedPlans = dayPlans.filter { normalized.contains($0.key) }
        onSave(mode, daysPerWeek, normalized, splitType, cleanedPlans, focus)
        Haptics.success()
        dismiss()
    }

    private func setDaysPerWeek(_ newValue: Int) {
        let clamped = min(max(newValue, 2), 7)
        guard clamped != daysPerWeek else { return }
        Haptics.selection()
        withAnimation(MotionTokens.springQuick) {
            daysPerWeek = clamped
            trainingDays = normalizedTrainingDays(trainingDays, targetCount: clamped)
            let options = splitStyleOptions
            if !options.contains(splitType) {
                splitType = .smart
            }
        }
    }

    private func toggleTrainingDay(_ day: String) {
        var selected = Set(trainingDays)
        let startingCount = selected.count
        if selected.contains(day) {
            selected.remove(day)
        } else if selected.count < daysPerWeek {
            selected.insert(day)
        } else {
            Haptics.warning()
            return
        }
        guard selected.count != startingCount else { return }
        Haptics.selection()
        withAnimation(MotionTokens.springQuick) {
            trainingDays = weekdaySymbols.filter { selected.contains($0) }
        }
    }

    private func normalizedTrainingDays(_ days: [String], targetCount: Int) -> [String] {
        let filtered = days.filter { weekdaySymbols.contains($0) }
        var ordered = weekdaySymbols.filter { filtered.contains($0) }

        if ordered.count > targetCount {
            ordered = Array(ordered.prefix(targetCount))
        }

        if ordered.count < targetCount {
            for day in weekdaySymbols where !ordered.contains(day) {
                ordered.append(day)
                if ordered.count == targetCount {
                    break
                }
            }
        }

        return ordered
    }

    private func shortLabel(for day: String) -> String {
        if let index = weekdaySymbols.firstIndex(of: day), index < shortWeekdaySymbols.count {
            return shortWeekdaySymbols[index]
        }
        return String(day.prefix(3))
    }

    private var splitStyleOptions: [SplitType] {
        let clamped = min(max(daysPerWeek, 2), 7)
        switch clamped {
        case 2:
            return [.smart, .fullBody, .upperLower]
        case 3:
            return [.smart, .fullBody, .pushPullLegs, .arnold]
        case 4:
            return [.smart, .upperLower, .hybrid, .bodyPart]
        case 5:
            return [.smart, .pushPullLegs, .hybrid, .bodyPart]
        case 6:
            return [.smart, .pushPullLegs, .hybrid, .bodyPart, .arnold]
        default:
            return [.smart, .fullBody, .bodyPart]
        }
    }

    private var resolvedSelectedSplitType: SplitType {
        resolveSplitType(splitType)
    }

    private var trainingDaysSummary: String {
        let labels = weekdaySymbols.enumerated().compactMap { index, day -> String? in
            guard trainingDays.contains(day) else { return nil }
            if index < shortWeekdaySymbols.count {
                return shortWeekdaySymbols[index]
            }
            return String(day.prefix(3))
        }
        if labels.isEmpty {
            return "Pick your training days to update the split schedule."
        }
        return "Training days: " + labels.joined(separator: ", ")
    }

    private var previewDayLabels: [String] {
        resolveSplitType(splitType).dayLabels(for: min(max(daysPerWeek, 2), 7))
    }

    private func splitTypeExampleDays(_ type: SplitType) -> [String] {
        let clamped = min(max(daysPerWeek, 2), 7)
        let resolved = resolveSplitType(type)
        return Array(resolved.dayLabels(for: clamped).prefix(3))
    }

    private var focusOptions: [String] {
        ["Strength", "Hypertrophy", "Fat loss + muscle"]
    }

    private func focusSubtitle(for focus: String) -> String {
        switch focus {
        case "Hypertrophy":
            return "Size and muscle growth focus."
        case "Fat loss + muscle":
            return "Lean out while building muscle."
        default:
            return "Strength and performance focus."
        }
    }

    private func resolveSplitType(_ type: SplitType) -> SplitType {
        guard type == .smart else { return type }
        switch min(max(daysPerWeek, 2), 7) {
        case 2:
            return .upperLower
        case 3:
            return .fullBody
        case 4:
            return .upperLower
        case 5:
            return .hybrid
        case 6:
            return .pushPullLegs
        default:
            return .fullBody
        }
    }

    private var splitSetupSummaryCard: some View {
        WorkoutCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current setup")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SummaryPill(title: "Mode", value: mode.title)
                        SummaryPill(title: "Days", value: "\(daysPerWeek)/wk")
                        SummaryPill(
                            title: "Split",
                            value: mode == .ai ? resolvedSelectedSplitType.title : "Custom"
                        )
                        SummaryPill(
                            title: "Focus",
                            value: focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not set" : focus
                        )
                    }
                }

                Text(trainingDaysSummary)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }

    private var progressSteps: [Step] {
        var steps: [Step] = [.intro, .mode]
        if mode == .ai {
            steps.append(contentsOf: [.splitStyle, .daysPerWeek, .trainingDays, .focus, .overview])
        } else {
            steps.append(contentsOf: [.daysPerWeek, .trainingDays, .weekPlanner, .overview])
        }
        return steps
    }

    private func normalizedProgressStep(_ step: Step) -> Step {
        if case .planDay = step {
            return .weekPlanner
        }
        return step
    }

    private func progressIndex(for step: Step) -> Int {
        let normalized = normalizedProgressStep(step)
        return progressSteps.firstIndex(of: normalized) ?? 0
    }

    private func progressLabel(for step: Step) -> String {
        let count = max(progressSteps.count, 1)
        let index = min(progressIndex(for: step) + 1, count)
        return "Step \(index) of \(count)"
    }

    private func progressValue(for step: Step) -> Double {
        let count = max(progressSteps.count, 1)
        let index = min(progressIndex(for: step) + 1, count)
        return Double(index) / Double(count)
    }

    private func progressBar(value: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(FitTheme.cardStroke.opacity(0.6))
                Capsule()
                    .fill(FitTheme.accent)
                    .frame(width: max(proxy.size.width * CGFloat(value), 14))
            }
        }
        .frame(height: 6)
    }
}

private struct SplitTypeCard: View {
    let splitType: SplitType
    let isSelected: Bool
    let exampleDays: [String]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: splitType == .smart ? "sparkles" : "dumbbell")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FitTheme.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(splitType.title)
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(splitType.subtitle)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)

                    if !exampleDays.isEmpty {
                        Text(exampleDays.joined(separator: " • "))
                            .font(FitFont.body(size: 11))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(FitTheme.accent)
                }
            }
            .padding(16)
            .background(isSelected ? FitTheme.accent.opacity(0.12) : FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? FitTheme.accent : FitTheme.cardStroke, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? FitTheme.accent.opacity(0.15) : FitTheme.shadow.opacity(0.6), radius: isSelected ? 14 : 10, x: 0, y: 6)
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(MotionTokens.springQuick, value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

private struct MiniDayPill: View {
    let title: String
    let isActive: Bool

    var body: some View {
        Text(title)
            .font(FitFont.body(size: 10, weight: .semibold))
            .foregroundColor(isActive ? FitTheme.buttonText : FitTheme.textSecondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isActive ? FitTheme.accent : FitTheme.cardHighlight)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.clear : FitTheme.cardStroke.opacity(0.7), lineWidth: 1)
            )
    }
}

private struct PlanDayRow: View {
    let dayLabel: String
    let plan: SplitDayPlan?
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(spacing: 12) {
                Circle()
                    .fill(plan == nil ? FitTheme.cardStroke : FitTheme.success)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dayLabel)
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                        .textCase(.uppercase)

                    Text(planTitle)
                        .font(FitFont.body(size: 15, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)

                    if let plan {
                        Text(plan.source.title)
                            .font(FitFont.body(size: 11))
                            .foregroundColor(FitTheme.textSecondary)
                    } else {
                        Text("Tap to plan")
                            .font(FitFont.body(size: 11))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .padding(14)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FitTheme.cardStroke.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var planTitle: String {
        guard let plan else { return "Plan workout" }
        if let title = plan.templateTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        let trimmed = plan.focus.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Plan workout" : trimmed
    }
}

private struct WeeklyPlanEditorSheet: View {
    let weekday: String
    let shortLabel: String
    let templates: [WorkoutTemplate]
    let showsCloseButton: Bool
    let onSave: (SplitDayPlan) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var focus: String
    @State private var source: SplitPlanSource
    @State private var selectedTemplateId: String?
    @State private var selectedTemplateTitle: String?
    @State private var selectedMuscleGroups: Set<String>
    @State private var selectedEquipment: Set<String>
    @State private var durationMinutes: Int
    @State private var templateSearch: String
    @State private var customWorkoutName: String
    @State private var customExercises: [WorkoutExerciseDraft]
    @State private var isExercisePickerPresented = false

    init(
        weekday: String,
        shortLabel: String,
        existingPlan: SplitDayPlan?,
        templates: [WorkoutTemplate],
        showsCloseButton: Bool = true,
        onSave: @escaping (SplitDayPlan) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.weekday = weekday
        self.shortLabel = shortLabel
        self.templates = templates
        self.showsCloseButton = showsCloseButton
        self.onSave = onSave
        self.onClear = onClear

        _focus = State(initialValue: existingPlan?.focus ?? "")
        _source = State(initialValue: existingPlan?.source ?? .ai)
        _selectedTemplateId = State(initialValue: existingPlan?.templateId)
        _selectedTemplateTitle = State(initialValue: existingPlan?.templateTitle)
        let defaultGroups = existingPlan?.muscleGroups.isEmpty == false
            ? existingPlan?.muscleGroups ?? []
            : [MuscleGroup.chest.rawValue, MuscleGroup.back.rawValue]
        _selectedMuscleGroups = State(initialValue: Set(defaultGroups))
        _selectedEquipment = State(initialValue: Set(existingPlan?.equipment ?? []))
        _durationMinutes = State(initialValue: existingPlan?.durationMinutes ?? 45)
        _templateSearch = State(initialValue: "")
        _customWorkoutName = State(initialValue: existingPlan?.templateTitle ?? existingPlan?.focus ?? "")
        let initialCustomExercises = WeeklyPlanEditorSheet.draftExercises(from: existingPlan?.customExercises ?? [])
        _customExercises = State(initialValue: initialCustomExercises)
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Plan \(shortLabel)")
                                .font(FitFont.heading(size: 22))
                                .foregroundColor(FitTheme.textPrimary)
                            Text("Set your workout focus and source.")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        Spacer()
                        if showsCloseButton {
                            Button("Close") {
                                dismiss()
                            }
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.accent)
                        } else {
                            Button(action: { dismiss() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Back")
                                        .font(FitFont.body(size: 14, weight: .semibold))
                                }
                                .foregroundColor(FitTheme.accent)
                            }
                        }
                    }
                    .padding(.top, 12)

                    FieldLabel(title: "Workout focus")
                    TextField("e.g., Chest, Upper, Pull", text: $focus)
                        .font(FitFont.body(size: 15))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(12)
                        .background(FitTheme.cardHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    FieldLabel(title: "Plan type")
                    PlanSourcePicker(source: $source)

                    if source == .saved {
                        FieldLabel(title: "Saved workouts")
                        if templates.isEmpty {
                            Text("No saved workouts yet. Create one in the Workout Builder.")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        } else {
                            SearchBar(text: $templateSearch, placeholder: "Search saved workouts")
                                .padding(.bottom, 4)
                            VStack(spacing: 10) {
                                if filteredTemplates.isEmpty {
                                    Text("No saved workouts found.")
                                        .font(FitFont.body(size: 12))
                                        .foregroundColor(FitTheme.textSecondary)
                                } else {
                                    ForEach(filteredTemplates) { template in
                                        Button(action: {
                                            selectedTemplateId = template.id
                                            selectedTemplateTitle = template.title
                                        }) {
                                            HStack(spacing: 10) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(template.title)
                                                        .font(FitFont.body(size: 14, weight: .semibold))
                                                        .foregroundColor(FitTheme.textPrimary)
                                                    if let description = template.description, !description.isEmpty {
                                                        Text(description)
                                                            .font(FitFont.body(size: 11))
                                                            .foregroundColor(FitTheme.textSecondary)
                                                            .lineLimit(1)
                                                    }
                                                }
                                                Spacer()
                                                if selectedTemplateId == template.id {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(FitTheme.accent)
                                                }
                                            }
                                            .padding(12)
                                            .background(selectedTemplateId == template.id ? FitTheme.accent.opacity(0.12) : FitTheme.cardBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(selectedTemplateId == template.id ? FitTheme.accent : FitTheme.cardStroke, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if source == .create {
                        BuilderStepHeader(step: 1, title: "Name your workout", subtitle: "Shown when you start.")
                        TextField("Workout name", text: $customWorkoutName)
                            .font(FitFont.body(size: 15))
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(12)
                            .background(FitTheme.cardHighlight)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Divider().background(FitTheme.cardStroke)

                        BuilderStepHeader(step: 2, title: "Add exercises", subtitle: "Sets, reps, rest, and notes.")
                        if customExercises.isEmpty {
                            Text("Add exercises to start building your session.")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        } else {
                            ForEach(customExercises.indices, id: \.self) { index in
                                DraftExerciseEditorRow(
                                    exercise: $customExercises[index],
                                    onRemove: {
                                        let id = customExercises[index].id
                                        customExercises.removeAll { $0.id == id }
                                    }
                                )
                            }
                        }

                        ActionButton(title: "Add Exercise", style: .secondary) {
                            isExercisePickerPresented = true
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if source == .ai {
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
                            selectedMinutes: $durationMinutes,
                            options: [20, 30, 45, 60, 75, 90]
                        )
                    }

                    HStack(spacing: 12) {
                        ActionButton(title: "Clear", style: .secondary) {
                            onClear()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)

                        ActionButton(title: "Save plan", style: .primary) {
                            let focusText = resolvedFocus
                            let trimmedCustomName = customWorkoutName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let customTitle = trimmedCustomName.isEmpty ? nil : trimmedCustomName
                            let customPlanExercises = source == .create ? planExercises(from: customExercises) : []
                            let customExercisesValue = customPlanExercises.isEmpty ? nil : customPlanExercises
                            let customExerciseNames = customExercisesValue.map { values in
                                values
                                    .map(\.name)
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                            }
                            let plan = SplitDayPlan(
                                weekday: weekday,
                                focus: focusText,
                                source: source,
                                templateId: source == .saved ? selectedTemplateId : nil,
                                templateTitle: source == .saved ? selectedTemplateTitle : customTitle,
                                muscleGroups: source == .ai ? selectedMuscleGroups.sorted() : [],
                                equipment: source == .ai ? selectedEquipment.sorted() : [],
                                durationMinutes: source == .ai ? durationMinutes : nil,
                                customExercises: source == .create ? customExercisesValue : nil,
                                exerciseNames: source == .create ? customExerciseNames : nil
                            )
                            onSave(plan)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $isExercisePickerPresented) {
            ExercisePickerModal(
                selectedNames: Set(customExercises.map { $0.name }),
                onAdd: { exercise in
                    let newExercise = WorkoutExerciseDraft(
                        name: exercise.name,
                        muscleGroup: exercise.muscleGroups.first ?? "General",
                        equipment: exercise.equipment.first ?? "Bodyweight",
                        sets: 3,
                        reps: 10,
                        restSeconds: defaultRestSeconds(for: exercise.name),
                        notes: ""
                    )
                    customExercises.append(newExercise)
                },
                onClose: { isExercisePickerPresented = false }
            )
        }
        .onChange(of: source) { newValue in
            if newValue != .saved {
                selectedTemplateId = nil
                selectedTemplateTitle = nil
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

    private var resolvedFocus: String {
        let trimmed = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if source == .create {
            let trimmedCustom = customWorkoutName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCustom.isEmpty { return trimmedCustom }
        }
        if source == .saved, let title = selectedTemplateTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        switch source {
        case .saved:
            return "Saved workout"
        case .create:
            return "Custom workout"
        case .ai:
            return "AI workout"
        }
    }

    private func planExercises(from exercises: [WorkoutExerciseDraft]) -> [SplitPlanExercise] {
        exercises.map { draft in
            SplitPlanExercise(
                name: draft.name,
                muscleGroup: draft.muscleGroup,
                equipment: draft.equipment,
                sets: draft.sets,
                reps: draft.reps,
                restSeconds: draft.restSeconds,
                notes: draft.notes.isEmpty ? nil : draft.notes
            )
        }
    }

    private func defaultRestSeconds(for name: String) -> Int {
        let lower = name.lowercased()
        let heavyKeywords = ["squat", "deadlift", "bench", "press", "row", "pull"]
        if heavyKeywords.contains(where: { lower.contains($0) }) {
            return 90
        }
        return 60
    }

    private static func draftExercises(from exercises: [SplitPlanExercise]) -> [WorkoutExerciseDraft] {
        exercises.map { exercise in
            WorkoutExerciseDraft(
                name: exercise.name,
                muscleGroup: exercise.muscleGroup,
                equipment: exercise.equipment,
                sets: max(1, exercise.sets),
                reps: max(1, exercise.reps),
                restSeconds: max(30, exercise.restSeconds),
                notes: exercise.notes ?? ""
            )
        }
    }
}

private struct PlanSourcePicker: View {
    @Binding var source: SplitPlanSource

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SplitPlanSource.allCases, id: \.self) { option in
                let isSelected = option == source
                Button(action: { source = option }) {
                    Text(option.shortTitle)
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            isSelected
                                ? AnyShapeStyle(FitTheme.primaryGradient)
                                : AnyShapeStyle(FitTheme.cardBackground)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.clear : FitTheme.cardStroke.opacity(0.7), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
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
                    if status == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(mainTextColor)
                    } else {
                        Text("\(dayNumber)")
                            .font(FitFont.body(size: 18, weight: .bold))
                            .foregroundColor(mainTextColor)
                    }
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
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        if status == .completed {
            return FitTheme.success
        }
        if !isTrainingDay {
            return isSelected ? FitTheme.cardHighlight.opacity(0.8) : FitTheme.cardHighlight
        }
        return isSelected ? accentColor : accentColor.opacity(0.22)
    }

    private var borderColor: Color {
        if status == .completed {
            return FitTheme.success
        }
        if isTrainingDay {
            return accentColor.opacity(isSelected ? 1 : 0.55)
        }
        return isSelected ? FitTheme.cardStroke.opacity(0.7) : FitTheme.cardStroke.opacity(0.4)
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
        if status == .completed { return FitTheme.textOnAccent.opacity(0.9) }
        if isSelected, isTrainingDay { return FitTheme.textOnAccent.opacity(0.9) }
        return FitTheme.textSecondary
    }

    private var mainTextColor: Color {
        if status == .completed { return FitTheme.textOnAccent }
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
    let onGenerate: () -> Void
    let onCreate: () -> Void
    let onClose: () -> Void

    @State private var searchText = ""
    @State private var showIntroMotion = false
    @State private var animateBackdrop = false

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            backgroundOrbs

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    quickActions
                    searchAndSummary

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Saved workouts")
                                .font(FitFont.body(size: 14, weight: .semibold))
                                .foregroundColor(FitTheme.textPrimary)
                            Spacer()
                            Text("\(filteredTemplates.count)")
                                .font(FitFont.body(size: 11, weight: .semibold))
                                .foregroundColor(FitTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(FitTheme.cardHighlight.opacity(0.8))
                                .clipShape(Capsule())
                        }

                        if filteredTemplates.isEmpty {
                            WorkoutCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("No saved workouts found")
                                        .font(FitFont.body(size: 15, weight: .semibold))
                                        .foregroundColor(FitTheme.textPrimary)
                                    Text("Try a different search or use Generate/Create above.")
                                        .font(FitFont.body(size: 12))
                                        .foregroundColor(FitTheme.textSecondary)
                                }
                            }
                        } else {
                            ForEach(filteredTemplates) { template in
                                WorkoutSwapRow(template: template) {
                                    onSelect(template)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .opacity(showIntroMotion ? 1 : 0)
            .offset(y: showIntroMotion ? 0 : 10)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                showIntroMotion = true
            }
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                animateBackdrop = true
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Swap Workout")
                    .font(FitFont.heading(size: 22))
                    .foregroundColor(FitTheme.textPrimary)
                Text("Choose saved, generate fresh, or create your own.")
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
                    .overlay(
                        Circle()
                            .stroke(FitTheme.cardStroke.opacity(0.65), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var quickActions: some View {
        WorkoutCard(isAccented: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick actions")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)

                HStack(spacing: 10) {
                    SwapActionTile(
                        icon: "sparkles",
                        title: "Generate",
                        subtitle: "Tune plan then generate",
                        accent: FitTheme.cardWorkoutAccent,
                        action: onGenerate
                    )
                    SwapActionTile(
                        icon: "square.and.pencil",
                        title: "Create",
                        subtitle: "Open template builder",
                        accent: FitTheme.accent,
                        action: onCreate
                    )
                }
            }
        }
    }

    private var searchAndSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchBar(text: $searchText, placeholder: "Search saved workouts")
            HStack(spacing: 10) {
                SummaryPill(title: "Library", value: "\(templates.count) templates")
                    .frame(maxWidth: .infinity, alignment: .leading)
                SummaryPill(title: "Ready", value: filteredTemplates.isEmpty ? "No match" : "\(filteredTemplates.count) found")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var backgroundOrbs: some View {
        ZStack {
            Circle()
                .fill(FitTheme.cardWorkoutAccent.opacity(0.2))
                .frame(width: animateBackdrop ? 340 : 280, height: animateBackdrop ? 340 : 280)
                .blur(radius: 45)
                .offset(x: animateBackdrop ? 150 : 110, y: -260)

            Circle()
                .fill(FitTheme.accent.opacity(0.18))
                .frame(width: animateBackdrop ? 300 : 240, height: animateBackdrop ? 300 : 240)
                .blur(radius: 38)
                .offset(x: animateBackdrop ? -120 : -90, y: -90)
        }
        .allowsHitTesting(false)
    }

    private var filteredTemplates: [WorkoutTemplate] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return templates
        }
        return templates.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
}

private struct SwapActionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FitFont.body(size: 15, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(subtitle)
                        .font(FitFont.body(size: 11))
                        .foregroundColor(FitTheme.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(FitTheme.cardBackground.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WorkoutSwapRow: View {
    let template: WorkoutTemplate
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(modeAccent.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: modeIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(modeAccent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(template.description ?? "Saved workout template")
                        .font(FitFont.body(size: 11))
                        .foregroundColor(FitTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text(modeLabel)
                        .font(FitFont.body(size: 9, weight: .semibold))
                        .foregroundColor(modeAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(modeAccent.opacity(0.14))
                        .clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(FitFont.body(size: 12, weight: .semibold))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            .padding(14)
            .background(FitTheme.cardBackground.opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: FitTheme.shadow.opacity(0.35), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var modeLabel: String {
        let trimmed = template.mode.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("ai") == .orderedSame {
            return "AI"
        }
        return "MANUAL"
    }

    private var modeIcon: String {
        modeLabel == "AI" ? "sparkles" : "dumbbell.fill"
    }

    private var modeAccent: Color {
        modeLabel == "AI" ? FitTheme.cardWorkoutAccent : FitTheme.accent
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

private struct WorkoutGeneratingFullscreenOverlay: View {
    @State private var messageIndex = 0
    @State private var progressPhase = 0
    @State private var spinnerRotation = 0.0
    @State private var pulseScale = 0.88
    @State private var glowScale = 0.96

    private let loadingMessages = [
        "Analyzing your goals",
        "Mapping the best exercise order",
        "Balancing intensity and recovery",
        "Fine-tuning set and rep ranges",
        "Finalizing your session"
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.62), Color.black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    FitTheme.cardWorkoutAccent.opacity(0.28),
                    FitTheme.cardWorkoutAccent.opacity(0.02),
                    .clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 260
            )
            .scaleEffect(glowScale)
            .ignoresSafeArea()

            VStack(spacing: 30) {
                ZStack {
                    Circle()
                        .fill(FitTheme.cardWorkoutAccent.opacity(0.18))
                        .frame(width: 210, height: 210)
                        .blur(radius: 16)
                        .scaleEffect(glowScale)

                    Circle()
                        .stroke(FitTheme.cardWorkoutAccent.opacity(0.32), lineWidth: 1.4)
                        .frame(width: 174, height: 174)
                        .scaleEffect(pulseScale)

                    Circle()
                        .trim(from: 0.08, to: 0.92)
                        .stroke(
                            FitTheme.primaryGradient,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .frame(width: 132, height: 132)
                        .rotationEffect(.degrees(spinnerRotation))

                    Circle()
                        .fill(FitTheme.cardWorkout)
                        .frame(width: 94, height: 94)
                        .overlay(
                            Circle()
                                .stroke(FitTheme.cardStroke.opacity(0.55), lineWidth: 1)
                        )

                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(FitTheme.cardWorkoutAccent)
                }

                VStack(spacing: 10) {
                    Text("Generating")
                        .font(FitFont.heading(size: 34))
                        .foregroundColor(.white)
                    Text(loadingMessages[messageIndex % loadingMessages.count])
                        .font(FitFont.body(size: 14))
                        .foregroundColor(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .animation(.easeInOut(duration: 0.35), value: messageIndex)
                }

                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { index in
                        Capsule()
                            .fill(index <= progressPhase ? FitTheme.cardWorkoutAccent : Color.white.opacity(0.2))
                            .frame(width: index == progressPhase ? 26 : 10, height: 8)
                            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: progressPhase)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .task {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spinnerRotation = 360
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                glowScale = 1.08
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_150_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        messageIndex = (messageIndex + 1) % loadingMessages.count
                        progressPhase = (progressPhase + 1) % 6
                    }
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

private struct WorkoutWelcomeView: View {
    let onGetStarted: () -> Void
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                VStack(spacing: 16) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(FitTheme.cardWorkout)
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundColor(FitTheme.cardWorkoutAccent)
                    }
                    
                    // Title
                    Text("Welcome to Your Personal Workout Tracker")
                        .font(FitFont.heading(size: 24, weight: .bold))
                        .foregroundColor(FitTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    // Subtitle
                    Text("Let's set up your weekly training schedule to help you reach your fitness goals")
                        .font(FitFont.body(size: 16))
                        .foregroundColor(FitTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Features
                VStack(spacing: 16) {
                    WelcomeFeatureRow(
                        icon: "calendar.badge.clock",
                        title: "Smart Scheduling",
                        description: "Plan your training days around your life"
                    )
                    
                    WelcomeFeatureRow(
                        icon: "sparkles",
                        title: "AI-Powered Workouts",
                        description: "Get personalized workouts or build your own"
                    )
                    
                    WelcomeFeatureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Track Progress",
                        description: "Monitor your lifts and celebrate achievements"
                    )
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        Haptics.light()
                        onGetStarted()
                    }) {
                        Text("Get Started")
                            .font(FitFont.body(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(FitTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    
                    Button(action: {
                        Haptics.light()
                        dismiss()
                        onDismiss()
                    }) {
                        Text("Maybe Later")
                            .font(FitFont.body(size: 14, weight: .medium))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct WelcomeFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(FitTheme.cardWorkout.opacity(0.5))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(FitTheme.cardWorkoutAccent)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FitFont.body(size: 15, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                
                Text(description)
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    WorkoutView(userId: "demo-user")
        .environmentObject(GuidedTourCoordinator())
}
