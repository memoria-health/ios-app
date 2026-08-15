import XCTest
@testable import Nemara

/// Wire types the Home tab's widgets fetch with: the widget-data
/// envelope (shape varies by metric — rows are heterogeneous) and the
/// sleep/activity summary rows.
final class DashboardDataCodableTests: XCTestCase {

    private let decoder = NemaraJSON.decoder()

    func test_widget_data_series_rows() throws {
        let json = """
        {"kind": "series", "terms": ["events"],
         "rows": [{"bucket": "2026-08-01", "events": 2},
                  {"bucket": "2026-08-02", "events": 0}],
         "statValue": "2", "prevValue": 5,
         "baseline": {"avg": 3.1, "lo": 1.0, "hi": 5.2}}
        """
        let d = try decoder.decode(NemaraAPIClient.WidgetData.self,
                                   from: json.data(using: .utf8)!)
        XCTAssertEqual(d.rows?.count, 2)
        XCTAssertEqual(d.rows?[0]["events"], .number(2))
        XCTAssertEqual(d.statValue, "2")
        XCTAssertEqual(d.baseline?.avg, 3.1)
    }

    func test_widget_data_days_since_stat() throws {
        let json = """
        {"kind": "series", "rows": [], "statValue": "47",
         "subtitle": "days since the last Fall (Jun 29) · longest gap 61d"}
        """
        let d = try decoder.decode(NemaraAPIClient.WidgetData.self,
                                   from: json.data(using: .utf8)!)
        XCTAssertEqual(d.statValue, "47")
        XCTAssertNil(d.baseline)
    }

    func test_widget_data_heatmap_cells() throws {
        let json = """
        {"kind": "heatmap", "dows": ["Mon","Tue"],
         "cells": [{"dow": 1, "h": 17, "n": 3}], "statValue": "3"}
        """
        let d = try decoder.decode(NemaraAPIClient.WidgetData.self,
                                   from: json.data(using: .utf8)!)
        XCTAssertEqual(d.cells?.first?.h, 17)
        XCTAssertEqual(d.cells?.first?.n, 3)
    }

    func test_widget_data_unavailable_marker() throws {
        let json = """
        {"kind": "series", "rows": [], "statValue": null,
         "unavailable": "no matching events have ever been recorded"}
        """
        let d = try decoder.decode(NemaraAPIClient.WidgetData.self,
                                   from: json.data(using: .utf8)!)
        XCTAssertNil(d.statValue)
        XCTAssertNotNil(d.unavailable)
    }

    func test_sleep_nights_row() throws {
        let json = """
        {"nights": [{"night": "2026-08-13",
                     "bedtime": "2026-08-13T22:30:00+00:00",
                     "sleep_onset": "2026-08-13T22:41:00+00:00",
                     "wake_time": "2026-08-14T06:40:00+00:00",
                     "duration_minutes": 490, "disturbances": 2,
                     "out_of_bed_events": [{"start": "2026-08-14T02:00:00+00:00"}],
                     "flags": []}]}
        """
        let d = try decoder.decode(NemaraAPIClient.SleepNightsResponse.self,
                                   from: json.data(using: .utf8)!)
        let night = try XCTUnwrap(d.nights.first)
        XCTAssertEqual(night.night, "2026-08-13")
        XCTAssertEqual(night.durationMinutes, 490)
        XCTAssertEqual(night.disturbances, 2)
        XCTAssertNotNil(night.bedtime)
        XCTAssertNotNil(night.wakeTime)
        XCTAssertEqual(night.outOfBedEvents?.count, 1)
    }

    func test_activity_days_row() throws {
        let json = """
        {"days": [{"day": "2026-08-13", "active_fraction": 0.42,
                   "state_minutes": {"lying": 300}, "labeled_minutes": 700,
                   "room_transitions": 14}]}
        """
        let d = try decoder.decode(NemaraAPIClient.ActivityDaysResponse.self,
                                   from: json.data(using: .utf8)!)
        let day = try XCTUnwrap(d.days.first)
        XCTAssertEqual(day.day, "2026-08-13")
        XCTAssertEqual(day.activeFraction, 0.42)
        XCTAssertEqual(day.roomTransitions, 14)
    }
}
