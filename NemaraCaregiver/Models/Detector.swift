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
        case pointInTime = "point_in_time"  // momentary — fires the moment it's seen
        case state       = "state"       // continuous/ongoing activity — one event per session
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
    /// Null unless `shape == .state`; the rising-edge episode gap (seconds).
    var episodeGapSeconds: Int?
    /// Caregiver-readable summary of the compiled instructions
    /// ("Counts: …" / "Doesn't count: …" / "Caution: …"). Nil while
    /// Memoria is (re)writing them or if summarization failed.
    var userCriteria: [String]?
    /// Plain-words change requests the caregiver has submitted, oldest first.
    var refinements: [String]?
    /// Wandering only: the caregiver's saved exit-door choice, so the picker
    /// can pre-highlight it. Nil until the caregiver runs the door picker.
    var doorConfig: DoorConfig?
    /// True for detectors that read FINE visual detail — small motion
    /// (seizure/choking) or small objects (medication/stove). Their
    /// accuracy varies with camera distance, lighting, and angle, so we
    /// show an expectations notice at enroll + in the detail sheet.
    /// Server-computed. Optional on the wire (older backends omit it);
    /// read through `showsAccuracyCaveat` which treats nil as false.
    var accuracyCaveat: Bool?
    var createdAt: Date
    var updatedAt: Date

    /// Non-optional accessor for the UI. Nil (field absent) reads as
    /// "no caveat".
    var showsAccuracyCaveat: Bool { accuracyCaveat ?? false }

    /// The exit-door selection stored on a `wandering` detector. Mirrors the
    /// backend `door_config` jsonb (see `POST /v1/patients/{id}/wandering-door`):
    /// `{ doors: [{box,label,source}], no_exit_door }`. A caregiver can pick
    /// MULTIPLE exit doors.
    struct DoorConfig: Codable, Hashable, Sendable {
        var doors: [Door]
        /// True => no door leads outside; the detector is turned off.
        var noExitDoor: Bool

        /// One selected exit door.
        struct Door: Codable, Hashable, Sendable {
            /// `[x, y, w, h]` fractions of the frame (0-1).
            var box: [Double]?
            var label: String?
            /// `"vlm"` (tapped a highlighted box) or `"manual"` (tap-override).
            var source: String?
        }

        enum CodingKeys: String, CodingKey {
            case doors
            case noExitDoor = "no_exit_door"
            // Legacy single-door keys (rows saved before multi-door shipped).
            case box, label, source
        }

        init(doors: [Door] = [], noExitDoor: Bool = false) {
            self.doors = doors
            self.noExitDoor = noExitDoor
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            noExitDoor = try c.decodeIfPresent(Bool.self, forKey: .noExitDoor) ?? false
            if let arr = try c.decodeIfPresent([Door].self, forKey: .doors) {
                doors = arr
            } else if let box = try c.decodeIfPresent([Double].self, forKey: .box) {
                // Back-compat: fold a legacy single-door row into the array.
                doors = [Door(
                    box: box,
                    label: try c.decodeIfPresent(String.self, forKey: .label),
                    source: try c.decodeIfPresent(String.self, forKey: .source),
                )]
            } else {
                doors = []
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(doors, forKey: .doors)
            try c.encode(noExitDoor, forKey: .noExitDoor)
        }
    }

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
        case episodeGapSeconds = "episode_gap_seconds"
        case userCriteria = "user_criteria"
        case refinements
        case doorConfig = "door_config"
        case accuracyCaveat = "accuracy_caveat"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Wandering exit-door picker wire types

/// Body of `POST /v1/detect-doors` — one camera frame (base64 JPEG) the VLM
/// scans for doorways to highlight in the exit-door picker.
struct DetectDoorsRequest: Encodable, Sendable {
    var imageBase64: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
    }
}

/// One doorway the VLM found. `box` is `[x, y, w, h]` as fractions of the
/// frame (0-1), top-left origin.
struct DetectedDoor: Decodable, Hashable, Sendable, Identifiable {
    var box: [Double]
    var label: String
    var id: String { "\(label)-\(box.map { String(format: "%.3f", $0) }.joined(separator: ","))" }
}

struct DetectDoorsResponse: Decodable, Sendable {
    var doors: [DetectedDoor]
}

/// One chosen exit door in a `SetWanderingDoorRequest`.
struct WanderingDoorInput: Encodable, Sendable {
    var box: [Double]
    var label: String?
    var source: String   // "vlm" | "manual"
}

/// Body of `POST /v1/cameras/{camera_id}/wandering-door` — the caregiver's
/// exit-door choice FOR ONE SENSOR. One or more `doors`, or `noExitDoor` when
/// this camera watches no exit (wandering skipped there).
struct SetWanderingDoorRequest: Encodable, Sendable {
    var doors: [WanderingDoorInput]
    var noExitDoor: Bool

    enum CodingKeys: String, CodingKey {
        case doors
        case noExitDoor = "no_exit_door"
    }
}

/// Per-sensor wandering exit-door config, from
/// `GET /v1/patients/{id}/wandering-doors` (and the POST response). The exit
/// door is per camera — each sensor sees a different scene.
struct CameraWanderingDoor: Decodable, Hashable, Sendable, Identifiable {
    var cameraId: UUID
    var doorConfig: Detector.DoorConfig?

    var id: UUID { cameraId }

    enum CodingKeys: String, CodingKey {
        case cameraId = "camera_id"
        case doorConfig = "door_config"
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
    /// Set only when `shape == .state`; the rising-edge episode gap (seconds).
    var episodeGapSeconds: Int? = nil

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
        case episodeGapSeconds = "episode_gap_seconds"
    }
}

/// Body of `POST /v1/detectors/infer` — the plain-English ask the LLM
/// classifies + structures for the create review screen.
struct InferDetectorRequest: Encodable, Sendable {
    var name: String?
    var prompt: String
}

/// Plain-English preview of the compiled behavior (customs visibility,
/// 2026-07-18): what the backend deduced from the caregiver's words,
/// shown on the review screen before the detector exists.
struct DetectorPlan: Decodable, Sendable {
    var watches: String
    var media: String
    var fires: String
    var checks: String
    var listens: Bool
}

/// LLM-inferred fields for the create review screen. Nulls where the
/// model couldn't confidently determine a value.
struct InferDetectorResponse: Decodable, Sendable {
    var shape: Detector.Shape
    var category: Detector.Category
    var iconName: String
    var sensitivity: Detector.Sensitivity
    var scheduleConfig: Detector.ScheduleConfig?
    /// Set when the model classified the activity as `.state`; nil otherwise.
    var episodeGapSeconds: Int?
    /// Nil only when preview composition failed server-side — hide the card.
    var plan: DetectorPlan?

    enum CodingKeys: String, CodingKey {
        case shape
        case category
        case iconName = "icon_name"
        case sensitivity
        case scheduleConfig = "schedule_config"
        case episodeGapSeconds = "episode_gap_seconds"
        case plan
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
    /// Fine-detail detector → show the accuracy notice in the picker.
    /// Optional on the wire (older backends omit it); read through
    /// `showsAccuracyCaveat`.
    var accuracyCaveat: Bool?

    var id: String { key }
    var showsAccuracyCaveat: Bool { accuracyCaveat ?? false }

    enum CodingKeys: String, CodingKey {
        case key
        case name
        case iconName = "icon_name"
        case description
        case category
        case cohort
        case recommended
        case alreadyAdded = "already_added"
        case accuracyCaveat = "accuracy_caveat"
    }
}

/// Body of `POST /v1/patients/{id}/detectors/from-library` — the catalog keys
/// to instantiate as preset detectors. Server skips unknown/already-present
/// keys (unknown → 422).
struct AddFromLibraryRequest: Encodable, Sendable {
    var keys: [String]
}
