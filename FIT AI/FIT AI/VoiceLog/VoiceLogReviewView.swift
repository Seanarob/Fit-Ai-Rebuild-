import SwiftUI

struct VoiceLogReviewView: View {
    @ObservedObject var viewModel: VoiceLogFlowViewModel
    let onClose: () -> Void
    
    @State private var editingItem: VoiceMealItem?
    
    var body: some View {
        ZStack {
            VoiceLogTokens.Color.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    
                    if let payload = payload {
                        totalsCard(payload.totals)
                        
                        if !payload.assumptions.isEmpty {
                            assumptionsCard(payload.assumptions)
                        }
                        
                        if !payload.questionsNeeded.isEmpty {
                            questionsCard(payload.questionsNeeded)
                        }
                        
                        itemsCard(payload.items)
                        
                        actions(payload: payload)
                    } else if case .error(let message, let action) = viewModel.flowState {
                        errorCard(message: message, retryAction: action)
                    }
                }
                .padding(20)
            }
        }
        .sheet(item: $editingItem) { item in
            VoiceLogEditItemSheet(
                userId: viewModel.userId,
                item: item,
                onSave: { updated in
                    Task { await viewModel.applyEditedItem(updated) }
                }
            )
        }
    }
    
    private var payload: VoiceMealAnalyzeResponse? {
        if case .review(let payload) = viewModel.flowState {
            return payload
        }
        return nil
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review")
                    .font(VoiceLogTokens.Typography.title(20))
                    .foregroundColor(VoiceLogTokens.Color.textPrimary)
                Text("Edit items before logging.")
                    .font(VoiceLogTokens.Typography.body(12))
                    .foregroundColor(VoiceLogTokens.Color.textSecondary)
            }
            
            Spacer()
            
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VoiceLogTokens.Color.textSecondary)
                    .padding(10)
                    .background(VoiceLogTokens.Color.card.opacity(0.9))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(VoiceLogTokens.Color.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
    
    private func totalsCard(_ totals: VoiceMealTotals) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Totals")
                .font(VoiceLogTokens.Typography.body(12, weight: .semibold))
                .foregroundColor(VoiceLogTokens.Color.textSecondary)
            
            HStack(spacing: 12) {
                MacroStat(title: "Calories", value: totals.calories, unit: "")
                MacroStat(title: "Protein", value: totals.proteinG, unit: "g")
                MacroStat(title: "Carbs", value: totals.carbsG, unit: "g")
                MacroStat(title: "Fat", value: totals.fatG, unit: "g")
            }
        }
        .padding(14)
        .background(VoiceLogTokens.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg)
                .stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
        )
    }
    
    private func assumptionsCard(_ assumptions: [VoiceMealAssumption]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Assumptions", systemImage: "sparkles")
                .font(VoiceLogTokens.Typography.body(12, weight: .semibold))
                .foregroundColor(VoiceLogTokens.Color.textSecondary)
            
            ForEach(assumptions) { assumption in
                Text(assumption.detail)
                    .font(VoiceLogTokens.Typography.body(12))
                    .foregroundColor(VoiceLogTokens.Color.textPrimary)
            }
        }
        .padding(14)
        .background(VoiceLogTokens.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg)
                .stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
        )
    }
    
    private func questionsCard(_ questions: [VoiceMealQuestion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quick check", systemImage: "questionmark.circle")
                .font(VoiceLogTokens.Typography.body(12, weight: .semibold))
                .foregroundColor(VoiceLogTokens.Color.textSecondary)
            
            Text("Some items were ambiguous. You can still log, or tap Re-analyze after edits.")
                .font(VoiceLogTokens.Typography.body(12))
                .foregroundColor(VoiceLogTokens.Color.textSecondary)
            
            ForEach(questions) { q in
                VStack(alignment: .leading, spacing: 4) {
                    Text(q.prompt)
                        .font(VoiceLogTokens.Typography.body(12, weight: .semibold))
                        .foregroundColor(VoiceLogTokens.Color.textPrimary)
                    Text(q.options.joined(separator: " • "))
                        .font(VoiceLogTokens.Typography.body(11))
                        .foregroundColor(VoiceLogTokens.Color.textSecondary)
                }
            }
        }
        .padding(14)
        .background(VoiceLogTokens.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg)
                .stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
        )
    }
    
    private func itemsCard(_ items: [VoiceMealItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Items")
                .font(VoiceLogTokens.Typography.body(12, weight: .semibold))
                .foregroundColor(VoiceLogTokens.Color.textSecondary)
            
            if items.isEmpty {
                Text("No items found. Tap Re-analyze or try Voice Log again.")
                    .font(VoiceLogTokens.Typography.body(12))
                    .foregroundColor(VoiceLogTokens.Color.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        VoiceLogItemRow(
                            item: item,
                            onEdit: { editingItem = item },
                            onDelete: { viewModel.deleteItem(id: item.id) }
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(VoiceLogTokens.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg)
                .stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
        )
    }
    
    private func actions(payload: VoiceMealAnalyzeResponse) -> some View {
        VStack(spacing: 12) {
            Button {
                Task { await viewModel.logMeal() }
            } label: {
                Text(viewModel.isSubmitting ? "Logging…" : "Log Meal")
                    .font(VoiceLogTokens.Typography.body(15, weight: .semibold))
                    .foregroundColor(FitTheme.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md))
                    .shadow(color: FitTheme.buttonShadow, radius: 10, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSubmitting || payload.items.isEmpty)
            .opacity((viewModel.isSubmitting || payload.items.isEmpty) ? 0.75 : 1)
            
            Button {
                Task { await viewModel.reanalyze() }
            } label: {
                Text("Re-analyze")
                    .font(VoiceLogTokens.Typography.body(14, weight: .semibold))
                    .foregroundColor(VoiceLogTokens.Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(VoiceLogTokens.Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md)
                            .stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
    
    private func errorCard(message: String, retryAction: VoiceLogRetryAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Something went wrong", systemImage: "exclamationmark.triangle.fill")
                .font(VoiceLogTokens.Typography.body(14, weight: .semibold))
                .foregroundColor(VoiceLogTokens.Color.textPrimary)
            
            Text(message)
                .font(VoiceLogTokens.Typography.body(12))
                .foregroundColor(VoiceLogTokens.Color.textSecondary)
            
            Button("Retry") {
                Task { await viewModel.retry(from: retryAction) }
            }
            .buttonStyle(.borderedProminent)
            .tint(VoiceLogTokens.Color.accent)
        }
        .padding(14)
        .background(VoiceLogTokens.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg)
                .stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
        )
    }
}

private struct MacroStat: View {
    let title: String
    let value: Double
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(VoiceLogTokens.Typography.body(11, weight: .semibold))
                .foregroundColor(VoiceLogTokens.Color.textSecondary)
            Text("\(value.voiceLogRounded)\(unit.isEmpty ? "" : " \(unit)")")
                .font(VoiceLogTokens.Typography.body(15, weight: .semibold))
                .foregroundColor(VoiceLogTokens.Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VoiceLogItemRow: View {
    let item: VoiceMealItem
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayName)
                    .font(VoiceLogTokens.Typography.body(14, weight: .semibold))
                    .foregroundColor(VoiceLogTokens.Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Text("\(item.qty.voiceLogQuantity) \(item.unit)")
                            .font(VoiceLogTokens.Typography.body(12, weight: .semibold))
                            .foregroundColor(VoiceLogTokens.Color.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(VoiceLogTokens.Color.accentSoft)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(item.macros.calories.voiceLogRounded) cal • P \(item.macros.proteinG.voiceLogRounded)g • C \(item.macros.carbsG.voiceLogRounded)g • F \(item.macros.fatG.voiceLogRounded)g")
                        .font(VoiceLogTokens.Typography.body(11))
                        .foregroundColor(VoiceLogTokens.Color.textSecondary)
                        .lineLimit(2)
                }
            }
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VoiceLogTokens.Color.textSecondary)
                    .padding(8)
                    .background(VoiceLogTokens.Color.card.opacity(0.9))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(VoiceLogTokens.Color.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(VoiceLogTokens.Color.card.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md)
                .stroke(VoiceLogTokens.Color.stroke.opacity(0.8), lineWidth: 1)
        )
    }
}

private extension Double {
    var voiceLogRounded: String {
        if self >= 1000 { return String(Int(self.rounded())) }
        if self >= 100 { return String(Int(self.rounded())) }
        return String(format: "%.0f", self.rounded())
    }
    
    var voiceLogQuantity: String {
        if abs(self.rounded() - self) < 0.0001 { return String(Int(self.rounded())) }
        return String(format: "%.2g", self)
    }
}

#Preview("Review") {
    let vm = VoiceLogFlowViewModel(
        userId: "preview",
        mealType: .dinner,
        logDate: Date(),
        apiClient: MockMealAPIClient()
    )
    vm.flowState = .review(payload: VoiceMealAnalyzeResponse(
        transcriptOriginal: "Greek yogurt with granola",
        assumptions: [VoiceMealAssumption(type: "milk_default", detail: "Assumed 2% milk (150g) with cereal.")],
        totals: VoiceMealTotals(calories: 720, proteinG: 42, carbsG: 68, fatG: 28),
        items: [
            VoiceMealItem(
                id: UUID().uuidString,
                displayName: "Greek yogurt (plain)",
                qty: 1,
                unit: "cup",
                gramsResolved: 245,
                rawCooked: nil,
                source: VoiceMealItemSource(provider: .usda, foodId: "123", label: "USDA"),
                macros: VoiceMealItemMacros(calories: 130, proteinG: 23, carbsG: 9, fatG: 0),
                confidence: 0.86,
                assumptionsUsed: []
            ),
            VoiceMealItem(
                id: UUID().uuidString,
                displayName: "Granola",
                qty: 0.5,
                unit: "cup",
                gramsResolved: 55,
                rawCooked: nil,
                source: VoiceMealItemSource(provider: .fatsecret, foodId: "456", label: "FatSecret"),
                macros: VoiceMealItemMacros(calories: 240, proteinG: 6, carbsG: 36, fatG: 9),
                confidence: 0.74,
                assumptionsUsed: []
            ),
        ],
        questionsNeeded: []
    ))
    return VoiceLogReviewView(viewModel: vm, onClose: {})
}
