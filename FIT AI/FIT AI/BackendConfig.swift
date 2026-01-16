import Foundation

struct BackendConfig {
    /// Update this to match your backend URL when running locally or in production.
    static var baseURL: URL {
        return URL(string: "https://tmwuolgnvsennjcyxuft.supabase.co/functions/v1/api")!
    }
}
