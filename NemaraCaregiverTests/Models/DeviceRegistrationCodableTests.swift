import XCTest
@testable import Nemara

final class DeviceRegistrationCodableTests: XCTestCase {

    private let decoder = NemaraJSON.decoder()
    private let encoder = NemaraJSON.encoder()

    func test_register_request_encodes_snake_case_keys() throws {
        let req = RegisterDeviceRequest(
            apnsToken: "abc123",
            bundleId: "co.elephantlabs.nemara",
            environment: .sandbox,
        )
        let data = try encoder.encode(req)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(object["apns_token"] as? String, "abc123")
        XCTAssertEqual(object["bundle_id"] as? String, "co.elephantlabs.nemara")
        XCTAssertEqual(object["environment"] as? String, "sandbox")
        XCTAssertEqual(object.count, 3)
    }

    func test_register_request_environment_production_round_trips() throws {
        let req = RegisterDeviceRequest(
            apnsToken: "tok",
            bundleId: "co.elephantlabs.nemara",
            environment: .production,
        )
        let data = try encoder.encode(req)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(object["environment"] as? String, "production")
    }

    func test_decode_device_response_assigns_every_field() throws {
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "caregiver_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          "apns_token": "deadbeef",
          "bundle_id": "co.elephantlabs.nemara",
          "environment": "sandbox",
          "created_at": "2026-05-23T10:00:00.000000+00:00",
          "updated_at": "2026-05-23T10:05:30.000000+00:00"
        }
        """
        let data = json.data(using: .utf8)!
        let resp = try decoder.decode(DeviceResponse.self, from: data)
        XCTAssertEqual(resp.id.uuidString.lowercased(), "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(
            resp.caregiverId.uuidString.lowercased(),
            "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        )
        XCTAssertEqual(resp.apnsToken, "deadbeef")
        XCTAssertEqual(resp.bundleId, "co.elephantlabs.nemara")
        XCTAssertEqual(resp.environment, .sandbox)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comp = cal.dateComponents([.year, .month, .day, .hour, .minute], from: resp.createdAt)
        XCTAssertEqual(comp.year, 2026)
        XCTAssertEqual(comp.month, 5)
        XCTAssertEqual(comp.day, 23)
        XCTAssertEqual(comp.hour, 10)
        XCTAssertEqual(comp.minute, 0)
    }

    func test_apns_environment_decodes_only_known_strings() {
        XCTAssertEqual(APNsEnvironment(rawValue: "sandbox"), .sandbox)
        XCTAssertEqual(APNsEnvironment(rawValue: "production"), .production)
        XCTAssertNil(APNsEnvironment(rawValue: "neither"))
    }
}
