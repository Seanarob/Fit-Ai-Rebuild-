import Foundation
import UserNotifications

enum FitNotificationPriority: Int, Comparable {
    case low = 1
    case normal = 2
    case high = 3
    case critical = 4

    static func < (lhs: FitNotificationPriority, rhs: FitNotificationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct NotificationScheduleDecision {
    let allow: Bool
    let removeIdentifiers: [String]
}

enum NotificationThrottler {
    private static let preferredDailyCap = 4
    private static let hardDailyCap = 6
    private static let minimumSpacing: TimeInterval = 90 * 60
    private static let throttleCategoryKey = "throttle_category"
    private static let throttlePriorityKey = "throttle_priority"

    static func defaultCategoryKey(for identifier: String) -> String {
        identifier.replacingOccurrences(
            of: #"\.\d{4}-\d{2}-\d{2}$"#,
            with: "",
            options: .regularExpression
        )
    }

    static func attachThrottleMetadata(
        to content: UNMutableNotificationContent,
        category: String,
        priority: FitNotificationPriority
    ) {
        var info = content.userInfo
        info[throttleCategoryKey] = category
        info[throttlePriorityKey] = priority.rawValue
        content.userInfo = info
    }

    static func evaluate(
        center: UNUserNotificationCenter = .current(),
        identifier: String,
        fireDate: Date,
        category: String,
        priority: FitNotificationPriority
    ) async -> NotificationScheduleDecision {
        if shouldBypassThrottle(identifier: identifier) {
            return NotificationScheduleDecision(allow: true, removeIdentifiers: [])
        }

        let pending = await center.pendingNotificationRequests()
        let calendar = Calendar.current
        let sameDayEntries = pending.compactMap { request -> PendingEntry? in
            guard !shouldBypassThrottle(identifier: request.identifier) else { return nil }
            guard let next = nextTriggerDate(for: request.trigger) else { return nil }
            guard calendar.isDate(next, inSameDayAs: fireDate) else { return nil }
            return PendingEntry(
                identifier: request.identifier,
                fireDate: next,
                category: categoryForRequest(request),
                priority: priorityForRequest(request)
            )
        }

        var removals = Set<String>()

        let sameCategory = sameDayEntries.filter { $0.category == category && $0.identifier != identifier }
        if let strongest = sameCategory.max(by: { $0.priority < $1.priority }), strongest.priority > priority {
            return NotificationScheduleDecision(allow: false, removeIdentifiers: [])
        }
        for entry in sameCategory {
            removals.insert(entry.identifier)
        }

        let spacingConflicts = sameDayEntries.filter {
            abs($0.fireDate.timeIntervalSince(fireDate)) < minimumSpacing && $0.identifier != identifier
        }
        if spacingConflicts.contains(where: { $0.priority >= priority && !removals.contains($0.identifier) }) {
            return NotificationScheduleDecision(allow: false, removeIdentifiers: [])
        }
        for entry in spacingConflicts where entry.priority < priority {
            removals.insert(entry.identifier)
        }

        let survivors = sameDayEntries.filter {
            !removals.contains($0.identifier) && $0.identifier != identifier
        }
        var projectedCount = survivors.count + 1

        if projectedCount > hardDailyCap {
            guard priority >= .critical else {
                return NotificationScheduleDecision(allow: false, removeIdentifiers: [])
            }
            let replaceable = survivors.sorted {
                if $0.priority == $1.priority {
                    return $0.fireDate > $1.fireDate
                }
                return $0.priority < $1.priority
            }
            for entry in replaceable where projectedCount > hardDailyCap && entry.priority < priority {
                removals.insert(entry.identifier)
                projectedCount -= 1
            }
            if projectedCount > hardDailyCap {
                return NotificationScheduleDecision(allow: false, removeIdentifiers: [])
            }
        }

        if projectedCount > preferredDailyCap && priority < .high {
            return NotificationScheduleDecision(allow: false, removeIdentifiers: [])
        }

        return NotificationScheduleDecision(allow: true, removeIdentifiers: Array(removals))
    }

    private static func shouldBypassThrottle(identifier: String) -> Bool {
        identifier.hasPrefix("fitai.rest.")
    }

    private static func nextTriggerDate(for trigger: UNNotificationTrigger?) -> Date? {
        if let calendarTrigger = trigger as? UNCalendarNotificationTrigger {
            guard !calendarTrigger.repeats else { return nil }
            return calendarTrigger.nextTriggerDate()
        }
        if let timeTrigger = trigger as? UNTimeIntervalNotificationTrigger {
            guard !timeTrigger.repeats else { return nil }
            return Date().addingTimeInterval(timeTrigger.timeInterval)
        }
        return nil
    }

    private static func categoryForRequest(_ request: UNNotificationRequest) -> String {
        if let raw = request.content.userInfo[throttleCategoryKey] as? String, !raw.isEmpty {
            return raw
        }
        return defaultCategoryKey(for: request.identifier)
    }

    private static func priorityForRequest(_ request: UNNotificationRequest) -> FitNotificationPriority {
        if let raw = request.content.userInfo[throttlePriorityKey] as? Int,
           let parsed = FitNotificationPriority(rawValue: raw) {
            return parsed
        }
        if let rawNumber = request.content.userInfo[throttlePriorityKey] as? NSNumber,
           let parsed = FitNotificationPriority(rawValue: rawNumber.intValue) {
            return parsed
        }
        return .normal
    }

    private struct PendingEntry {
        let identifier: String
        let fireDate: Date
        let category: String
        let priority: FitNotificationPriority
    }
}
