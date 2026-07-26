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
    // Terms of Service + Privacy acceptance (mirrors the backend). Null until
    // the caregiver accepts; iOS gates account creation on acceptance, so a
    // freshly signed-up account is already stamped.
    var tosAcceptedAt: Date?
    var tosVersion: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case phone
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case tosAcceptedAt = "tos_accepted_at"
        case tosVersion = "tos_version"
    }
}

/// Body of `POST /v1/me`. Idempotent — email is taken from the JWT.
struct CreateCaregiverRequest: Encodable, Sendable {
    var displayName: String
    var phone: String?
    /// ToS/Privacy version the caregiver accepted at signup. iOS gates account
    /// creation on acceptance, so this is set and provisioning stamps
    /// tos_accepted_at server-side. Omitted when nil.
    var tosVersion: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case phone
        case tosVersion = "tos_version"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayName, forKey: .displayName)
        try c.encodeIfPresent(phone, forKey: .phone)
        try c.encodeIfPresent(tosVersion, forKey: .tosVersion)
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
