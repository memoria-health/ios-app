import Foundation

/// One day of the Daily Journal — mirrors nemara-backend
/// `src/api/journal.py`. Every field the server computes; the client
/// only renders. Unknown enum values degrade instead of failing the
/// day (a newer backend must never blank the page).
struct JournalDay: Decodable, Equatable {
    var date: String
    var partial: Bool
    var timezone: String
    var coverageHours: Int
    var sections: [JournalSection]

    enum CodingKeys: String, CodingKey {
        case date, partial, timezone, sections
        case coverageHours = "coverage_hours"
    }
}

struct JournalSection: Decodable, Equatable, Identifiable {
    var category: Detector.Category
    var entries: [JournalEntry]

    var id: Detector.Category { category }
}

struct JournalEntry: Decodable, Equatable, Identifiable {
    var detectorId: UUID?
    var title: String
    /// SF Symbol name from the detector row (sleep/activity get fixed
    /// icons server-side). Pairs with the category tint on every row.
    var icon: String?
    var category: Detector.Category
    var severity: Int?
    var kind: String
    var line: JournalLine
    var strip: JournalStrip?
    var reviewEventId: UUID?

    /// Sections can hold entries without a detector id (sleep/activity
    /// summaries), so identity falls back to the title.
    var id: String { detectorId?.uuidString ?? title }

    enum CodingKeys: String, CodingKey {
        case title, icon, category, severity, kind, line, strip
        case detectorId = "detector_id"
        case reviewEventId = "review_event_id"
    }
}

struct JournalLine: Decodable, Equatable {
    enum Status: String, Decodable {
        case ok, review, none

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .none
        }
    }

    var primary: String
    var meta: String?
    var status: Status
}

struct JournalStrip: Decodable, Equatable {
    enum Axis: String, Decodable {
        case midnight, noon

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Axis(rawValue: raw) ?? .midnight
        }
    }

    var axis: Axis
    var spans: [[Double]]
    var marks: [Double]
    var flag: Double?
}
