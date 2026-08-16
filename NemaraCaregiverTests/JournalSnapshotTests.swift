import SwiftUI
import XCTest
@testable import Nemara

/// Renders a full journal day to PNG so presentation is verified by
/// eyes. Images land in /tmp/journal-snaps/.
@MainActor
final class JournalSnapshotTests: XCTestCase {

    private func entry(_ title: String, _ cat: Detector.Category,
                       kind: String, primary: String, meta: String?,
                       status: JournalLine.Status,
                       strip: JournalStrip? = nil,
                       review: Bool = false) -> JournalEntry {
        JournalEntry(
            detectorId: UUID(), title: title, category: cat, severity: nil,
            kind: kind,
            line: JournalLine(primary: primary, meta: meta, status: status),
            strip: strip, reviewEventId: review ? UUID() : nil)
    }

    func test_render_full_day() {
        let day = JournalDay(
            date: "2026-08-15", partial: false, timezone: "UTC",
            coverageHours: 14,
            sections: [
                JournalSection(category: .safety, entries: [
                    entry("Falls", .safety, kind: "point",
                          primary: "No falls", meta: "47 days", status: .ok),
                    entry("Front door", .safety, kind: "point",
                          primary: "Front door",
                          meta: "2:14 AM · Living Room", status: .review,
                          strip: JournalStrip(axis: .midnight, spans: [],
                                              marks: [2.23], flag: nil),
                          review: true),
                ]),
                JournalSection(category: .routine, entries: [
                    entry("Sleep", .routine, kind: "record_sleep",
                          primary: "10:42 PM – 6:47 AM", meta: "2 wake-ups",
                          status: .none,
                          strip: JournalStrip(axis: .noon,
                                              spans: [[10.7, 18.78]],
                                              marks: [], flag: nil)),
                    entry("Activity", .routine, kind: "record_activity",
                          primary: "About 3 h up and moving", meta: nil,
                          status: .none,
                          strip: JournalStrip(axis: .midnight,
                                              spans: [[7.5, 9.0], [11.0, 11.5],
                                                      [16.0, 17.0]],
                                              marks: [], flag: nil)),
                    entry("Medication", .routine, kind: "absence",
                          primary: "Done by 9 PM", meta: nil, status: .ok),
                    entry("Water", .routine, kind: "record_count",
                          primary: "6 times", meta: nil, status: .none,
                          strip: JournalStrip(axis: .midnight, spans: [],
                                              marks: [9.1, 10.5, 12.8, 14.2,
                                                      16.7, 18.3],
                                              flag: nil)),
                ]),
                JournalSection(category: .behaviour, entries: [
                    entry("Agitation", .behaviour, kind: "episode",
                          primary: "1 episode",
                          meta: "5:10 PM · Living Room", status: .none,
                          strip: JournalStrip(axis: .midnight, spans: [],
                                              marks: [17.17], flag: nil)),
                    entry("TV in the evening", .behaviour,
                          kind: "record_duration", primary: "About 1 h 40 m",
                          meta: nil, status: .none,
                          strip: JournalStrip(axis: .midnight,
                                              spans: [[22.3, 23.9]],
                                              marks: [], flag: nil)),
                ]),
                JournalSection(category: .care, entries: [
                    entry("Company at meals", .care, kind: "point",
                          primary: "Company at meals", meta: "1:20 PM · Kitchen",
                          status: .ok),
                ]),
            ])
        let view = JournalDayView(day: day, onReview: { _ in })
            .padding(14)
            .frame(width: 393)
            .background(NemaraColor.paper)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else {
            return XCTFail("render failed")
        }
        try? FileManager.default.createDirectory(
            atPath: "/tmp/journal-snaps", withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: "/tmp/journal-snaps/day.png"))
    }

    func test_render_empty_state() {
        let view = DashboardEmptyStateView(hasDetectors: true)
            .frame(width: 393)
            .background(NemaraColor.paper)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else {
            return XCTFail("render failed")
        }
        try? FileManager.default.createDirectory(
            atPath: "/tmp/journal-snaps", withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: "/tmp/journal-snaps/empty.png"))
    }
}
