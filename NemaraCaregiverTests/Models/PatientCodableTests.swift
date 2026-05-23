import XCTest
@testable import Nemara

final class PatientCodableTests: XCTestCase {

    private let decoder = NemaraJSON.decoder()
    private let encoder = NemaraJSON.encoder()

    func test_decode_full_patient_assigns_every_field() throws {
        let p = try decoder.decode(Patient.self, from: JSONFixtures.patient.data(using: .utf8)!)

        XCTAssertEqual(p.id.uuidString.lowercased(), "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb")
        XCTAssertEqual(p.caregiverId.uuidString.lowercased(), "a4f1c2d8-5c7e-4dab-9c2f-72e1f3b0aa01")
        XCTAssertEqual(p.fullName, "Margaret O'Brien")
        XCTAssertEqual(p.preferredName, "Maggie")
        XCTAssertEqual(p.gender, "Female")
        XCTAssertEqual(p.relation, .parent)
        XCTAssertEqual(p.homeAddress, "12 Cedar Ln, Berkeley CA")
        XCTAssertEqual(p.state, .critical)
        XCTAssertEqual(p.statusLine, "Possible fall, living room")
        XCTAssertEqual(p.batteryPercent, 78)
        XCTAssertFalse(p.camerasPaused)
        XCTAssertEqual(
            p.photoStorageKey,
            "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb.jpg",
        )
        XCTAssertNotNil(p.dateOfBirth)
        XCTAssertNotNil(p.lastEventAt)

        // Sanity-check the date-only parsing path.
        let cal = Calendar(identifier: .gregorian)
        let comp = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: p.dateOfBirth!)
        XCTAssertEqual(comp.year, 1944)
        XCTAssertEqual(comp.month, 5)
        XCTAssertEqual(comp.day, 12)
    }

    func test_decode_minimal_patient_with_nulls() throws {
        let p = try decoder.decode(Patient.self, from: JSONFixtures.patientMinimal.data(using: .utf8)!)
        XCTAssertNil(p.dateOfBirth)
        XCTAssertNil(p.gender)
        XCTAssertNil(p.homeAddress)
        XCTAssertNil(p.lastEventAt)
        XCTAssertNil(p.batteryPercent)
        XCTAssertNil(p.photoStorageKey)
        XCTAssertEqual(p.state, .calm)
        XCTAssertEqual(p.statusLine, "All quiet")
        XCTAssertEqual(p.age, 0, "age should be 0 when DOB is unknown")
    }

    func test_round_trip_preserves_all_fields() throws {
        let original = try decoder.decode(Patient.self, from: JSONFixtures.patient.data(using: .utf8)!)
        let reencoded = try encoder.encode(original)
        let decoded = try decoder.decode(Patient.self, from: reencoded)
        XCTAssertEqual(decoded, original)
    }

    func test_relation_enum_raw_values_match_wire() {
        XCTAssertEqual(Patient.Relation.parent.rawValue, "parent")
        XCTAssertEqual(Patient.Relation.spouse.rawValue, "spouse")
        XCTAssertEqual(Patient.Relation.grandparent.rawValue, "grandparent")
        XCTAssertEqual(Patient.Relation.sibling.rawValue, "sibling")
        XCTAssertEqual(Patient.Relation.client.rawValue, "client")
        XCTAssertEqual(Patient.Relation.other.rawValue, "other")
        XCTAssertEqual(Patient.Relation.parent.displayName, "Parent")
        XCTAssertEqual(Patient.Relation.grandparent.displayName, "Grandparent")
    }

    func test_update_request_omits_nil_fields() throws {
        let body = UpdatePatientRequest(fullName: "Margaret O'Brien", camerasPaused: true)
        let json = try encoder.encode(body)
        let obj = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(obj["full_name"] as? String, "Margaret O'Brien")
        XCTAssertEqual(obj["cameras_paused"] as? Bool, true)
        XCTAssertNil(obj["preferred_name"])
        XCTAssertNil(obj["relation"])
        XCTAssertNil(obj["home_address"])
        XCTAssertNil(obj["gender"])
        XCTAssertNil(obj["date_of_birth"])
    }
}
