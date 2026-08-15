import Foundation

/// One rendered card on the patient Home tab.
struct DashboardEntry: Equatable, Identifiable {
    let detector: Detector
    let spec: DashboardWidget
    /// True until the detector is `minDays` old — the card shows its
    /// quiet "watching" face instead of an empty chart.
    let isCollecting: Bool

    var id: UUID { detector.id }
}

/// One category section — exists only when it has at least one entry.
struct DashboardSection: Equatable, Identifiable {
    let category: Detector.Category
    let entries: [DashboardEntry]

    var id: Detector.Category { category }
}

/// The deterministic layout half of the Home tab. The backend's
/// compiler decided each detector's widget once, at detector-write
/// time; this folds the live detector list into ordered sections.
/// No LLM, no persistence, no surprises: same input, same dashboard.
enum DashboardBuilder {

    /// Primitives this build knows how to draw. An unknown type from a
    /// newer backend is skipped, never a blank card.
    static let renderable: Set<String> = [
        "streak_tile", "dot_calendar", "hour_clock", "trend_band",
        "sleep_bands", "week_heatmap", "delta_tile", "duration_bars",
        "count_bars", "ratio_tile", "room_bars",
    ]

    /// Fixed section order — matches the category order everywhere
    /// else in the product. `.unknown` never renders.
    static let sectionOrder: [Detector.Category] = [
        .safety, .routine, .behaviour, .care,
    ]

    static func sections(
        from detectors: [Detector], now: Date = Date()
    ) -> [DashboardSection] {
        var byCategory: [Detector.Category: [DashboardEntry]] = [:]
        for d in detectors {
            guard d.isOn,
                  let spec = d.dashboardWidget,
                  renderable.contains(spec.widget) else { continue }
            let ageDays = now.timeIntervalSince(d.createdAt) / 86_400
            byCategory[d.category, default: []].append(DashboardEntry(
                detector: d, spec: spec,
                isCollecting: ageDays < Double(spec.minDays)))
        }
        return sectionOrder.compactMap { category in
            guard var entries = byCategory[category], !entries.isEmpty else {
                return nil
            }
            entries.sort { lhs, rhs in
                let ls = lhs.detector.severity ?? 0
                let rs = rhs.detector.severity ?? 0
                if ls != rs { return ls > rs }
                return lhs.detector.createdAt < rhs.detector.createdAt
            }
            return DashboardSection(category: category, entries: entries)
        }
    }
}
