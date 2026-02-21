import Foundation

enum PostHogSettings {
    enum Key: String {
        case apiKey = "POSTHOG_API_KEY"
        case host = "POSTHOG_HOST"
    }

    private static let values: [String: String]? = {
        if let data = loadPostHogPlistData(),
           let raw = try? PropertyListSerialization.propertyList(
               from: data,
               format: nil
           ) as? [String: Any] {
            let values = extractStrings(from: raw)
            if !values.isEmpty {
                return values
            }
        }

        if let raw = Bundle.main.infoDictionary {
            let values = extractStrings(from: raw)
            if !values.isEmpty {
                return values
            }
        }

        return nil
    }()

    private static func extractStrings(from raw: [String: Any]) -> [String: String] {
        let keys = [Key.apiKey.rawValue, Key.host.rawValue]
        var values: [String: String] = [:]
        for key in keys {
            if let string = raw[key] as? String, !string.isEmpty {
                values[key] = string
            }
        }
        return values
    }

    private static func loadPostHogPlistData() -> Data? {
        if let plistURL = Bundle.main.url(forResource: "PostHog", withExtension: "plist"),
           let data = try? Data(contentsOf: plistURL) {
            return data
        }

        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            if url.lastPathComponent == "PostHog.plist",
               let data = try? Data(contentsOf: url) {
                return data
            }
        }

        return nil
    }

    static func value(for key: Key) -> String? {
        values?[key.rawValue]
    }

    static var apiKey: String? {
        value(for: .apiKey)
    }

    static var host: String {
        value(for: .host) ?? "https://us.i.posthog.com"
    }
}
