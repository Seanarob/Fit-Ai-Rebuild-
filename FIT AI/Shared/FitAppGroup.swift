import Foundation

enum FitAppGroup {
    static let identifier = "group.com.sean.FIT-AI"

    static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}

