import Foundation

public struct OnboardingStep {
    public let title: String
    public let summary: String
}

    public struct OnboardingForm: Codable {
    public enum PrimaryTrainingGoal: String, CaseIterable, Codable, Identifiable {
        case strength
        case hypertrophy
        case fatLoss

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .strength: return "Strength"
            case .hypertrophy: return "Hypertrophy"
            case .fatLoss: return "Fat loss + muscle"
            }
        }
    }

    public enum Goal: String, CaseIterable, Codable, Identifiable {
        case gainWeight = "gain_weight"
        case loseWeight = "lose_weight"
        case loseWeightFast = "lose_weight_fast"
        case maintain = "maintain"

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .gainWeight: return "Gain weight"
            case .loseWeight: return "Lose weight"
            case .loseWeightFast: return "Lose weight faster"
            case .maintain: return "Maintain"
            }
        }
    }

    public enum TrainingLevel: String, CaseIterable, Codable, Identifiable, Hashable {
        case beginner, intermediate, advanced

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .beginner: return "Beginner"
            case .intermediate: return "Intermediate"
            case .advanced: return "Advanced"
            }
        }
    }

    public enum Sex: String, CaseIterable, Codable, Identifiable, Hashable {
        case male
        case female
        case other
        case preferNotToSay

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .male: return "Male"
            case .female: return "Female"
            case .other: return "Other"
            case .preferNotToSay: return "Prefer not to say"
            }
        }
    }
    
    public enum ActivityLevel: String, CaseIterable, Codable, Identifiable, Hashable {
        case sedentary
        case lightlyActive
        case moderatelyActive
        case veryActive
        case extremelyActive
        
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .sedentary: return "Sedentary"
            case .lightlyActive: return "Lightly Active"
            case .moderatelyActive: return "Moderately Active"
            case .veryActive: return "Very Active"
            case .extremelyActive: return "Extremely Active"
            }
        }
        
        public var description: String {
            switch self {
            case .sedentary: return "Little to no exercise"
            case .lightlyActive: return "Light exercise 1-3 days/week"
            case .moderatelyActive: return "Moderate exercise 3-5 days/week"
            case .veryActive: return "Hard exercise 6-7 days/week"
            case .extremelyActive: return "Very hard exercise, physical job"
            }
        }
    }
    
    public enum SpecialConsideration: String, CaseIterable, Codable, Identifiable, Hashable {
        case highProtein
        case lowCarb
        case athlete
        case strengthTraining
        case enduranceTraining
        case vegetarianVegan
        
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .highProtein: return "High Protein"
            case .lowCarb: return "Low Carb"
            case .athlete: return "Athlete"
            case .strengthTraining: return "Strength Training"
            case .enduranceTraining: return "Endurance Training"
            case .vegetarianVegan: return "Vegetarian/Vegan"
            }
        }
    }

    public enum EquipmentAccess: String, CaseIterable, Codable, Identifiable, Hashable {
        case gym = "gym"
        case home = "home"
        case limited = "limited"

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .gym: return "Gym"
            case .home: return "Home"
            case .limited: return "Limited"
            }
        }
    }

    public static let checkinDays = Calendar.current.weekdaySymbols

    public var userId: String? = nil
    public var fullName: String = ""
    public var age: String = ""
    public var birthday: Date? = nil
    public var sex: Sex = .male
    public var heightFeet: String = "5"
    public var heightInches: String = "9"
    public var heightUnit: String = "ft/in" // "ft/in" or "cm"
    public var weightLbs: String = ""
    public var goalWeightLbs: String = ""
    public var targetDate: Date? = nil
    public var goal: Goal = .maintain
    public var primaryTrainingGoal: PrimaryTrainingGoal = .hypertrophy
    public var activityLevel: ActivityLevel = .moderatelyActive
    public var trainingLevel: TrainingLevel = .intermediate
    public var workoutDaysPerWeek: Int = 3
    public var workoutDurationMinutes: Int = 45
    public var equipment: EquipmentAccess = .gym
    public var specialConsiderations: Set<SpecialConsideration> = []
    public var additionalNotes: String = ""
    public var foodAllergies: String = ""
    public var foodDislikes: String = ""
    public var dietStyle: String = ""
    public var checkinDay: String = ""
    public var macroProtein: String = ""
    public var macroCarbs: String = ""
    public var macroFats: String = ""
    public var macroCalories: String = ""
    public var photosPending: Bool = true
    public var weeklyWeightLossLbs: Double = 1.0
    public var healthKitSyncEnabled: Bool = false
    public var physiqueFocus: [String] = []
    public var weakPoints: [String] = []
    public var trainingDaysOfWeek: [String] = []
    public var habitsSleep: String = ""
    public var habitsNutrition: String = ""
    public var habitsStress: String = ""
    public var habitsRecovery: String = ""
    public var pastFailures: [String] = []
    public var pastFailuresNote: String = ""
    public var checkinEnergy: Int = 0
    public var checkinReadiness: Int = 0
    public var checkinSoreness: Int = 0
    public var checkinWeight: String = ""
    public var lastSeenGap: String = ""
    public var coachSignals: [String] = []
    
    // Custom encoding/decoding for Date and Set
    enum CodingKeys: String, CodingKey {
        case userId, fullName, age, sex, heightFeet, heightInches, heightUnit
        case weightLbs, goalWeightLbs, goal, primaryTrainingGoal, activityLevel, trainingLevel
        case workoutDaysPerWeek, workoutDurationMinutes, equipment
        case foodAllergies, foodDislikes, dietStyle, checkinDay
        case macroProtein, macroCarbs, macroFats, macroCalories, photosPending
        case weeklyWeightLossLbs, healthKitSyncEnabled
        case physiqueFocus, weakPoints, trainingDaysOfWeek
        case habitsSleep, habitsNutrition, habitsStress, habitsRecovery
        case pastFailures, pastFailuresNote
        case checkinEnergy, checkinReadiness, checkinSoreness, checkinWeight
        case lastSeenGap, coachSignals
        case birthdayTimestamp, targetDateTimestamp, specialConsiderationsArray, additionalNotes
    }
    
    public init() {
        checkinDay = OnboardingForm.checkinDays.first ?? "Monday"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName) ?? ""
        age = try container.decodeIfPresent(String.self, forKey: .age) ?? ""
        sex = try container.decodeIfPresent(Sex.self, forKey: .sex) ?? .male
        heightFeet = try container.decodeIfPresent(String.self, forKey: .heightFeet) ?? "5"
        heightInches = try container.decodeIfPresent(String.self, forKey: .heightInches) ?? "9"
        heightUnit = try container.decodeIfPresent(String.self, forKey: .heightUnit) ?? "ft/in"
        weightLbs = try container.decodeIfPresent(String.self, forKey: .weightLbs) ?? ""
        goalWeightLbs = try container.decodeIfPresent(String.self, forKey: .goalWeightLbs) ?? ""
        goal = try container.decodeIfPresent(Goal.self, forKey: .goal) ?? .maintain
        primaryTrainingGoal = try container.decodeIfPresent(PrimaryTrainingGoal.self, forKey: .primaryTrainingGoal) ?? .hypertrophy
        activityLevel = try container.decodeIfPresent(ActivityLevel.self, forKey: .activityLevel) ?? .moderatelyActive
        trainingLevel = try container.decodeIfPresent(TrainingLevel.self, forKey: .trainingLevel) ?? .intermediate
        workoutDaysPerWeek = try container.decodeIfPresent(Int.self, forKey: .workoutDaysPerWeek) ?? 3
        workoutDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .workoutDurationMinutes) ?? 45
        equipment = try container.decodeIfPresent(EquipmentAccess.self, forKey: .equipment) ?? .gym
        foodAllergies = try container.decodeIfPresent(String.self, forKey: .foodAllergies) ?? ""
        foodDislikes = try container.decodeIfPresent(String.self, forKey: .foodDislikes) ?? ""
        dietStyle = try container.decodeIfPresent(String.self, forKey: .dietStyle) ?? ""
        checkinDay = try container.decodeIfPresent(String.self, forKey: .checkinDay) ?? (OnboardingForm.checkinDays.first ?? "Monday")
        macroProtein = try container.decodeIfPresent(String.self, forKey: .macroProtein) ?? ""
        macroCarbs = try container.decodeIfPresent(String.self, forKey: .macroCarbs) ?? ""
        macroFats = try container.decodeIfPresent(String.self, forKey: .macroFats) ?? ""
        macroCalories = try container.decodeIfPresent(String.self, forKey: .macroCalories) ?? ""
        photosPending = try container.decodeIfPresent(Bool.self, forKey: .photosPending) ?? true
        additionalNotes = try container.decodeIfPresent(String.self, forKey: .additionalNotes) ?? ""
        weeklyWeightLossLbs = try container.decodeIfPresent(Double.self, forKey: .weeklyWeightLossLbs) ?? 1.0
        healthKitSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .healthKitSyncEnabled) ?? false
        physiqueFocus = try container.decodeIfPresent([String].self, forKey: .physiqueFocus) ?? []
        weakPoints = try container.decodeIfPresent([String].self, forKey: .weakPoints) ?? []
        trainingDaysOfWeek = try container.decodeIfPresent([String].self, forKey: .trainingDaysOfWeek) ?? []
        habitsSleep = try container.decodeIfPresent(String.self, forKey: .habitsSleep) ?? ""
        habitsNutrition = try container.decodeIfPresent(String.self, forKey: .habitsNutrition) ?? ""
        habitsStress = try container.decodeIfPresent(String.self, forKey: .habitsStress) ?? ""
        habitsRecovery = try container.decodeIfPresent(String.self, forKey: .habitsRecovery) ?? ""
        pastFailures = try container.decodeIfPresent([String].self, forKey: .pastFailures) ?? []
        pastFailuresNote = try container.decodeIfPresent(String.self, forKey: .pastFailuresNote) ?? ""
        checkinEnergy = try container.decodeIfPresent(Int.self, forKey: .checkinEnergy) ?? 0
        checkinReadiness = try container.decodeIfPresent(Int.self, forKey: .checkinReadiness) ?? 0
        checkinSoreness = try container.decodeIfPresent(Int.self, forKey: .checkinSoreness) ?? 0
        checkinWeight = try container.decodeIfPresent(String.self, forKey: .checkinWeight) ?? ""
        lastSeenGap = try container.decodeIfPresent(String.self, forKey: .lastSeenGap) ?? ""
        coachSignals = try container.decodeIfPresent([String].self, forKey: .coachSignals) ?? []
        
        // Decode dates from timestamps
        if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .birthdayTimestamp) {
            birthday = Date(timeIntervalSince1970: timestamp)
        }
        if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .targetDateTimestamp) {
            targetDate = Date(timeIntervalSince1970: timestamp)
        }
        
        // Decode Set from array
        if let array = try container.decodeIfPresent([String].self, forKey: .specialConsiderationsArray) {
            specialConsiderations = Set(array.compactMap { SpecialConsideration(rawValue: $0) })
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(fullName, forKey: .fullName)
        try container.encode(age, forKey: .age)
        try container.encode(sex, forKey: .sex)
        try container.encode(heightFeet, forKey: .heightFeet)
        try container.encode(heightInches, forKey: .heightInches)
        try container.encode(heightUnit, forKey: .heightUnit)
        try container.encode(weightLbs, forKey: .weightLbs)
        try container.encode(goalWeightLbs, forKey: .goalWeightLbs)
        try container.encode(goal, forKey: .goal)
        try container.encode(primaryTrainingGoal, forKey: .primaryTrainingGoal)
        try container.encode(activityLevel, forKey: .activityLevel)
        try container.encode(trainingLevel, forKey: .trainingLevel)
        try container.encode(workoutDaysPerWeek, forKey: .workoutDaysPerWeek)
        try container.encode(workoutDurationMinutes, forKey: .workoutDurationMinutes)
        try container.encode(equipment, forKey: .equipment)
        try container.encode(foodAllergies, forKey: .foodAllergies)
        try container.encode(foodDislikes, forKey: .foodDislikes)
        try container.encode(dietStyle, forKey: .dietStyle)
        try container.encode(checkinDay, forKey: .checkinDay)
        try container.encode(macroProtein, forKey: .macroProtein)
        try container.encode(macroCarbs, forKey: .macroCarbs)
        try container.encode(macroFats, forKey: .macroFats)
        try container.encode(macroCalories, forKey: .macroCalories)
        try container.encode(photosPending, forKey: .photosPending)
        try container.encode(additionalNotes, forKey: .additionalNotes)
        try container.encode(weeklyWeightLossLbs, forKey: .weeklyWeightLossLbs)
        try container.encode(healthKitSyncEnabled, forKey: .healthKitSyncEnabled)
        try container.encode(physiqueFocus, forKey: .physiqueFocus)
        try container.encode(weakPoints, forKey: .weakPoints)
        try container.encode(trainingDaysOfWeek, forKey: .trainingDaysOfWeek)
        try container.encode(habitsSleep, forKey: .habitsSleep)
        try container.encode(habitsNutrition, forKey: .habitsNutrition)
        try container.encode(habitsStress, forKey: .habitsStress)
        try container.encode(habitsRecovery, forKey: .habitsRecovery)
        try container.encode(pastFailures, forKey: .pastFailures)
        try container.encode(pastFailuresNote, forKey: .pastFailuresNote)
        try container.encode(checkinEnergy, forKey: .checkinEnergy)
        try container.encode(checkinReadiness, forKey: .checkinReadiness)
        try container.encode(checkinSoreness, forKey: .checkinSoreness)
        try container.encode(checkinWeight, forKey: .checkinWeight)
        try container.encode(lastSeenGap, forKey: .lastSeenGap)
        try container.encode(coachSignals, forKey: .coachSignals)
        
        // Encode dates as timestamps
        if let birthday = birthday {
            try container.encode(birthday.timeIntervalSince1970, forKey: .birthdayTimestamp)
        }
        if let targetDate = targetDate {
            try container.encode(targetDate.timeIntervalSince1970, forKey: .targetDateTimestamp)
        }
        
        // Encode Set as array
        try container.encode(Array(specialConsiderations.map { $0.rawValue }), forKey: .specialConsiderationsArray)
    }
}
