import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct NutritionView: View {
    let userId: String

    @StateObject private var viewModel: NutritionViewModel
    @State private var isLogSheetPresented = false
    @State private var isScanSheetPresented = false
    @State private var selectedMealType: MealType = .breakfast
    @State private var mealPlanSnapshot: MealPlanSnapshot?
    @State private var mealPlanStatus: String?

    private let targets = MacroTargets(calories: 2500, protein: 185, carbs: 240, fats: 70)

    init(userId: String) {
        self.userId = userId
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

                    quickActionsCard

                    mealPlanCard

                    ForEach(MealType.allCases) { meal in
                        mealSectionCard(meal)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.custom("Avenir Next Condensed", size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $isLogSheetPresented) {
            NutritionLogSheet(
                viewModel: viewModel,
                mealType: selectedMealType
            )
        }
        .sheet(isPresented: $isScanSheetPresented) {
            NutritionScanSheet(
                userId: userId,
                mealType: selectedMealType,
                onLogged: {
                    Task {
                        await viewModel.loadDailyLogs()
                    }
                }
            )
        }
        .task {
            await viewModel.loadDailyLogs()
            await loadActiveMealPlan()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nutrition")
                    .font(.custom("Avenir Next Condensed", size: 30))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                Text("Log meals, scan food, and track macros.")
                    .font(.custom("Avenir Next Condensed", size: 15))
                    .foregroundColor(FitTheme.textSecondary)
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .padding(10)
                    .background(FitTheme.cardBackground)
                    .clipShape(Circle())
            }
        }
    }

    private var macroSummaryCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Today's Macros")
                        .font(.custom("Avenir Next Condensed", size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Spacer()

                    Text("Daily target")
                        .font(.custom("Avenir Next Condensed", size: 12))
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

    private var quickActionsCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("Quick Actions")
                    .font(.custom("Avenir Next Condensed", size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(FitTheme.textPrimary)

                HStack(spacing: 12) {
                    ActionButton(title: "Log Meal", style: .primary) {
                        selectedMealType = .breakfast
                        isLogSheetPresented = true
                    }
                    ActionButton(title: "Scan Food", style: .secondary) {
                        selectedMealType = .lunch
                        isScanSheetPresented = true
                    }
                }

                ActionButton(title: "Meal Plan", style: .secondary) {
                    Task {
                        await generateMealPlan()
                    }
                }
            }
        }
    }

    private var mealPlanCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Meal Plan")
                        .font(.custom("Avenir Next Condensed", size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Spacer()

                    if let status = mealPlanStatus {
                        Text(status)
                            .font(.custom("Avenir Next Condensed", size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }

                if let plan = mealPlanSnapshot, !plan.meals.isEmpty {
                    ForEach(plan.meals) { meal in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(meal.name)
                                .font(.custom("Avenir Next Condensed", size: 15))
                                .foregroundColor(FitTheme.textPrimary)

                            Text("\(Int(meal.macros.calories)) kcal · P \(Int(meal.macros.protein)) · C \(Int(meal.macros.carbs)) · F \(Int(meal.macros.fats))")
                                .font(.custom("Avenir Next Condensed", size: 12))
                                .foregroundColor(FitTheme.textSecondary)

                            if !meal.items.isEmpty {
                                Text(meal.items.joined(separator: ", "))
                                    .font(.custom("Avenir Next Condensed", size: 11))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                        }
                        .padding(10)
                        .background(FitTheme.cardHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    if let totals = plan.totals {
                        Text("Total: \(Int(totals.calories)) kcal · P \(Int(totals.protein)) · C \(Int(totals.carbs)) · F \(Int(totals.fats))")
                            .font(.custom("Avenir Next Condensed", size: 13))
                            .foregroundColor(FitTheme.accent)
                    }

                    if let notes = plan.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.custom("Avenir Next Condensed", size: 12))
                            .foregroundColor(FitTheme.textSecondary)
                    }
                } else {
                    Text("Generate a macro-focused plan tailored to your targets.")
                        .font(.custom("Avenir Next Condensed", size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }

                ActionButton(title: "Generate Plan", style: .primary) {
                    Task {
                        await generateMealPlan()
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
                        .font(.custom("Avenir Next Condensed", size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Spacer()

                    Button("Add") {
                        selectedMealType = meal
                        isLogSheetPresented = true
                    }
                    .font(.custom("Avenir Next Condensed", size: 13))
                    .foregroundColor(FitTheme.accent)
                }

                if items.isEmpty {
                    Text("No items logged yet.")
                        .font(.custom("Avenir Next Condensed", size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                } else {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.custom("Avenir Next Condensed", size: 15))
                                    .foregroundColor(FitTheme.textPrimary)

                                Text(item.detail)
                                    .font(.custom("Avenir Next Condensed", size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                            Spacer()
                            Text("\(Int(item.macros.calories)) kcal")
                                .font(.custom("Avenir Next Condensed", size: 12))
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

    private func generateMealPlan() async {
        guard !userId.isEmpty else { return }
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
                        FitTheme.accent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(Int(value))")
                        .font(.custom("Avenir Next Condensed", size: ringSize > 80 ? 18 : 13))
                        .fontWeight(.semibold)
                        .foregroundColor(FitTheme.textPrimary)

                    Text(unit)
                        .font(.custom("Avenir Next Condensed", size: ringSize > 80 ? 11 : 9))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            .frame(width: ringSize, height: ringSize)

            Text(title)
                .font(.custom("Avenir Next Condensed", size: 11))
                .foregroundColor(FitTheme.textSecondary)
        }
    }
}

private struct NutritionLogSheet: View {
    @ObservedObject var viewModel: NutritionViewModel
    let mealType: MealType

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [FoodItem] = []
    @State private var isSearching = false
    @State private var selectedItem: FoodItem?
    @State private var portionValue: String = "100"
    @State private var portionUnit: PortionUnit = .grams
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var activeMealType: MealType
    @State private var isBarcodeScannerPresented = false

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
                        Text("Log \(activeMealType.title)")
                            .font(.custom("Avenir Next Condensed", size: 22))
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
                                .font(.custom("Avenir Next Condensed", size: 12))
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
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search foods")
                .font(.custom("Avenir Next Condensed", size: 13))
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
                    .font(.custom("Avenir Next Condensed", size: 13))
                    .foregroundColor(FitTheme.accent)
                }
            }
            .padding(12)
            .background(FitTheme.cardHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            ActionButton(title: "Scan barcode", style: .secondary) {
                isBarcodeScannerPresented = true
            }
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
                            .font(.custom("Avenir Next Condensed", size: 15))
                            .foregroundColor(FitTheme.textPrimary)

                        Text("\(Int(item.calories)) kcal · P \(Int(item.protein)) · C \(Int(item.carbs)) · F \(Int(item.fats))")
                            .font(.custom("Avenir Next Condensed", size: 12))
                            .foregroundColor(FitTheme.textSecondary)

                        if let serving = item.serving, !serving.isEmpty {
                            Text(serving)
                                .font(.custom("Avenir Next Condensed", size: 11))
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
                    .font(.custom("Avenir Next Condensed", size: 12))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
    }

    private func selectedFoodCard(_ item: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.name)
                .font(.custom("Avenir Next Condensed", size: 18))
                .fontWeight(.semibold)
                .foregroundColor(FitTheme.textPrimary)

            Text("Per 100 g estimate")
                .font(.custom("Avenir Next Condensed", size: 12))
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
                ActionButton(title: isSubmitting ? "Logging…" : "Add", style: .primary) {
                    Task {
                        await addItem(item)
                    }
                }
            }
        }
        .padding(16)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func macroRow(title: String, value: Double, unit: String) -> some View {
        HStack {
            Text(title)
                .font(.custom("Avenir Next Condensed", size: 13))
                .foregroundColor(FitTheme.textSecondary)
            Spacer()
            Text("\(Int(value)) \(unit)")
                .font(.custom("Avenir Next Condensed", size: 13))
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
}

private struct NutritionScanSheet: View {
    let userId: String
    let mealType: MealType
    let onLogged: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var imageData: Data?
    @State private var isSubmitting = false
    @State private var resultText: String?
    @State private var activeMealType: MealType
    @State private var loadError: String?
    @State private var isShowingCamera = false
    @State private var cameraError: String?

    init(userId: String, mealType: MealType, onLogged: @escaping () -> Void) {
        self.userId = userId
        self.mealType = mealType
        self.onLogged = onLogged
        _activeMealType = State(initialValue: mealType)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Scan Meal Photo")
                            .font(.custom("Avenir Next Condensed", size: 22))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.textPrimary)

                        Text("Capture or choose a photo to scan.")
                            .font(.custom("Avenir Next Condensed", size: 13))
                            .foregroundColor(FitTheme.textSecondary)

                        Picker("Meal", selection: $activeMealType) {
                            ForEach(MealType.allCases) { meal in
                                Text(meal.title).tag(meal)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(FitTheme.accent)

                        HStack(spacing: 12) {
                            Button("Take photo") {
                                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                    isShowingCamera = true
                                    cameraError = nil
                                } else {
                                    cameraError = "Camera is not available on this device."
                                }
                            }
                            .font(.custom("Avenir Next Condensed", size: 14))
                            .fontWeight(.semibold)
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(FitTheme.cardHighlight)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                HStack {
                                    Image(systemName: "photo.on.rectangle")
                                    Text(selectedImage == nil ? "Pick a photo" : "Change photo")
                                }
                                .font(.custom("Avenir Next Condensed", size: 14))
                                .foregroundColor(FitTheme.textPrimary)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(FitTheme.cardHighlight)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }

                        if let selectedImage {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        } else {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(FitTheme.cardHighlight)
                                .frame(height: 180)
                                .overlay(
                                    Text("No photo selected")
                                        .font(.custom("Avenir Next Condensed", size: 12))
                                        .foregroundColor(FitTheme.textSecondary)
                                )
                        }

                        ActionButton(title: isSubmitting ? "Scanning…" : "Submit", style: .primary) {
                            Task {
                                await submit()
                            }
                        }

                        if let cameraError {
                            Text(cameraError)
                                .font(.custom("Avenir Next Condensed", size: 12))
                                .foregroundColor(.red.opacity(0.8))
                        }

                        if let loadError {
                            Text(loadError)
                                .font(.custom("Avenir Next Condensed", size: 12))
                                .foregroundColor(FitTheme.textSecondary)
                        }

                        if let resultText {
                            Text(resultText)
                                .font(.custom("Avenir Next Condensed", size: 12))
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
        .sheet(isPresented: $isShowingCamera) {
            SingleImageCameraPicker(isPresented: $isShowingCamera) { image in
                handleSelectedImage(image)
            }
        }
        .onChange(of: selectedItem) { newValue in
            guard let newValue else { return }
            Task {
                loadError = nil
                do {
                    if let data = try await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        handleSelectedImage(image, data: data)
                    } else {
                        loadError = "Unable to load photo."
                    }
                } catch {
                    loadError = "Unable to load photo."
                }
            }
        }
    }

    private func handleSelectedImage(_ image: UIImage, data: Data? = nil) {
        selectedImage = image
        imageData = data ?? image.jpegData(compressionQuality: 0.85)
    }

    private func submit() async {
        guard let imageData else {
            loadError = "Pick a photo first."
            return
        }
        isSubmitting = true
        do {
            let response = try await NutritionAPIService.shared.scanMealPhoto(
                userId: userId,
                mealType: activeMealType.rawValue,
                imageData: imageData
            )
            await MainActor.run {
                resultText = response
                isSubmitting = false
            }
            onLogged()
        } catch {
            await MainActor.run {
                resultText = "Scan failed. Try again."
                isSubmitting = false
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
                .font(.custom("Avenir Next Condensed", size: 14))
                .fontWeight(.semibold)
                .foregroundColor(style == .primary ? FitTheme.buttonText : FitTheme.textPrimary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(style == .primary ? FitTheme.accent : FitTheme.cardHighlight)
                .clipShape(Capsule())
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
                    .stroke(FitTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: FitTheme.shadow, radius: 16, x: 0, y: 8)
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
    NutritionView(userId: "demo-user")
}
