import Foundation

/// A patient under care. Mirrors `nemara-backend/src/schemas/patient.py`
/// `PatientResponse`.
///
/// `state`, `statusLine`, `lastEventAt`, `batteryPercent`, `camerasPaused`
/// are server-managed — wall phones / backend services own these. iOS
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

    let id: UUID
    var caregiverId: UUID
    var fullName: String
    var preferredName: String
    var dateOfBirth: Date?
    var gender: String?
    var relation: Relation
    var homeAddress: String?
    var state: State
    var statusLine: String
    var lastEventAt: Date?
    var batteryPercent: Int?
    var camerasPaused: Bool
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
        case state
        case statusLine = "status_line"
        case lastEventAt = "last_event_at"
        case batteryPercent = "battery_percent"
        case camerasPaused = "cameras_paused"
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

/// Body of `POST /v1/patients`. Server-managed state/status fields
/// are not settable at creation.
struct CreatePatientRequest: Encodable, Sendable {
    var fullName: String
    var preferredName: String
    var relation: Patient.Relation
    var dateOfBirth: Date?
    var gender: String?
    var homeAddress: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case preferredName = "preferred_name"
        case relation
        case dateOfBirth = "date_of_birth"
        case gender
        case homeAddress = "home_address"
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

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case preferredName = "preferred_name"
        case dateOfBirth = "date_of_birth"
        case gender
        case relation
        case homeAddress = "home_address"
        case camerasPaused = "cameras_paused"
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
    }
}
