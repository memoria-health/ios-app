import XCTest
@testable import Nemara

final class CaregiverCodableTests: XCTestCase {

    private let decoder = NemaraJSON.decoder()
    private let encoder = NemaraJSON.encoder()

    func test_decode_caregiver_with_phone_assigns_every_field() throws {
        let data = JSONFixtures.caregiver.data(using: .utf8)!
        let c = try decoder.decode(Caregiver.self, from: data)

        XCTAssertEqual(c.id.uuidString.lowercased(), "a4f1c2d8-5c7e-4dab-9c2f-72e1f3b0aa01")
        XCTAssertEqual(c.displayName, "Jane Patel")
        XCTAssertEqual(c.email, "jane@patel.co")
        XCTAssertEqual(c.phone, "+14155550123")

        // Spot-check the timestamp at the calendar level rather than the
        // epoch level — DateFormatter "SSSSSS" rounds to milliseconds on
        // some Apple platforms, so an epoch-second equality check is too
        // strict. Year/month/day/hour/minute is what users actually see.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comp = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: c.createdAt,
        )
        XCTAssertEqual(comp.year, 2026)
        XCTAssertEqual(comp.month, 5)
        XCTAssertEqual(comp.day, 1)
        XCTAssertEqual(comp.hour, 14)
        XCTAssertEqual(comp.minute, 23)
        XCTAssertEqual(comp.second, 11)
    }

    func test_decode_caregiver_handles_null_phone() throws {
        let data = JSONFixtures.caregiverNoPhone.data(using: .utf8)!
        let c = try decoder.decode(Caregiver.self, from: data)
        XCTAssertNil(c.phone)
        XCTAssertEqual(c.displayName, "Aaron Lee")
    }

    func test_round_trip_preserves_all_fields() throws {
        let original = try decoder.decode(Caregiver.self, from: JSONFixtures.caregiver.data(using: .utf8)!)
        let reencoded = try encoder.encode(original)
        let decoded = try decoder.decode(Caregiver.self, from: reencoded)
        XCTAssertEqual(decoded, original)
    }

    func test_update_request_omits_nil_fields() throws {
        let body = UpdateCaregiverRequest(displayName: "Jane P.", phone: nil)
        let json = try encoder.encode(body)
        let object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(object["display_name"] as? String, "Jane P.")
        XCTAssertNil(object["phone"], "nil phone should be omitted, not encoded as null")
    }

    func test_create_request_encodes_display_name_snake_case() throws {
        let body = CreateCaregiverRequest(displayName: "Jane Patel", phone: "+14155550123")
        let json = try encoder.encode(body)
        let object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(object["display_name"] as? String, "Jane Patel")
        XCTAssertEqual(object["phone"] as? String, "+14155550123")
    }
}
