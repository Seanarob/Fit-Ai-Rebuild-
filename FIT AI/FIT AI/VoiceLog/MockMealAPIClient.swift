import Foundation

struct MockMealAPIClient: MealAPIClientProtocol {
    var artificialDelayMs: UInt64 = 650
    var shouldFail: Bool = false
    
    func analyzeVoiceMeal(_ request: VoiceMealAnalyzeRequest) async throws -> VoiceMealAnalyzeResponse {
        try await Task.sleep(nanoseconds: artificialDelayMs * 1_000_000)
        if shouldFail { throw VoiceLogAPIError.server(message: "Mock failure. Try again.") }
        
        return VoiceMealAnalyzeResponse(
            transcriptOriginal: request.transcript,
            assumptions: [
                VoiceMealAssumption(type: "milk_default", detail: "Assumed 2% milk (150g) with cereal.")
            ],
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
                VoiceMealItem(
                    id: UUID().uuidString,
                    displayName: "2% milk",
                    qty: 150,
                    unit: "g",
                    gramsResolved: 150,
                    rawCooked: nil,
                    source: VoiceMealItemSource(provider: .usda, foodId: "789", label: "USDA"),
                    macros: VoiceMealItemMacros(calories: 110, proteinG: 8, carbsG: 12, fatG: 4),
                    confidence: 0.65,
                    assumptionsUsed: ["milk_default"]
                )
            ],
            questionsNeeded: []
        )
    }
    
    func repriceVoiceMeal(_ request: VoiceMealRepriceRequest) async throws -> VoiceMealRepriceResponse {
        try await Task.sleep(nanoseconds: 350_000_000)
        if shouldFail { throw VoiceLogAPIError.server(message: "Mock failure. Try again.") }
        
        let items = request.items.map { item in
            var updated = item
            // Mock: scale macros by qty compared to 1 unit baseline.
            let scale = max(updated.qty, 0.01)
            updated.macros = VoiceMealItemMacros(
                calories: updated.macros.calories * scale,
                proteinG: updated.macros.proteinG * scale,
                carbsG: updated.macros.carbsG * scale,
                fatG: updated.macros.fatG * scale
            )
            return updated
        }
        
        let totals = items.reduce(VoiceMealTotals.zero) { partial, item in
            VoiceMealTotals(
                calories: partial.calories + item.macros.calories,
                proteinG: partial.proteinG + item.macros.proteinG,
                carbsG: partial.carbsG + item.macros.carbsG,
                fatG: partial.fatG + item.macros.fatG
            )
        }
        
        return VoiceMealAnalyzeResponse(
            transcriptOriginal: "",
            assumptions: [],
            totals: totals,
            items: items,
            questionsNeeded: []
        )
    }
    
    func logMeal(_ request: VoiceMealLogRequest) async throws -> VoiceMealLogResponse {
        try await Task.sleep(nanoseconds: 450_000_000)
        if shouldFail { throw VoiceLogAPIError.server(message: "Mock failure. Try again.") }
        return VoiceMealLogResponse(success: true)
    }
}

