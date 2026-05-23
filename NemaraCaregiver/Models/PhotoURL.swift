import Foundation

/// Decoded shape of `GET /v1/patients/{id}/photo-url`. Mirrors
/// `nemara-backend/src/schemas/patient.py` `PhotoURLResponse`.
///
/// The URL is short-lived (default 10 min); the caregiver app fetches
/// a fresh one each time a view appears that needs the avatar.
struct PhotoURLResponse: Decodable, Sendable {
    let url: URL
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case url
        case expiresInSeconds = "expires_in_seconds"
    }
}
