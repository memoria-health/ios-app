import XCTest
@testable import Nemara

/// `dashboard_widget` — the compiled Home-tab widget spec riding on
/// DetectorResponse. Decode tolerance is the contract that matters: a
/// malformed or future-shaped spec must cost us the WIDGET, never the
/// detector row (same philosophy as the alert-trigger tolerant decode).
final class DashboardWidgetCodableTests: XCTestCase {

    private let decoder = NemaraJSON.decoder()

    private func detectorJSON(dashboardWidget: String?) -> String {
        let widgetLine = dashboardWidget.map { "\"dashboard_widget\": \($0)," } ?? ""
        return """
        {
          "id": "9C3F1C0A-0E1B-4B7B-9A3C-1D2E3F405060",
          "patient_id": "1B2C3D4E-5F60-4A1B-8C2D-3E4F50617283",
          "name": "Wandering",
          "icon_name": "door.left.hand.open",
          "description": "Main door opening.",
          "category": "safety",
          "source": "preset",
          "alert_trigger": "leading",
          "is_sustained": false,
          "when_scope": "10 PM - 6 AM",
          "sensitivity": "standard",
          "is_on": true,
          "identifier": "wandering",
          \(widgetLine)
          "created_at": "2026-08-15T10:00:00Z",
          "updated_at": "2026-08-15T10:00:00Z"
        }
        """
    }

    private let wanderingSpec = """
    {
      "widget": "hour_clock",
      "size": "wide",
      "title": "Night exits",
      "params": {
        "metric": "events",
        "detector": "9c3f1c0a-0e1b-4b7b-9a3c-1d2e3f405060",
        "byHour": true,
        "days": 14,
        "domain": ["22:00", "06:00"],
        "ratio": "nightsWith"
      },
      "caption_fields": ["ratio", "door"],
      "min_days": 3,
      "compiler": "catalog",
      "compiled_at": "2026-08-15T10:00:00.123456+00:00"
    }
    """

    func test_decode_full_spec() throws {
        let d = try decoder.decode(
            Detector.self,
            from: detectorJSON(dashboardWidget: wanderingSpec).data(using: .utf8)!)
        let w = try XCTUnwrap(d.dashboardWidget)
        XCTAssertEqual(w.widget, "hour_clock")
        XCTAssertEqual(w.size, .wide)
        XCTAssertEqual(w.title, "Night exits")
        XCTAssertEqual(w.minDays, 3)
        XCTAssertEqual(w.captionFields, ["ratio", "door"])
        XCTAssertEqual(w.params["metric"], .string("events"))
        XCTAssertEqual(w.params["byHour"], .bool(true))
        XCTAssertEqual(w.params["days"], .number(14))
        XCTAssertEqual(w.params["domain"],
                       .array([.string("22:00"), .string("06:00")]))
    }

    func test_absent_spec_is_nil() throws {
        let d = try decoder.decode(
            Detector.self,
            from: detectorJSON(dashboardWidget: nil).data(using: .utf8)!)
        XCTAssertNil(d.dashboardWidget)
    }

    func test_malformed_spec_costs_the_widget_not_the_detector() throws {
        let bad = #"{"widget": "hour_clock", "min_days": "three"}"#
        let d = try decoder.decode(
            Detector.self,
            from: detectorJSON(dashboardWidget: bad).data(using: .utf8)!)
        XCTAssertNil(d.dashboardWidget)
        XCTAssertEqual(d.identifier, "wandering")
    }

    func test_params_reencode_as_widget_data_source() throws {
        let d = try decoder.decode(
            Detector.self,
            from: detectorJSON(dashboardWidget: wanderingSpec).data(using: .utf8)!)
        let params = try XCTUnwrap(d.dashboardWidget?.params)
        let data = try JSONEncoder().encode(params)
        let round = try JSONDecoder().decode([String: JSONValue].self, from: data)
        XCTAssertEqual(round, params)
    }
}
