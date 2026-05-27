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
    /// stays alive, re-enabling is instant.
    ///
    /// Independent of `desiredState`: a camera can be both `disabled`
    /// AND `desiredState=.disconnected` simultaneously, in which case
    /// the wall phone has actually left LiveKit AND we'd skip AI even
    /// if it came back.
    var disabled: Bool

    /// Which physical device class this camera row represents. The
    /// detection pipeline treats both identically (both publish to
    /// the same LiveKit room), but the UI branches: phone cameras
    /// pair via a 6-digit code, sensor cameras pair via the
    /// discovered-list flow (and on iOS, optionally via the
    /// WiFi-setup AP). Mirrors `cameras.source_type` on the backend.
    enum SourceType: String, Sendable, Codable {
        /// Wall-mounted NemaraCam iPhone (the original path).
        case phone = "iphone"
        /// Raspberry Pi running the Nemara streaming daemon.
        case sensor = "pi"
    }
    var sourceType: SourceType

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
        case sourceType = "source_type"
        case livekitIdentity = "livekit_identity"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
    }

    /// Default to .phone when decoding from a Supabase Realtime
    /// payload that predates the source_type column. Without this
    /// initializer, older payloads would fail decode and crash the
    /// realtime stream.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.patientId = try c.decode(UUID.self, forKey: .patientId)
        self.displayId = try c.decode(Int.self, forKey: .displayId)
        self.room = try c.decode(String.self, forKey: .room)
        self.iconName = try c.decode(String.self, forKey: .iconName)
        self.online = try c.decode(Bool.self, forKey: .online)
        self.disabled = try c.decode(Bool.self, forKey: .disabled)
        self.desiredState = try c.decode(DesiredState.self, forKey: .desiredState)
        self.sourceType = try c.decodeIfPresent(SourceType.self, forKey: .sourceType) ?? .phone
        self.livekitIdentity = try c.decodeIfPresent(String.self, forKey: .livekitIdentity)
        self.lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    /// Explicit memberwise init kept for in-app construction (e.g.,
    /// optimistic Camera rows built before the network round-trip).
    /// Parameter order matches the field declaration order so it
    /// reads the same as the synthesized memberwise init would.
    init(
        disabled: Bool,
        sourceType: SourceType = .phone,
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
    ) {
        self.disabled = disabled
        self.sourceType = sourceType
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

/// One sensor camera the backend has heard from but no caregiver has
/// claimed yet. Populates the "Sensor Camera" tab of the add-camera
/// sheet. Mirrors `nemara-backend/src/schemas/pi_discovery.py`
/// `DiscoveredPi`.
struct DiscoveredCamera: Identifiable, Sendable, Decodable {
    var id: UUID { discoveryId }

    let discoveryId: UUID
    let hardwareId: String
    let deviceLabel: String
    let currentUrl: String
    let currentAudioUrl: String?
    let firstSeenAt: Date
    let lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case discoveryId = "discovery_id"
        case hardwareId = "hardware_id"
        case deviceLabel = "device_label"
        case currentUrl = "current_url"
        case currentAudioUrl = "current_audio_url"
        case firstSeenAt = "first_seen_at"
        case lastSeenAt = "last_seen_at"
    }
}

/// Top-level shape of `GET /v1/cameras/discovered`. Caregiver-facing
/// picker iterates `pis`.
struct DiscoveredCamerasResponse: Decodable, Sendable {
    let pis: [DiscoveredCamera]
}

/// Body for `POST /v1/patients/{id}/cameras/pi-provision`, discovery
/// mode. Binds an already-announced sensor camera to a patient + room.
/// The direct-URL mode is intentionally not surfaced to the app
/// (operators use it via curl for testing).
struct ProvisionSensorCameraRequest: Encodable, Sendable {
    var room: String
    var iconName: String
    var discoveryId: UUID

    enum CodingKeys: String, CodingKey {
        case room
        case iconName = "icon_name"
        case discoveryId = "discovery_id"
    }
}

/// Response from `pi-provision`. The app uses `cameraId` to navigate
/// to the new camera's detail view post-pairing.
struct ProvisionSensorCameraResponse: Decodable, Sendable {
    let cameraId: UUID
    let patientId: UUID
    let piStreamUrl: String
    let piAudioUrl: String?
    let livekitIdentity: String
    let livekitRoom: String

    enum CodingKeys: String, CodingKey {
        case cameraId = "camera_id"
        case patientId = "patient_id"
        case piStreamUrl = "pi_stream_url"
        case piAudioUrl = "pi_audio_url"
        case livekitIdentity = "livekit_identity"
        case livekitRoom = "livekit_room"
    }
}

/// Body for `PATCH /v1/cameras/{id}`. Nil fields are omitted (matches
/// backend's `extra="forbid"` policy: sending a field commits us to
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
