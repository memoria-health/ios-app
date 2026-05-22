import XCTest
@testable import Nemara

final class DetectorCodableTests: XCTestCase {

    private let decoder = NemaraJSON.decoder()
    private let encoder = NemaraJSON.encoder()

    func test_decode_preset_detector_assigns_every_field() throws {
        let d = try decoder.decode(Detector.self, from: JSONFixtures.detectorPreset.data(using: .utf8)!)
        XCTAssertEqual(d.name, "Falls")
        XCTAssertEqual(d.iconName, "figure.fall")
        XCTAssertEqual(d.description, "Detects falls in any room.")
        XCTAssertEqual(d.category, .safety)
        XCTAssertEqual(d.source, .preset)
        XCTAssertEqual(d.shape, .pointInTime)
        XCTAssertEqual(d.whereScope, "ALL ROOMS")
        XCTAssertEqual(d.whenScope, "ALWAYS")
        XCTAssertEqual(d.sensitivity, .high)
        XCTAssertTrue(d.isOn)
        XCTAssertNil(d.customPrompt)
    }

    func test_decode_custom_detector_carries_prompt() throws {
        let d = try decoder.decode(Detector.self, from: JSONFixtures.detectorCustom.data(using: .utf8)!)
        XCTAssertEqual(d.source, .custom)
        XCTAssertEqual(d.shape, .state)
        XCTAssertEqual(d.customPrompt, "Confirm patient swallowed pills next to the dispenser.")
    }

    func test_enum_raw_values_match_wire() {
        XCTAssertEqual(Detector.Shape.pointInTime.rawValue, "point_in_time")
        XCTAssertEqual(Detector.Shape.state.rawValue, "state")
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
        XCTAssertEqual(Detector.Shape.pointInTime.displayName, "POINT-IN-TIME")
        XCTAssertEqual(Detector.Shape.state.displayName, "STATE")
        XCTAssertEqual(Detector.Sensitivity.low.displayName, "Low")
        XCTAssertEqual(Detector.Sensitivity.standard.displayName, "Standard")
    }

    func test_round_trip_preserves_all_fields() throws {
        for fixture in [JSONFixtures.detectorPreset, JSONFixtures.detectorCustom] {
            let original = try decoder.decode(Detector.self, from: fixture.data(using: .utf8)!)
            let reencoded = try encoder.encode(original)
            let decoded = try decoder.decode(Detector.self, from: reencoded)
            XCTAssertEqual(decoded, original)
        }
    }

    func test_create_request_encodes_all_fields_with_snake_case() throws {
        let body = CreateDetectorRequest(
            name: "Water leak",
            iconName: "drop.fill",
            description: "Detect water on the bathroom floor.",
            category: .safety,
            shape: .pointInTime,
            whereScope: "BATHROOM",
            whenScope: "ALWAYS",
            customPrompt: "Flag puddles larger than a hand.",
            sensitivity: .high,
        )
        let json = try encoder.encode(body)
        let obj = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(obj["name"] as? String, "Water leak")
        XCTAssertEqual(obj["icon_name"] as? String, "drop.fill")
        XCTAssertEqual(obj["description"] as? String, "Detect water on the bathroom floor.")
        XCTAssertEqual(obj["category"] as? String, "safety")
        XCTAssertEqual(obj["shape"] as? String, "point_in_time")
        XCTAssertEqual(obj["where_scope"] as? String, "BATHROOM")
        XCTAssertEqual(obj["when_scope"] as? String, "ALWAYS")
        XCTAssertEqual(obj["custom_prompt"] as? String, "Flag puddles larger than a hand.")
        XCTAssertEqual(obj["sensitivity"] as? String, "high")
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
