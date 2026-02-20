import SwiftUI

enum StreakBadgeRarity: String, CaseIterable {
    case common = "Common"
    case uncommon = "Uncommon"
    case rare = "Rare"
    case epic = "Epic"
    case legendary = "Legendary"
    case mythic = "Mythic"

    var color: Color {
        switch self {
        case .common: return Color.green
        case .uncommon: return Color.blue
        case .rare: return Color.purple
        case .epic: return Color.orange
        case .legendary: return Color.yellow
        case .mythic: return Color.red
        }
    }
}

struct StreakBadgeDefinition: Identifiable, Hashable {
    let id: Int
    let imageName: String
    let title: String
    let nickname: String
    let rarity: StreakBadgeRarity
    let requiredDays: Int

    var requirementText: String {
        "\(requiredDays)-day app check-in streak"
    }
}

enum StreakBadgeCatalog {
    static let all: [StreakBadgeDefinition] = [
        .init(id: 1, imageName: "StreakBadge01", title: "First Flame", nickname: "Spark", rarity: .common, requiredDays: 3),
        .init(id: 2, imageName: "StreakBadge02", title: "Weekly Ember", nickname: "Ember", rarity: .uncommon, requiredDays: 7),
        .init(id: 3, imageName: "StreakBadge03", title: "Rhythm Runner", nickname: "Stride", rarity: .uncommon, requiredDays: 14),
        .init(id: 4, imageName: "StreakBadge04", title: "Consistency Knight", nickname: "Aegis", rarity: .rare, requiredDays: 30),
        .init(id: 5, imageName: "StreakBadge05", title: "Discipline Sage", nickname: "Sage", rarity: .rare, requiredDays: 60),
        .init(id: 6, imageName: "StreakBadge06", title: "Streak Titan", nickname: "Titan", rarity: .epic, requiredDays: 90),
        .init(id: 7, imageName: "StreakBadge07", title: "Iron Phoenix", nickname: "Phoenix", rarity: .legendary, requiredDays: 120),
        .init(id: 8, imageName: "StreakBadge08", title: "Mythic Zenith", nickname: "Zenith", rarity: .mythic, requiredDays: 180)
    ]
}
