import XCTest
@testable import Nemara

/// DashboardBuilder — the deterministic layout half of the Home tab.
/// The LLM/catalog decided each detector's widget at compile time;
/// this turns the live detector list into ordered sections. Rules
/// (design spec): fixed category order safety→routine→behaviour→care,
/// a category renders only when it has an active detector with a
/// renderable spec, severe-first inside a section, collecting face
/// until min_days of data exist.
final class DashboardBuilderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func det(
        _ name: String,
        category: Detector.Category = .safety,
        isOn: Bool = true,
        widget: String? = "streak_tile",
        minDays: Int = 1,
        severity: Int? = nil,
        ageDays: Double = 30
    ) -> Detector {
        Detector(
            id: UUID(), patientId: UUID(), name: name, iconName: "x",
            description: "", category: category, source: .preset,
            alertTrigger: .leading, isSustained: false,
            durationSeconds: nil, whereRooms: nil, whenScope: "ALWAYS",
            sensitivity: .standard, isOn: isOn, customPrompt: nil,
            identifier: nil, scheduleConfig: nil, episodeGapSeconds: nil,
            userCriteria: nil, refinements: nil, doorConfig: nil,
            accuracyCaveat: nil,
            dashboardWidget: widget.map {
                DashboardWidget(widget: $0, size: .tile, title: name,
                                params: ["metric": .string("events")],
                                captionFields: nil, ranges: nil,
                                minDays: minDays, compiler: "catalog",
                                compiledAt: nil)
            },
            severity: severity,
            createdAt: now.addingTimeInterval(-ageDays * 86_400),
            updatedAt: now
        )
    }

    func test_sections_keep_fixed_category_order() {
        let sections = DashboardBuilder.sections(
            from: [det("B", category: .behaviour), det("S", category: .safety)],
            now: now)
        XCTAssertEqual(sections.map(\.category), [.safety, .behaviour])
    }

    func test_empty_categories_do_not_render() {
        let sections = DashboardBuilder.sections(
            from: [det("S", category: .safety)], now: now)
        XCTAssertEqual(sections.count, 1)
    }

    func test_off_detectors_are_excluded() {
        let sections = DashboardBuilder.sections(
            from: [det("Off", isOn: false)], now: now)
        XCTAssertTrue(sections.isEmpty)
    }

    func test_detectors_without_spec_are_excluded() {
        let sections = DashboardBuilder.sections(
            from: [det("NoSpec", widget: nil)], now: now)
        XCTAssertTrue(sections.isEmpty)
    }

    func test_unknown_widget_types_are_skipped() {
        let sections = DashboardBuilder.sections(
            from: [det("Future", widget: "hologram")], now: now)
        XCTAssertTrue(sections.isEmpty)
    }

    func test_unknown_category_is_dropped() {
        let sections = DashboardBuilder.sections(
            from: [det("X", category: .unknown)], now: now)
        XCTAssertTrue(sections.isEmpty)
    }

    func test_severity_orders_within_section_then_created_at() {
        let older = det("Older", severity: 50, ageDays: 40)
        let newer = det("Newer", severity: 50, ageDays: 10)
        let severe = det("Severe", severity: 200, ageDays: 5)
        let sections = DashboardBuilder.sections(
            from: [newer, older, severe], now: now)
        XCTAssertEqual(sections[0].entries.map { $0.detector.name },
                       ["Severe", "Older", "Newer"])
    }

    func test_collecting_until_min_days_of_age() {
        let young = det("Young", minDays: 3, ageDays: 1)
        let ripe = det("Ripe", minDays: 3, ageDays: 5)
        let sections = DashboardBuilder.sections(from: [young, ripe], now: now)
        let byName = Dictionary(
            uniqueKeysWithValues: sections[0].entries.map {
                ($0.detector.name, $0.isCollecting)
            })
        XCTAssertEqual(byName["Young"], true)
        XCTAssertEqual(byName["Ripe"], false)
    }
}
