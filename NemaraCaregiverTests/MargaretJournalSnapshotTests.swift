import SwiftUI
import XCTest
@testable import Nemara

/// Renders REAL journal payloads (dumped from the local backend into
/// /tmp/margaret-days/*.json) through the production decoder + views.
/// Skips cleanly when no dumps exist, so CI never depends on them.
@MainActor
final class MargaretJournalSnapshotTests: XCTestCase {

    func test_render_dumped_days() throws {
        let dir = "/tmp/margaret-days"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir))?
            .filter { $0.hasSuffix(".json") }.sorted() ?? []
        try XCTSkipIf(files.isEmpty, "no dumped journal days")
        try? FileManager.default.createDirectory(
            atPath: "/tmp/journal-snaps", withIntermediateDirectories: true)

        for file in files {
            let data = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/\(file)"))
            let day = try NemaraJSON.decoder().decode(JournalDay.self, from: data)
            let view = VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 1) {
                    Text(day.partial ? "SO FAR TODAY" : "AUGUST DAY")
                        .font(NemaraFont.captionStrong)
                        .foregroundStyle(NemaraColor.ink3)
                        .kerning(1.2)
                    Text(day.date)
                        .font(NemaraFont.title2)
                        .foregroundStyle(NemaraColor.ink)
                }
                .frame(maxWidth: .infinity)
                JournalDayView(day: day, onReview: { _ in })
            }
            .padding(14)
            .frame(width: 393)
            .background(NemaraColor.paper)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let png = renderer.uiImage?.pngData() else {
                XCTFail("render failed: \(file)"); continue
            }
            let name = file.replacingOccurrences(of: ".json", with: "")
            try? png.write(to: URL(fileURLWithPath:
                "/tmp/journal-snaps/margaret-\(name).png"))
        }
    }
}
