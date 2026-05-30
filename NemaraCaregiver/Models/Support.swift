import Foundation

/// Body of `POST /v1/support`. Mirrors
/// `nemara-backend/src/schemas/support.py` `SupportRequest`.
struct SupportRequest: Encodable, Sendable {
    var subject: String
    var message: String
}

/// Echoed status string the backend returns so the iOS UI can show a
/// friendly toast (e.g. "Sent. We'll reply to your account email.").
struct SupportResponse: Decodable, Sendable {
    var status: String
}
