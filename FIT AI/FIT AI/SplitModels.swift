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

enum SplitType: String, CaseIterable, Identifiable, Codable {
    case smart
    case fullBody
    case upperLower
    case pushPullLegs
    case hybrid
    case bodyPart
    case arnold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart:
            return "AI picks for you"
        case .fullBody:
            return "Full Body"
        case .upperLower:
            return "Upper / Lower"
        case .pushPullLegs:
            return "Push / Pull / Legs"
        case .hybrid:
            return "PPL + Upper/Lower"
        case .bodyPart:
            return "Body-Part Split"
        case .arnold:
            return "Arnold Split"
        }
    }

    var subtitle: String {
        switch self {
        case .smart:
            return "FitAI chooses the best split for your days and goal."
        case .fullBody:
            return "All major muscle groups each session."
        case .upperLower:
            return "Upper = chest/back/shoulders/arms; Lower = quads/glutes/hamstrings/calves."
        case .pushPullLegs:
            return "Push = chest/shoulders/triceps; Pull = back/biceps/forearms; Legs = quads/glutes/hamstrings/calves."
        case .hybrid:
            return "Push/Pull/Legs plus Upper/Lower balance."
        case .bodyPart:
            return "One or two body parts per day."
        case .arnold:
            return "Chest/Back, Shoulders/Arms, Legs — repeat."
        }
    }

    func dayLabels(for daysPerWeek: Int) -> [String] {
        let clamped = min(max(daysPerWeek, 2), 7)
        switch self {
        case .smart:
            return []
        case .fullBody:
            let base = ["Full Body A", "Full Body B", "Full Body C", "Full Body D", "Full Body E", "Full Body F", "Full Body G"]
            return Array(base.prefix(clamped))
        case .upperLower:
            return repeatingLabels(["Upper", "Lower"], count: clamped)
        case .pushPullLegs:
            return repeatingLabels(["Push", "Pull", "Legs"], count: clamped)
        case .hybrid:
            return repeatingLabels(["Push", "Pull", "Legs", "Upper", "Lower"], count: clamped)
        case .bodyPart:
            if clamped <= 4 {
                return Array(["Chest", "Back", "Legs", "Shoulders/Arms"].prefix(clamped))
            }
            return repeatingLabels(["Chest", "Back", "Legs", "Shoulders", "Arms"], count: clamped)
        case .arnold:
            return repeatingLabels(["Chest/Back", "Shoulders/Arms", "Legs"], count: clamped)
        }
    }

    private func repeatingLabels(_ base: [String], count: Int) -> [String] {
        guard !base.isEmpty, count > 0 else { return [] }
        var labels: [String] = []
        while labels.count < count {
            labels.append(base[labels.count % base.count])
        }
        return labels
    }
}

enum SplitPlanSource: String, CaseIterable, Identifiable, Codable {
    case saved
    case create
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saved:
            return "Saved workout"
        case .create:
            return "Create from scratch"
        case .ai:
            return "Generate with AI"
        }
    }

    var shortTitle: String {
        switch self {
        case .saved:
            return "Saved"
        case .create:
            return "Create"
        case .ai:
            return "AI"
        }
    }
}

struct SplitPlanExercise: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var muscleGroup: String
    var equipment: String
    var sets: Int
    var reps: Int
    var restSeconds: Int
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: String,
        equipment: String,
        sets: Int,
        reps: Int,
        restSeconds: Int,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.notes = notes
    }
}

struct SplitDayPlan: Codable, Identifiable {
    let weekday: String
    var focus: String
    var source: SplitPlanSource
    var templateId: String?
    var templateTitle: String?
    var muscleGroups: [String]
    var equipment: [String]
    var durationMinutes: Int?
    var customExercises: [SplitPlanExercise]?
    var exerciseNames: [String]?

    var id: String { weekday }

    init(
        weekday: String,
        focus: String = "",
        source: SplitPlanSource = .ai,
        templateId: String? = nil,
        templateTitle: String? = nil,
        muscleGroups: [String] = [],
        equipment: [String] = [],
        durationMinutes: Int? = nil,
        customExercises: [SplitPlanExercise]? = nil,
        exerciseNames: [String]? = nil
    ) {
        self.weekday = weekday
        self.focus = focus
        self.source = source
        self.templateId = templateId
        self.templateTitle = templateTitle
        self.muscleGroups = muscleGroups
        self.equipment = equipment
        self.durationMinutes = durationMinutes
        self.customExercises = customExercises
        self.exerciseNames = exerciseNames
    }
}

struct SplitSetupPreferences: Codable {
    var mode: String
    var daysPerWeek: Int
    var trainingDays: [String]
    var splitType: SplitType? = nil
    var dayPlans: [String: SplitDayPlan]? = nil
    var focus: String? = nil
    var isUserConfigured: Bool? = nil
}
