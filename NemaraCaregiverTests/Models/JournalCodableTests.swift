import XCTest
@testable import Nemara

/// The Daily Journal wire shape — one day, category sections, one
/// typed line per detector. Tolerant where the backend may grow.
final class JournalCodableTests: XCTestCase {

    private let decoder = NemaraJSON.decoder()

    private let sample = """
    {"date": "2026-08-15", "partial": false,
     "timezone": "America/Los_Angeles", "coverage_hours": 14,
     "sections": [
       {"category": "safety", "entries": [
         {"detector_id": "9c3f1c0a-0e1b-4b7b-9a3c-1d2e3f405060",
          "title": "Falls", "category": "safety", "severity": 95,
          "kind": "point",
          "line": {"primary": "No falls", "meta": "47 days", "status": "ok"},
          "strip": null, "review_event_id": null},
         {"detector_id": "9c3f1c0a-0e1b-4b7b-9a3c-1d2e3f405061",
          "title": "Front door", "category": "safety", "severity": 88,
          "kind": "point",
          "line": {"primary": "Front door", "meta": "2:14 AM · Living Room",
                   "status": "review"},
          "strip": {"axis": "midnight", "spans": [], "marks": [2.23],
                    "flag": null},
          "review_event_id": "0e1b4b7b-9a3c-4b7b-9a3c-1d2e3f405060"}]},
       {"category": "routine", "entries": [
         {"detector_id": null, "title": "Sleep", "category": "routine",
          "severity": null, "kind": "record_sleep",
          "line": {"primary": "10:42 PM – 6:47 AM", "meta": "2 wake-ups",
                   "status": "none"},
          "strip": {"axis": "noon", "spans": [[10.7, 18.78]], "marks": [],
                    "flag": null},
          "review_event_id": null}]}
     ]}
    """

    func test_decode_full_day() throws {
        let day = try decoder.decode(JournalDay.self,
                                     from: sample.data(using: .utf8)!)
        XCTAssertEqual(day.date, "2026-08-15")
        XCTAssertFalse(day.partial)
        XCTAssertEqual(day.coverageHours, 14)
        XCTAssertEqual(day.sections.count, 2)
        let falls = day.sections[0].entries[0]
        XCTAssertEqual(falls.line.status, .ok)
        XCTAssertNil(falls.strip)
        let door = day.sections[0].entries[1]
        XCTAssertEqual(door.line.status, .review)
        XCTAssertEqual(door.strip?.marks, [2.23])
        XCTAssertNotNil(door.reviewEventId)
        let sleep = day.sections[1].entries[0]
        XCTAssertEqual(sleep.strip?.axis, .noon)
        XCTAssertEqual(sleep.strip?.spans, [[10.7, 18.78]])
    }

    func test_unknown_status_and_axis_degrade() throws {
        let json = """
        {"date": "2026-08-15", "partial": true, "timezone": "UTC",
         "coverage_hours": 0,
         "sections": [{"category": "safety", "entries": [
           {"detector_id": null, "title": "X", "category": "safety",
            "severity": null, "kind": "hologram",
            "line": {"primary": "?", "meta": null, "status": "sparkly"},
            "strip": {"axis": "sideways", "spans": [], "marks": [],
                      "flag": null},
            "review_event_id": null}]}]}
        """
        let day = try decoder.decode(JournalDay.self,
                                     from: json.data(using: .utf8)!)
        let e = day.sections[0].entries[0]
        XCTAssertEqual(e.line.status, .none)
        XCTAssertEqual(e.strip?.axis, .midnight)
    }
}
