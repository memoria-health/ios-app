import Foundation

/// A patient under care. Mirrors `nemara-backend/src/schemas/patient.py`
/// `PatientResponse`.
///
/// `state`, `statusLine`, `lastEventAt`, `camerasPaused` are
/// server-managed. Wall phones / backend services own these. iOS
/// never PATCHes them directly except via `cameras_paused` (the explicit
/// Monitoring toggle).
struct Patient: Identifiable, Hashable, Sendable, Codable {
    /// Aggregated patient status surfaced on the roster row.
    enum State: String, Sendable, Codable {
        case calm
        case critical
        case offline
    }

    /// Patient's relation to the caregiver. Backend stores these as a
    /// `relation_kind` Postgres enum; raw values match the wire.
    enum Relation: String, CaseIterable, Sendable, Codable {
        case parent
        case spouse
        case grandparent
        case sibling
        case client
        case other

        /// Capitalized text used in UI rows (e.g. "Parent").
        var displayName: String {
            rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// Data-residency region for this patient's data. The onboarding country
    /// picker maps to these; the backend routes storage + liftability off it.
    /// Set at creation, immutable after. Raw values match the wire ('US'/'IN').
    enum Region: String, CaseIterable, Sendable, Codable {
        case us = "US"
        case india = "IN"

        /// Country label shown in the onboarding picker.
        var displayName: String {
            switch self {
            case .us: return "United States"
            case .india: return "India"
            }
        }
    }

    let id: UUID
    var caregiverId: UUID
    var fullName: String
    var preferredName: String
    var dateOfBirth: Date?
    var gender: String?
    var relation: Relation
    var homeAddress: String?
    /// Country this home is in (ISO alpha-2), picked at onboarding. Optional for
    /// decode resilience; backend always sends it.
    var country: String?
    /// Data-residency region for this patient's data, DERIVED from `country`.
    /// Optional for decode resilience (the app doesn't switch on it yet).
    var region: Region?
    var state: State
    var statusLine: String
    var lastEventAt: Date?
    var camerasPaused: Bool
    /// Facilities audio kill: false = the patient's cameras never publish
    /// an audio track (no live sound, no audio in clips, no speech
    /// alerts). Optional for decode resilience; treat nil as true.
    var audioCaptureEnabled: Bool?
    /// Per-patient master toggle for event-driven email alerts. When on,
    /// the backend fans alerts to the owning caregiver's account email
    /// plus every address in `emailAlertRecipients`. Mirrors the web
    /// dashboard's per-patient EmailAlertsSettings card.
    var emailAlertsEnabled: Bool
    /// Additional email addresses (beyond the caregiver's account email)
    /// to copy on this patient's alerts. Server replaces the full array
    /// on every PATCH, so clients send the whole list.
    var emailAlertRecipients: [String]
    /// Per-patient opt-in for contributing short video/audio clips to
    /// Memoria's research dataset (only captured when someone is present).
    /// Default false; flipped by the first-open consent sheet and the
    /// Settings card. Mirrors the web dashboard's DataCollectionSettings.
    var dataCollectionEnabled: Bool
    /// When the caregiver first made a data-collection decision (Share or
    /// Not now). NULL ⇒ never asked ⇒ show the first-open consent sheet.
    /// Non-null ⇒ decided ⇒ never auto-prompt again. Server-stamped on
    /// any PATCH that carries `data_collection_enabled`; the client never
    /// sends this field.
    var dataCollectionDecidedAt: Date?
    /// RETIRED patient-level privacy flag — superseded by per-camera
    /// privacy (`Camera.privacyEnabled`); no UI reads or writes it
    /// anymore. Optional for decode resilience: the backend is dropping
    /// the column, and a required Bool would fail every patient decode
    /// the moment it disappears from the payload.
    var privacyModeEnabled: Bool?
    /// Bucket-relative key in patient-photos (e.g. "{id}.jpg") when
    /// the caregiver has uploaded an avatar. NULL falls back to
    /// the initials placeholder in `NemaraAvatar`. The signed URL
    /// is fetched separately via `NemaraAPIClient.patientPhotoURL`.
    var photoStorageKey: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case caregiverId = "caregiver_id"
        case fullName = "full_name"
        case preferredName = "preferred_name"
        case dateOfBirth = "date_of_birth"
        case gender
        case relation
        case homeAddress = "home_address"
        case country
        case region
        case state
        case statusLine = "status_line"
        case lastEventAt = "last_event_at"
        case camerasPaused = "cameras_paused"
        case audioCaptureEnabled = "audio_capture_enabled"
        case emailAlertsEnabled = "email_alerts_enabled"
        case emailAlertRecipients = "email_alert_recipients"
        case dataCollectionEnabled = "data_collection_enabled"
        case dataCollectionDecidedAt = "data_collection_decided_at"
        case privacyModeEnabled = "privacy_mode_enabled"
        case photoStorageKey = "photo_storage_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// First letter for the avatar tile while we don't have real photos.
    var avatarLetter: String {
        String(preferredName.first ?? fullName.first ?? "?")
    }

    /// Age computed from `dateOfBirth`. Years only; 0 when DOB is unknown.
    var age: Int {
        guard let dob = dateOfBirth else { return 0 }
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
    }
}

// MARK: - Tolerant decoding (backend-version skew)

/// Custom decoder in an EXTENSION (so the struct keeps its synthesized
/// memberwise init — same convention as `Detector`).
///
/// Patient is the FIRST thing `bootstrap()` loads, and bootstrap runs
/// inside sign-in, so any key this throws on takes login down with
/// "Couldn't read the response" rather than breaking one screen. Camera
/// and Detector each got this treatment after being burned; Patient was
/// the one model on the critical path still using the synthesized
/// decoder, which makes EVERY non-optional property mandatory.
///
/// Rule: columns that have existed since launch stay required — without
/// those the payload is not a patient at all. Every column added since
/// falls back to its pre-column default, so an app build that runs
/// against an older backend still signs in.
extension Patient {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        caregiverId = try c.decode(UUID.self, forKey: .caregiverId)
        fullName = try c.decode(String.self, forKey: .fullName)
        preferredName = try c.decode(String.self, forKey: .preferredName)
        relation = try c.decode(Relation.self, forKey: .relation)
        state = try c.decode(State.self, forKey: .state)
        statusLine = try c.decode(String.self, forKey: .statusLine)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)

        dateOfBirth = try c.decodeIfPresent(Date.self, forKey: .dateOfBirth)
        gender = try c.decodeIfPresent(String.self, forKey: .gender)
        homeAddress = try c.decodeIfPresent(String.self, forKey: .homeAddress)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        region = try c.decodeIfPresent(Region.self, forKey: .region)
        lastEventAt = try c.decodeIfPresent(Date.self, forKey: .lastEventAt)
        photoStorageKey = try c.decodeIfPresent(String.self, forKey: .photoStorageKey)
        audioCaptureEnabled = try c.decodeIfPresent(Bool.self, forKey: .audioCaptureEnabled)
        privacyModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .privacyModeEnabled)
        dataCollectionDecidedAt = try c.decodeIfPresent(Date.self, forKey: .dataCollectionDecidedAt)

        // Post-launch columns. Each default is the behavior that was in
        // force before the column existed: monitoring live, no email
        // fan-out, and NOT contributing clips to the research dataset —
        // absent consent must never read as consent given.
        camerasPaused = try c.decodeIfPresent(Bool.self, forKey: .camerasPaused) ?? false
        emailAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .emailAlertsEnabled) ?? false
        emailAlertRecipients = try c.decodeIfPresent([String].self, forKey: .emailAlertRecipients) ?? []
        dataCollectionEnabled = try c.decodeIfPresent(Bool.self, forKey: .dataCollectionEnabled) ?? false
    }
}

/// Body of `POST /v1/patients`. Server-managed state/status fields
/// are not settable at creation.
struct CreatePatientRequest: Encodable, Sendable {
    var fullName: String
    var preferredName: String
    var relation: Patient.Relation
    var dateOfBirth: Date?
    var gender: String?
    var homeAddress: String?
    /// Country this home is in (ISO alpha-2). Set at onboarding; the residency
    /// region is derived from it server-side. Immutable after creation.
    var country: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case preferredName = "preferred_name"
        case relation
        case dateOfBirth = "date_of_birth"
        case gender
        case homeAddress = "home_address"
        case country
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fullName, forKey: .fullName)
        try c.encode(preferredName, forKey: .preferredName)
        try c.encode(relation, forKey: .relation)
        // The backend column is a Postgres DATE (not timestamptz) so it
        // rejects ISO-8601 strings that carry time-of-day. Format as
        // YYYY-MM-DD in UTC to match what pydantic's date validator
        // accepts.
        if let dob = dateOfBirth {
            try c.encode(NemaraJSON.dateOnlyString(from: dob), forKey: .dateOfBirth)
        }
        try c.encodeIfPresent(gender, forKey: .gender)
        try c.encodeIfPresent(homeAddress, forKey: .homeAddress)
        try c.encode(country, forKey: .country)
    }
}

/// Body of `PATCH /v1/patients/{id}`. Nil = field omitted.
struct UpdatePatientRequest: Encodable, Sendable {
    var fullName: String?
    var preferredName: String?
    var dateOfBirth: Date?
    var gender: String?
    var relation: Patient.Relation?
    var homeAddress: String?
    var camerasPaused: Bool?
    var audioCaptureEnabled: Bool?
    var emailAlertsEnabled: Bool?
    /// Send the full array. The backend replaces the column wholesale.
    var emailAlertRecipients: [String]?
    /// Data-collection opt-in. The backend stamps `data_collection_decided_at`
    /// server-side whenever this field is present (true OR false records a
    /// decision), so the client never sends the timestamp itself.
    var dataCollectionEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case preferredName = "preferred_name"
        case dateOfBirth = "date_of_birth"
        case gender
        case relation
        case homeAddress = "home_address"
        case camerasPaused = "cameras_paused"
        case audioCaptureEnabled = "audio_capture_enabled"
        case emailAlertsEnabled = "email_alerts_enabled"
        case emailAlertRecipients = "email_alert_recipients"
        case dataCollectionEnabled = "data_collection_enabled"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(preferredName, forKey: .preferredName)
        // See CreatePatientRequest — backend's date_of_birth is a
        // pure DATE, not a timestamp; serialize as YYYY-MM-DD.
        if let dob = dateOfBirth {
            try c.encode(NemaraJSON.dateOnlyString(from: dob), forKey: .dateOfBirth)
        }
        try c.encodeIfPresent(gender, forKey: .gender)
        try c.encodeIfPresent(relation, forKey: .relation)
        try c.encodeIfPresent(homeAddress, forKey: .homeAddress)
        try c.encodeIfPresent(camerasPaused, forKey: .camerasPaused)
        try c.encodeIfPresent(audioCaptureEnabled, forKey: .audioCaptureEnabled)
        try c.encodeIfPresent(emailAlertsEnabled, forKey: .emailAlertsEnabled)
        try c.encodeIfPresent(emailAlertRecipients, forKey: .emailAlertRecipients)
        try c.encodeIfPresent(dataCollectionEnabled, forKey: .dataCollectionEnabled)
    }
}

/// Body returned by `POST /v1/patients/{id}/test-email`. Echoes a
/// human-readable status the iOS UI shows next to the Send test button.
struct TestEmailResponse: Decodable, Sendable {
    var status: String
}
