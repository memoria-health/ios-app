import SwiftUI

/// The one place a detector/event category becomes a colour.
///
/// This replaced six copies of `category == .safety ? terra : sky` scattered
/// across detector rows, event cards, event detail and the add-detector
/// picker. With two categories a ternary was survivable; with four it is six
/// places to forget, and adding a fifth would have meant finding them all
/// again.
///
/// Pairing rule: colour NEVER carries the category alone. Four muted hues at
/// chip size is past what colour can reliably distinguish — particularly for
/// this audience, who are largely 50+ and a meaningful fraction of whom have
/// some colour vision deficiency. Every surface pairs the hue with the
/// detector's own icon or a text label, so the colour is reinforcement, not
/// information.
extension Detector.Category {

    /// The categories a caregiver may choose, in the order they are
    /// offered. Excludes `.unknown`, which exists only to absorb a value
    /// from a newer server and must never be selectable.
    static let selectable: [Detector.Category] = [
        .safety, .routine, .behaviour, .care,
    ]

    /// Foreground / accent — icon tint, rules, emphasised text.
    var accent: Color {
        switch self {
        case .safety:    return NemaraColor.terra
        case .routine:   return NemaraColor.sky
        case .behaviour: return NemaraColor.plum
        case .care:      return NemaraColor.sage
        // A category this build predates. Neutral ink rather than a guessed
        // hue: showing it in some other category's colour would be an
        // outright lie about what happened.
        case .unknown:   return NemaraColor.ink3
        }
    }

    /// Background wash — card tints, chip fills, tile backgrounds.
    var soft: Color {
        switch self {
        case .safety:    return NemaraColor.terraSoft
        case .routine:   return NemaraColor.skySoft
        case .behaviour: return NemaraColor.plumSoft
        case .care:      return NemaraColor.sageSoft
        case .unknown:   return NemaraColor.cardAlt
        }
    }

    /// Deep variant for text that must hold contrast on `soft`.
    var deep: Color {
        switch self {
        case .safety:    return NemaraColor.terraDeep
        // The others have no separate deep token yet; the accent already
        // carries enough contrast on its own soft wash. Kept as one switch
        // so the day a deep plum is added there is exactly one place to add
        // it.
        default:         return accent
        }
    }

    /// Whether this category escalates the patient card to the attention
    /// treatment. Only safety does.
    ///
    /// A named property rather than `== .safety` at the call site: it states
    /// the intent (does this shout?) instead of the mechanism, so the day
    /// escalation stops being a straight category check — if severity ever
    /// reaches the client — there is one place to change.
    var escalates: Bool { self == .safety }

    /// Caregiver-facing label.
    var displayName: String {
        switch self {
        case .safety:    return "Safety"
        case .routine:   return "Routine"
        case .behaviour: return "Behaviour"
        case .care:      return "Care"
        case .unknown:   return "Other"
        }
    }
}
