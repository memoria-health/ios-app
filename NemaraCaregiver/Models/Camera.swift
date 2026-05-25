import Foundation

/// A wall-mounted phone acting as a camera + microphone for one room.
/// Mirrors `nemara-backend/src/schemas/camera.py` `CameraResponse`.
///
/// `id` is the persistent UUID assigned by the backend (used for
/// DELETE + cross-table references). `displayId` is the 1-based integer
/// rendered as "CAM 01" in the UI.
struct Camera: Identifiable, Hashable, Sendable, Codable {

    /// User-facing "off" toggle. When true, the backend tick worker
    /// skips the LLM call (writes a synthetic "skipped" row to
    /// `analyses` instead of calling Gemini). LiveKit connection
    /// stays alive — re-enabling is instant.
    ///
    /// Independent of `desiredState`: a camera can be both `disabled`
    /// AND `desiredState=.disconnected` simultaneously, in which case
    /// the wall phone has actually left LiveKit AND we'd skip AI even
    /// if it came back.
    var disabled: Bool

    /// Whether the wall phone should be joined to the LiveKit room.
    /// The phone polls `GET /v1/cameras/me/desired-state` every 1s
    /// and reconciles by calling `room.disconnect()` /
    /// `room.connect()`. Reconnect latency ~1-2s after the caregiver
    /// flips this back to `.connected`.
    ///
    /// Stronger than `disabled` — when `.disconnected`, no video bytes
    /// are encoded, uploaded, or seen by LiveKit Cloud at all.
    /// Privacy + battery option.
    enum DesiredState: String, Sendable, Codable {
        case connected
        case disconnected
    }
    var desiredState: DesiredState

    let id: UUID
    var patientId: UUID
    var displayId: Int
    var room: String
    var iconName: String
    var online: Bool
    /// LiveKit participant identity for this camera (`cam_<8 hex>`).
    /// Nil for placeholder rows that hold an open pairing code but
    /// haven't been claimed by a wall phone yet. Used by Live tab to
    /// match a Camera row to its subscribed LiveKit video track AND
    /// as the canonical "this row is a real paired camera" check
    /// (more reliable than `online`, which lies for unpaired rows).
    var livekitIdentity: String?
    var lastSeenAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case displayId = "display_id"
        case room
        case iconName = "icon_name"
        case online
        case disabled
        case desiredState = "desired_state"
        case livekitIdentity = "livekit_identity"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
    }
}

/// Body for `POST /v1/patients/{id}/cameras/pairing-code`.
struct CreatePairingCodeRequest: Encodable, Sendable {
    var room: String
    var iconName: String

    enum CodingKeys: String, CodingKey {
        case room
        case iconName = "icon_name"
    }
}

/// Response from the same. Caregiver app displays the code +
/// countdown to expiry.
struct CreatePairingCodeResponse: Decodable, Sendable {
    let pairingCode: String  // 6 digits, 100000–999999
    let expiresAt: Date
    let cameraId: UUID

    enum CodingKeys: String, CodingKey {
        case pairingCode = "pairing_code"
        case expiresAt = "expires_at"
        case cameraId = "camera_id"
    }
}

/// Body for `PATCH /v1/cameras/{id}`. Nil fields are omitted (matches
/// backend's `extra="forbid"` policy — sending a field commits us to
/// changing it).
struct UpdateCameraRequest: Encodable, Sendable {
    var disabled: Bool?
    var desiredState: Camera.DesiredState?

    enum CodingKeys: String, CodingKey {
        case disabled
        case desiredState = "desired_state"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(disabled, forKey: .disabled)
        try c.encodeIfPresent(desiredState, forKey: .desiredState)
    }
}

/// Response shape for `GET /v1/cameras/{id}/detectors` — the set of
/// detector IDs currently assigned to this camera. Caregiver app
/// cross-references against the patient's full detector list to
/// render per-camera toggles.
struct CameraDetectorsResponse: Decodable, Sendable {
    let detectorIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case detectorIds = "detector_ids"
    }
}

/// Body for `PUT /v1/cameras/{id}/detectors`. Replaces the camera's
/// detector assignment set with exactly the given IDs. Every ID must
/// belong to the same patient as the camera; otherwise backend returns
/// 422.
struct SetCameraDetectorsRequest: Encodable, Sendable {
    var detectorIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case detectorIds = "detector_ids"
    }
}
