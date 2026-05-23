import XCTest
@testable import Nemara

final class DetectionEventCodableTests: XCTestCase {

    private let decoder = NemaraJSON.decoder()
    private let encoder = NemaraJSON.encoder()

    func test_decode_unreviewed_event_assigns_every_field() throws {
        let e = try decoder.decode(DetectionEvent.self, from: JSONFixtures.event.data(using: .utf8)!)
        XCTAssertEqual(e.id.uuidString.lowercased(), "ee110001-0000-4000-8000-000000000001")
        XCTAssertEqual(e.patientId.uuidString.lowercased(), "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb")
        XCTAssertNotNil(e.detectorId)
        XCTAssertNotNil(e.cameraId)
        XCTAssertEqual(e.category, .safety)
        XCTAssertEqual(e.source, .preset)
        XCTAssertEqual(e.title, "Possible fall")
        XCTAssertEqual(e.location, "Living room")
        XCTAssertTrue(e.hasClip)
        XCTAssertTrue(e.opened)
        XCTAssertFalse(e.reviewed)
        XCTAssertNil(e.reviewChoice)
        XCTAssertNil(e.reviewNotes)
        XCTAssertNil(e.reviewedAt)
        XCTAssertEqual(
            e.clipStorageKey,
            "events/ee110001-0000-4000-8000-000000000001.mp4",
        )
    }

    func test_decode_reviewed_event_with_clipless_routine() throws {
        let e = try decoder.decode(DetectionEvent.self, from: JSONFixtures.eventReviewed.data(using: .utf8)!)
        XCTAssertEqual(e.category, .routine)
        XCTAssertEqual(e.source, .custom)
        XCTAssertNil(e.detectorId)
        XCTAssertNil(e.cameraId)
        XCTAssertFalse(e.hasClip)
        XCTAssertTrue(e.reviewed)
        XCTAssertEqual(e.reviewChoice, .correct)
        XCTAssertEqual(e.reviewNotes, "Confirmed, watched the clip.")
        XCTAssertNotNil(e.reviewedAt)
        XCTAssertNil(e.clipStorageKey)
    }

    func test_round_trip_preserves_all_fields() throws {
        for fixture in [JSONFixtures.event, JSONFixtures.eventReviewed] {
            let original = try decoder.decode(DetectionEvent.self, from: fixture.data(using: .utf8)!)
            let reencoded = try encoder.encode(original)
            let decoded = try decoder.decode(DetectionEvent.self, from: reencoded)
            XCTAssertEqual(decoded, original)
        }
    }

    func test_event_list_decodes_items_and_cursor() throws {
        let list = try decoder.decode(EventListResponse.self, from: JSONFixtures.eventList.data(using: .utf8)!)
        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.nextCursor, "eyJvY2N1cnJlZF9hdCI6Mn0=")
    }

    func test_event_list_last_page_has_null_cursor() throws {
        let list = try decoder.decode(EventListResponse.self, from: JSONFixtures.eventListLastPage.data(using: .utf8)!)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertNil(list.nextCursor)
    }

    func test_event_filter_raw_values_match_backend_enum() {
        XCTAssertEqual(EventFilter.all.rawValue, "all")
        XCTAssertEqual(EventFilter.unreviewed.rawValue, "unreviewed")
        XCTAssertEqual(EventFilter.reviewed.rawValue, "reviewed")
        XCTAssertEqual(EventFilter.unreviewed.displayName, "Unreviewed")
    }

    func test_review_choice_raw_values_match_wire() {
        XCTAssertEqual(DetectionEvent.ReviewChoice.correct.rawValue, "correct")
        XCTAssertEqual(DetectionEvent.ReviewChoice.wrong.rawValue, "wrong")
        XCTAssertEqual(DetectionEvent.ReviewChoice.unsure.rawValue, "unsure")
    }

    func test_update_request_review_submission_encodes_all_set_fields() throws {
        let body = UpdateEventRequest(
            opened: true,
            reviewed: true,
            reviewChoice: .correct,
            reviewNotes: "Verified",
        )
        let json = try encoder.encode(body)
        let obj = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(obj["opened"] as? Bool, true)
        XCTAssertEqual(obj["reviewed"] as? Bool, true)
        XCTAssertEqual(obj["review_choice"] as? String, "correct")
        XCTAssertEqual(obj["review_notes"] as? String, "Verified")
    }

    func test_update_request_opened_only_omits_review_fields() throws {
        let body = UpdateEventRequest(opened: true)
        let json = try encoder.encode(body)
        let obj = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(obj.count, 1)
        XCTAssertEqual(obj["opened"] as? Bool, true)
        XCTAssertNil(obj["reviewed"])
        XCTAssertNil(obj["review_choice"])
        XCTAssertNil(obj["review_notes"])
    }
}
