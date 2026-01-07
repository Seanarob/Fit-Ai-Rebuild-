import Foundation
import Supabase

enum SupabaseError: LocalizedError {
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Supabase is not configured. Update Supabase.plist with your project URL and anon key."
        }
    }
}

struct SupabaseProfile: Decodable, Identifiable {
    let id: String
    let fullName: String?
    let username: String?
    let email: String?
    let role: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case username
        case email
        case role
        case createdAt = "created_at"
    }
}

final class SupabaseService {
    static let shared = SupabaseService()

    private let client: SupabaseClient?

    private init() {
        guard
            let url = SupabaseConfig.projectURL,
            let key = SupabaseConfig.anonKey
        else {
            client = nil
            return
        }

        let options = SupabaseClientOptions(
            db: .init(decoder: PostgrestClient.Configuration.jsonDecoder)
        )

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: options
        )
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else {
            throw SupabaseError.missingConfiguration
        }
        return client
    }

    func fetchProfiles(limit: Int = 25) async throws -> [SupabaseProfile] {
        let client = try requireClient()
        var query = client.from("profiles").select()
        query = query.order("created_at", ascending: false)
        if limit > 0 {
            query = query.limit(limit)
        }
        let response: PostgrestResponse<[SupabaseProfile]> = try await query.execute()
        return response.value
    }

    func signIn(email: String, password: String) async throws -> AuthResponse {
        let client = try requireClient()
        return try await client.auth.signIn(email: email, password: password)
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
            let response = try await SupabaseService.shared.signIn(email: email, password: password)
            let user = response.session?.user ?? response.user
            let emailDisplay = user.email ?? user.id.uuidString
            statusMessage = "Signed in as \(emailDisplay)"
        }
    }

    private func perform(operation: @Sendable () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
