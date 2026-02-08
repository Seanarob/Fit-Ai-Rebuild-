import Foundation

enum SplitCreationMode: String, CaseIterable, Identifiable, Codable {
    case ai
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai:
            return "AI picks for you"
        case .custom:
            return "I'll build my own"
        }
    }

    var subtitle: String {
        switch self {
        case .ai:
            return "Fast setup with smart defaults you can tweak."
        case .custom:
            return "Choose the split structure and muscle focus."
        }
    }

    var icon: String {
        switch self {
        case .ai:
            return "sparkles"
        case .custom:
            return "slider.horizontal.3"
        }
    }
}

struct SplitSetupPreferences: Codable {
    var mode: String
    var daysPerWeek: Int
    var trainingDays: [String]
}
