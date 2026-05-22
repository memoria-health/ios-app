import Foundation

/// A wall-mounted phone acting as a camera + microphone for one room.
///
/// Each patient has 1–N cameras. The patient Live tab picks the
/// `active` camera (whichever room the patient is currently in) and
/// renders only that single landscape feed.
struct Camera: Identifiable, Hashable, Sendable {
    let id: Int             // 1, 2, 3, … display as CAM 01 / 02
    var room: String
    var iconName: String    // SF Symbol or design-system icon name
    var online: Bool
}
