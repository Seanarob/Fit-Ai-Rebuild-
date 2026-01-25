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
    @State private var isHistoryPresented = false
    @State private var showLoggedToast = false
    @State private var targets = MacroTargets(calories: 0, protein: 0, carbs: 0, fats: 0)

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
                .padding(.bottom, 32)
            }

        }
        .sheet(isPresented: $isLogSheetPresented, onDismiss: {
            showBarcodeOnLogSheet = false
            Task { await viewModel.loadDailyLogs() }
        }) {
            NutritionLogSheet(
                viewModel: viewModel,
                mealType: selectedMealType,
                showBarcodeOnAppear: showBarcodeOnLogSheet
            )
        }
        .fullScreenCover(isPresented: $isScanSheetPresented) {
            ScanFoodCameraView(
                userId: userId,
                mealType: selectedMealType,
                onLogged: {
                    Task {
                        await viewModel.loadDailyLogs()
                    }
                }
            )
        }
        .sheet(isPresented: $isSavedFoodsPresented, onDismiss: {
            Task { await viewModel.loadDailyLogs() }
        }) {
            SavedFoodsSheet(viewModel: viewModel, mealType: selectedMealType)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isHistoryPresented) {
            NutritionHistoryView(userId: userId)
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
        .task {
            await viewModel.loadDailyLogs()
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

                Button(action: { isHistoryPresented = true }) {
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

    private var macroSummaryCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Today's Macros")
                        .font(FitFont.body(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Spacer()

                    Text("Daily target")
                        .font(FitFont.body(size: 12))
                        .foregroundColor(FitTheme.textSecondary)
                }

                let totals = viewModel.totals

                HStack(alignment: .center, spacing: 20) {
                    MacroRingView(
                        title: "Calories",
                        value: totals.calories,
                        target: targets.calories,
                        unit: "kcal",
                        ringSize: 96
                    )

                    VStack(spacing: 14) {
                        MacroRingView(
                            title: "Protein",
                            value: totals.protein,
                            target: targets.protein,
                            unit: "g",
                            ringSize: 64
                        )
                        MacroRingView(
                            title: "Carbs",
                            value: totals.carbs,
                            target: targets.carbs,
                            unit: "g",
                            ringSize: 64
                        )
                        MacroRingView(
                            title: "Fats",
                            value: totals.fats,
                            target: targets.fats,
                            unit: "g",
                            ringSize: 64
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

                Text("Add a meal to start tracking your macros for today.")
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
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(meal.name)
                                    .font(FitFont.body(size: 15))
                                    .foregroundColor(FitTheme.textPrimary)

                                Spacer()

                                Button("Log") {
                                    Task {
                                        await logMealPlanMeal(meal)
                                    }
                                }
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.accent)
                            }

                            Text("\(Int(meal.macros.calories)) kcal · P \(Int(meal.macros.protein)) · C \(Int(meal.macros.carbs)) · F \(Int(meal.macros.fats))")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)

                            if !meal.items.isEmpty {
                                Text(meal.items.joined(separator: ", "))
                                    .font(FitFont.body(size: 11))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                        }
                        .padding(10)
                        .background(FitTheme.cardHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                        }
                        .padding(10)
                        .background(FitTheme.cardHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

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
            // keep defaults when profile fetch fails
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
        let success = await viewModel.logManualItem(item: item, mealType: mealType)
        if success {
            await loadActiveMealPlan()
        } else {
            await MainActor.run {
                mealPlanStatus = "Log failed"
            }
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
    @State private var selectedDate = Date()

    @Environment(\.dismiss) private var dismiss

    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: NutritionViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DatePicker("Select date", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(FitTheme.accent)

                        historySummaryCard

                        ForEach(MealType.allCases) { meal in
                            historyMealCard(meal)
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Nutrition History")
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
                await viewModel.loadDailyLogs(date: selectedDate)
            }
            .onChange(of: selectedDate) { newValue in
                Task {
                    await viewModel.loadDailyLogs(date: newValue)
                }
            }
        }
    }

    private var historySummaryCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("Daily Totals")
                    .font(FitFont.body(size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                let totals = viewModel.totals
                Text("\(Int(totals.calories)) kcal · P \(Int(totals.protein)) · C \(Int(totals.carbs)) · F \(Int(totals.fats))")
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }

    private func historyMealCard(_ meal: MealType) -> some View {
        let items = viewModel.dailyMeals[meal, default: []]
        return CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text(meal.title)
                    .font(FitFont.body(size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                if items.isEmpty {
                    Text("No items logged.")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                } else {
                    ForEach(items) { item in
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
                        }
                        .padding(10)
                        .background(FitTheme.cardHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
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
    let title: String
    let value: Double
    let target: Double
    let unit: String
    let ringSize: CGFloat

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(value / target, 1.0)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(FitTheme.cardHighlight, lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        FitTheme.macroColor(for: title),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(Int(value))")
                        .font(FitFont.body(size: ringSize > 80 ? 18 : 13))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Text(unit)
                        .font(FitFont.body(size: ringSize > 80 ? 11 : 9))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            .frame(width: ringSize, height: ringSize)

            Text(title)
                .font(FitFont.body(size: 11))
                .foregroundColor(FitTheme.textSecondary)
        }
    }
}

private struct NutritionLogSheet: View {
    @ObservedObject var viewModel: NutritionViewModel
    let mealType: MealType
    let showBarcodeOnAppear: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [FoodItem] = []
    @State private var isSearching = false
    @State private var selectedItem: FoodItem?
    @State private var portionValue: String = "100"
    @State private var portionUnit: PortionUnit = .grams
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isSavingFavorite = false
    @State private var saveMessage: String?
    @State private var activeMealType: MealType
    @State private var isBarcodeScannerPresented = false
    @State private var hasPresentedBarcode = false

    init(viewModel: NutritionViewModel, mealType: MealType, showBarcodeOnAppear: Bool = false) {
        self.viewModel = viewModel
        self.mealType = mealType
        self.showBarcodeOnAppear = showBarcodeOnAppear
        _activeMealType = State(initialValue: mealType)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Log \(activeMealType.title)")
                            .font(FitFont.heading(size: 22))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.textPrimary)

                        Picker("Meal", selection: $activeMealType) {
                            ForEach(MealType.allCases) { meal in
                                Text(meal.title).tag(meal)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(FitTheme.accent)

                        searchBar

                        if let selectedItem {
                            selectedFoodCard(selectedItem)
                        } else {
                            resultsList
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(FitTheme.textPrimary)
                }
            }
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

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search foods")
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)

            HStack {
                TextField("Chicken breast", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundColor(FitTheme.textPrimary)

                if isSearching {
                    ProgressView()
                        .tint(FitTheme.accent)
                } else {
                    Button("Go") {
                        Task {
                            await runSearch()
                        }
                    }
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.accent)
                }
            }
            .padding(12)
            .background(FitTheme.cardHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(results) { item in
                Button {
                    selectedItem = item
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(FitFont.body(size: 15))
                            .foregroundColor(FitTheme.textPrimary)

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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FitTheme.cardHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            if results.isEmpty && !query.isEmpty && !isSearching {
                Text("No matches found.")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }

    private func selectedFoodCard(_ item: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.name)
                .font(FitFont.body(size: 18))
                .fontWeight(.semibold)
                .foregroundColor(FitTheme.textPrimary)

            Text("Per 100 g estimate")
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.textSecondary)

            macroRow(title: "Calories", value: item.calories, unit: "kcal")
            macroRow(title: "Protein", value: item.protein, unit: "g")
            macroRow(title: "Carbs", value: item.carbs, unit: "g")
            macroRow(title: "Fats", value: item.fats, unit: "g")

            HStack(spacing: 12) {
                TextField("100", text: $portionValue)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(FitTheme.cardHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(FitTheme.textPrimary)

                Picker("Unit", selection: $portionUnit) {
                    ForEach(PortionUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .tint(FitTheme.accent)
            }

            HStack(spacing: 12) {
                ActionButton(title: "Back", style: .secondary) {
                    selectedItem = nil
                }
                ActionButton(title: isSavingFavorite ? "Saving…" : "Save", style: .secondary) {
                    Task {
                        await saveFavorite(item)
                    }
                }
            }

            ActionButton(title: isSubmitting ? "Logging…" : "Add", style: .primary) {
                Task {
                    await addItem(item)
                }
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .padding(16)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func macroRow(title: String, value: Double, unit: String) -> some View {
        HStack {
            Text(title)
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textSecondary)
            Spacer()
            Text("\(Int(value)) \(unit)")
                .font(FitFont.body(size: 13))
                .foregroundColor(FitTheme.textPrimary)
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        do {
            let items = try await NutritionAPIService.shared.searchFoods(query: trimmed, userId: viewModel.userId)
            await MainActor.run {
                results = items
                isSearching = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Unable to search foods."
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

    private func addItem(_ item: FoodItem) async {
        let portion = Double(portionValue) ?? 0
        guard portion > 0 else { return }
        let grams = portionUnit == .grams ? portion : portion * 28.3495
        let multiplier = grams / 100.0

        let macros = MacroTotals(
            calories: item.calories * multiplier,
            protein: item.protein * multiplier,
            carbs: item.carbs * multiplier,
            fats: item.fats * multiplier
        )

        let detail = "\(Int(portion)) \(portionUnit.title)"
        let loggedItem = LoggedFoodItem(
            name: item.name,
            portionValue: portion,
            portionUnit: portionUnit,
            macros: macros,
            detail: detail
        )
        isSubmitting = true
        let success = await viewModel.logManualItem(item: loggedItem, mealType: activeMealType)
        isSubmitting = false
        if success {
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
                saveMessage = "Saved to favorites."
                Haptics.success()
                isSavingFavorite = false
            }
        } catch {
            await MainActor.run {
                saveMessage = "Unable to save favorite."
                isSavingFavorite = false
            }
        }
    }
}

private struct ScanFoodCameraView: View {
    let userId: String
    let mealType: MealType
    let onLogged: () -> Void

    @Environment(\.dismiss) private var dismiss

    @StateObject private var camera = MealPhotoCameraModel()
    @State private var scanMode: ScanMode = .photo
    @State private var selectedItem: PhotosPickerItem?
    @State private var scanResult: MealPhotoScanResult?
    @State private var isSubmitting = false
    @State private var isLogging = false
    @State private var activeMealType: MealType
    @State private var errorMessage: String?
    @State private var hasScannedBarcode = false
    @State private var barcodeSessionId = UUID()
    @State private var showHelp = false

    init(userId: String, mealType: MealType, onLogged: @escaping () -> Void) {
        self.userId = userId
        self.mealType = mealType
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
                isSubmitting = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Scan failed. Try again."
                isSubmitting = false
            }
        }
    }

    private func handleBarcode(_ code: String) async {
        scanResult = nil
        errorMessage = nil
        do {
            let item = try await NutritionAPIService.shared.fetchFoodByBarcode(code: code, userId: userId)
            await MainActor.run {
                scanResult = MealPhotoScanResult(food: item, photoUrl: nil, query: "Barcode", message: nil)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Unable to find a match for that barcode."
            }
        }
    }

    private func scanResultCard(_ result: MealPhotoScanResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan Result")
                .font(FitFont.body(size: 16))
                .fontWeight(.semibold)
                .foregroundColor(FitTheme.textPrimary)

            if let query = result.query, !query.isEmpty {
                Text("Best match for: \(query)")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }

            if let food = result.food {
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

                HStack(spacing: 12) {
                    ActionButton(title: "Scan Again", style: .secondary) {
                        scanResult = nil
                        hasScannedBarcode = false
                        if scanMode == .barcode {
                            barcodeSessionId = UUID()
                        }
                    }
                    ActionButton(title: isLogging ? "Logging…" : "Log Meal", style: .primary) {
                        Task {
                            await logScannedFood(food)
                        }
                    }
                }
            } else {
                Text(result.message ?? "No match found. Try another photo.")
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .padding(16)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func logScannedFood(_ food: FoodItem) async {
        isLogging = true
        let macros = MacroTotals(
            calories: food.calories,
            protein: food.protein,
            carbs: food.carbs,
            fats: food.fats
        )
        let loggedItem = LoggedFoodItem(
            name: food.name,
            portionValue: 0,
            portionUnit: .grams,
            macros: macros,
            detail: food.serving ?? "1 serving"
        )
        do {
            try await NutritionAPIService.shared.logManualItem(
                userId: userId,
                date: Date(),
                mealType: activeMealType.rawValue,
                item: loggedItem
            )
            isLogging = false
            Haptics.success()
            NotificationCenter.default.post(
                name: .fitAINutritionLogged,
                object: nil,
                userInfo: [
                    "macros": [
                        "calories": macros.calories,
                        "protein": macros.protein,
                        "carbs": macros.carbs,
                        "fats": macros.fats
                    ]
                ]
            )
            onLogged()
            dismiss()
        } catch {
            isLogging = false
            errorMessage = "Unable to log scanned food."
        }
    }
}

private struct AnalyzingIndicator: View {
    @State private var animate = false

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

            Text("Analyzing")
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

    @Environment(\.dismiss) private var dismiss

    @State private var favorites: [FoodItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activeMealType: MealType

    init(viewModel: NutritionViewModel, mealType: MealType) {
        self.viewModel = viewModel
        self.mealType = mealType
        _activeMealType = State(initialValue: mealType)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Saved Foods")
                            .font(FitFont.heading(size: 22))
                            .foregroundColor(FitTheme.textPrimary)

                        Picker("Meal", selection: $activeMealType) {
                            ForEach(MealType.allCases) { meal in
                                Text(meal.title).tag(meal)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(FitTheme.accent)

                        if isLoading {
                            ProgressView()
                                .tint(FitTheme.accent)
                        } else if favorites.isEmpty {
                            Text("No saved foods yet.")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        } else {
                            ForEach(favorites) { item in
                                savedFoodRow(item)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(FitFont.body(size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                    }
                    .padding(20)
                }
            }
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
    }

    private func savedFoodRow(_ item: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textPrimary)

                Spacer()

                Button("Log") {
                    Task {
                        await logFavorite(item)
                    }
                }
                .font(FitFont.body(size: 12))
                .foregroundColor(FitTheme.accent)
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
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
        let success = await viewModel.logManualItem(item: loggedItem, mealType: activeMealType)
        if !success {
            await MainActor.run {
                errorMessage = "Unable to log saved food."
            }
        }
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video) else {
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
                output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]
            }
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer
        } catch {
            onError?("Camera permission is required to scan barcodes.")
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        for metadata in metadataObjects {
            guard let readable = metadata as? AVMetadataMachineReadableCodeObject,
                  let code = readable.stringValue else { continue }
            session.stopRunning()
            onFound?(code)
            return
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

#Preview {
    NutritionView(userId: "demo-user", intent: .constant(nil))
}
