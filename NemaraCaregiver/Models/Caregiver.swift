import Foundation

/// The authenticated user of the Nemara caregiver app. Mirrors
/// `nemara-backend/src/schemas/caregiver.py` `CaregiverResponse`.
struct Caregiver: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var displayName: String
    var email: String
    var phone: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case phone
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body of `POST /v1/me`. Idempotent — email is taken from the JWT.
struct CreateCaregiverRequest: Encodable, Sendable {
    var displayName: String
    var phone: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case phone
    }
}

/// Body of `PATCH /v1/me`. Nil fields are omitted (backend treats omitted
/// as "leave unchanged"); to clear a column, send an explicit empty
/// payload via a different code path.
struct UpdateCaregiverRequest: Encodable, Sendable {
    var displayName: String?
    var phone: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case phone
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(phone, forKey: .phone)
    }
}
