import Foundation

/// Body of `POST /v1/me/devices`. Mirrors
/// `nemara-backend/src/schemas/devices.py:RegisterDeviceRequest`.
///
/// The caregiver app POSTs this on launch (after auth) and on any
/// APNs token refresh. Idempotent on `apnsToken` — back-to-back
/// POSTs with the same token are de-duplicated on the server.
struct RegisterDeviceRequest: Encodable, Sendable {
    var apnsToken: String
    var bundleId: String
    var environment: APNsEnvironment

    enum CodingKeys: String, CodingKey {
        case apnsToken = "apns_token"
        case bundleId = "bundle_id"
        case environment
    }
}

/// APNs environment selector. The backend's check constraint accepts
/// exactly these two strings (lowercase); we route token registration
/// to the matching APNs host.
enum APNsEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

/// Response from `POST /v1/me/devices`. The caregiver app doesn't
/// strictly need the row back — the registration is fire-and-forget —
/// but mirroring the canonical row keeps the API symmetric with the
/// other endpoints and lets future code cache the registration state.
struct DeviceResponse: Decodable, Sendable {
    let id: UUID
    let caregiverId: UUID
    let apnsToken: String
    let bundleId: String
    let environment: APNsEnvironment
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case caregiverId = "caregiver_id"
        case apnsToken = "apns_token"
        case bundleId = "bundle_id"
        case environment
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
