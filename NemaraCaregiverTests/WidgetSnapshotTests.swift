import SwiftUI
import XCTest
@testable import Nemara

/// Renders every Home-tab widget to PNG at true card widths so
/// presentation is verified by EYES, not inference. Images land in
/// /tmp/widget-snaps/ on the host.
@MainActor
final class WidgetSnapshotTests: XCTestCase {

    private let dir = "/tmp/widget-snaps"

    private func snap<V: View>(_ view: V, width: CGFloat, _ name: String) {
        let card = view
            .padding(14)
            .background(NemaraColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(8)
            .frame(width: width)
            .background(NemaraColor.paper)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else {
            return XCTFail("render failed: \(name)")
        }
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    private func days(_ n: Int, _ f: (Int) -> Double) -> [WidgetDataShaper.SeriesPoint] {
        (0..<n).map { i in
            .init(bucket: String(format: "2026-08-%02d", i + 1), value: f(i))
        }
    }

    func test_render_all_widgets() {
        snap(StatTileView(
            stat: "47",
            subtitle: "days since the last Fall (Jun 29) · longest gap 61d",
            unavailable: nil, accent: NemaraColor.terra,
            noun: "Falls"), width: 186, "1-streak")

        snap(StatTileView(
            stat: nil, subtitle: nil,
            unavailable: "no matching events have ever been recorded",
            accent: NemaraColor.terra), width: 186, "2-streak-none")

        snap(HourClockView(
            points: [.init(bucket: "23:00", value: 1),
                     .init(bucket: "02:00", value: 2),
                     .init(bucket: "03:00", value: 1)],
            domain: ["22:00", "06:00"], accent: NemaraColor.terra),
            width: 384, "3-hourclock")

        snap(DotCalendarView(
            points: days(14) { [0, 3, 7].contains($0) ? 0 : 1 },
            adherence: false, accent: NemaraColor.sky), width: 384, "4-dots")

        snap(DotCalendarView(
            points: days(14) { [4, 9].contains($0) ? 1 : 0 },
            adherence: true, accent: NemaraColor.sky), width: 384, "5-dots-adherence")

        snap(TrendBandView(
            points: days(30) { i in 40 + 12 * sin(Double(i) / 4) - (i > 24 ? 14 : 0) },
            baseline: .init(avg: 42, lo: 33, hi: 51), unit: "%",
            accent: NemaraColor.sky), width: 384, "6-trend")

        snap(SleepBandsView(
            nights: (1...7).map { d in
                let bed = Calendar.current.date(
                    from: DateComponents(year: 2026, month: 8, day: d,
                                         hour: 22, minute: 20 + d * 4))!
                return NemaraAPIClient.SleepNight(
                    night: String(format: "2026-08-%02d", d),
                    bedtime: bed, sleepOnset: bed.addingTimeInterval(720),
                    wakeTime: bed.addingTimeInterval(Double(27_000 + d * 600)),
                    durationMinutes: 470 + d * 8,
                    disturbances: d == 3 || d == 6 ? 3 : 1,
                    outOfBedEvents: nil)
            }, accent: NemaraColor.sky), width: 384, "7-sleep")

        snap(WeekHeatmapView(
            cells: [.init(dow: 4, h: 17, n: 2), .init(dow: 5, h: 18, n: 3),
                    .init(dow: 6, h: 17, n: 1), .init(dow: 2, h: 13, n: 1)],
            dows: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
            accent: NemaraColor.plum), width: 384, "8-heatmap")

        snap(CountBarsView(
            points: days(7) { Double([12, 0, 35, 8, 22, 85, 40][$0]) },
            accent: NemaraColor.plum), width: 384, "9-bars")

        snap(RoomBarsView(
            rows: [("Kitchen", 6), ("Living Room", 3), ("Bedroom", 1)],
            accent: NemaraColor.terra), width: 384, "10-rooms")

        snap(DashboardEmptyStateView(hasDetectors: true),
             width: 393, "11-empty")
    }
}
