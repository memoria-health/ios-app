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
        case state       = "state"

        var displayName: String {
            switch self {
            case .pointInTime: return "POINT-IN-TIME"
            case .state:       return "STATE"
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body of `POST /v1/patients/{id}/detectors`. Server forces
/// `source = custom`; `customPrompt` is required.
struct CreateDetectorRequest: Encodable, Sendable {
    var name: String
    var iconName: String
    var description: String
    var category: Detector.Category
    var shape: Detector.Shape
    var whereScope: String
    var whenScope: String
    var customPrompt: String
    var sensitivity: Detector.Sensitivity = .standard

    enum CodingKeys: String, CodingKey {
        case name
        case iconName = "icon_name"
        case description
        case category
        case shape
        case whereScope = "where_scope"
        case whenScope = "when_scope"
        case customPrompt = "custom_prompt"
        case sensitivity
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
