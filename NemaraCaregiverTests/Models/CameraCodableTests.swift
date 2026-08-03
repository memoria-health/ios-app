import XCTest
@testable import Nemara

final class CameraCodableTests: XCTestCase {

    private let decoder = NemaraJSON.decoder()
    private let encoder = NemaraJSON.encoder()

    func test_decode_online_camera_assigns_every_field() throws {
        let cam = try decoder.decode(Camera.self, from: JSONFixtures.camera.data(using: .utf8)!)
        XCTAssertEqual(cam.id.uuidString.lowercased(), "ce110001-0000-4000-8000-000000000001")
        XCTAssertEqual(cam.patientId.uuidString.lowercased(), "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb")
        XCTAssertEqual(cam.displayId, 1)
        XCTAssertEqual(cam.room, "Living room")
        XCTAssertEqual(cam.iconName, "tv")
        XCTAssertTrue(cam.online)
        XCTAssertEqual(cam.livekitIdentity, "cam_ce110001")
        XCTAssertFalse(cam.disabled)
        XCTAssertFalse(cam.aiPaused)
        XCTAssertEqual(cam.desiredState, .connected)
        XCTAssertTrue(cam.paired)
    }

    func test_decode_offline_camera_is_unpaired_with_no_identity() throws {
        let cam = try decoder.decode(Camera.self, from: JSONFixtures.cameraOffline.data(using: .utf8)!)
        XCTAssertFalse(cam.online)
        XCTAssertFalse(cam.paired)
        XCTAssertNil(cam.livekitIdentity)
        XCTAssertEqual(cam.desiredState, .disconnected)
        XCTAssertEqual(cam.displayId, 2)
    }

    func test_round_trip_preserves_all_fields() throws {
        let original = try decoder.decode(Camera.self, from: JSONFixtures.camera.data(using: .utf8)!)
        let reencoded = try encoder.encode(original)
        let decoded = try decoder.decode(Camera.self, from: reencoded)
        XCTAssertEqual(decoded, original)
    }
}
