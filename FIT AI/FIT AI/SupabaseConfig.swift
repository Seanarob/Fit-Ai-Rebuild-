import Foundation

enum SupabaseConfig {
    enum Key: String {
        case url = "SUPABASE_URL"
        case anonKey = "SUPABASE_ANON_KEY"
        case redirectURL = "SUPABASE_REDIRECT_URL"
    }

    private static let values: [String: String]? = {
        if let data = loadSupabasePlistData(),
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
        let keys = [Key.url.rawValue, Key.anonKey.rawValue, Key.redirectURL.rawValue]
        var values: [String: String] = [:]
        for key in keys {
            if let string = raw[key] as? String, !string.isEmpty {
                values[key] = string
            }
        }
        return values
    }

    private static func loadSupabasePlistData() -> Data? {
        if let plistURL = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
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
            if url.lastPathComponent == "Supabase.plist",
               let data = try? Data(contentsOf: url) {
                return data
            }
        }

        return nil
    }

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

    static var redirectURL: URL? {
        guard let raw = value(for: .redirectURL) else {
            return nil
        }
        return URL(string: raw)
    }
}
