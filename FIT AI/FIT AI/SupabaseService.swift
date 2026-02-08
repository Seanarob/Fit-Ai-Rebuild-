import Combine
import Foundation
import GoTrue
import Supabase

enum SupabaseError: LocalizedError {
    case missingConfiguration
    case missingRedirectURL
    case invalidAuthCallback
    case oauthFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Supabase is not configured. Update Supabase.plist with your project URL and anon key."
        case .missingRedirectURL:
            return "Supabase redirect URL is missing. Add SUPABASE_REDIRECT_URL to Supabase.plist."
        case .invalidAuthCallback:
            return "The sign-in callback did not include an auth code or access token."
        case .oauthFailure(let message):
            return message
        }
    }
}

final class SupabaseService {
    static let shared = SupabaseService()

    private let client: SupabaseClient?
    private let implicitClient: SupabaseClient?

    private init() {
        guard
            let url = SupabaseConfig.projectURL,
            let key = SupabaseConfig.anonKey
        else {
            client = nil
            implicitClient = nil
            return
        }

        let pkceOptions = SupabaseClientOptions(auth: .init(flowType: .pkce))
        client = SupabaseClient(supabaseURL: url, supabaseKey: key, options: pkceOptions)

        let implicitOptions = SupabaseClientOptions(auth: .init(flowType: .implicit))
        implicitClient = SupabaseClient(supabaseURL: url, supabaseKey: key, options: implicitOptions)
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else {
            throw SupabaseError.missingConfiguration
        }
        return client
    }

    func fetchProfiles(limit: Int = 25) async throws -> [SupabaseProfile] {
        let client = try requireClient()
        let response: PostgrestResponse<Data> = try await client.database
            .from("profiles")
            .select()
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        let data = response.data
        let profiles = try await Task.detached {
            try JSONDecoder().decode([SupabaseProfile].self, from: data)
        }.value
        return profiles
    }

    func signIn(email: String, password: String) async throws -> Session {
        let client = try requireClient()
        return try await client.auth.signIn(email: email, password: password)
    }

    func googleSignInURL() async throws -> URL {
        let client = try requireClient()
        guard let redirectURL = SupabaseConfig.redirectURL else {
            throw SupabaseError.missingRedirectURL
        }
        return try await client.auth.getOAuthSignInURL(provider: .google, redirectTo: redirectURL)
    }

    func handleAuthCallback(url: URL) async throws -> Session {
        let client = try requireClient()
        let params = extractOAuthParams(from: url)

        if let errorDescription = params["error_description"] ?? params["error"] {
            throw SupabaseError.oauthFailure(errorDescription.replacingOccurrences(of: "+", with: " "))
        }

        if params["code"] != nil {
            return try await client.auth.session(from: url)
        }

        if params["access_token"] != nil {
            guard let implicitClient else {
                throw SupabaseError.invalidAuthCallback
            }
            return try await implicitClient.auth.session(from: url)
        }

        throw SupabaseError.invalidAuthCallback
    }
    
    func getUserId(from session: Session) -> String {
        return session.user.id.uuidString
    }

    private func extractOAuthParams(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }

        if let fragment = components.fragment {
            return parseParams(from: fragment)
        }

        if let queryItems = components.queryItems {
            var params: [String: String] = [:]
            for item in queryItems {
                params[item.name] = item.value ?? ""
            }
            return params
        }

        return [:]
    }

    private func parseParams(from fragment: String) -> [String: String] {
        var params: [String: String] = [:]
        let pairs = fragment.split(separator: "&").map { $0.split(separator: "=") }
        for pair in pairs where pair.count == 2 {
            let rawValue = String(pair[1]).replacingOccurrences(of: "+", with: " ")
            let value = rawValue.removingPercentEncoding ?? rawValue
            params[String(pair[0])] = value
        }
        return params
    }
}

@MainActor
final class SupabaseViewModel: ObservableObject {
    @Published private(set) var profiles: [SupabaseProfile] = []
    @Published var statusMessage: String?
    @Published var isLoading = false

    func refreshProfiles(limit: Int = 20) async {
        await perform {
            let results = try await SupabaseService.shared.fetchProfiles(limit: limit)
            profiles = results
            statusMessage = "Loaded \(results.count) profile(s)"
        }
    }

    func signIn(email: String, password: String) async {
        guard !email.isEmpty && !password.isEmpty else {
            statusMessage = "Provide both email and password above."
            return
        }
        await perform {
            let session = try await SupabaseService.shared.signIn(email: email, password: password)
            let user = session.user
            let emailDisplay = user.email ?? user.id.uuidString
            statusMessage = "Signed in as \(emailDisplay)"
        }
    }

    private func perform(operation: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
