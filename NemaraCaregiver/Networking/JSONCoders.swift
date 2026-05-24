import Foundation

/// Shared JSON encoder + decoder configuration for the nemara-backend
/// wire. Used by `NemaraAPIClient` and by `NemaraCaregiverTests` so
/// round-trip tests exercise the same code path as live network calls.
///
/// Date handling: pydantic v2 emits `datetime` columns as ISO-8601 with
/// 6-digit microsecond precision (e.g. `"2026-05-21T22:18:00.182734+00:00"`)
/// and `date` columns as `"YYYY-MM-DD"`. Apple's `ISO8601DateFormatter`
/// only handles up to 3-digit (millisecond) fractional, so we use a set
/// of `DateFormatter`s and try each in order.
enum NemaraJSON {

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = parse(raw) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognized date string: \(raw)",
            ))
        }
        return d
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(microsecondISO8601.string(from: date))
        }
        return e
    }

    /// Format a Date as YYYY-MM-DD for fields the backend models as a
    /// Postgres DATE (not timestamptz). Required for `date_of_birth` —
    /// pydantic's date validator rejects ISO-8601 with time component.
    static func dateOnlyString(from date: Date) -> String {
        dateOnly.string(from: date)
    }

    // MARK: - Internals

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = format
        return f
    }

    // Round-trip encode target. 6-digit fractional matches pydantic's
    // default, so decode(encode(value)) is byte-for-byte stable.
    private static let microsecondISO8601 = formatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX")
    private static let millisecondISO8601 = formatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX")
    private static let plainISO8601       = formatter("yyyy-MM-dd'T'HH:mm:ssXXXXX")
    private static let dateOnly           = formatter("yyyy-MM-dd")

    private static func parse(_ raw: String) -> Date? {
        if let d = microsecondISO8601.date(from: raw) { return d }
        if let d = millisecondISO8601.date(from: raw) { return d }
        if let d = plainISO8601.date(from: raw) { return d }
        if let d = dateOnly.date(from: raw) { return d }
        return nil
    }
}
