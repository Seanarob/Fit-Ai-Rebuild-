import AVFoundation
import Combine
import PhotosUI
import SwiftUI
import UIKit

struct NutritionView: View {
    let userId: String
    @Binding var intent: NutritionTabIntent?

    @StateObject private var viewModel: NutritionViewModel
    @State private var isLogSheetPresented = false
    @State private var isScanSheetPresented = false
    @State private var selectedMealType: MealType = .breakfast
    @State private var mealPlanSnapshot: MealPlanSnapshot?
    @State private var mealPlanStatus: String?
    @State private var showBarcodeOnLogSheet = false
    @State private var isLogActionsPresented = false
    @State private var isSavedFoodsPresented = false
    @State private var isMealPlanExpanded = true
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var isCalendarPresented = false
    @State private var showLoggedToast = false
    @State private var targets = MacroTargets(calories: 0, protein: 0, carbs: 0, fats: 0)
    @State private var selectedMealPlanMeal: MealPlanMeal?
    @State private var isRegeneratingMeal = false
    @State private var macroDisplayMode: MacroDisplayMode = .remaining
    @State private var showSaveMealSheet = false
    @State private var mealToSave: (type: MealType, items: [LoggedFoodItem])?
    @State private var editingItem: (item: LoggedFoodItem, mealType: MealType)?
    @State private var showEditFoodSheet = false
    
    private enum MacroDisplayMode: String, CaseIterable {
        case remaining = "Remaining"
        case consumed = "Consumed"
    }

    init(userId: String, intent: Binding<NutritionTabIntent?> = .constant(nil)) {
        self.userId = userId
        _intent = intent
        _viewModel = StateObject(wrappedValue: NutritionViewModel(userId: userId))
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    
                    NutritionStreakBadge()

                    weekStrip

                    macroSummaryCard

                    mealPlanCard
                    if hasMealsLogged {
                        ForEach(MealType.allCases) { meal in
                            mealSectionCard(meal)
                        }
                    } else {
                        emptyMealsCard
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }

        }
        .sheet(isPresented: $isLogSheetPresented, onDismiss: {
            showBarcodeOnLogSheet = false
            Task { await viewModel.loadDailyLogs(date: selectedDate) }
        }) {
            NutritionLogSheet(
                viewModel: viewModel,
                mealType: selectedMealType,
                logDate: selectedDate,
                showBarcodeOnAppear: showBarcodeOnLogSheet
            )
        }
        .fullScreenCover(isPresented: $isScanSheetPresented) {
            ScanFoodCameraView(
                userId: userId,
                mealType: selectedMealType,
                logDate: selectedDate,
                onLogged: {
                    Task {
                        await viewModel.loadDailyLogs(date: selectedDate)
                    }
                }
            )
        }
        .sheet(isPresented: $isSavedFoodsPresented, onDismiss: {
            Task { await viewModel.loadDailyLogs(date: selectedDate) }
        }) {
            SavedFoodsSheet(viewModel: viewModel, mealType: selectedMealType, logDate: selectedDate)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isCalendarPresented) {
            NutritionHistoryView(userId: userId, selectedDate: $selectedDate)
        }
        .sheet(isPresented: $isLogActionsPresented) {
            LogFoodActionSheet(
                onPhotoLog: {
                    isScanSheetPresented = true
                },
                onScanBarcode: {
                    showBarcodeOnLogSheet = true
                    isLogSheetPresented = true
                },
                onFoodDatabase: {
                    showBarcodeOnLogSheet = false
                    isLogSheetPresented = true
                },
                onSavedFoods: {
                    isSavedFoodsPresented = true
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $selectedMealPlanMeal) { meal in
            MealPlanDetailSheet(
                meal: meal,
                isRegenerating: isRegeneratingMeal,
                onLog: {
                    Task {
                        await logMealPlanMeal(meal)
                        selectedMealPlanMeal = nil
                    }
                },
                onRegenerate: {
                    Task {
                        await regenerateMeal(meal)
                    }
                },
                onDismiss: {
                    selectedMealPlanMeal = nil
                },
                onMealUpdated: { updatedMeal in
                    updateMealPlanMeal(updatedMeal)
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSaveMealSheet, onDismiss: {
            // Clear state after sheet is fully dismissed to avoid race conditions
            mealToSave = nil
        }) {
            if let mealData = mealToSave {
                SaveMealSheet(
                    mealType: mealData.type,
                    items: mealData.items,
                    onSave: { name in
                        // Guard against empty items
                        guard !mealData.items.isEmpty else {
                            showSaveMealSheet = false
                            return
                        }
                        SavedMealsStore.shared.saveMealFromItems(
                            name: name,
                            mealType: mealData.type,
                            items: mealData.items
                        )
                        Haptics.success()
                        showSaveMealSheet = false
                    },
                    onCancel: {
                        showSaveMealSheet = false
                    }
                )
                .presentationDetents([.medium])
            } else {
                // Fallback empty view if data not available
                Text("Loading...")
                    .foregroundColor(FitTheme.textSecondary)
                    .onAppear {
                        // Dismiss immediately if no data
                        showSaveMealSheet = false
                    }
            }
        }
        .sheet(isPresented: $showEditFoodSheet, onDismiss: {
            editingItem = nil
        }) {
            if let editing = editingItem {
                EditFoodItemSheet(
                    item: editing.item,
                    mealType: editing.mealType,
                    onSave: { updatedItem in
                        Task {
                            await viewModel.updateLoggedItem(
                                original: editing.item,
                                updated: updatedItem,
                                mealType: editing.mealType,
                                date: selectedDate
                            )
                            showEditFoodSheet = false
                        }
                    },
                    onDelete: {
                        Task {
                            await viewModel.deleteLoggedItem(
                                item: editing.item,
                                mealType: editing.mealType,
                                date: selectedDate
                            )
                            showEditFoodSheet = false
                        }
                    },
                    onCancel: {
                        showEditFoodSheet = false
                    }
                )
                .presentationDetents([.medium, .large])
            } else {
                Text("Loading...")
                    .foregroundColor(FitTheme.textSecondary)
                    .onAppear {
                        showEditFoodSheet = false
                    }
            }
        }
        .task {
            await viewModel.loadDailyLogs(date: selectedDate)
            await loadTargets()
            await loadActiveMealPlan()
        }
        .onAppear {
            if intent == .logMeal {
                isLogActionsPresented = true
                intent = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAIMacrosUpdated)) { _ in
            Task { await loadTargets() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitAINutritionLogged)) { _ in
            showLoggedToastMessage()
        }
        .onChange(of: selectedDate) { newValue in
            Task {
                await viewModel.loadDailyLogs(date: newValue)
            }
        }
        .onChange(of: intent) { newValue in
            guard let newValue else { return }
            switch newValue {
            case .logMeal:
                isLogActionsPresented = true
            }
            intent = nil
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                isLogActionsPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(FitTheme.buttonText)
                    .frame(width: 56, height: 56)
                    .background(FitTheme.primaryGradient)
                    .clipShape(Circle())
                    .shadow(color: FitTheme.buttonShadow, radius: 14, x: 0, y: 8)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 28)
        }
        .overlay(alignment: .top) {
            if showLoggedToast {
                ToastBanner(message: "Logged!")
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nutrition")
                    .font(FitFont.heading(size: 30))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                Text("Log meals, scan food, and track macros.")
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textSecondary)
            }

            Spacer()

            VStack(spacing: 10) {
                CoachCharacterView(size: 72, showBackground: false, pose: .idle)
                    .allowsHitTesting(false)

                Button(action: { isCalendarPresented = true }) {
                    Image(systemName: "calendar")
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(10)
                        .background(FitTheme.cardBackground)
                        .clipShape(Circle())
                }
            }
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(weekDates, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                Button {
                    selectDate(date)
                } label: {
                    VStack(spacing: 4) {
                        Text(weekdaySymbol(for: date))
                            .font(FitFont.body(size: 11))
                            .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textSecondary)

                        Text("\(calendar.component(.day, from: date))")
                            .font(FitFont.body(size: 14))
                            .fontWeight(.semibold)
                            .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            FitTheme.primaryGradient
                        } else {
                            FitTheme.cardHighlight
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.clear : FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: FitTheme.shadow, radius: 14, x: 0, y: 8)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    handleWeekSwipe(value)
                }
        )
    }

    private var macroSummaryTitle: String {
        if calendar.isDateInToday(selectedDate) {
            return "Today's Macros"
        }
        let day = calendar.component(.day, from: selectedDate)
        let month = Self.monthFormatter.string(from: selectedDate)
        return "\(month) \(day)\(ordinalSuffix(for: day)) Macros"
    }

    private var macroSummaryCard: some View {
        let totals = viewModel.totals
        let caloriesRemaining = targets.calories - totals.calories
        let isOverCalories = caloriesRemaining < 0
        let showRemaining = macroDisplayMode == .remaining
        
        return CardContainer(isAccented: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(macroSummaryTitle)
                        .font(FitFont.body(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Spacer()
                    
                    // Toggle button for Remaining/Consumed
                    Picker("Display", selection: $macroDisplayMode) {
                        ForEach(MacroDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                
                // Calorie status banner - only show when over
                if targets.calories > 0 && isOverCalories {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                        
                        Text("Over by \(Int(abs(caloriesRemaining))) kcal")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(.red)
                            .contentTransition(.numericText())
                        
                        Spacer()
                        
                        Text("\(Int(totals.calories)) / \(Int(targets.calories))")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(alignment: .center, spacing: 20) {
                    MacroRingView(
                        title: "Calories",
                        value: totals.calories,
                        target: targets.calories,
                        unit: "kcal",
                        ringSize: 96,
                        displayMode: showRemaining ? .remaining : .consumed
                    )

                    VStack(spacing: 14) {
                        MacroRingView(
                            title: "Protein",
                            value: totals.protein,
                            target: targets.protein,
                            unit: "g",
                            ringSize: 64,
                            displayMode: showRemaining ? .remaining : .consumed
                        )
                        MacroRingView(
                            title: "Carbs",
                            value: totals.carbs,
                            target: targets.carbs,
                            unit: "g",
                            ringSize: 64,
                            displayMode: showRemaining ? .remaining : .consumed
                        )
                        MacroRingView(
                            title: "Fats",
                            value: totals.fats,
                            target: targets.fats,
                            unit: "g",
                            ringSize: 64,
                            displayMode: showRemaining ? .remaining : .consumed
                        )
                    }
                }
            }
        }
    }

    private var hasMealsLogged: Bool {
        viewModel.dailyMeals.values.flatMap { $0 }.isEmpty == false
    }

    private var emptyMealsCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Log your first meal")
                    .font(FitFont.body(size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                Text("Add a meal to start tracking your macros for this day.")
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)

                ActionButton(title: "Log Meal", style: .primary) {
                    isLogActionsPresented = true
                }
            }
        }
    }

    private var mealPlanCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Meal Plan")
                        .font(FitFont.body(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Spacer()

                    if let status = mealPlanStatus {
                        Text(status)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }

                    Button(action: { isMealPlanExpanded.toggle() }) {
                        Image(systemName: isMealPlanExpanded ? "chevron.up" : "chevron.down")
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                            .padding(6)
                            .background(FitTheme.cardHighlight)
                            .clipShape(Circle())
                    }
                }

                if isMealPlanExpanded, let plan = mealPlanSnapshot, !plan.meals.isEmpty {
                    ForEach(plan.meals) { meal in
                        Button {
                            selectedMealPlanMeal = meal
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(meal.name)
                                        .font(FitFont.body(size: 15))
                                        .foregroundColor(FitTheme.textPrimary)

                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(FitTheme.textSecondary)
                                }

                                Text("\(Int(meal.macros.calories)) kcal · P \(Int(meal.macros.protein)) · C \(Int(meal.macros.carbs)) · F \(Int(meal.macros.fats))")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)

                                if !meal.items.isEmpty {
                                    Text(meal.items.prefix(2).joined(separator: ", ") + (meal.items.count > 2 ? "..." : ""))
                                        .font(FitFont.body(size: 11))
                                        .foregroundColor(FitTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FitTheme.cardHighlight)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    if let totals = plan.totals {
                        Text("Total: \(Int(totals.calories)) kcal · P \(Int(totals.protein)) · C \(Int(totals.carbs)) · F \(Int(totals.fats))")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.accent)
                    }

                    if let notes = plan.notes, !notes.isEmpty {
                        Text(notes)
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                } else if isMealPlanExpanded {
                    Text("Generate a macro-focused plan tailored to your targets.")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }

                if isMealPlanExpanded {
                    ActionButton(title: "Generate Plan", style: .primary) {
                        Task {
                            await generateMealPlan()
                        }
                    }
                }
            }
        }
    }

    private func mealSectionCard(_ meal: MealType) -> some View {
        let items = viewModel.dailyMeals[meal, default: []]
        return CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(meal.title)
                        .font(FitFont.body(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Spacer()
                    
                    // Save as Meal button - only show if items exist
                    if !items.isEmpty {
                        Button {
                            mealToSave = (meal, items)
                            showSaveMealSheet = true
                        } label: {
                            Image(systemName: "bookmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(FitTheme.textSecondary)
                                .padding(8)
                                .background(FitTheme.cardHighlight)
                                .clipShape(Circle())
                        }
                    }

                    Button("Add") {
                        selectedMealType = meal
                        isLogSheetPresented = true
                    }
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.accent)
                }

                if items.isEmpty {
                    Text("No items logged yet.")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                } else {
                    ForEach(items) { item in
                        Button {
                            editingItem = (item: item, mealType: meal)
                            showEditFoodSheet = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(FitFont.body(size: 15))
                                        .foregroundColor(FitTheme.textPrimary)

                                    Text(item.detail)
                                        .font(FitFont.body(size: 12))
                                        .foregroundColor(FitTheme.textSecondary)
                                }
                                Spacer()
                                Text("\(Int(item.macros.calories)) kcal")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                                
                                // Edit indicator
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(FitTheme.textSecondary.opacity(0.5))
                            }
                            .padding(10)
                            .background(FitTheme.cardHighlight)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Meal total macros summary
                    let mealTotal = items.reduce(MacroTotals.zero) { $0.adding($1.macros) }
                    HStack(spacing: 12) {
                        Spacer()
                        Text("\(Int(mealTotal.calories)) kcal")
                            .font(FitFont.body(size: 12, weight: .semibold))
                            .foregroundColor(FitTheme.accent)
                        Text("P \(Int(mealTotal.protein))")
                            .font(FitFont.body(size: 11))
                            .foregroundColor(FitTheme.proteinColor)
                        Text("C \(Int(mealTotal.carbs))")
                            .font(FitFont.body(size: 11))
                            .foregroundColor(FitTheme.carbColor)
                        Text("F \(Int(mealTotal.fats))")
                            .font(FitFont.body(size: 11))
                            .foregroundColor(FitTheme.fatColor)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private var weekDates: [Date] {
        let start = startOfWeek(for: selectedDate)
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    private func startOfWeek(for date: Date) -> Date {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
            return interval.start
        }
        return calendar.startOfDay(for: date)
    }

    private func selectDate(_ date: Date) {
        let normalized = calendar.startOfDay(for: date)
        guard !calendar.isDate(normalized, inSameDayAs: selectedDate) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedDate = normalized
        }
    }

    private func handleWeekSwipe(_ value: DragGesture.Value) {
        let threshold: CGFloat = 40
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        if value.translation.width <= -threshold {
            shiftWeek(by: 1)
        } else if value.translation.width >= threshold {
            shiftWeek(by: -1)
        }
    }

    private func shiftWeek(by offset: Int) {
        guard let newDate = calendar.date(byAdding: .day, value: 7 * offset, to: selectedDate) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedDate = calendar.startOfDay(for: newDate)
        }
    }

    private func weekdaySymbol(for date: Date) -> String {
        Self.weekdayFormatter.string(from: date)
    }

    private func ordinalSuffix(for day: Int) -> String {
        let tens = (day / 10) % 10
        if tens == 1 {
            return "th"
        }
        switch day % 10 {
        case 1:
            return "st"
        case 2:
            return "nd"
        case 3:
            return "rd"
        default:
            return "th"
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        formatter.locale = Locale.current
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = Locale.current
        return formatter
    }()

    private func loadActiveMealPlan() async {
        guard !userId.isEmpty else { return }
        do {
            if let plan = try await NutritionAPIService.shared.fetchActiveMealPlan(userId: userId) {
                await MainActor.run {
                    mealPlanSnapshot = plan
                    mealPlanStatus = "Active"
                }
            }
        } catch {
            await MainActor.run {
                mealPlanStatus = "Unavailable"
            }
        }
    }

    private func loadTargets() async {
        guard !userId.isEmpty else { return }
        
        // First, try to load from local onboarding form as immediate fallback
        loadLocalMacroTargets()
        
        // Then try to fetch from server (will override if available)
        do {
            let profile = try await ProfileAPIService.shared.fetchProfile(userId: userId)
            if let macros = profile["macros"] as? [String: Any] {
                let totals = MacroTotals.fromDictionary(macros)
                if totals != .zero {
                    targets = MacroTargets(
                        calories: totals.calories,
                        protein: totals.protein,
                        carbs: totals.carbs,
                        fats: totals.fats
                    )
                }
            }
        } catch {
            // Keep local targets when profile fetch fails
        }
    }
    
    /// Load macro targets from locally saved onboarding form as fallback
    private func loadLocalMacroTargets() {
        guard let data = UserDefaults.standard.data(forKey: "fitai.onboarding.form"),
              let form = try? JSONDecoder().decode(OnboardingForm.self, from: data) else {
            return
        }
        
        let calories = Double(form.macroCalories) ?? 0
        let protein = Double(form.macroProtein) ?? 0
        let carbs = Double(form.macroCarbs) ?? 0
        let fats = Double(form.macroFats) ?? 0
        
        // Only apply if we have valid values
        if calories > 0 || protein > 0 || carbs > 0 || fats > 0 {
            targets = MacroTargets(
                calories: calories,
                protein: protein,
                carbs: carbs,
                fats: fats
            )
        }
    }

    private func generateMealPlan() async {
        guard !userId.isEmpty else { return }
        if targets.calories <= 0 {
            await MainActor.run {
                mealPlanStatus = "Set macros first"
            }
            return
        }
        await MainActor.run {
            mealPlanStatus = "Generating…"
        }
        do {
            let plan = try await NutritionAPIService.shared.generateMealPlan(
                userId: userId,
                targets: targets
            )
            await MainActor.run {
                mealPlanSnapshot = plan
                mealPlanStatus = "Updated"
            }
        } catch {
            await MainActor.run {
                mealPlanStatus = "Failed"
            }
        }
    }

    private func logMealPlanMeal(_ meal: MealPlanMeal) async {
        let mealType = mealType(from: meal.name)
        let item = LoggedFoodItem(
            name: meal.name,
            portionValue: 0,
            portionUnit: .grams,
            macros: meal.macros,
            detail: "Meal plan"
        )
        let success = await viewModel.logManualItem(item: item, mealType: mealType, date: selectedDate)
        if success {
            await loadActiveMealPlan()
        } else {
            await MainActor.run {
                mealPlanStatus = "Log failed"
            }
        }
    }
    
    private func regenerateMeal(_ meal: MealPlanMeal) async {
        guard !userId.isEmpty else { return }
        await MainActor.run {
            isRegeneratingMeal = true
        }
        
        // Re-generate the entire meal plan (API doesn't support single meal regeneration yet)
        // In the future, this could call a specific endpoint
        do {
            let plan = try await NutritionAPIService.shared.generateMealPlan(
                userId: userId,
                targets: targets
            )
            await MainActor.run {
                mealPlanSnapshot = plan
                mealPlanStatus = "Updated"
                isRegeneratingMeal = false
                selectedMealPlanMeal = nil
            }
        } catch {
            await MainActor.run {
                mealPlanStatus = "Regenerate failed"
                isRegeneratingMeal = false
            }
        }
    }
    
    private func updateMealPlanMeal(_ updatedMeal: MealPlanMeal) {
        guard var plan = mealPlanSnapshot else { return }
        
        // Find and update the meal in the plan
        if let index = plan.meals.firstIndex(where: { $0.id == updatedMeal.id }) {
            plan.meals[index] = updatedMeal
            mealPlanSnapshot = plan
            selectedMealPlanMeal = updatedMeal
            mealPlanStatus = "Meal updated"
        }
    }

    private func showLoggedToastMessage() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showLoggedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showLoggedToast = false
            }
        }
    }

    private func mealType(from name: String) -> MealType {
        let lower = name.lowercased()
        if lower.contains("breakfast") { return .breakfast }
        if lower.contains("lunch") { return .lunch }
        if lower.contains("dinner") { return .dinner }
        if lower.contains("snack") { return .snacks }
        return .lunch
    }
}

private struct NutritionHistoryView: View {
    let userId: String

    @StateObject private var viewModel: NutritionViewModel
    @Binding private var selectedDate: Date

    @Environment(\.dismiss) private var dismiss

    init(userId: String, selectedDate: Binding<Date>) {
        self.userId = userId
        _selectedDate = selectedDate
        _viewModel = StateObject(wrappedValue: NutritionViewModel(userId: userId))
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private var dateSelection: Binding<Date> {
        Binding(
            get: { selectedDate },
            set: { selectedDate = calendar.startOfDay(for: $0) }
        )
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    header
                    
                    // Calendar card
                    calendarCard
                    
                    // Summary card
                    historySummaryCard

                    // Meal cards
                    ForEach(MealType.allCases) { meal in
                        historyMealCard(meal)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        errorCard(errorMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .task {
            await viewModel.loadDailyLogs(date: selectedDate)
        }
        .onChange(of: selectedDate) { newValue in
            Task {
                await viewModel.loadDailyLogs(date: newValue)
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
                        .fill(FitTheme.cardNutritionAccent.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "calendar")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(FitTheme.cardNutritionAccent)
                }
                
                Text("Nutrition History")
                    .font(FitFont.heading(size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(FitTheme.textPrimary)
                
                Text("View your past meals and macros")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }
    
    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardNutritionAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Date")
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    Text(formattedDate)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            
            DatePicker("Select date", selection: dateSelection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(FitTheme.cardNutritionAccent)
                .environment(\.colorScheme, .light)
        }
        .padding(18)
        .background(FitTheme.cardNutrition)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardNutritionAccent.opacity(0.2), lineWidth: 1)
        )
    }

    private var historySummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.cardProgressAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text("Daily Summary")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
            }
            
            let totals = viewModel.totals
            HStack(spacing: 12) {
                macroSummaryItem(value: Int(totals.calories), label: "kcal", color: FitTheme.accent)
                macroSummaryItem(value: Int(totals.protein), label: "protein", color: FitTheme.proteinColor)
                macroSummaryItem(value: Int(totals.carbs), label: "carbs", color: FitTheme.carbColor)
                macroSummaryItem(value: Int(totals.fats), label: "fats", color: FitTheme.fatColor)
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
    
    private func macroSummaryItem(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(FitFont.heading(size: 18))
                .foregroundColor(color)
            Text(label)
                .font(FitFont.body(size: 11))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func historyMealCard(_ meal: MealType) -> some View {
        let items = viewModel.dailyMeals[meal, default: []]
        let mealColor = mealAccentColor(for: meal)
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: mealIcon(for: meal))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(mealColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.title)
                        .font(FitFont.heading(size: 18))
                        .foregroundColor(FitTheme.textPrimary)
                    if !items.isEmpty {
                        let totalCals = items.reduce(0) { $0 + Int($1.macros.calories) }
                        Text("\(items.count) items • \(totalCals) kcal")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                
                Spacer()
                
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(mealColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(mealColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "fork.knife")
                        .foregroundColor(FitTheme.textSecondary.opacity(0.5))
                    Text("No items logged")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FitTheme.cardHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(FitFont.body(size: 14, weight: .medium))
                                    .foregroundColor(FitTheme.textPrimary)
                                    .lineLimit(1)
                                Text(item.detail)
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(Int(item.macros.calories))")
                                .font(FitFont.body(size: 14, weight: .semibold))
                                .foregroundColor(mealColor)
                            + Text(" kcal")
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
        .padding(18)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardStroke.opacity(0.5), lineWidth: 1)
        )
    }
    
    private func mealIcon(for meal: MealType) -> String {
        switch meal {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snacks: return "leaf.fill"
        }
    }
    
    private func mealAccentColor(for meal: MealType) -> Color {
        switch meal {
        case .breakfast: return FitTheme.cardReminderAccent
        case .lunch: return FitTheme.cardProgressAccent
        case .dinner: return FitTheme.cardWorkoutAccent
        case .snacks: return FitTheme.cardNutritionAccent
        }
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
}

private struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(FitFont.body(size: 13))
            .foregroundColor(FitTheme.textPrimary)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(FitTheme.cardBackground)
            .clipShape(Capsule())
            .shadow(color: FitTheme.shadow, radius: 8, x: 0, y: 4)
    }
}

private struct MacroRingView: View {
    enum DisplayMode {
        case remaining
        case consumed
    }
    
    let title: String
    let value: Double
    let target: Double
    let unit: String
    let ringSize: CGFloat
    var displayMode: DisplayMode = .remaining

    private var isOver: Bool {
        guard target > 0 else { return false }
        return value > target
    }
    
    private var remaining: Double {
        max(target - value, 0)
    }
    
    private var overAmount: Double {
        max(value - target, 0)
    }
    
    // For consumed mode: ring fills up as you consume
    // For remaining mode: ring starts full and depletes as you consume
    private var ringProgress: Double {
        guard target > 0 else { return 0 }
        switch displayMode {
        case .consumed:
            // Fill up based on consumption (0 -> 1)
            return min(value / target, 1.0)
        case .remaining:
            // Deplete based on consumption (1 -> 0)
            // If over, show full ring in red
            if isOver { return 1.0 }
            return max((target - value) / target, 0)
        }
    }
    
    private var ringColor: Color {
        if isOver {
            return Color.red.opacity(0.85)
        }
        return FitTheme.macroColor(for: title)
    }
    
    private var displayValue: Int {
        switch displayMode {
        case .consumed:
            return Int(value)
        case .remaining:
            return isOver ? Int(overAmount) : Int(remaining)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(FitTheme.cardHighlight, lineWidth: 8)

                // Progress ring
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: ringProgress)

                // Center value
                VStack(spacing: 2) {
                    Text(isOver && displayMode == .remaining ? "+\(displayValue)" : "\(displayValue)")
                        .font(FitFont.body(size: ringSize > 80 ? 18 : 13))
                        .fontWeight(.semibold)
                        .foregroundColor(isOver ? .red : FitTheme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: displayValue)

                    Text(unit)
                        .font(FitFont.body(size: ringSize > 80 ? 11 : 9))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            .frame(width: ringSize, height: ringSize)

            Text(title)
                .font(FitFont.body(size: 11))
                .foregroundColor(FitTheme.textSecondary)
            
            // Show status text for larger rings only when over
            if ringSize > 80 && target > 0 && isOver {
                Text("\(Int(overAmount))\(unit) over")
                    .font(FitFont.body(size: 10))
                    .foregroundColor(.red)
                    .contentTransition(.opacity)
            }
        }
    }
}

private struct NutritionLogSheet: View {
    @ObservedObject var viewModel: NutritionViewModel
    let mealType: MealType
    let logDate: Date
    let showBarcodeOnAppear: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [FoodItem] = []
    @State private var isSearching = false
    @State private var selectedItem: FoodItem?
    @State private var portionValue: String = "1"
    @State private var portionUnit: PortionUnit = .serving
    @State private var selectedServingOption: ServingOption?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isSavingFavorite = false
    @State private var saveMessage: String?
    @State private var activeMealType: MealType
    @State private var isBarcodeScannerPresented = false
    @State private var hasPresentedBarcode = false
    @State private var autocompleteSuggestions: [String] = []
    @State private var isLoadingAutocomplete = false
    @State private var showAutocomplete = false
    @State private var autocompleteTask: Task<Void, Never>?
    @State private var isServingSizePickerPresented = false
    @State private var numberOfServings: Double = 1.0
    @State private var numberOfServingsText: String = "1"
    @FocusState private var isSearchFocused: Bool

    init(
        viewModel: NutritionViewModel,
        mealType: MealType,
        logDate: Date,
        showBarcodeOnAppear: Bool = false
    ) {
        self.viewModel = viewModel
        self.mealType = mealType
        self.logDate = logDate
        self.showBarcodeOnAppear = showBarcodeOnAppear
        _activeMealType = State(initialValue: mealType)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()
                    .onTapGesture {
                        isSearchFocused = false
                        showAutocomplete = false
                    }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        headerSection
                        
                        // Meal Type Pills
                        mealTypePills
                        
                        // Search Card
                        searchCard
                        
                        // Content
                        if let selectedItem {
                            selectedFoodCard(selectedItem)
                        } else {
                            resultsList
                        }

                        if let errorMessage {
                            errorCard(errorMessage)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(10)
                            .background(FitTheme.cardBackground)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
                            )
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Log Food")
                        .font(FitFont.heading(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isBarcodeScannerPresented = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(FitTheme.cardNutritionAccent)
                            .padding(10)
                            .background(FitTheme.cardNutrition)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(FitTheme.cardNutritionAccent.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $isBarcodeScannerPresented) {
            BarcodeScannerView(
                onFound: { code in
                    isBarcodeScannerPresented = false
                    Task {
                        await lookupBarcode(code)
                    }
                },
                onError: { message in
                    isBarcodeScannerPresented = false
                    errorMessage = message
                }
            )
        }
        .onAppear {
            if showBarcodeOnAppear, !hasPresentedBarcode {
                hasPresentedBarcode = true
                isBarcodeScannerPresented = true
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Log \(activeMealType.title)")
                .font(FitFont.heading(size: 28))
                .fontWeight(.bold)
                .foregroundColor(FitTheme.textPrimary)
            
            Text("Search or scan to add foods")
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
        }
    }
    
    // MARK: - Meal Type Pills
    
    private var mealTypePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(MealType.allCases) { meal in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeMealType = meal
                        }
                        Haptics.light()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mealIcon(for: meal))
                                .font(.system(size: 12, weight: .medium))
                            Text(meal.title)
                                .font(FitFont.body(size: 14, weight: .medium))
                        }
                        .foregroundColor(activeMealType == meal ? FitTheme.buttonText : FitTheme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            activeMealType == meal 
                                ? AnyShapeStyle(FitTheme.primaryGradient)
                                : AnyShapeStyle(FitTheme.cardBackground)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(activeMealType == meal ? Color.clear : FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
                        )
                        .shadow(color: activeMealType == meal ? FitTheme.buttonShadow : .clear, radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func mealIcon(for meal: MealType) -> String {
        switch meal {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .snacks: return "leaf.fill"
        }
    }
    
    // MARK: - Search Card
    
    private var searchCard: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSearchFocused ? FitTheme.cardNutritionAccent : FitTheme.textSecondary)
                
                TextField("Search foods...", text: $query)
                    .textFieldStyle(.plain)
                    .font(FitFont.body(size: 16))
                    .foregroundColor(FitTheme.textPrimary)
                    .focused($isSearchFocused)
                    .onChange(of: query) { newValue in
                        fetchAutocomplete(for: newValue)
                    }
                    .onSubmit {
                        showAutocomplete = false
                        isSearchFocused = false
                        Task { await runSearch() }
                    }
                
                if isSearching {
                    ProgressView()
                        .tint(FitTheme.cardNutritionAccent)
                        .scaleEffect(0.9)
                } else if isLoadingAutocomplete {
                    ProgressView()
                        .tint(FitTheme.textSecondary)
                        .scaleEffect(0.7)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                        showAutocomplete = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                
                Button {
                    showAutocomplete = false
                    isSearchFocused = false
                    Task { await runSearch() }
                } label: {
                    Text("Search")
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.buttonText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(FitTheme.primaryGradient)
                        .clipShape(Capsule())
                }
                .opacity(query.isEmpty ? 0.5 : 1)
                .disabled(query.isEmpty)
            }
            .padding(16)
            .background(FitTheme.cardNutrition)
            .clipShape(RoundedRectangle(cornerRadius: showAutocomplete && !autocompleteSuggestions.isEmpty ? 20 : 24, style: .continuous))
            
            // Autocomplete dropdown
            if showAutocomplete && !autocompleteSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(autocompleteSuggestions.enumerated()), id: \.element) { index, suggestion in
                        Button {
                            query = suggestion
                            showAutocomplete = false
                            isSearchFocused = false
                            Task { await runSearch() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(FitTheme.cardNutritionAccent)
                                
                                Text(suggestion)
                                    .font(FitFont.body(size: 15))
                                    .foregroundColor(FitTheme.textPrimary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 11))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                index % 2 == 0 
                                    ? FitTheme.cardNutrition 
                                    : FitTheme.cardNutrition.opacity(0.7)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        if index < autocompleteSuggestions.count - 1 {
                            Divider()
                                .background(FitTheme.cardNutritionAccent.opacity(0.15))
                                .padding(.leading, 44)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(FitTheme.cardNutritionAccent.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: FitTheme.cardNutritionAccent.opacity(0.15), radius: 12, x: 0, y: 6)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isSearchFocused ? FitTheme.cardNutritionAccent.opacity(0.5) : FitTheme.cardNutritionAccent.opacity(0.25),
                    lineWidth: isSearchFocused ? 2 : 1
                )
                .allowsHitTesting(false)
        )
        .shadow(color: FitTheme.cardNutritionAccent.opacity(0.12), radius: 18, x: 0, y: 10)
        .animation(.easeInOut(duration: 0.2), value: showAutocomplete)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }
    
    private func fetchAutocomplete(for text: String) {
        autocompleteTask?.cancel()
        
        guard text.count >= 2 else {
            autocompleteSuggestions = []
            showAutocomplete = false
            return
        }
        
        autocompleteTask = Task {
            // Debounce: wait 250ms before fetching
            try? await Task.sleep(nanoseconds: 250_000_000)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run { isLoadingAutocomplete = true }
            
            do {
                let suggestions = try await NutritionAPIService.shared.autocompleteFoods(query: text, maxResults: 6)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    autocompleteSuggestions = suggestions
                    showAutocomplete = !suggestions.isEmpty && isSearchFocused
                    isLoadingAutocomplete = false
                }
            } catch {
                await MainActor.run {
                    isLoadingAutocomplete = false
                }
            }
        }
    }
    
    // MARK: - Error Card
    
    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)
            
            Text(message)
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
            
            Spacer()
        }
        .padding(16)
        .background(FitTheme.cardReminder)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardReminderAccent.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Results List
    
    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !results.isEmpty {
                Text("Results")
                    .font(FitFont.body(size: 13, weight: .medium))
                    .foregroundColor(FitTheme.textSecondary)
                    .padding(.leading, 4)
            }
            
            ForEach(results) { item in
                Button {
                    selectedItem = item
                    applyDefaultServing(for: item)
                    Haptics.light()
                } label: {
                    HStack(spacing: 14) {
                        // Food icon
                        ZStack {
                            Circle()
                                .fill(FitTheme.cardNutritionAccent.opacity(0.15))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "fork.knife")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(FitTheme.cardNutritionAccent)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(FitFont.body(size: 15, weight: .medium))
                                .foregroundColor(FitTheme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            HStack(spacing: 8) {
                                Text("\(Int(item.calories)) cal")
                                    .font(FitFont.body(size: 12, weight: .semibold))
                                    .foregroundColor(FitTheme.cardNutritionAccent)
                                
                                Text("•")
                                    .foregroundColor(FitTheme.textSecondary)
                                
                                Text("P \(Int(item.protein))g")
                                    .foregroundColor(FitTheme.proteinColor)
                                
                                Text("C \(Int(item.carbs))g")
                                    .foregroundColor(FitTheme.carbColor)
                                
                                Text("F \(Int(item.fats))g")
                                    .foregroundColor(FitTheme.fatColor)
                            }
                            .font(FitFont.body(size: 11))
                            
                            if let serving = item.serving, !serving.isEmpty {
                                Text(serving)
                                    .font(FitFont.body(size: 11))
                                    .foregroundColor(FitTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(FitTheme.cardNutritionAccent)
                    }
                    .padding(14)
                    .background(FitTheme.cardNutrition)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(FitTheme.cardNutritionAccent.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: FitTheme.cardNutritionAccent.opacity(0.08), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }

            if results.isEmpty && !query.isEmpty && !isSearching {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(FitTheme.textSecondary.opacity(0.5))
                    
                    Text("No results found")
                        .font(FitFont.body(size: 16, weight: .medium))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Text("Try a different search term")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
            
            if results.isEmpty && query.isEmpty && !isSearching {
                VStack(spacing: 16) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(FitTheme.cardNutritionAccent.opacity(0.4))
                    
                    Text("Search for foods")
                        .font(FitFont.body(size: 16, weight: .medium))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Text("Type a food name above or scan a barcode")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
            }
        }
    }

    // MARK: - Selected Food Card
    
    private func selectedFoodCard(_ item: FoodItem) -> some View {
        let servingOptions = item.parsedServingOptions
        
        // Current macros based on selection and number of servings
        let displayMacros: MacroTotals = {
            let baseQty = Double(portionValue) ?? 1.0
            let qty = baseQty * numberOfServings
            if let serving = selectedServingOption {
                return serving.macros(quantity: qty)
            } else if portionUnit == .grams {
                let multiplier = qty / 100.0
                return MacroTotals(
                    calories: item.calories * multiplier,
                    protein: item.protein * multiplier,
                    carbs: item.carbs * multiplier,
                    fats: item.fats * multiplier
                )
            } else if portionUnit == .ounces {
                let grams = qty * 28.3495
                let multiplier = grams / 100.0
                return MacroTotals(
                    calories: item.calories * multiplier,
                    protein: item.protein * multiplier,
                    carbs: item.carbs * multiplier,
                    fats: item.fats * multiplier
                )
            } else {
                return MacroTotals(
                    calories: item.calories * qty,
                    protein: item.protein * qty,
                    carbs: item.carbs * qty,
                    fats: item.fats * qty
                )
            }
        }()
        
        // Display text for current serving
        let servingDisplayText: String = {
            if let serving = selectedServingOption {
                return serving.description
            } else if portionUnit == .grams {
                return "\(portionValue) g"
            } else if portionUnit == .ounces {
                return "\(portionValue) oz"
            } else {
                return "1 serving"
            }
        }()
        
        return VStack(alignment: .leading, spacing: 16) {
            // Back button row
            Button {
                selectedItem = nil
                selectedServingOption = nil
                numberOfServings = 1.0
                numberOfServingsText = "1"
                portionValue = "1"
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back to results")
                        .font(FitFont.body(size: 14))
                }
                .foregroundColor(FitTheme.textSecondary)
            }
            
            // Food Header Card
            VStack(alignment: .leading, spacing: 16) {
                // Food name and brand
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(FitFont.heading(size: 22))
                        .fontWeight(.bold)
                        .foregroundColor(FitTheme.textPrimary)
                    
                    if let serving = item.serving, !serving.isEmpty {
                        Text(serving)
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                
                // Quick macro overview
                HStack(spacing: 0) {
                    macroChip(value: displayMacros.calories, label: "cal", color: FitTheme.cardNutritionAccent)
                    Spacer()
                    macroChip(value: displayMacros.protein, label: "protein", color: FitTheme.proteinColor)
                    Spacer()
                    macroChip(value: displayMacros.carbs, label: "carbs", color: FitTheme.carbColor)
                    Spacer()
                    macroChip(value: displayMacros.fats, label: "fat", color: FitTheme.fatColor)
                }
            }
            .padding(18)
            .background(FitTheme.cardNutrition)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(FitTheme.cardNutritionAccent.opacity(0.25), lineWidth: 1.5)
            )
            .shadow(color: FitTheme.cardNutritionAccent.opacity(0.12), radius: 18, x: 0, y: 10)
            
            // Serving controls card
            VStack(spacing: 0) {
                // Serving Size row
                HStack {
                    Text("Serving Size")
                        .font(FitFont.body(size: 15))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Spacer()
                    
                    Button {
                        isServingSizePickerPresented = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(servingDisplayText)
                                .font(FitFont.body(size: 15, weight: .medium))
                                .foregroundColor(FitTheme.textPrimary)
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(FitTheme.cardNutritionAccent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(FitTheme.cardNutrition)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FitTheme.cardNutritionAccent.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(16)
                
                Divider()
                    .background(FitTheme.cardStroke)
                
                // Number of Servings row
                HStack {
                    Text("Number of Servings")
                        .font(FitFont.body(size: 15))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Spacer()
                    
                    HStack(spacing: 0) {
                        Button {
                            let step = 0.25
                            if numberOfServings > step {
                                updateNumberOfServings(max(step, numberOfServings - step))
                                Haptics.light()
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(FitTheme.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(FitTheme.cardHighlight)
                        }
                        
                        TextField("1", text: $numberOfServingsText)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.plain)
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(width: 50, height: 40)
                        .background(FitTheme.cardBackground)
                        .onChange(of: numberOfServingsText) { newValue in
                            if let value = parseServingInput(newValue), value > 0 {
                                numberOfServings = value
                            }
                        }
                        
                        Button {
                            updateNumberOfServings(numberOfServings + 0.25)
                            Haptics.light()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(FitTheme.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(FitTheme.cardHighlight)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FitTheme.cardStroke, lineWidth: 1)
                    )
                }
                .padding(16)
                
                Divider()
                    .background(FitTheme.cardStroke)
                
                // Meal selector row
                HStack {
                    Text("Log to")
                        .font(FitFont.body(size: 15))
                        .foregroundColor(FitTheme.textSecondary)
                    
                    Spacer()
                    
                    Menu {
                        ForEach(MealType.allCases) { meal in
                            Button {
                                activeMealType = meal
                            } label: {
                                HStack {
                                    Image(systemName: mealIcon(for: meal))
                                    Text(meal.title)
                                    if activeMealType == meal {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mealIcon(for: activeMealType))
                                .font(.system(size: 12))
                            Text(activeMealType.title)
                                .font(FitFont.body(size: 15, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(FitTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(FitTheme.cardNutrition)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FitTheme.cardNutritionAccent.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: FitTheme.shadow, radius: 18, x: 0, y: 10)
            
            // Action buttons
            HStack(spacing: 12) {
                // Save to favorites
                Button {
                    Task {
                        await saveFavorite(item)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSavingFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 14))
                        Text(isSavingFavorite ? "Saving..." : "Favorite")
                            .font(FitFont.body(size: 14, weight: .medium))
                    }
                    .foregroundColor(FitTheme.cardNutritionAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(FitTheme.cardNutrition)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(FitTheme.cardNutritionAccent.opacity(0.3), lineWidth: 1)
                    )
                }
                .disabled(isSavingFavorite)
                
                // Log button
                Button {
                    Task {
                        await addItem(item)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text(isSubmitting ? "Logging..." : "Log Food")
                            .font(FitFont.body(size: 15, weight: .semibold))
                    }
                    .foregroundColor(FitTheme.buttonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: FitTheme.buttonShadow, radius: 12, x: 0, y: 6)
                }
                .disabled(isSubmitting)
            }

            if let saveMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(FitTheme.success)
                    Text(saveMessage)
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.success)
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $isServingSizePickerPresented) {
            ServingSizePickerSheet(
                item: item,
                selectedServingOption: $selectedServingOption,
                portionUnit: $portionUnit,
                portionValue: $portionValue,
                onDismiss: {
                    isServingSizePickerPresented = false
                }
            )
        }
        .onAppear {
            if selectedServingOption == nil {
                applyDefaultServing(for: item)
            }
        }
    }
    
    private func macroChip(value: Double, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(value))")
                .font(FitFont.heading(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(FitFont.body(size: 11))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    // MARK: - Helper Functions

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        autocompleteTask?.cancel()
        await MainActor.run {
            showAutocomplete = false
            autocompleteSuggestions = []
            isSearching = true
            errorMessage = nil
        }
        
        do {
            let items = try await NutritionAPIService.shared.searchFoods(query: trimmed, userId: viewModel.userId)
            await MainActor.run {
                results = items
                isSearching = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Unable to search foods. Please try again."
                isSearching = false
            }
        }
    }

    private func lookupBarcode(_ code: String) async {
        guard !code.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        do {
            let item = try await NutritionAPIService.shared.fetchFoodByBarcode(
                code: code,
                userId: viewModel.userId
            )
            await MainActor.run {
                selectedItem = item
                applyDefaultServing(for: item)
                results = []
                isSearching = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Unable to find a match for that barcode."
                isSearching = false
            }
        }
    }

    private func updateNumberOfServings(_ value: Double) {
        let clamped = max(0.01, value)
        numberOfServings = clamped
        numberOfServingsText = formattedServingValue(clamped)
    }

    private func applyDefaultServing(for item: FoodItem) {
        let options = item.parsedServingOptions
        if let defaultOption = defaultServingOption(for: item, options: options) {
            selectedServingOption = defaultOption
            portionUnit = .serving
            portionValue = "1"
        } else if let serving = item.serving,
                  let parsed = parsedServingValueAndUnit(from: serving) {
            selectedServingOption = nil
            switch parsed.unit {
            case "g", "gram", "grams":
                portionUnit = .grams
                portionValue = formattedServingValue(parsed.value)
            case "oz", "ounce", "ounces":
                portionUnit = .ounces
                portionValue = formattedServingValue(parsed.value)
            default:
                portionUnit = .serving
                portionValue = "1"
            }
        } else {
            selectedServingOption = nil
            portionUnit = .serving
            portionValue = "1"
        }
        numberOfServings = 1
        numberOfServingsText = "1"
    }

    private func formattedServingValue(_ value: Double, maxFractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func parseServingInput(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/").map { String($0) }
            if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 {
                return numerator / denominator
            }
            return nil
        }
        return Double(trimmed)
    }

    private func addItem(_ item: FoodItem) async {
        let basePortionValue = Double(portionValue) ?? 1.0
        let totalPortion = basePortionValue * numberOfServings
        guard totalPortion > 0 else { return }
        
        let macros: MacroTotals
        let detail: String
        
        if let serving = selectedServingOption {
            macros = serving.macros(quantity: totalPortion)
            if numberOfServings == 1 {
                detail = serving.description
            } else {
                let servingsText = formattedServingValue(numberOfServings)
                detail = "\(servingsText) × \(serving.description)"
            }
        } else if portionUnit == .grams {
            let multiplier = totalPortion / 100.0
            macros = MacroTotals(
                calories: item.calories * multiplier,
                protein: item.protein * multiplier,
                carbs: item.carbs * multiplier,
                fats: item.fats * multiplier
            )
            let gramsText = formattedServingValue(totalPortion)
            detail = "\(gramsText) g"
        } else {
            let grams = totalPortion * 28.3495
            let multiplier = grams / 100.0
            macros = MacroTotals(
                calories: item.calories * multiplier,
                protein: item.protein * multiplier,
                carbs: item.carbs * multiplier,
                fats: item.fats * multiplier
            )
            let ozText = formattedServingValue(totalPortion)
            detail = "\(ozText) oz"
        }

        let loggedItem = LoggedFoodItem(
            name: item.name,
            portionValue: totalPortion,
            portionUnit: portionUnit,
            macros: macros,
            detail: detail
        )
        isSubmitting = true
        let success = await viewModel.logManualItem(item: loggedItem, mealType: activeMealType, date: logDate)
        isSubmitting = false
        if success {
            Haptics.success()
            dismiss()
        } else {
            errorMessage = "Unable to log item."
        }
    }

    private func saveFavorite(_ item: FoodItem) async {
        guard !viewModel.userId.isEmpty else { return }
        isSavingFavorite = true
        saveMessage = nil
        do {
            try await NutritionAPIService.shared.saveFavorite(userId: viewModel.userId, food: item)
            await MainActor.run {
                saveMessage = "Saved to favorites"
                Haptics.success()
                isSavingFavorite = false
            }
        } catch {
            await MainActor.run {
                saveMessage = "Unable to save favorite"
                isSavingFavorite = false
            }
        }
    }
}

private func normalizedServingKey(_ text: String) -> String {
    let scalars = text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
    return String(String.UnicodeScalarView(scalars))
}

private func parsedServingValueAndUnit(from text: String) -> (value: Double, unit: String)? {
    let trimmed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    var numberChars = ""
    var unitChars = ""
    var hasNumber = false
    for scalar in trimmed.unicodeScalars {
        if CharacterSet.decimalDigits.contains(scalar) || scalar == "." {
            numberChars.append(Character(scalar))
            hasNumber = true
            continue
        }
        if hasNumber {
            if CharacterSet.letters.contains(scalar) {
                unitChars.append(Character(scalar))
            } else if !unitChars.isEmpty {
                break
            }
        }
    }
    guard let value = Double(numberChars), !unitChars.isEmpty else { return nil }
    return (value, unitChars)
}

private func servingGrams(from text: String) -> Double? {
    guard let parsed = parsedServingValueAndUnit(from: text) else { return nil }
    switch parsed.unit {
    case "g", "gram", "grams":
        return parsed.value
    case "oz", "ounce", "ounces":
        return parsed.value * 28.3495
    default:
        return nil
    }
}

private func isWeightBasedDescription(_ text: String) -> Bool {
    let lowered = text.lowercased()
    return lowered.contains(" g")
        || lowered.contains("gram")
        || lowered.contains(" oz")
        || lowered.contains("ounce")
        || lowered.contains(" ml")
        || lowered.contains("milliliter")
        || lowered.contains("kg")
        || lowered.contains("lb")
        || lowered.contains("pound")
}

private func defaultServingOption(for item: FoodItem, options: [ServingOption]) -> ServingOption? {
    guard !options.isEmpty else { return nil }
    let trimmedServing = item.serving?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let serving = trimmedServing, !serving.isEmpty {
        if isWeightBasedDescription(serving),
           let naturalOption = options.first(where: { !isWeightBasedDescription($0.description) }) {
            return naturalOption
        }
        let servingKey = normalizedServingKey(serving)
        if let exactMatch = options.first(where: { normalizedServingKey($0.description) == servingKey }) {
            return exactMatch
        }
        if let containsMatch = options.first(where: {
            let optionKey = normalizedServingKey($0.description)
            return optionKey.contains(servingKey) || servingKey.contains(optionKey)
        }) {
            return containsMatch
        }
        if let servingGrams = servingGrams(from: serving) {
            let tolerance = max(0.5, servingGrams * 0.02)
            if let metricMatch = options
                .compactMap({ option -> (ServingOption, Double)? in
                    guard let grams = option.metricGrams else { return nil }
                    return (option, abs(grams - servingGrams))
                })
                .filter({ $0.1 <= tolerance })
                .sorted(by: { $0.1 < $1.1 })
                .first {
                return metricMatch.0
            }
        }
    }
    if let naturalOption = options.first(where: { !isWeightBasedDescription($0.description) }) {
        return naturalOption
    }
    return options.first
}

private struct ScanFoodCameraView: View {
    let userId: String
    let mealType: MealType
    let logDate: Date
    let onLogged: () -> Void

    @Environment(\.dismiss) private var dismiss

    @StateObject private var camera = MealPhotoCameraModel()
    @State private var scanMode: ScanMode = .photo
    @State private var selectedItem: PhotosPickerItem?
    @State private var scanResult: MealPhotoScanResult?
    @State private var matchedFoods: [FoodItem] = []
    @State private var unmatchedItems: [String] = []
    @State private var isSearchingMacros = false
    @State private var isSubmitting = false
    @State private var isLogging = false
    @State private var activeMealType: MealType
    @State private var errorMessage: String?
    @State private var hasScannedBarcode = false
    @State private var barcodeSessionId = UUID()
    @State private var showHelp = false

    init(userId: String, mealType: MealType, logDate: Date, onLogged: @escaping () -> Void) {
        self.userId = userId
        self.mealType = mealType
        self.logDate = logDate
        self.onLogged = onLogged
        _activeMealType = State(initialValue: mealType)
    }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack {
                topBar

                Spacer()

                if let scanResult {
                    scanResultCard(scanResult)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                bottomPanel
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            camera.requestAccess()
            if scanMode == .photo {
                camera.start()
            }
        }
        .onChange(of: camera.isAuthorized) { isAuthorized in
            if isAuthorized && scanMode == .photo {
                camera.start()
            }
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: scanMode) { newValue in
            scanResult = nil
            matchedFoods = []
            unmatchedItems = []
            isSearchingMacros = false
            errorMessage = nil
            hasScannedBarcode = false
            if newValue == .barcode {
                barcodeSessionId = UUID()
            }
            if newValue == .photo {
                camera.start()
            } else {
                camera.stop()
            }
        }
        .onChange(of: selectedItem) { newValue in
            guard let newValue else { return }
            Task {
                scanResult = nil
                matchedFoods = []
                unmatchedItems = []
                isSearchingMacros = false
                errorMessage = nil
                isSubmitting = true
                do {
                    if let data = try await newValue.loadTransferable(type: Data.self) {
                        await submit(imageData: data)
                    } else {
                        errorMessage = "Unable to load photo."
                        isSubmitting = false
                    }
                } catch {
                    errorMessage = "Unable to load photo."
                    isSubmitting = false
                }
            }
        }
        .alert("How to scan", isPresented: $showHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Keep the meal centered and well-lit for best results.")
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            if scanMode == .photo {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else if scanMode == .barcode {
                BarcodeScannerView(
                    onFound: { code in
                        guard !hasScannedBarcode else { return }
                        hasScannedBarcode = true
                        Task {
                            await handleBarcode(code)
                        }
                    },
                    onError: { message in
                        errorMessage = message
                    }
                )
                .id(barcodeSessionId)
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [12]))
                .padding(.horizontal, 40)
                .padding(.vertical, 160)
                .opacity(scanMode == .photo ? 1 : 0)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.buttonText)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }

            Spacer()

            Text("Scan Food")
                .font(FitFont.body(size: 18))
                .foregroundColor(FitTheme.buttonText)

            Spacer()

            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.buttonText)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            Text(instructionText)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.buttonText.opacity(0.8))

            modePicker

            HStack {
                Button {
                    camera.toggleTorch()
                } label: {
                    Image(systemName: camera.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(FitTheme.buttonText)
                        .frame(width: 42, height: 42)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .disabled(scanMode != .photo)

                Spacer()

                Button {
                    capturePhoto()
                } label: {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 68, height: 68)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.6), lineWidth: 3)
                                .frame(width: 80, height: 80)
                        )
                }
                .disabled(scanMode != .photo || !camera.isAuthorized)

                Spacer()

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(FitTheme.buttonText)
                        .frame(width: 42, height: 42)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .disabled(scanMode != .photo)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.buttonText.opacity(0.8))
            } else if let cameraError = camera.errorMessage {
                Text(cameraError)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.buttonText.opacity(0.8))
            } else if isSubmitting {
                AnalyzingIndicator()
            }
        }
        .padding(18)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(ScanMode.allCases) { mode in
                Button {
                    scanMode = mode
                } label: {
                    Text(mode.title)
                        .font(FitFont.body(size: 12))
                        .foregroundColor(scanMode == mode ? .black : FitTheme.buttonText.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(scanMode == mode ? Color.white : Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }

    private var instructionText: String {
        switch scanMode {
        case .photo:
            return "Fit the entire meal in the frame."
        case .barcode:
            return "Center the barcode in the frame."
        case .label:
            return "Label scan is in beta."
        }
    }

    private func capturePhoto() {
        guard scanMode == .photo else { return }
        guard camera.isAuthorized else {
            errorMessage = "Camera access is required to scan food."
            return
        }
        scanResult = nil
        matchedFoods = []
        unmatchedItems = []
        isSearchingMacros = false
        errorMessage = nil
        isSubmitting = true
        camera.capturePhoto { data, _ in
            Task {
                await submit(imageData: data)
            }
        }
    }

    private func submit(imageData: Data) async {
        do {
            let response = try await NutritionAPIService.shared.scanMealPhoto(
                userId: userId,
                mealType: activeMealType.rawValue,
                imageData: imageData
            )
            await MainActor.run {
                scanResult = response
                matchedFoods = []
                unmatchedItems = []
                isSearchingMacros = false
                isSubmitting = false
            }
            await lookupMacros(for: response)
        } catch {
            await MainActor.run {
                errorMessage = "Scan failed. Try again."
                isSubmitting = false
            }
        }
    }

    private func handleBarcode(_ code: String) async {
        scanResult = nil
        matchedFoods = []
        unmatchedItems = []
        isSearchingMacros = false
        errorMessage = nil
        do {
            let item = try await NutritionAPIService.shared.fetchFoodByBarcode(code: code, userId: userId)
            await MainActor.run {
                matchedFoods = [item]
                scanResult = MealPhotoScanResult(food: item, items: [], photoUrl: nil, query: "Barcode", message: nil)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Unable to find a match for that barcode."
            }
        }
    }

    private func displayFoods(for result: MealPhotoScanResult) -> [FoodItem] {
        if !matchedFoods.isEmpty {
            return matchedFoods
        }
        if let food = result.food {
            return [food]
        }
        return []
    }

    private func mealTotals(for foods: [FoodItem]) -> MacroTotals {
        foods.reduce(.zero) { partial, food in
            partial.adding(macroTotals(for: food))
        }
    }

    private func macroTotals(for food: FoodItem) -> MacroTotals {
        MacroTotals(
            calories: food.calories,
            protein: food.protein,
            carbs: food.carbs,
            fats: food.fats
        )
    }

    private func recognizedItemsText(for result: MealPhotoScanResult) -> String? {
        if !result.items.isEmpty {
            return result.items.joined(separator: ", ")
        }
        if let query = result.query, !query.isEmpty, query.lowercased() != "barcode" {
            return query
        }
        return nil
    }

    private func lookupMacros(for result: MealPhotoScanResult) async {
        guard !result.items.isEmpty else { return }
        await MainActor.run {
            isSearchingMacros = true
            matchedFoods = []
            unmatchedItems = []
        }
        var matches: [FoodItem] = []
        var misses: [String] = []
        for item in result.items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            do {
                let results = try await NutritionAPIService.shared.searchFoods(query: trimmed, userId: userId)
                if let match = results.first {
                    matches.append(match)
                } else {
                    misses.append(trimmed)
                }
            } catch {
                misses.append(trimmed)
            }
        }
        await MainActor.run {
            matchedFoods = matches
            unmatchedItems = misses
            isSearchingMacros = false
        }
    }

    private func resetScanResults() {
        scanResult = nil
        matchedFoods = []
        unmatchedItems = []
        isSearchingMacros = false
        errorMessage = nil
    }

    private func scanResultCard(_ result: MealPhotoScanResult) -> some View {
        let foods = displayFoods(for: result)
        let totals = mealTotals(for: foods)
        let recognizedText = recognizedItemsText(for: result)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Scan Result")
                .font(FitFont.body(size: 16))
                .fontWeight(.semibold)
                .foregroundColor(FitTheme.textPrimary)

            if let recognizedText, !recognizedText.isEmpty {
                Text("Recognized: \(recognizedText)")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }

            if isSearchingMacros {
                AnalyzingIndicator(label: "Finding macros")
            }

            if !foods.isEmpty {
                VStack(spacing: 10) {
                    ForEach(foods) { food in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(food.name)
                                .font(FitFont.body(size: 15))
                                .foregroundColor(FitTheme.textPrimary)

                            Text("\(Int(food.calories)) kcal · P \(Int(food.protein)) · C \(Int(food.carbs)) · F \(Int(food.fats))")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)

                            if let serving = food.serving, !serving.isEmpty {
                                Text(serving)
                                    .font(FitFont.body(size: 11))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                        }
                        .padding(12)
                        .background(FitTheme.cardHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Meal totals")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)

                    Text("\(Int(totals.calories)) kcal · P \(Int(totals.protein)) · C \(Int(totals.carbs)) · F \(Int(totals.fats))")
                        .font(FitFont.body(size: 14))
                        .foregroundColor(FitTheme.textPrimary)
                }
                .padding(12)
                .background(FitTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if !unmatchedItems.isEmpty {
                    Text("No macros found for: \(unmatchedItems.joined(separator: ", "))")
                        .font(FitFont.body(size: 11))
                        .foregroundColor(FitTheme.textSecondary)
                }

                Text("Would you like to log the meal or scan it again?")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)

                HStack(spacing: 12) {
                    ActionButton(title: "Scan Again", style: .secondary) {
                        resetScanResults()
                        hasScannedBarcode = false
                        if scanMode == .barcode {
                            barcodeSessionId = UUID()
                        }
                    }
                    ActionButton(title: isLogging ? "Logging…" : "Log Meal", style: .primary) {
                        Task {
                            await logScannedFoods(foods)
                        }
                    }
                    .disabled(isSearchingMacros || foods.isEmpty)
                }
            } else if !isSearchingMacros {
                if !unmatchedItems.isEmpty {
                    Text("No macros found for: \(unmatchedItems.joined(separator: ", "))")
                        .font(FitFont.body(size: 11))
                        .foregroundColor(FitTheme.textSecondary)
                } else {
                    Text(result.message ?? "No match found. Try another photo.")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
        }
        .padding(16)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func logScannedFoods(_ foods: [FoodItem]) async {
        guard !foods.isEmpty else { return }
        isLogging = true
        var totals = MacroTotals.zero
        do {
            for food in foods {
                let macros = macroTotals(for: food)
                totals = totals.adding(macros)
                let loggedItem = LoggedFoodItem(
                    name: food.name,
                    portionValue: 0,
                    portionUnit: .grams,
                    macros: macros,
                    detail: food.serving ?? "1 serving"
                )
                try await NutritionAPIService.shared.logManualItem(
                    userId: userId,
                    date: logDate,
                    mealType: activeMealType.rawValue,
                    item: loggedItem
                )
            }
            isLogging = false
            Haptics.success()
            NotificationCenter.default.post(
                name: .fitAINutritionLogged,
                object: nil,
                userInfo: [
                    "macros": [
                        "calories": totals.calories,
                        "protein": totals.protein,
                        "carbs": totals.carbs,
                        "fats": totals.fats
                    ]
                ]
            )
            onLogged()
            dismiss()
        } catch {
            isLogging = false
            errorMessage = "Unable to log scanned meal."
        }
    }
}

private struct AnalyzingIndicator: View {
    let label: String
    @State private var animate = false

    init(label: String = "Analyzing") {
        self.label = label
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(FitTheme.buttonText.opacity(0.9))
                        .frame(width: 6, height: 6)
                        .scaleEffect(animate ? 1.0 : 0.4)
                        .opacity(animate ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: animate
                        )
                }
            }

            Text(label)
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.buttonText.opacity(0.9))
        }
        .onAppear {
            animate = true
        }
        .onDisappear {
            animate = false
        }
    }
}

private enum ScanMode: String, CaseIterable, Identifiable {
    case photo = "photo"
    case barcode = "barcode"
    case label = "label"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo:
            return "Photo"
        case .barcode:
            return "Barcode"
        case .label:
            return "Label Beta"
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
    }
}

private final class MealPhotoCameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var isAuthorized = false
    @Published var errorMessage: String?
    @Published var isTorchOn = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var isConfigured = false
    private var onPhoto: ((Data, UIImage) -> Void)?
    private var captureDevice: AVCaptureDevice?

    func requestAccess() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isAuthorized = true
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                    if granted {
                        self.configureSession()
                    } else {
                        self.errorMessage = "Camera access is required to scan food."
                    }
                }
            }
        default:
            isAuthorized = false
            errorMessage = "Camera access is required to scan food."
        }
    }

    func start() {
        guard isAuthorized else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capturePhoto(onPhoto: @escaping (Data, UIImage) -> Void) {
        guard isAuthorized else {
            errorMessage = "Camera access is required to scan food."
            return
        }
        self.onPhoto = onPhoto
        let settings = AVCapturePhotoSettings()
        if output.supportedFlashModes.contains(.auto) {
            settings.flashMode = .auto
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    func toggleTorch() {
        guard let device = captureDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = isTorchOn ? .off : .on
            device.unlockForConfiguration()
            isTorchOn.toggle()
        } catch {
            errorMessage = "Torch unavailable."
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            errorMessage = error.localizedDescription
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            errorMessage = "Unable to capture photo."
            return
        }
        onPhoto?(data, image)
    }

    private func configureSession() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            errorMessage = "Camera is not available on this device."
            session.commitConfiguration()
            return
        }
        captureDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            isConfigured = true
        } catch {
            errorMessage = "Unable to start camera."
        }

        session.commitConfiguration()
    }
}

private struct MealPlanDetailSheet: View {
    let meal: MealPlanMeal
    let isRegenerating: Bool
    let onLog: () -> Void
    let onRegenerate: () -> Void
    let onDismiss: () -> Void
    let onMealUpdated: (MealPlanMeal) -> Void
    
    @State private var isEditing = false
    @State private var editedItems: [String] = []
    @State private var editedName: String = ""
    @State private var showAddIngredientSearch = false
    @State private var editedCalories: Int
    @State private var editedProtein: Int
    @State private var editedCarbs: Int
    @State private var editedFats: Int
    
    init(
        meal: MealPlanMeal,
        isRegenerating: Bool,
        onLog: @escaping () -> Void,
        onRegenerate: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onMealUpdated: @escaping (MealPlanMeal) -> Void
    ) {
        self.meal = meal
        self.isRegenerating = isRegenerating
        self.onLog = onLog
        self.onRegenerate = onRegenerate
        self.onDismiss = onDismiss
        self.onMealUpdated = onMealUpdated
        _editedCalories = State(initialValue: meal.calories)
        _editedProtein = State(initialValue: meal.protein)
        _editedCarbs = State(initialValue: meal.carbs)
        _editedFats = State(initialValue: meal.fats)
    }
    
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        if isEditing {
                            TextField("Meal name", text: $editedName)
                                .font(FitFont.heading(size: 24))
                                .foregroundColor(FitTheme.textPrimary)
                        } else {
                            Text(meal.name)
                                .font(FitFont.heading(size: 24))
                                .foregroundColor(FitTheme.textPrimary)
                        }
                        
                        Spacer()
                        
                        if isEditing {
                            Button("Save") {
                                saveMealChanges()
                                withAnimation { isEditing = false }
                            }
                            .font(FitFont.body(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.accent)
                        } else {
                            Button(action: {
                                editedName = meal.name
                                editedItems = meal.items
                                withAnimation { isEditing = true }
                            }) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(FitTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Macro Summary
                    macroSummaryCard
                    
                    // Ingredients List
                    if isEditing {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Ingredients")
                                    .font(FitFont.body(size: 14, weight: .semibold))
                                    .foregroundColor(FitTheme.textSecondary)
                                
                                Spacer()
                                
                                Text("Swipe to delete")
                                    .font(FitFont.body(size: 11))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                            
                            List {
                                ForEach(editedItems, id: \.self) { item in
                                    Text(item)
                                        .font(FitFont.body(size: 15))
                                        .foregroundColor(FitTheme.textPrimary)
                                        .listRowBackground(FitTheme.cardHighlight)
                                }
                                .onDelete { indexSet in
                                    removeIngredient(at: indexSet)
                                }
                            }
                            .listStyle(.plain)
                            .frame(height: CGFloat(editedItems.count * 50))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            // Add new ingredient - opens food search
                            Button(action: {
                                showAddIngredientSearch = true
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(FitTheme.accent)
                                    
                                    Text("Add ingredient...")
                                        .font(FitFont.body(size: 15))
                                        .foregroundColor(FitTheme.textSecondary)
                                    
                                    Spacer()
                                }
                                .padding(12)
                                .background(FitTheme.cardHighlight)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    } else if !meal.items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ingredients")
                                .font(FitFont.body(size: 14, weight: .semibold))
                                .foregroundColor(FitTheme.textSecondary)
                            
                            VStack(spacing: 8) {
                                ForEach(meal.items, id: \.self) { item in
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(FitTheme.accent)
                                            .frame(width: 6, height: 6)
                                        
                                        Text(item)
                                            .font(FitFont.body(size: 15))
                                            .foregroundColor(FitTheme.textPrimary)
                                        
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(FitTheme.cardHighlight)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    
                    // Actions
                    VStack(spacing: 12) {
                        Button(action: onLog) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Log This Meal")
                            }
                            .font(FitFont.body(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(FitTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: onRegenerate) {
                            HStack {
                                if isRegenerating {
                                    ProgressView()
                                        .tint(FitTheme.accent)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Swap For Different Meal")
                                }
                            }
                            .font(FitFont.body(size: 15, weight: .medium))
                            .foregroundColor(FitTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FitTheme.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRegenerating)
                    }
                }
                .padding(20)
            }
        }
    }
    
    private var macroSummaryCard: some View {
        let displayCals = isEditing ? editedCalories : Int(meal.macros.calories)
        let displayProtein = isEditing ? editedProtein : Int(meal.macros.protein)
        let displayCarbs = isEditing ? editedCarbs : Int(meal.macros.carbs)
        let displayFats = isEditing ? editedFats : Int(meal.macros.fats)
        
        return VStack(spacing: 14) {
            // Total Calories
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Calories")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(displayCals)")
                            .font(FitFont.heading(size: 32, weight: .bold))
                            .foregroundColor(FitTheme.textPrimary)
                            .contentTransition(.numericText())
                        Text("kcal")
                            .font(FitFont.body(size: 16))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                Spacer()
                
                if isEditing {
                    Text("Updated")
                        .font(FitFont.body(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(FitTheme.accent)
                        .clipShape(Capsule())
                }
            }
            
            // Macro breakdown
            HStack(spacing: 16) {
                macroItem(label: "Protein", value: displayProtein, color: .blue)
                macroItem(label: "Carbs", value: displayCarbs, color: .green)
                macroItem(label: "Fat", value: displayFats, color: .orange)
            }
        }
        .padding(16)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isEditing ? FitTheme.accent.opacity(0.3) : FitTheme.cardStroke, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
    
    private func macroItem(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)g")
                .font(FitFont.body(size: 18, weight: .bold))
                .foregroundColor(FitTheme.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(FitFont.body(size: 11))
                .foregroundColor(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private func saveMealChanges() {
        var updatedMeal = meal
        updatedMeal.name = editedName
        updatedMeal.items = editedItems
        updatedMeal.macros = MacroTotals(
            calories: Double(editedCalories),
            protein: Double(editedProtein),
            carbs: Double(editedCarbs),
            fats: Double(editedFats)
        )
        onMealUpdated(updatedMeal)
        Haptics.success()
    }
    
    private func removeIngredient(at indexSet: IndexSet) {
        // Estimate macros to remove (rough approximation per ingredient)
        let ingredientCount = editedItems.count
        guard ingredientCount > 0 else { return }
        
        let macrosPerIngredient = (
            calories: editedCalories / ingredientCount,
            protein: editedProtein / ingredientCount,
            carbs: editedCarbs / ingredientCount,
            fats: editedFats / ingredientCount
        )
        
        for index in indexSet {
            editedItems.remove(at: index)
            editedCalories = max(0, editedCalories - macrosPerIngredient.calories)
            editedProtein = max(0, editedProtein - macrosPerIngredient.protein)
            editedCarbs = max(0, editedCarbs - macrosPerIngredient.carbs)
            editedFats = max(0, editedFats - macrosPerIngredient.fats)
        }
        Haptics.light()
    }
    
    private func addIngredient(name: String, calories: Int, protein: Int, carbs: Int, fats: Int) {
        editedItems.append(name)
        editedCalories += calories
        editedProtein += protein
        editedCarbs += carbs
        editedFats += fats
        Haptics.success()
    }
}

private struct LogFoodActionSheet: View {
    let onPhotoLog: () -> Void
    let onScanBarcode: () -> Void
    let onFoodDatabase: () -> Void
    let onSavedFoods: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(FitTheme.cardStroke)
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)

                Text("Log Food")
                    .font(FitFont.heading(size: 20))
                    .foregroundColor(FitTheme.textPrimary)

                Text("Quick Log")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    LogActionTile(
                        title: "Photo Log",
                        subtitle: "Snap a plate",
                        systemImage: "camera.fill"
                    ) {
                        dismiss()
                        onPhotoLog()
                    }

                    LogActionTile(
                        title: "Scan Barcode",
                        subtitle: "Packaged foods",
                        systemImage: "barcode.viewfinder"
                    ) {
                        dismiss()
                        onScanBarcode()
                    }

                    LogActionTile(
                        title: "Food Database",
                        subtitle: "Search foods",
                        systemImage: "magnifyingglass"
                    ) {
                        dismiss()
                        onFoodDatabase()
                    }

                    LogActionTile(
                        title: "Saved Foods",
                        subtitle: "Your shortcuts",
                        systemImage: "bookmark.fill"
                    ) {
                        dismiss()
                        onSavedFoods()
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct LogActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FitTheme.accent)

                Text(title)
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textPrimary)

                Text(subtitle)
                    .font(FitFont.body(size: 11))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SavedFoodsSheet: View {
    @ObservedObject var viewModel: NutritionViewModel
    let mealType: MealType
    let logDate: Date

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var savedMealsStore = SavedMealsStore.shared

    @State private var selectedTab: SavedItemsTab = .meals
    @State private var favorites: [FoodItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activeMealType: MealType
    @State private var mealToDelete: SavedMeal?
    @State private var showDeleteConfirmation = false
    
    private enum SavedItemsTab: String, CaseIterable {
        case meals = "Saved Meals"
        case foods = "Saved Foods"
    }

    init(viewModel: NutritionViewModel, mealType: MealType, logDate: Date) {
        self.viewModel = viewModel
        self.mealType = mealType
        self.logDate = logDate
        _activeMealType = State(initialValue: mealType)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab selector
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(SavedItemsTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Meal type filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MealType.allCases) { meal in
                                mealTypeChip(meal)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if selectedTab == .meals {
                                savedMealsContent
                            } else {
                                savedFoodsContent
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(selectedTab.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(FitTheme.textPrimary)
                }
            }
        }
        .task {
            await loadFavorites()
        }
        .alert("Delete Meal?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let meal = mealToDelete {
                    savedMealsStore.deleteMeal(meal)
                    Haptics.success()
                }
            }
        } message: {
            Text("This will permanently delete \"\(mealToDelete?.name ?? "this meal")\" from your saved meals.")
        }
    }
    
    // MARK: - Meal Type Chip
    
    private func mealTypeChip(_ meal: MealType) -> some View {
        let isSelected = activeMealType == meal
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeMealType = meal
            }
        } label: {
            Text(meal.title)
                .font(FitFont.body(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? FitTheme.buttonText : FitTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? FitTheme.accent : FitTheme.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : FitTheme.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Saved Meals Content
    
    @ViewBuilder
    private var savedMealsContent: some View {
        let filteredMeals = savedMealsStore.meals(for: activeMealType)
        
        if filteredMeals.isEmpty {
            emptyMealsState
        } else {
            VStack(spacing: 12) {
                ForEach(filteredMeals) { meal in
                    savedMealRow(meal)
                }
            }
        }
    }
    
    private var emptyMealsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 48))
                .foregroundColor(FitTheme.textSecondary.opacity(0.5))
            
            VStack(spacing: 6) {
                Text("No Saved Meals")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
                
                Text("Save meals you eat often for quick logging.\nTap the bookmark icon on any logged meal to save it.")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private func savedMealRow(_ meal: SavedMeal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name)
                        .font(FitFont.body(size: 16, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                    
                    Text("\(meal.items.count) item\(meal.items.count == 1 ? "" : "s")")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button {
                        mealToDelete = meal
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                            .padding(8)
                            .background(FitTheme.cardHighlight)
                            .clipShape(Circle())
                    }
                    
                    Button {
                        Task {
                            await logSavedMeal(meal)
                        }
                    } label: {
                        Text("Log")
                            .font(FitFont.body(size: 13, weight: .semibold))
                            .foregroundColor(FitTheme.buttonText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(FitTheme.primaryGradient)
                            .clipShape(Capsule())
                    }
                }
            }
            
            // Macro summary
            HStack(spacing: 12) {
                macroChip(value: Int(meal.totalMacros.calories), label: "kcal", color: FitTheme.accent)
                macroChip(value: Int(meal.totalMacros.protein), label: "P", color: FitTheme.proteinColor)
                macroChip(value: Int(meal.totalMacros.carbs), label: "C", color: FitTheme.carbColor)
                macroChip(value: Int(meal.totalMacros.fats), label: "F", color: FitTheme.fatColor)
            }
            
            // Item preview
            if !meal.items.isEmpty {
                Text(meal.itemNames)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
        )
    }
    
    private func macroChip(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(FitFont.body(size: 12, weight: .semibold))
                .foregroundColor(color)
            Text(label)
                .font(FitFont.body(size: 10))
                .foregroundColor(FitTheme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private func logSavedMeal(_ meal: SavedMeal) async {
        for item in meal.items {
            let loggedItem = item.toLoggedFoodItem()
            _ = await viewModel.logManualItem(item: loggedItem, mealType: activeMealType, date: logDate)
        }
        savedMealsStore.updateMealUsage(meal)
        Haptics.success()
        dismiss()
    }
    
    // MARK: - Saved Foods Content
    
    @ViewBuilder
    private var savedFoodsContent: some View {
        if isLoading {
            ProgressView()
                .tint(FitTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if favorites.isEmpty {
            emptyFoodsState
        } else {
            VStack(spacing: 10) {
                ForEach(favorites) { item in
                    savedFoodRow(item)
                }
            }
        }
    }
    
    private var emptyFoodsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.slash")
                .font(.system(size: 48))
                .foregroundColor(FitTheme.textSecondary.opacity(0.5))
            
            VStack(spacing: 6) {
                Text("No Saved Foods")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
                
                Text("Foods you favorite will appear here\nfor quick access.")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func savedFoodRow(_ item: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textPrimary)

                Spacer()

                Button {
                    Task {
                        await logFavorite(item)
                    }
                } label: {
                    Text("Log")
                        .font(FitFont.body(size: 13, weight: .semibold))
                        .foregroundColor(FitTheme.buttonText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(FitTheme.primaryGradient)
                        .clipShape(Capsule())
                }
            }

            Text("\(Int(item.calories)) kcal · P \(Int(item.protein)) · C \(Int(item.carbs)) · F \(Int(item.fats))")
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)

            if let serving = item.serving, !serving.isEmpty {
                Text(serving)
                    .font(FitFont.body(size: 11))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .padding(12)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
        )
    }

    private func loadFavorites() async {
        guard !viewModel.userId.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let items = try await NutritionAPIService.shared.fetchFavorites(userId: viewModel.userId)
            await MainActor.run {
                favorites = items
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Unable to load saved foods."
                isLoading = false
            }
        }
    }

    private func logFavorite(_ item: FoodItem) async {
        let macros = MacroTotals(
            calories: item.calories,
            protein: item.protein,
            carbs: item.carbs,
            fats: item.fats
        )
        let loggedItem = LoggedFoodItem(
            name: item.name,
            portionValue: 0,
            portionUnit: .grams,
            macros: macros,
            detail: item.serving ?? "1 serving"
        )
        let success = await viewModel.logManualItem(item: loggedItem, mealType: activeMealType, date: logDate)
        if success {
            Haptics.success()
            dismiss()
        } else {
            await MainActor.run {
                errorMessage = "Unable to log saved food."
            }
        }
    }
}

// MARK: - Save Meal Sheet

private struct SaveMealSheet: View {
    let mealType: MealType
    let items: [LoggedFoodItem]
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    @State private var mealName: String = ""
    @FocusState private var isNameFocused: Bool
    
    private var totalMacros: MacroTotals {
        items.reduce(MacroTotals.zero) { $0.adding($1.macros) }
    }
    
    private var suggestedName: String {
        "My \(mealType.title)"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header illustration
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 40))
                            .foregroundColor(FitTheme.accent)
                            .padding(20)
                            .background(FitTheme.accentSoft.opacity(0.3))
                            .clipShape(Circle())
                        
                        Text("Save This Meal")
                            .font(FitFont.heading(size: 22))
                            .foregroundColor(FitTheme.textPrimary)
                        
                        Text("Log it quickly next time")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                    .padding(.top, 20)
                    
                    // Name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meal Name")
                            .font(FitFont.body(size: 13))
                            .foregroundColor(FitTheme.textSecondary)
                        
                        TextField(suggestedName, text: $mealName)
                            .font(FitFont.body(size: 16))
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(14)
                            .background(FitTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(FitTheme.cardStroke, lineWidth: 1)
                            )
                            .focused($isNameFocused)
                    }
                    .padding(.horizontal, 20)
                    
                    // Items preview
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                            .font(FitFont.body(size: 13, weight: .medium))
                            .foregroundColor(FitTheme.textSecondary)
                        
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(items) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(FitFont.body(size: 14))
                                                .foregroundColor(FitTheme.textPrimary)
                                                .lineLimit(1)
                                            
                                            Text(item.detail)
                                                .font(FitFont.body(size: 11))
                                                .foregroundColor(FitTheme.textSecondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Text("\(Int(item.macros.calories)) kcal")
                                            .font(FitFont.body(size: 12))
                                            .foregroundColor(FitTheme.textSecondary)
                                    }
                                    .padding(10)
                                    .background(FitTheme.cardHighlight)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                        
                        // Total macros
                        HStack(spacing: 12) {
                            Text("Total:")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                            
                            Spacer()
                            
                            Text("\(Int(totalMacros.calories)) kcal")
                                .font(FitFont.body(size: 12, weight: .semibold))
                                .foregroundColor(FitTheme.accent)
                            
                            Text("P \(Int(totalMacros.protein))")
                                .font(FitFont.body(size: 11))
                                .foregroundColor(FitTheme.proteinColor)
                            
                            Text("C \(Int(totalMacros.carbs))")
                                .font(FitFont.body(size: 11))
                                .foregroundColor(FitTheme.carbColor)
                            
                            Text("F \(Int(totalMacros.fats))")
                                .font(FitFont.body(size: 11))
                                .foregroundColor(FitTheme.fatColor)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            let name = mealName.isEmpty ? suggestedName : mealName
                            onSave(name)
                        } label: {
                            Text("Save Meal")
                                .font(FitFont.body(size: 16, weight: .semibold))
                                .foregroundColor(FitTheme.buttonText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(FitTheme.primaryGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        
                        Button {
                            onCancel()
                        } label: {
                            Text("Cancel")
                                .font(FitFont.body(size: 15))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                isNameFocused = true
            }
        }
    }
}

// MARK: - Serving Size Picker Sheet

private struct ServingSizePickerSheet: View {
    let item: FoodItem
    @Binding var selectedServingOption: ServingOption?
    @Binding var portionUnit: PortionUnit
    @Binding var portionValue: String
    let onDismiss: () -> Void
    
    private var servingOptions: [ServingOption] {
        item.parsedServingOptions
    }
    
    /// The default serving - first option or the food's base serving
    private var defaultServing: ServingOption? {
        defaultServingOption(for: item, options: servingOptions)
    }
    
    /// All other serving options
    private var allServings: [ServingOption] {
        servingOptions.filter { option in
            guard let defaultServing else { return true }
            let desc = option.description.lowercased()
            let isCommon = desc.contains("1 g") || desc == "1g" || desc == "g"
                || desc.contains("1 oz") || desc == "1oz" || desc == "oz" || desc.contains("1 ounce")
            return option.id != defaultServing.id && !isCommon
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.07)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Default section
                        if let defaultServing {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Default")
                                    .font(FitFont.body(size: 13))
                                    .foregroundColor(Color.gray)
                                
                                ServingOptionRow(
                                    option: defaultServing,
                                    isSelected: selectedServingOption?.id == defaultServing.id,
                                    isDefault: true
                                ) {
                                    selectedServingOption = defaultServing
                                    portionUnit = .serving
                                    portionValue = "1"
                                    onDismiss()
                                }
                            }
                        }
                        
                        // Common section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Common")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(Color.gray)
                            
                            VStack(spacing: 0) {
                                ServingOptionRow(
                                    title: "1 g",
                                    isSelected: portionUnit == .grams && selectedServingOption == nil && portionValue == "1",
                                    showDivider: true
                                ) {
                                    selectedServingOption = nil
                                    portionUnit = .grams
                                    portionValue = "1"
                                    onDismiss()
                                }
                                
                                ServingOptionRow(
                                    title: "1 oz",
                                    isSelected: portionUnit == .ounces && selectedServingOption == nil && portionValue == "1"
                                ) {
                                    selectedServingOption = nil
                                    portionUnit = .ounces
                                    portionValue = "1"
                                    onDismiss()
                                }
                            }
                            .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        
                        // All Servings section
                        if !allServings.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("All Servings")
                                    .font(FitFont.body(size: 13))
                                    .foregroundColor(Color.gray)
                                
                                VStack(spacing: 0) {
                                    ForEach(Array(allServings.enumerated()), id: \.element.id) { index, option in
                                        ServingOptionRow(
                                            option: option,
                                            isSelected: selectedServingOption?.id == option.id,
                                            showDivider: index < allServings.count - 1
                                        ) {
                                            selectedServingOption = option
                                            portionUnit = .serving
                                            portionValue = "1"
                                            onDismiss()
                                        }
                                    }
                                }
                                .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Select Serving Size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                    .font(FitFont.body(size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.2, green: 0.2, blue: 0.2))
                    .clipShape(Capsule())
                }
            }
            .toolbarBackground(Color(red: 0.07, green: 0.07, blue: 0.07), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ServingOptionRow: View {
    var option: ServingOption? = nil
    var title: String? = nil
    let isSelected: Bool
    var isDefault: Bool = false
    var showDivider: Bool = false
    let onTap: () -> Void
    
    private var displayTitle: String {
        title ?? option?.description ?? "1 serving"
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack {
                    Text(displayTitle)
                        .font(FitFont.body(size: 16))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if isDefault {
                        Text("Default")
                            .font(FitFont.body(size: 12))
                            .foregroundColor(FitTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(FitTheme.accent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                
                if showDivider {
                    Divider()
                        .background(Color(red: 0.25, green: 0.25, blue: 0.25))
                        .padding(.leading, 16)
                }
            }
        }
        .background(isDefault || title != nil ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: isDefault || (title != nil && !showDivider) ? 14 : 0))
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

private struct BarcodeScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerController {
        let controller = BarcodeScannerController()
        controller.onFound = onFound
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerController, context: Context) {}
}

final class BarcodeScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var hasFoundCode = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black
        checkCameraPermission()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasFoundCode = false
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                        self?.startSession()
                    } else {
                        self?.onError?("Camera access is required to scan barcodes. Please enable it in Settings.")
                    }
                }
            }
        case .denied, .restricted:
            onError?("Camera access is required to scan barcodes. Please enable it in Settings.")
        @unknown default:
            onError?("Camera access is required to scan barcodes.")
        }
    }

    private func startSession() {
        guard isConfigured else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureSession() {
        guard !isConfigured else { return }
        
        session.beginConfiguration()
        session.sessionPreset = .high
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            onError?("Camera is not available on this device.")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                // Support all common barcode types including UPC-A (most common in US)
                output.metadataObjectTypes = [
                    .ean8,
                    .ean13,
                    .upce,
                    .code128,
                    .code39,
                    .code93,
                    .itf14,
                    .dataMatrix,
                    .qr
                ]
            }
            
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.layer.bounds
            view.layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer
            
            isConfigured = true
            session.commitConfiguration()
            
            // Auto-focus for better barcode detection
            if device.isFocusModeSupported(.continuousAutoFocus) {
                try device.lockForConfiguration()
                device.focusMode = .continuousAutoFocus
                device.unlockForConfiguration()
            }
        } catch {
            session.commitConfiguration()
            onError?("Unable to configure camera: \(error.localizedDescription)")
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        // Prevent multiple callbacks for same scan
        guard !hasFoundCode else { return }
        
        for metadata in metadataObjects {
            guard let readable = metadata as? AVMetadataMachineReadableCodeObject,
                  let code = readable.stringValue,
                  !code.isEmpty else { continue }
            
            hasFoundCode = true
            
            // Haptic feedback on successful scan
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            stopSession()
            onFound?(code)
            return
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
            .background(isAccented ? FitTheme.cardNutrition : FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isAccented ? FitTheme.cardNutritionAccent.opacity(0.3) : FitTheme.cardStroke.opacity(0.6), lineWidth: isAccented ? 1.5 : 1)
            )
            .shadow(color: isAccented ? FitTheme.cardNutritionAccent.opacity(0.15) : FitTheme.shadow, radius: 18, x: 0, y: 10)
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

// MARK: - Edit Food Item Sheet

private struct EditFoodItemSheet: View {
    let item: LoggedFoodItem
    let mealType: MealType
    let onSave: (LoggedFoodItem) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    
    @State private var servingSize: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fats: String
    @State private var showDeleteConfirmation = false
    
    init(
        item: LoggedFoodItem,
        mealType: MealType,
        onSave: @escaping (LoggedFoodItem) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.item = item
        self.mealType = mealType
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        
        // Initialize state with current values
        _servingSize = State(initialValue: item.detail)
        _calories = State(initialValue: String(Int(item.macros.calories)))
        _protein = State(initialValue: String(Int(item.macros.protein)))
        _carbs = State(initialValue: String(Int(item.macros.carbs)))
        _fats = State(initialValue: String(Int(item.macros.fats)))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Food name header
                        VStack(spacing: 8) {
                            Text(item.name)
                                .font(FitFont.heading(size: 22))
                                .foregroundColor(FitTheme.textPrimary)
                                .multilineTextAlignment(.center)
                            
                            Text(mealType.title)
                                .font(FitFont.body(size: 14))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        .padding(.top, 20)
                        
                        // Serving size
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Serving Size")
                                .font(FitFont.body(size: 13))
                                .foregroundColor(FitTheme.textSecondary)
                            
                            TextField("1 serving", text: $servingSize)
                                .font(FitFont.body(size: 16))
                                .foregroundColor(FitTheme.textPrimary)
                                .padding(14)
                                .background(FitTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(FitTheme.cardStroke, lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 20)
                        
                        // Macro fields
                        VStack(spacing: 12) {
                            macroField(title: "Calories", value: $calories, unit: "kcal", color: FitTheme.accent)
                            macroField(title: "Protein", value: $protein, unit: "g", color: FitTheme.proteinColor)
                            macroField(title: "Carbs", value: $carbs, unit: "g", color: FitTheme.carbColor)
                            macroField(title: "Fats", value: $fats, unit: "g", color: FitTheme.fatColor)
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 40)
                        
                        // Action buttons
                        VStack(spacing: 12) {
                            Button {
                                saveChanges()
                            } label: {
                                Text("Save Changes")
                                    .font(FitFont.body(size: 16, weight: .semibold))
                                    .foregroundColor(FitTheme.buttonText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(FitTheme.primaryGradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            
                            Button {
                                showDeleteConfirmation = true
                            } label: {
                                Text("Delete Item")
                                    .font(FitFont.body(size: 15))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(FitTheme.textSecondary)
                }
            }
            .alert("Delete Item?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove \"\(item.name)\" from your log.")
            }
        }
    }
    
    private func macroField(title: String, value: Binding<String>, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)
            
            HStack {
                TextField("0", text: value)
                    .keyboardType(.numberPad)
                    .font(FitFont.body(size: 16))
                    .foregroundColor(FitTheme.textPrimary)
                
                Text(unit)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(color)
            }
            .padding(14)
            .background(FitTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private func saveChanges() {
        let updatedMacros = MacroTotals(
            calories: Double(calories) ?? item.macros.calories,
            protein: Double(protein) ?? item.macros.protein,
            carbs: Double(carbs) ?? item.macros.carbs,
            fats: Double(fats) ?? item.macros.fats
        )
        
        let updatedItem = LoggedFoodItem(
            name: item.name,
            portionValue: item.portionValue,
            portionUnit: item.portionUnit,
            macros: updatedMacros,
            detail: servingSize
        )
        
        onSave(updatedItem)
    }
}

#Preview {
    NutritionView(userId: "demo-user", intent: .constant(nil))
}
