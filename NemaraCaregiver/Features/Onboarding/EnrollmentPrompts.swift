import Foundation

/// The 12 angle prompts the caregiver walks through during face
/// enrollment. Manual-advance flow — the caregiver moves through them
/// at their own pace by tapping the capture button. We don't auto-
/// detect pose with Vision in v0; the human in the loop is reliable
/// enough at "tilt your head up" given a screen prompt.
///
/// Order matters: starts with the easiest (straight-on) so a caregiver
/// who only manages a few captures still gives us the most-useful
/// frontal pose.
enum EnrollmentPrompts {
    static let all: [String] = [
        "Look straight at the camera",
        "Tilt your head slightly up",
        "Tilt your head slightly down",
        "Turn slightly to your left",
        "Turn slightly to your right",
        "Smile naturally",
        "Close your mouth",
        "Look up to the left",
        "Look up to the right",
        "Look down to the left",
        "Look down to the right",
        "One more straight-on photo",
    ]

    /// Number of prompts. Used by the progress indicator at the top
    /// of the capture screen.
    static var count: Int { all.count }
}
