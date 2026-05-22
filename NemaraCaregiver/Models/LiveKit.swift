import Foundation

/// Request body for `POST /v1/livekit/token`. Mirrors
/// `nemara-backend/src/schemas/livekit_io.py:MintTokenRequest`.
///
/// `role`:
///   - `viewer`      — caregiver Look-In (read-only video + audio)
///   - `broadcaster` — caregiver Talk mode (mic publish + subscribe)
///
/// The `camera` role lives on the wall-phone side; the caregiver app
/// never requests it.
struct MintTokenRequest: Encodable, Sendable {
    var room: String
    var identity: String
    var role: String
}

/// Response from the same endpoint.
struct MintTokenResponse: Decodable, Sendable {
    let token: String
    let url: String
    /// ISO-8601 instant when the JWT expires. Clients refresh at TTL/2
    /// (~30 min for the current 1h TTL).
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case token
        case url
        case expiresAt = "expires_at"
    }
}

/// Response from `POST /v1/patients/{id}/talk/start`. Tells the
/// caregiver UI which camera audio is being routed to so it can
/// label the on-air banner ("Talking to Kitchen" vs "Talking to all
/// rooms").
struct TalkStartResponse: Decodable, Sendable {
    /// The camera the backend judged to be "active" (most recent
    /// analyses row with `people_present=true` in the last 30s). Nil
    /// when no active camera is known — backend falls back to fan-out
    /// across every paired camera.
    let activeCameraId: UUID?

    enum CodingKeys: String, CodingKey {
        case activeCameraId = "active_camera_id"
    }
}
