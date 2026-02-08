import Foundation
import Combine

final class HealthSyncState: ObservableObject {
    static let shared = HealthSyncState()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    @Published var lastSyncDate: Date? {
        didSet {
            if let lastSyncDate {
                UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
            }
        }
    }

    private static let enabledKey = "fitai.health.sync.enabled"
    private static let lastSyncKey = "fitai.health.sync.lastSync"

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }
}
