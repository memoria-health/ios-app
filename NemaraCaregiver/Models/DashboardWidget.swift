import Foundation

/// The compiled Home-tab widget spec for one detector — written by the
/// backend's widget compiler on detector writes, rendered as-is by the
/// patient Home tab. Mirrors `detectors.dashboard_widget` (jsonb); see
/// nemara-backend `src/services/dashboard/widget_compiler.py`.
///
/// `widget` stays a raw string on purpose: an unknown primitive from a
/// newer backend decodes fine and is simply skipped by the renderer,
/// so a backend ship never blanks the whole detector row.
struct DashboardWidget: Codable, Hashable, Sendable {

    enum Size: String, Codable, Sendable {
        case tile, wide
    }

    var widget: String
    var size: Size
    var title: String
    /// The `/v1/insights/widget-data` source this widget fetches with,
    /// verbatim (metric, detector id, days, domain, …).
    var params: [String: JSONValue]
    /// Typed caption slots the card renders — never free text.
    var captionFields: [String]?
    /// Apple-Health-style range picker values (ranged widgets only).
    var ranges: [String]?
    /// Days of data required before the chart face replaces the
    /// collecting face.
    var minDays: Int
    var compiler: String?
    /// ISO timestamp string; display never needs it as a Date.
    var compiledAt: String?

    enum CodingKeys: String, CodingKey {
        case widget, size, title, params, ranges, compiler
        case captionFields = "caption_fields"
        case minDays = "min_days"
        case compiledAt = "compiled_at"
    }
}

/// Minimal JSON value tree — lets widget params carry heterogeneous
/// values (strings, numbers, bools, arrays, nested dicts) and re-encode
/// verbatim into the widget-data request body.
indirect enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported JSON value"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
}
