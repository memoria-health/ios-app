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

/// Request body for `POST /v1/patients/{id}/talk/start`. The
/// caregiver picks the routing target explicitly via the carousel;
/// re-POSTing with a different `cameraId` transfers the active call.
struct TalkStartRequest: Encodable, Sendable {
    var cameraId: UUID

    enum CodingKeys: String, CodingKey {
        case cameraId = "camera_id"
    }
}

/// Request body for the dev-only
/// `POST /v1/patients/{id}/cameras/{cid}/record-clip` (data collection).
/// Tells the wall camera to record the next `durationSeconds` seconds
/// and ship the clip to the laptop receiver. Backend clamps to 5–300s.
struct RecordClipRequest: Encodable, Sendable {
    var durationSeconds: Int = 15

    enum CodingKeys: String, CodingKey {
        case durationSeconds = "duration_seconds"
    }
}

/// Response from `GET /v1/patients/{id}/active-camera`. The Live tab
/// uses this to default the carousel to the right tile; `cameraId`
/// is nil when no qualifying analyses row exists in the last 30s.
struct ActiveCameraResponse: Decodable, Sendable {
    let cameraId: UUID?

    enum CodingKeys: String, CodingKey {
        case cameraId = "camera_id"
    }
}
