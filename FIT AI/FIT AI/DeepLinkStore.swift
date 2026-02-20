import Foundation

enum FitDeepLinkDestination: String, Codable {
    case home
    case coach
    case workout
    case nutrition
    case progress
    case checkin
}

enum DeepLinkStore {
    private static let destinationKey = "fitai.deeplink.destination"

    static func setDestination(_ destination: FitDeepLinkDestination) {
        UserDefaults.standard.set(destination.rawValue, forKey: destinationKey)
    }

    static func consumeDestination() -> FitDeepLinkDestination? {
        guard let raw = UserDefaults.standard.string(forKey: destinationKey),
              let destination = FitDeepLinkDestination(rawValue: raw) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: destinationKey)
        return destination
    }
}
