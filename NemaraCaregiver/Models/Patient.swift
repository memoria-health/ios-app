import Foundation

/// A patient under care. The home roster lists these; tapping one opens
/// the patient bundle (Live / Events / Settings).
///
/// `state` is the latest aggregated status surfaced on the roster row —
/// it's a derived value, but we cache it on the model so the row can
/// render without joining against events at every refresh.
struct Patient: Identifiable, Hashable, Sendable {
    enum State: String, Sendable {
        case calm
        case critical
        case offline
    }

    enum Relation: String, CaseIterable, Sendable {
        case parent     = "Parent"
        case spouse     = "Spouse"
        case grandparent = "Grandparent"
        case sibling    = "Sibling"
        case client     = "Client"
        case other      = "Other"
    }

    let id: UUID
    var fullName: String        // "Margaret O'Brien"
    var preferredName: String   // "Maggie"
    var dateOfBirth: Date
    var gender: String          // free text "Female" / "Male" / "Non-binary" / etc.
    var relation: Relation
    var homeAddress: String?
    var state: State
    var statusLine: String      // "Possible fall, living room" / "Resting in living room" / etc.
    var lastEventAt: Date?
    var batteryPercent: Int?    // wall phone battery, nil when offline

    /// When `true`, every wall-mounted phone in this patient's home
    /// stops streaming and stops running detectors. Surfaces on the
    /// Patient Settings "Monitoring" toggle and is reflected in the
    /// roster row (PAUSED pill) and Live tab (paused overlay).
    var camerasPaused: Bool = false

    /// First letter used for `NemaraAvatar` while we don't have real photos.
    var avatarLetter: String {
        String(preferredName.first ?? fullName.first ?? "?")
    }

    /// Age computed from `dateOfBirth`. Years only.
    var age: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
    }
}
