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

    /// AI paused, lighter than `disabled`. When true, the backend
    /// tick skips the Gemini call (synthetic "skipped" row with
    /// skipped_reason='ai_paused') but the live tile STAYS VISIBLE
    /// in the grid and video keeps streaming. Lets the caregiver
    /// watch a room without paying for AI calls.
    var aiPaused: Bool

    /// Which physical device class this camera row represents. The
    /// detection pipeline treats both identically (both publish to
    /// the same LiveKit room), but the UI branches: phone cameras
    /// pair via a 6-digit code, sensor cameras pair via the
    /// discovered-list flow (and on iOS, optionally via the
    /// WiFi-setup AP). Mirrors `cameras.source_type` on the backend.
    enum SourceType: String, Sendable, Codable {
        /// Wall-mounted NemaraCam iPhone (the original path).
        case phone = "iphone"
        /// Any non-iPhone published camera — a Raspberry Pi streaming
        /// daemon ("pi") or a mini-PC gateway ("gateway"). They behave
        /// identically in the UI (discovered-list pairing, not the 6-digit
        /// code), so both wire values decode into this case.
        case sensor = "pi"

        /// Lenient decode: only "iphone" is a phone; every other backend
        /// `source_type` ("pi", "gateway", and any future relay type) is a
        /// sensor-style camera. Stops one unrecognized value (as "gateway"
        /// did) from failing the entire camera-list decode.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = (raw == "iphone") ? .phone : .sensor
        }
    }
    var sourceType: SourceType

    /// AI room classification for this camera's view. Drives the
    /// per-camera privacy derivation on the backend: bathroom/bedroom
    /// rooms get `privacy_enabled=true` automatically. Nil until the
    /// classifier has run (or on older backends).
    enum RoomClass: String, Sendable, Codable {
        case bathroom
        case bedroom
        case other

        /// Lenient decode: any unrecognized future class ("garage",
        /// "hallway", …) folds into `.other` instead of failing the
        /// whole camera-list decode — same defensive pattern as
        /// `SourceType`.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = RoomClass(rawValue: raw) ?? .other
        }
    }
    /// What the classifier thinks this room is. Nil = not classified yet.
    var roomClass: RoomClass?
    /// Classifier confidence in `roomClass`, 0–1. Nil when unclassified.
    var roomClassConfidence: Double?
    /// When the classification last ran. Nil when unclassified.
    var roomClassifiedAt: Date?

    /// Per-camera privacy, derived server-side from `roomClass`
    /// (bathroom/bedroom → true, locked, no user toggle). While true
    /// the backend NEVER delivers live video/audio for this camera —
    /// the Live tile shows a "Private room" placard, talk/call is
    /// disabled for it — and sensitive event clips arrive blurred with
    /// audio stripped (`DetectionEvent.clipCensored`). Defaults false
    /// so older payloads (pre-column) decode cleanly.
    var privacyEnabled: Bool

    /// True when the classifier put this camera in a room that is
    /// private by policy (bathroom/bedroom). Drives the one-time
    /// sensitive-room explainer card on the Live tab.
    var isSensitiveRoom: Bool {
        roomClass == .bathroom || roomClass == .bedroom
    }

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
    var createdAt: Date

    /// True once the wall phone has completed the /pair handshake.
    /// False = row exists with an open pairing code, no phone has
    /// claimed it yet. Drives the "PAIRING" status badge and the
    /// "Show pairing code" button on CameraDetailView.
    var paired: Bool

    /// Whether the Memoria Sensor app is currently RUNNING on this
    /// camera's iPhone. The phone polls the backend every 1s while the
    /// app is open; the backend flips this false when those polls stop
    /// (app closed / force-quit / phone off). Distinct from `online`
    /// (publishing) and `desiredState` (intent): false here means the
    /// caregiver must physically REOPEN the app — Reconnect can't help.
    ///
    /// Optional: nil from older backends / pre-migration Realtime rows,
    /// which we treat as "present" (never falsely show "app closed").
    /// Only meaningful for `.phone` sensors — Pi sensors have no app to
    /// close and the backend never writes them, so this stays nil/true.
    /// Use `isAppClosed`, which encodes that guard.
    var appPresent: Bool?

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
        case sourceType = "source_type"
        case roomClass = "room_class"
        case roomClassConfidence = "room_class_confidence"
        case roomClassifiedAt = "room_classified_at"
        case privacyEnabled = "privacy_enabled"
        case livekitIdentity = "livekit_identity"
        case createdAt = "created_at"
        case paired
        case appPresent = "app_present"
        // Realtime-payload-only. The backend's REST shape exposes
        // `paired` directly; Supabase Realtime ships the raw DB row,
        // which has `api_key_hash` / `ingest_token_hash` but no
        // `paired`. We read these on decode (below) to derive
        // `paired` source-type-aware and then drop them.
        case apiKeyHash = "api_key_hash"
        case ingestTokenHash = "ingest_token_hash"
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
        // Default to .phone for Supabase Realtime payloads that predate
        // the source_type column. Without this fallback, decoding older
        // rows would fail and crash the realtime stream.
        sourceType = try c.decodeIfPresent(SourceType.self, forKey: .sourceType) ?? .phone
        // Room-classification + per-camera privacy columns. All tolerant:
        // absent on older backends / pre-migration Realtime rows → nil /
        // false, so this decode never fails on a payload that predates
        // the privacy migration.
        roomClass = try c.decodeIfPresent(RoomClass.self, forKey: .roomClass)
        roomClassConfidence = try c.decodeIfPresent(Double.self, forKey: .roomClassConfidence)
        roomClassifiedAt = try c.decodeIfPresent(Date.self, forKey: .roomClassifiedAt)
        privacyEnabled = try c.decodeIfPresent(Bool.self, forKey: .privacyEnabled) ?? false
        livekitIdentity = try c.decodeIfPresent(String.self, forKey: .livekitIdentity)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        if let explicit = try c.decodeIfPresent(Bool.self, forKey: .paired) {
            paired = explicit
        } else {
            // Derive from auth-credential columns. iPhone cameras carry
            // their bearer hash on api_key_hash; Pi cameras skip the
            // pairing-code/api_key flow and store the equivalent on
            // ingest_token_hash. The previous code only checked
            // api_key_hash, which made every Pi camera decode as
            // paired=false from Realtime — UI then flipped to
            // "PAIRING" on every UPDATE even though pairing
            // completed at provision time.
            let apiKeyHash = try c.decodeIfPresent(String.self, forKey: .apiKeyHash)
            let ingestTokenHash = try c.decodeIfPresent(String.self, forKey: .ingestTokenHash)
            paired = (apiKeyHash != nil) || (ingestTokenHash != nil)
        }
        // Absent on older backends / pre-migration rows → nil, treated
        // as "present" by `isAppClosed` (never falsely shows app-closed).
        appPresent = try c.decodeIfPresent(Bool.self, forKey: .appPresent)
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
        try c.encode(sourceType, forKey: .sourceType)
        try c.encodeIfPresent(roomClass, forKey: .roomClass)
        try c.encodeIfPresent(roomClassConfidence, forKey: .roomClassConfidence)
        try c.encodeIfPresent(roomClassifiedAt, forKey: .roomClassifiedAt)
        try c.encode(privacyEnabled, forKey: .privacyEnabled)
        try c.encodeIfPresent(livekitIdentity, forKey: .livekitIdentity)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(paired, forKey: .paired)
        try c.encodeIfPresent(appPresent, forKey: .appPresent)
    }

    /// Memberwise init kept available for fixtures + AppEnvironment
    /// previews. Swift auto-synthesizes one until you write any custom
    /// init; once we added `init(from:)`, we have to spell this out.
    init(
        disabled: Bool,
        aiPaused: Bool,
        sourceType: SourceType = .phone,
        roomClass: RoomClass? = nil,
        roomClassConfidence: Double? = nil,
        roomClassifiedAt: Date? = nil,
        privacyEnabled: Bool = false,
        desiredState: DesiredState,
        id: UUID,
        patientId: UUID,
        displayId: Int,
        room: String,
        iconName: String,
        online: Bool,
        livekitIdentity: String?,
        createdAt: Date,
        paired: Bool,
        appPresent: Bool? = nil,
    ) {
        self.disabled = disabled
        self.aiPaused = aiPaused
        self.sourceType = sourceType
        self.roomClass = roomClass
        self.roomClassConfidence = roomClassConfidence
        self.roomClassifiedAt = roomClassifiedAt
        self.privacyEnabled = privacyEnabled
        self.desiredState = desiredState
        self.id = id
        self.patientId = patientId
        self.displayId = displayId
        self.room = room
        self.iconName = iconName
        self.online = online
        self.livekitIdentity = livekitIdentity
        self.createdAt = createdAt
        self.paired = paired
        self.appPresent = appPresent
    }

    /// True when this iPhone sensor's Memoria Sensor app is CLOSED:
    /// not online, and the backend's heartbeat says the app stopped
    /// polling (`appPresent == false`). In this state the caregiver
    /// cannot reconnect from here — the phone isn't running to receive
    /// the intent — so the UI must say "open Memoria Sensor", NOT
    /// "Disconnected (tap Reconnect)". Never true for Pi sensors
    /// (`.phone` guard — they have no app to close) and never while the
    /// camera is online. nil `appPresent` (old payloads) → not closed.
    var isAppClosed: Bool {
        sourceType == .phone && !online && appPresent == false
    }

    /// Eligibility predicate for the Live tab: "this camera SHOULD be
    /// rendered as a tile right now, subject to the LiveKit SDK
    /// having (or being about to have) a video track for it."
    ///
    /// History note: this used to also gate on `online` (a backend
    /// signal). As of the REST-polled reconciler refactor (2026-05-29),
    /// the SDK's `videoTracksByIdentity` map is the source of truth
    /// for "is the camera actually publishing right now" and the Live
    /// tab gates rendering on track presence directly via
    /// `LiveKitClient.connectivity`. `online` is still a meaningful
    /// signal — it's used for the Cameras-tab settings pill — but the
    /// Live tab no longer reads it. This stops the failure mode where
    /// the backend's `online` would lie (e.g., during the SDK-event-
    /// loss bug) and hide a tile whose publisher was actually fine.
    ///
    /// True iff: paired (has a livekit_identity), not user-hidden,
    /// the caregiver intent is connected.
    var isLiveStreaming: Bool {
        livekitIdentity != nil
            && !disabled
            && desiredState == .connected
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
///
/// The backend's push refactor removed `pi_stream_url` and
/// `pi_audio_url` from this response: in push mode the Pi opens an
/// outbound connection to the backend rather than the backend
/// pulling from a Pi-served URL, so those fields are meaningless.
/// The Pi's ingest bearer token is delivered separately via the
/// next `/v1/cameras/pi-announce` response, not here.
struct ProvisionSensorCameraResponse: Decodable, Sendable {
    let cameraId: UUID
    let patientId: UUID
    let livekitIdentity: String
    let livekitRoom: String

    enum CodingKeys: String, CodingKey {
        case cameraId = "camera_id"
        case patientId = "patient_id"
        case livekitIdentity = "livekit_identity"
        case livekitRoom = "livekit_room"
    }
}

/// Body for `PATCH /v1/cameras/{id}`. Nil fields are omitted (matches
/// backend's `extra="forbid"` policy: sending a field commits us to
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

/// A camera as the ACCOUNT sees it, including ones no patient owns yet.
///
/// The installer provisions a camera against the account; who it watches
/// is decided here, in the app. `unassigned` rows are what the sensor
/// sheet lists as ready to set up — they are NOT discovered over the
/// local network, so the caregiver can be anywhere.
struct AccountCamera: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let room: String
    let iconName: String
    let online: Bool
    let sourceType: String
    /// Everyone this camera watches, primary first. Empty = unassigned.
    let patientIds: [UUID]
    let primaryPatientId: UUID?
    let unassigned: Bool

    enum CodingKeys: String, CodingKey {
        case id, room, online, unassigned
        case iconName = "icon_name"
        case sourceType = "source_type"
        case patientIds = "patient_ids"
        case primaryPatientId = "primary_patient_id"
    }
}

/// Body for `POST /v1/cameras/{id}/coverage`.
struct CoverageBody: Encodable {
    let room: String?
    let iconName: String?
    let primaryPatientId: UUID
    let alsoPatientIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case room
        case iconName = "icon_name"
        case primaryPatientId = "primary_patient_id"
        case alsoPatientIds = "also_patient_ids"
    }
}
