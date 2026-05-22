import Foundation

/// A detector configured for a patient. Every detector — preset or
/// custom — describes itself along four axes (per design system):
/// what, shape, where, when.
struct Detector: Identifiable, Hashable, Sendable {
    enum Category: String, Sendable {
        case safety
        case routine
    }

    enum Source: String, Sendable {
        case preset
        case custom
    }

    /// "Shape" of a detection — a single moment vs. a sustained condition.
    enum Shape: String, Sendable {
        case pointInTime = "POINT-IN-TIME"
        case state       = "STATE"
    }

    enum Sensitivity: String, CaseIterable, Sendable {
        case low      = "Low"
        case standard = "Standard"
        case high     = "High"
        case off      = "Off"
    }

    let id: UUID
    var name: String
    var iconName: String        // SF Symbol-ish glyph used in the row
    var description: String
    var category: Category
    var source: Source
    var shape: Shape
    var whereScope: String      // "ALL ROOMS" / "KITCHEN" / "HALLWAY"
    var whenScope: String       // "ALWAYS" / "8 AM, 8 PM ±1H" / "11 PM – 6 AM"
    var sensitivity: Sensitivity
    var isOn: Bool
}
