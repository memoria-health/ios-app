import Foundation

/// A detector configured for a patient. Mirrors
/// `nemara-backend/src/schemas/detector.py` `DetectorResponse`.
///
/// Every detector — preset or custom — describes itself along four
/// axes (per design system): what, shape, where, when.
struct Detector: Identifiable, Hashable, Sendable, Codable {
    enum Category: String, Sendable, Codable {
        case safety
        case routine
    }

    enum Source: String, Sendable, Codable {
        case preset
        case custom
    }

    /// "Shape" of a detection — a single moment vs. a sustained
    /// condition. Wire raw values are snake_case to match the backend
    /// `detector_shape` enum; `displayName` is the all-caps text used in
    /// the detector row.
    enum Shape: String, Sendable, Codable {
        case pointInTime = "point_in_time"
        case state       = "state"       // legacy preset (agitation); not offered in UI
        case scheduled   = "scheduled"   // absence detector — fires if signal absent in window

        var displayName: String {
            switch self {
            case .pointInTime: return "POINT-IN-TIME"
            case .state:       return "STATE"
            case .scheduled:   return "SCHEDULED"
            }
        }
    }

    enum Sensitivity: String, CaseIterable, Sendable, Codable {
        case low
        case standard
        case high
        case off

        var displayName: String {
            rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// Evaluation window for a `scheduled` detector. Fields are optional
    /// so the LLM can return a partial inference (blanks the user fills
    /// in). Times are local "HH:MM" 24h; daysOfWeek is 0=Mon..6=Sun.
    struct ScheduleConfig: Codable, Hashable, Sendable {
        enum Cadence: String, Codable, Sendable {
            case daily
            case weekly
        }
        var cadence: Cadence?
        var daysOfWeek: [Int]?
        var windowStart: String?
        var windowEnd: String?
        var deadline: String?

        enum CodingKeys: String, CodingKey {
            case cadence
            case daysOfWeek = "days_of_week"
            case windowStart = "window_start"
            case windowEnd = "window_end"
            case deadline
        }
    }

    let id: UUID
    var patientId: UUID
    var name: String
    var iconName: String
    var description: String
    var category: Category
    var source: Source
    var shape: Shape
    var whereScope: String
    var whenScope: String
    var sensitivity: Sensitivity
    var isOn: Bool
    var customPrompt: String?
    /// Runtime-contract identifier. For presets: `"fall"` / `"wandering"`
    /// / `"agitation"` / `"medication"`. For custom detectors:
    /// `"custom_<8hex>"` once the backend's async LLM compile finishes.
    /// **Optional** because freshly-created custom detectors return
    /// with `identifier=null` while the compile runs (~3-5s); UI can
    /// show a "compiling…" state during that window.
    var identifier: String?
    /// Null for reactive detectors; the evaluation window for `scheduled`.
    var scheduleConfig: ScheduleConfig?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case name
        case iconName = "icon_name"
        case description
        case category
        case source
        case shape
        case whereScope = "where_scope"
        case whenScope = "when_scope"
        case sensitivity
        case isOn = "is_on"
        case customPrompt = "custom_prompt"
        case identifier
        case scheduleConfig = "schedule_config"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body of `POST /v1/patients/{id}/detectors`. Server forces
/// `source = custom`. Only `name` + `customPrompt` are required; the
/// rest are normally LLM-inferred then confirmed on the review screen.
/// `whereScope`/`whenScope` default server-side (no longer shown in UI).
struct CreateDetectorRequest: Encodable, Sendable {
    var name: String
    var customPrompt: String
    var description: String = "Custom detector"
    var category: Detector.Category = .safety
    var shape: Detector.Shape = .pointInTime
    var iconName: String = "eye"
    var whereScope: String = "ALL ROOMS"
    var whenScope: String = "ALWAYS"
    var sensitivity: Detector.Sensitivity = .standard
    var scheduleConfig: Detector.ScheduleConfig? = nil

    enum CodingKeys: String, CodingKey {
        case name
        case customPrompt = "custom_prompt"
        case description
        case category
        case shape
        case iconName = "icon_name"
        case whereScope = "where_scope"
        case whenScope = "when_scope"
        case sensitivity
        case scheduleConfig = "schedule_config"
    }
}

/// Body of `POST /v1/detectors/infer` — the plain-English ask the LLM
/// classifies + structures for the create review screen.
struct InferDetectorRequest: Encodable, Sendable {
    var name: String?
    var prompt: String
}

/// LLM-inferred fields for the create review screen. Nulls where the
/// model couldn't confidently determine a value.
struct InferDetectorResponse: Decodable, Sendable {
    var shape: Detector.Shape
    var category: Detector.Category
    var iconName: String
    var sensitivity: Detector.Sensitivity
    var scheduleConfig: Detector.ScheduleConfig?

    enum CodingKeys: String, CodingKey {
        case shape
        case category
        case iconName = "icon_name"
        case sensitivity
        case scheduleConfig = "schedule_config"
    }
}

/// Body of `PATCH /v1/detectors/{id}`. Nil = field omitted.
struct UpdateDetectorRequest: Encodable, Sendable {
    var name: String?
    var iconName: String?
    var description: String?
    var category: Detector.Category?
    var shape: Detector.Shape?
    var whereScope: String?
    var whenScope: String?
    var sensitivity: Detector.Sensitivity?
    var isOn: Bool?
    var customPrompt: String?

    enum CodingKeys: String, CodingKey {
        case name
        case iconName = "icon_name"
        case description
        case category
        case shape
        case whereScope = "where_scope"
        case whenScope = "when_scope"
        case sensitivity
        case isOn = "is_on"
        case customPrompt = "custom_prompt"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(iconName, forKey: .iconName)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(shape, forKey: .shape)
        try c.encodeIfPresent(whereScope, forKey: .whereScope)
        try c.encodeIfPresent(whenScope, forKey: .whenScope)
        try c.encodeIfPresent(sensitivity, forKey: .sensitivity)
        try c.encodeIfPresent(isOn, forKey: .isOn)
        try c.encodeIfPresent(customPrompt, forKey: .customPrompt)
    }
}

/// One detector-catalog entry from
/// `GET /v1/patients/{id}/detectors/library` — the detection library. Mirrors
/// `nemara-backend/src/schemas/detector.py` `DetectorLibraryEntry`.
///
/// `alreadyAdded` is true when the patient already has a detector with this
/// identifier (e.g. an auto-seeded preset), so the picker pre-checks/disables
/// it. `recommended` entries are the cohort's default presets.
struct DetectorLibraryEntry: Identifiable, Hashable, Sendable, Decodable {
    var key: String
    var name: String
    var iconName: String
    var description: String
    var category: Detector.Category
    var cohort: String          // "child" | "adult" | "both"
    var recommended: Bool
    var alreadyAdded: Bool

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key
        case name
        case iconName = "icon_name"
        case description
        case category
        case cohort
        case recommended
        case alreadyAdded = "already_added"
    }
}

/// Body of `POST /v1/patients/{id}/detectors/from-library` — the catalog keys
/// to instantiate as preset detectors. Server skips unknown/already-present
/// keys (unknown → 422).
struct AddFromLibraryRequest: Encodable, Sendable {
    var keys: [String]
}
