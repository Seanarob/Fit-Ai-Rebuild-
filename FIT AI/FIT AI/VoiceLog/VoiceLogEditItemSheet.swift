import SwiftUI

struct VoiceLogEditItemSheet: View {
    let userId: String
    let item: VoiceMealItem
    let onSave: (VoiceMealItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var qty: Double
    @State private var unit: String
    @State private var rawCooked: VoiceMealItem.RawCooked?
    @State private var displayName: String
    @State private var source: VoiceMealItemSource
    @State private var showSearch = false
    
    @State private var selectedMilkPreset: MilkPreset = .twoPercent
    
    init(userId: String, item: VoiceMealItem, onSave: @escaping (VoiceMealItem) -> Void) {
        self.userId = userId
        self.item = item
        self.onSave = onSave
        _qty = State(initialValue: item.qty)
        _unit = State(initialValue: item.unit)
        _rawCooked = State(initialValue: item.rawCooked)
        _displayName = State(initialValue: item.displayName)
        _source = State(initialValue: item.source)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Quantity") {
                    HStack {
                        TextField("Qty", value: $qty, format: .number)
                            .keyboardType(.decimalPad)
                        Spacer()
                        Stepper("", value: $qty, in: 0.0...9999.0, step: qtyStep)
                            .labelsHidden()
                    }
                }
                
                Section("Unit") {
                    Picker("Unit", selection: $unit) {
                        ForEach(unitOptions, id: \.self) { u in
                            Text(u).tag(u)
                        }
                    }
                }
                
                if shouldShowRawCooked {
                    Section("Raw / Cooked") {
                        Picker("State", selection: Binding(
                            get: { rawCooked ?? .cooked },
                            set: { rawCooked = $0 }
                        )) {
                            Text("Cooked").tag(VoiceMealItem.RawCooked.cooked)
                            Text("Raw").tag(VoiceMealItem.RawCooked.raw)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                if shouldShowMilkPresets {
                    Section {
                        Picker("Type", selection: $selectedMilkPreset) {
                            ForEach(MilkPreset.allCases, id: \.self) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        Button("Search match") { showSearch = true }
                    } header: {
                        Text("Milk")
                    } footer: {
                        Text("Changing milk type updates the food match (and macros) after repricing.")
                    }
                } else {
                    Section {
                        Button("Search match") { showSearch = true }
                    } header: {
                        Text("Match")
                    } footer: {
                        Text("Replace the nutrition database match if the item seems off.")
                    }
                }
                
                Section {
                    Button("Save") {
                        var updated = item
                        updated.displayName = displayName
                        updated.source = source
                        updated.qty = max(qty, 0)
                        updated.unit = unit
                        updated.rawCooked = rawCooked
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(qty <= 0)
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        var updated = item
                        updated.displayName = displayName
                        updated.source = source
                        updated.qty = max(qty, 0)
                        updated.unit = unit
                        updated.rawCooked = rawCooked
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(qty <= 0)
                }
            }
            .navigationDestination(isPresented: $showSearch) {
                VoiceLogSearchMatchView(
                    userId: userId,
                    initialQuery: searchSeedQuery,
                    onPick: { picked in
                        displayName = picked.displayName
                        source = picked.source
                        showSearch = false
                    }
                )
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private var qtyStep: Double {
        if unit.lowercased() == "g" { return 5 }
        if unit.lowercased() == "oz" { return 0.5 }
        return 0.25
    }
    
    private var unitOptions: [String] {
        var options = ["count", "serving", "g", "oz", "lb", "cup", "tbsp", "tsp", "slice"]
        if !options.contains(unit) { options.insert(unit, at: 0) }
        return options
    }
    
    private var shouldShowRawCooked: Bool {
        if rawCooked != nil { return true }
        let name = item.displayName.lowercased()
        return ["beef", "chicken", "turkey", "rice", "pasta", "steak"].contains(where: { name.contains($0) })
    }
    
    private var shouldShowMilkPresets: Bool {
        let name = item.displayName.lowercased()
        if item.assumptionsUsed.contains(where: { $0.contains("milk") }) { return true }
        return name.contains("milk")
    }
    
    private var searchSeedQuery: String {
        if shouldShowMilkPresets {
            return selectedMilkPreset.query
        }
        return displayName
    }
}

private enum MilkPreset: CaseIterable, Hashable {
    case twoPercent
    case whole
    case skim
    case almond
    case oat
    
    var title: String {
        switch self {
        case .twoPercent: return "2%"
        case .whole: return "Whole"
        case .skim: return "Skim"
        case .almond: return "Almond"
        case .oat: return "Oat"
        }
    }
    
    var query: String {
        switch self {
        case .twoPercent: return "2% milk"
        case .whole: return "whole milk"
        case .skim: return "skim milk"
        case .almond: return "almond milk"
        case .oat: return "oat milk"
        }
    }
}

private struct VoiceLogSearchMatchView: View {
    let userId: String
    let initialQuery: String
    let onPick: (PickedMatch) -> Void
    
    @State private var query: String
    @State private var isLoading = false
    @State private var error: String?
    @State private var results: [FoodItem] = []
    
    private let service = NutritionAPIService()
    
    init(userId: String, initialQuery: String, onPick: @escaping (PickedMatch) -> Void) {
        self.userId = userId
        self.initialQuery = initialQuery
        self.onPick = onPick
        _query = State(initialValue: initialQuery)
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Search foods", text: $query)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button("Search") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isLoading)
                }
            }
            
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Searching…")
                            .foregroundColor(FitTheme.textSecondary)
                    }
                }
            }
            
            if let error {
                Section {
                    Text(error)
                        .foregroundColor(FitTheme.textSecondary)
                }
            }
            
            if !results.isEmpty {
                Section("Results") {
                    ForEach(results) { item in
                        Button {
                            onPick(PickedMatch(from: item))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .foregroundColor(FitTheme.textPrimary)
                                Text(item.source.uppercased())
                                    .font(.caption)
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Search match")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if results.isEmpty, query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                await search()
            }
        }
    }
    
    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        isLoading = true
        error = nil
        do {
            results = try await service.searchFoods(query: q, userId: userId)
        } catch {
            self.error = "Couldn't search right now. Try again."
            results = []
        }
        isLoading = false
    }
}

private struct PickedMatch: Hashable {
    var displayName: String
    var source: VoiceMealItemSource
    
    init(from item: FoodItem) {
        displayName = item.name
        source = VoiceMealItemSource(
            provider: VoiceMealItemSource.Provider(fromNutritionSource: item.source),
            foodId: item.fdcId ?? item.id,
            label: item.source
        )
    }
}

private extension VoiceMealItemSource.Provider {
    init(fromNutritionSource source: String) {
        switch source.lowercased() {
        case "nutritionix": self = .nutritionix
        case "fatsecret": self = .fatsecret
        default: self = .usda
        }
    }
}

#Preview("Edit Item") {
    let item = VoiceMealItem(
        id: UUID().uuidString,
        displayName: "2% milk",
        qty: 150,
        unit: "g",
        gramsResolved: 150,
        rawCooked: nil,
        source: VoiceMealItemSource(provider: .usda, foodId: "789", label: "USDA"),
        macros: .zero,
        confidence: 0.6,
        assumptionsUsed: ["milk_default"]
    )
    return VoiceLogEditItemSheet(userId: "preview", item: item, onSave: { _ in })
}
