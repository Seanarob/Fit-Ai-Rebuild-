import Foundation
import PostHog

enum PostHogAnalytics {
    enum Feature: String {
        case workoutTracking = "workout_tracking"
        case foodLogging = "food_logging"
        case bodyScan = "body_scan"
        case checkIn = "check_in"
        case aiChat = "ai_chat"
        case splitSetup = "split_setup"
        case workoutGeneration = "workout_generation"
    }

    typealias Properties = [String: Any]

    static func featureUsed(
        _ feature: Feature,
        action: String,
        properties: Properties = [:]
    ) {
        var merged: Properties = [
            "feature": feature.rawValue,
            "action": action
        ]
        for (key, value) in properties {
            merged[key] = value
        }
        PostHogSDK.shared.capture("feature_used", properties: merged)
    }
}
