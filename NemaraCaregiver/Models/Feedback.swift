import Foundation

/// Body of `POST /v1/feedback`. Mirrors
/// `nemara-backend/src/schemas/feedback.py` `FeedbackRequest`. Nil
/// fields are omitted (synthesized `encodeIfPresent`); the backend
/// requires a rating or at least one non-blank text field.
struct FeedbackRequest: Encodable, Sendable {
    var rating: Int?
    var whatsWorking: String?
    var whatsFrustrating: String?
    var category: String?
    /// Optional screenshots, each a base64-encoded JPEG (no `data:`
    /// prefix). Nil/empty → omitted. The backend forwards these to the
    /// founder notification email and never persists them.
    var attachments: [String]?

    enum CodingKeys: String, CodingKey {
        case rating
        case whatsWorking = "whats_working"
        case whatsFrustrating = "whats_frustrating"
        case category
        case attachments
    }
}

/// `{ status, id }` echoed by `POST /v1/feedback`.
struct FeedbackResponse: Decodable, Sendable {
    var status: String
    var id: UUID
}
