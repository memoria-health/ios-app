import Foundation

/// A wall-mounted phone acting as a camera + microphone for one room.
/// Mirrors `nemara-backend/src/schemas/camera.py` `CameraResponse`.
///
/// `id` is the persistent UUID assigned by the backend (used for
/// DELETE + cross-table references). `displayId` is the 1-based integer
/// rendered as "CAM 01" in the UI.
struct Camera: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var patientId: UUID
    var displayId: Int
    var room: String
    var iconName: String
    var online: Bool
    var lastSeenAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case displayId = "display_id"
        case room
        case iconName = "icon_name"
        case online
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
    }
}
