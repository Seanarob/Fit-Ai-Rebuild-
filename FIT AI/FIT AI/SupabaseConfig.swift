import Foundation

enum SupabaseConfig {
    enum Key: String {
        case url = "SUPABASE_URL"
        case anonKey = "SUPABASE_ANON_KEY"
    }

    private static let values: [String: String]? = {
        guard
            let plistURL = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
            let data = try? Data(contentsOf: plistURL),
            let raw = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
            ) as? [String: Any]
        else {
            return nil
        }

        return raw.compactMapValues { value in
            if let string = value as? String, !string.isEmpty {
                return string
            }
            return nil
        }
    }()

    static func value(for key: Key) -> String? {
        values?[key.rawValue]
    }

    static var projectURL: URL? {
        guard let raw = value(for: .url) else {
            return nil
        }
        return URL(string: raw)
    }

    static var anonKey: String? {
        value(for: .anonKey)
    }
}
