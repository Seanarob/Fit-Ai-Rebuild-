import Foundation

// MARK: - Shared

enum VoiceLogAPIError: LocalizedError, Equatable {
    case invalidResponse
    case server(message: String)
    case decoding
    case shortTranscript
    case noSpeechDetected
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't reach the server. Please try again."
        case .server(let message):
            return message
        case .decoding:
            return "We couldn't read the server response. Please try again."
        case .shortTranscript:
            return "Try saying a bit more detail (at least 3 words)."
        case .noSpeechDetected:
            return "No speech detected. Try again in a quieter space."
        }
    }
}

struct VoiceMealContext: Codable, Hashable {
    enum MealType: String, Codable, Hashable {
        case breakfast, lunch, dinner, snack, unknown
    }
    
    var mealType: MealType
    var dietPrefs: [String]?
    var defaultUnits: String
}

struct VoiceMealAnalyzeRequest: Codable, Hashable {
    var transcript: String
    var locale: String
    var timezone: String
    var timestamp: String
    var userId: String
    var context: VoiceMealContext
}

struct VoiceMealAssumption: Codable, Hashable, Identifiable {
    var id: String { type + ":" + detail }
    var type: String
    var detail: String
}

struct VoiceMealTotals: Codable, Hashable {
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
}

struct VoiceMealItemSource: Codable, Hashable {
    enum Provider: String, Codable, Hashable {
        case nutritionix
        case fatsecret
        case usda
    }
    
    var provider: Provider
    var foodId: String
    var label: String?
}

struct VoiceMealItemMacros: Codable, Hashable {
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
}

struct VoiceMealQuestion: Codable, Hashable, Identifiable {
    var id: String { field }
    var field: String
    var prompt: String
    var options: [String]
}

struct VoiceMealItem: Codable, Hashable, Identifiable {
    enum RawCooked: String, Codable, Hashable {
        case raw
        case cooked
    }
    
    var id: String
    var displayName: String
    var qty: Double
    var unit: String
    var gramsResolved: Double?
    var rawCooked: RawCooked?
    var source: VoiceMealItemSource
    var macros: VoiceMealItemMacros
    var confidence: Double
    var assumptionsUsed: [String]
}

struct VoiceMealAnalyzeResponse: Codable, Hashable {
    var transcriptOriginal: String
    var assumptions: [VoiceMealAssumption]
    var totals: VoiceMealTotals
    var items: [VoiceMealItem]
    var questionsNeeded: [VoiceMealQuestion]
}

struct VoiceMealRepriceRequest: Codable, Hashable {
    var locale: String
    var timezone: String
    var timestamp: String
    var userId: String
    var items: [VoiceMealItem]
}

typealias VoiceMealRepriceResponse = VoiceMealAnalyzeResponse

struct VoiceMealLogRequest: Codable, Hashable {
    var transcriptOriginal: String
    var items: [VoiceMealItem]
    var totals: VoiceMealTotals
    var timestamp: String
    var mealType: VoiceMealContext.MealType
    var userId: String
}

struct VoiceMealLogResponse: Codable, Hashable {
    var success: Bool
}

// MARK: - Helpers

extension VoiceMealTotals {
    static var zero: VoiceMealTotals {
        VoiceMealTotals(calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
    }
}

extension VoiceMealItemMacros {
    static var zero: VoiceMealItemMacros {
        VoiceMealItemMacros(calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
    }
}

extension VoiceMealAnalyzeResponse {
    static var empty: VoiceMealAnalyzeResponse {
        VoiceMealAnalyzeResponse(
            transcriptOriginal: "",
            assumptions: [],
            totals: .zero,
            items: [],
            questionsNeeded: []
        )
    }
}

extension VoiceMealContext.MealType {
    init(from mealType: MealType) {
        switch mealType {
        case .breakfast: self = .breakfast
        case .lunch: self = .lunch
        case .dinner: self = .dinner
        case .snacks: self = .snack
        }
    }
}
