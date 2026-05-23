import Foundation

/// Decoded shape of `GET /v1/events/{id}/clip-url`. Mirrors
/// `nemara-backend/src/schemas/event.py` `ClipURLResponse`.
///
/// The URL is short-lived (default 10 min). The caregiver app fetches
/// a fresh one every time the player opens; we don't cache.
struct ClipURLResponse: Decodable, Sendable {
    let url: URL
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case url
        case expiresInSeconds = "expires_in_seconds"
    }
}
