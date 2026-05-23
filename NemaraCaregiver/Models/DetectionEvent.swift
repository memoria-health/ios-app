import Foundation

/// A detection event surfaced in the Events tab for a patient. Mirrors
/// `nemara-backend/src/schemas/event.py` `EventResponse`.
struct DetectionEvent: Identifiable, Hashable, Sendable, Codable {
    /// The caregiver's choice from the Event Review step.
    enum ReviewChoice: String, Sendable, Codable {
        case correct
        case wrong
        case unsure
    }

    let id: UUID
    var patientId: UUID
    var detectorId: UUID?
    var cameraId: UUID?
    var category: Detector.Category
    var source: Detector.Source
    var iconName: String
    var title: String
    var location: String
    var occurredAt: Date
    var hasClip: Bool
    var narrative: String
    var opened: Bool
    var reviewed: Bool
    var reviewChoice: ReviewChoice?
    var reviewNotes: String?
    var reviewedAt: Date?
    /// Bucket-relative key in incident-clips when the clip has been
    /// archived (NULL on the wire while archival is still in flight).
    /// iOS doesn't fetch the bytes through this key directly — it
    /// asks `/v1/events/{id}/clip-url` for a signed URL — but the
    /// field is decoded so the Codable round-trip is exhaustive
    /// and a future "preload thumbnails" flow can use it.
    var clipStorageKey: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case detectorId = "detector_id"
        case cameraId = "camera_id"
        case category
        case source
        case iconName = "icon_name"
        case title
        case location
        case occurredAt = "occurred_at"
        case hasClip = "has_clip"
        case narrative
        case opened
        case reviewed
        case reviewChoice = "review_choice"
        case reviewNotes = "review_notes"
        case reviewedAt = "reviewed_at"
        case clipStorageKey = "clip_storage_key"
        case createdAt = "created_at"
    }

    /// Human-readable time label for the event card / detail header.
    /// Same-day: "HH:mm". Yesterday: "Yesterday HH:mm". Older this
    /// week: "EEE HH:mm" (e.g. "Mon 16:42"). Beyond: "MMM d HH:mm".
    var time: String {
        let cal = Calendar.current
        let now = Date()
        let hm = DateFormatter()
        hm.locale = Locale(identifier: "en_US_POSIX")
        hm.dateFormat = "HH:mm"
        if cal.isDateInToday(occurredAt) {
            return hm.string(from: occurredAt)
        }
        if cal.isDateInYesterday(occurredAt) {
            return "Yesterday \(hm.string(from: occurredAt))"
        }
        let days = cal.dateComponents([.day], from: occurredAt, to: now).day ?? 0
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = days < 7 ? "EEE HH:mm" : "MMM d HH:mm"
        return f.string(from: occurredAt)
    }

    /// "42 min ago" / "2h ago" / "1d ago".
    var ago: String {
        let secs = Int(Date().timeIntervalSince(occurredAt))
        if secs < 60 { return "just now" }
        let mins = secs / 60
        if mins < 60 { return "\(mins) min ago" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}

/// Server-side filter for `GET /v1/patients/{id}/events?filter=`. Raw
/// values match the backend `EventFilter` enum.
enum EventFilter: String, CaseIterable, Sendable, Codable, Identifiable {
    case all
    case unreviewed
    case reviewed

    var id: String { rawValue }

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// Paged event list response.
struct EventListResponse: Sendable, Codable {
    var items: [DetectionEvent]
    var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

/// Body of `PATCH /v1/events/{id}`. Nil = field omitted. Backend stamps
/// `reviewed_at = now()` when `reviewed` flips false → true.
struct UpdateEventRequest: Encodable, Sendable {
    var opened: Bool?
    var reviewed: Bool?
    var reviewChoice: DetectionEvent.ReviewChoice?
    var reviewNotes: String?

    enum CodingKeys: String, CodingKey {
        case opened
        case reviewed
        case reviewChoice = "review_choice"
        case reviewNotes = "review_notes"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(opened, forKey: .opened)
        try c.encodeIfPresent(reviewed, forKey: .reviewed)
        try c.encodeIfPresent(reviewChoice, forKey: .reviewChoice)
        try c.encodeIfPresent(reviewNotes, forKey: .reviewNotes)
    }
}
