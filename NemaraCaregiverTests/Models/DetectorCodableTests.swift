import XCTest
@testable import Nemara

final class DetectorCodableTests: XCTestCase {

    private let decoder = NemaraJSON.decoder()
    private let encoder = NemaraJSON.encoder()

    private func decode(_ json: String) throws -> Detector {
        try decoder.decode(Detector.self, from: json.data(using: .utf8)!)
    }

    // MARK: - Decoding

    func test_decode_preset_detector_assigns_every_field() throws {
        let d = try decode(JSONFixtures.detectorPreset)
        XCTAssertEqual(d.name, "Falls")
        XCTAssertEqual(d.iconName, "figure.fall")
        XCTAssertEqual(d.description, "Detects falls in any room.")
        XCTAssertEqual(d.category, .safety)
        XCTAssertEqual(d.source, .preset)
        XCTAssertEqual(d.alertTrigger, .leading)
        XCTAssertFalse(d.isSustained)
        XCTAssertNil(d.durationSeconds)
        XCTAssertNil(d.whereRooms)
        XCTAssertEqual(d.whenScope, "ALWAYS")
        XCTAssertEqual(d.sensitivity, .high)
        XCTAssertTrue(d.isOn)
        XCTAssertNil(d.customPrompt)
        XCTAssertEqual(d.identifier, "fall")
        XCTAssertFalse(d.showsAccuracyCaveat)
    }

    func test_decode_custom_detector_carries_sustained_shape() throws {
        let d = try decode(JSONFixtures.detectorCustom)
        XCTAssertEqual(d.source, .custom)
        XCTAssertEqual(d.alertTrigger, .duration)
        XCTAssertTrue(d.isSustained)
        XCTAssertEqual(d.durationSeconds, 900)
        XCTAssertEqual(d.episodeGapSeconds, 300)
        XCTAssertEqual(d.whereRooms, ["KITCHEN", "DINING ROOM"])
        XCTAssertEqual(d.identifier, "custom_a1b2c3d4")
        XCTAssertTrue(d.showsAccuracyCaveat)
        XCTAssertEqual(d.customPrompt, "Confirm patient swallowed pills next to the dispenser.")
    }

    /// The tolerant decoder's reason for existing: an older backend omits
    /// the alert-trigger columns entirely. Absent must mean "leading /
    /// not sustained", NOT a thrown `keyNotFound` — that error surfaces to
    /// the caregiver as "Couldn't read the response" and blocks sign-in.
    func test_decode_tolerates_backend_without_alert_columns() throws {
        let d = try decode(JSONFixtures.detectorLegacyBackend)
        XCTAssertEqual(d.name, "Wandering")
        XCTAssertEqual(d.alertTrigger, .leading)
        XCTAssertFalse(d.isSustained)
        XCTAssertNil(d.durationSeconds)
        XCTAssertNil(d.whereRooms)
        XCTAssertNil(d.identifier)
        XCTAssertNil(d.doorConfig)
        XCTAssertFalse(d.showsAccuracyCaveat)
    }

    /// Regression guard. `where_scope` was dropped from the API on
    /// 2026-07-28 and no backend sends it any more. A merge briefly
    /// restored a hard `decode(String.self, forKey: .whereScope)` here,
    /// which would have thrown on EVERY detector. No fixture carries the
    /// key; decoding must not depend on it.
    func test_decode_succeeds_when_where_scope_is_absent() throws {
        for fixture in [
            JSONFixtures.detectorPreset,
            JSONFixtures.detectorCustom,
            JSONFixtures.detectorLegacyBackend,
        ] {
            XCTAssertFalse(fixture.contains("where_scope"), "fixture should not carry the retired key")
            XCTAssertNoThrow(try decode(fixture))
        }
    }

    // MARK: - Wire contract

    func test_alert_trigger_raw_values_match_wire() {
        XCTAssertEqual(Detector.AlertTrigger.leading.rawValue, "leading")
        XCTAssertEqual(Detector.AlertTrigger.trailing.rawValue, "trailing")
        XCTAssertEqual(Detector.AlertTrigger.duration.rawValue, "duration")
        XCTAssertEqual(Detector.AlertTrigger.absence.rawValue, "absence")
        XCTAssertEqual(Detector.AlertTrigger.recordOnly.rawValue, "record_only")
    }

    func test_enum_raw_values_match_wire() {
        XCTAssertEqual(Detector.Sensitivity.low.rawValue, "low")
        XCTAssertEqual(Detector.Sensitivity.standard.rawValue, "standard")
        XCTAssertEqual(Detector.Sensitivity.high.rawValue, "high")
        XCTAssertEqual(Detector.Sensitivity.off.rawValue, "off")
        XCTAssertEqual(Detector.Category.safety.rawValue, "safety")
        XCTAssertEqual(Detector.Category.routine.rawValue, "routine")
        XCTAssertEqual(Detector.Source.preset.rawValue, "preset")
        XCTAssertEqual(Detector.Source.custom.rawValue, "custom")
    }

    func test_display_names_render_in_expected_case() {
        XCTAssertEqual(Detector.Sensitivity.low.displayName, "Low")
        XCTAssertEqual(Detector.Sensitivity.standard.displayName, "Standard")
        XCTAssertEqual(Detector.AlertTrigger.leading.caregiverLabel, "Alerts the moment it happens")
        XCTAssertEqual(Detector.AlertTrigger.recordOnly.caregiverShort, "Tracked quietly")
    }

    // MARK: - Room scope

    /// `whereRooms` is the only room-scope truth. Nil, empty, and an
    /// explicit "ALL ROOMS" all mean every room.
    func test_rooms_label_treats_nil_empty_and_all_rooms_alike() throws {
        var d = try decode(JSONFixtures.detectorPreset)
        XCTAssertEqual(d.roomsLabel, "All rooms")
        d.whereRooms = []
        XCTAssertEqual(d.roomsLabel, "All rooms")
        d.whereRooms = ["ALL ROOMS"]
        XCTAssertEqual(d.roomsLabel, "All rooms")
        d.whereRooms = ["all rooms"]
        XCTAssertEqual(d.roomsLabel, "All rooms", "match is case-insensitive")
    }

    func test_rooms_label_joins_a_multi_room_scope() throws {
        let d = try decode(JSONFixtures.detectorCustom)
        XCTAssertEqual(d.roomsLabel, "KITCHEN, DINING ROOM")
    }

    // MARK: - Round trip

    func test_round_trip_preserves_all_fields() throws {
        for fixture in [
            JSONFixtures.detectorPreset,
            JSONFixtures.detectorCustom,
            JSONFixtures.detectorLegacyBackend,
        ] {
            let original = try decode(fixture)
            let reencoded = try encoder.encode(original)
            let decoded = try decoder.decode(Detector.self, from: reencoded)
            XCTAssertEqual(decoded, original)
        }
    }

    // MARK: - Request bodies

    func test_create_request_encodes_all_fields_with_snake_case() throws {
        let body = CreateDetectorRequest(
            name: "Water leak",
            customPrompt: "Flag puddles larger than a hand.",
            description: "Detect water on the bathroom floor.",
            category: .safety,
            alertTrigger: .duration,
            isSustained: true,
            durationSeconds: 600,
            iconName: "drop.fill",
            whereRooms: ["BATHROOM"],
            whenScope: "ALWAYS",
            sensitivity: .high,
        )
        let json = try encoder.encode(body)
        let obj = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(obj["name"] as? String, "Water leak")
        XCTAssertEqual(obj["icon_name"] as? String, "drop.fill")
        XCTAssertEqual(obj["description"] as? String, "Detect water on the bathroom floor.")
        XCTAssertEqual(obj["category"] as? String, "safety")
        XCTAssertEqual(obj["alert_trigger"] as? String, "duration")
        XCTAssertEqual(obj["is_sustained"] as? Bool, true)
        XCTAssertEqual(obj["duration_seconds"] as? Int, 600)
        XCTAssertEqual(obj["where_rooms"] as? [String], ["BATHROOM"])
        XCTAssertEqual(obj["when_scope"] as? String, "ALWAYS")
        XCTAssertEqual(obj["custom_prompt"] as? String, "Flag puddles larger than a hand.")
        XCTAssertEqual(obj["sensitivity"] as? String, "high")
    }

    /// The backend's create endpoint rejects unknown fields, so encoding
    /// the retired `where_scope` 422'd every custom-detector create from
    /// iOS. It must never reappear in the body.
    func test_create_request_never_encodes_retired_where_scope() throws {
        let body = CreateDetectorRequest(name: "Anything", customPrompt: "Any prompt.")
        let json = try encoder.encode(body)
        let obj = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertNil(obj["where_scope"])
    }

    func test_update_request_omits_nil_fields() throws {
        let body = UpdateDetectorRequest(sensitivity: .standard, isOn: false)
        let json = try encoder.encode(body)
        let obj = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(obj["sensitivity"] as? String, "standard")
        XCTAssertEqual(obj["is_on"] as? Bool, false)
        XCTAssertEqual(obj.count, 2, "only the two set fields should be encoded")
    }
}
