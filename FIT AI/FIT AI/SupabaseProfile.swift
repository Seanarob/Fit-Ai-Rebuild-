import Foundation

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

extension SupabaseProfile: @unchecked Sendable {}
