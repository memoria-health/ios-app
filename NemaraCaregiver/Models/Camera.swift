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

    /// AI paused — lighter than `disabled`. When true, the backend
    /// tick skips the Gemini call (synthetic "skipped" row with
    /// skipped_reason='ai_paused') but the live tile STAYS VISIBLE
    /// in the grid and video keeps streaming. Lets the caregiver
    /// watch a room without paying for AI calls.
    var aiPaused: Bool

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

    /// True once the wall phone has completed the /pair handshake.
    /// False = row exists with an open pairing code, no phone has
    /// claimed it yet. Drives the "PAIRING" status badge and the
    /// "Show pairing code" button on CameraDetailView.
    var paired: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case displayId = "display_id"
        case room
        case iconName = "icon_name"
        case online
        case disabled
        case aiPaused = "ai_paused"
        case desiredState = "desired_state"
        case livekitIdentity = "livekit_identity"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
        case paired
        // Realtime-payload-only. The backend's REST shape exposes
        // `paired` directly; Supabase Realtime ships the raw DB row,
        // which has `api_key_hash` but no `paired`. We read it on
        // decode (below) to derive `paired` and then drop it.
        case apiKeyHash = "api_key_hash"
    }

    /// Custom decoder so a Camera can be hydrated from BOTH:
    ///   1. The REST response (`paired` is present, explicit).
    ///   2. A Supabase Realtime row (no `paired`, derive from
    ///      `api_key_hash` — null hash → unpaired).
    /// Without (2) the realtime handler would silently fail to decode
    /// every cameras-table change (paired is a required Bool with no
    /// default), leaving the iOS cache stale across pair/unpair events.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        patientId = try c.decode(UUID.self, forKey: .patientId)
        displayId = try c.decode(Int.self, forKey: .displayId)
        room = try c.decode(String.self, forKey: .room)
        iconName = try c.decode(String.self, forKey: .iconName)
        online = try c.decode(Bool.self, forKey: .online)
        disabled = try c.decode(Bool.self, forKey: .disabled)
        aiPaused = try c.decode(Bool.self, forKey: .aiPaused)
        desiredState = try c.decode(DesiredState.self, forKey: .desiredState)
        livekitIdentity = try c.decodeIfPresent(String.self, forKey: .livekitIdentity)
        lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        if let explicit = try c.decodeIfPresent(Bool.self, forKey: .paired) {
            paired = explicit
        } else {
            let hash = try c.decodeIfPresent(String.self, forKey: .apiKeyHash)
            paired = (hash != nil)
        }
    }

    /// Custom encoder needed because we added `apiKeyHash` to
    /// CodingKeys (for decode-only) without a stored property — that
    /// blocks Encodable auto-synthesis. We emit every "real" field
    /// and skip apiKeyHash entirely (we never need to send it back
    /// to the server; it's read-only on the wire).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(patientId, forKey: .patientId)
        try c.encode(displayId, forKey: .displayId)
        try c.encode(room, forKey: .room)
        try c.encode(iconName, forKey: .iconName)
        try c.encode(online, forKey: .online)
        try c.encode(disabled, forKey: .disabled)
        try c.encode(aiPaused, forKey: .aiPaused)
        try c.encode(desiredState, forKey: .desiredState)
        try c.encodeIfPresent(livekitIdentity, forKey: .livekitIdentity)
        try c.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(paired, forKey: .paired)
    }

    /// Memberwise init kept available for fixtures + AppEnvironment
    /// previews. Swift auto-synthesizes one until you write any custom
    /// init; once we added `init(from:)`, we have to spell this out.
    init(
        disabled: Bool,
        aiPaused: Bool,
        desiredState: DesiredState,
        id: UUID,
        patientId: UUID,
        displayId: Int,
        room: String,
        iconName: String,
        online: Bool,
        livekitIdentity: String?,
        lastSeenAt: Date?,
        createdAt: Date,
        paired: Bool,
    ) {
        self.disabled = disabled
        self.aiPaused = aiPaused
        self.desiredState = desiredState
        self.id = id
        self.patientId = patientId
        self.displayId = displayId
        self.room = room
        self.iconName = iconName
        self.online = online
        self.livekitIdentity = livekitIdentity
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.paired = paired
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
    var aiPaused: Bool?
    var desiredState: Camera.DesiredState?

    enum CodingKeys: String, CodingKey {
        case disabled
        case aiPaused = "ai_paused"
        case desiredState = "desired_state"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(disabled, forKey: .disabled)
        try c.encodeIfPresent(aiPaused, forKey: .aiPaused)
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
