import SwiftUI

/// One dashboard card: chrome (title, range picker, caption) around
/// the chart the compiler picked for this detector. Two faces only —
/// chart, or the quiet collecting placeholder. Alerts live on the
/// roster and the Events tab, never here.
struct DashboardWidgetView: View {
    @Environment(AppEnvironment.self) private var env

    let entry: DashboardEntry

    @State private var data: NemaraAPIClient.WidgetData?
    @State private var nights: [NemaraAPIClient.SleepNight] = []
    @State private var failed = false
    @State private var range: String

    init(entry: DashboardEntry) {
        self.entry = entry
        // Seed the picker at the range matching the compiler's default
        // window: a naive `.first` would seed "D" and fetch one day of
        // data for a 30-day trend chart on first paint.
        let days = WidgetDataShaper.number(entry.spec.params["days"])
        let match: String? = switch days {
        case 1: "D"
        case 7: "W"
        case 30: "M"
        case 90: "3M"
        default: nil
        }
        let ranges = entry.spec.ranges ?? []
        _range = State(initialValue:
            match.flatMap { ranges.contains($0) ? $0 : nil }
            ?? ranges.first ?? "")
    }

    private var spec: DashboardWidget { entry.spec }
    private var accent: Color { entry.detector.category.accent }

    var body: some View {
        NemaraCard(tone: .default) {
            VStack(alignment: .leading, spacing: 8) {
                header
                if entry.isCollecting {
                    collectingFace
                } else {
                    chartFace
                }
            }
        }
        .task(id: range) { await load() }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(spec.title)
                .font(NemaraFont.bodySemibold)
                .foregroundStyle(NemaraColor.ink)
            Spacer(minLength: 0)
            if let ranges = spec.ranges, ranges.count > 1, !entry.isCollecting {
                rangePicker(ranges)
            }
        }
    }

    private func rangePicker(_ ranges: [String]) -> some View {
        HStack(spacing: 2) {
            ForEach(ranges, id: \.self) { r in
                Button {
                    range = r
                } label: {
                    Text(r)
                        .font(NemaraFont.captionStrong)
                        .foregroundStyle(range == r ? NemaraColor.ink : NemaraColor.ink3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            range == r ? NemaraColor.cardAlt : .clear,
                            in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var collectingFace: some View {
        Text("Watching \(spec.title.lowercased()). First look in \(spec.minDays) day\(spec.minDays == 1 ? "" : "s").")
            .font(NemaraFont.bodySmall)
            .foregroundStyle(NemaraColor.ink3)
            .padding(.vertical, 6)
    }

    // MARK: - Chart face

    @ViewBuilder
    private var chartFace: some View {
        if failed {
            Button {
                failed = false
                Task { await load() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Couldn't load. Tap to retry")
                }
                .font(NemaraFont.bodySemibold)
                .foregroundStyle(accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(accent.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
        } else {
            switch spec.widget {
            case "streak_tile":
                StatTileView(stat: data?.statValue,
                             subtitle: data?.subtitle,
                             unavailable: data?.unavailable, accent: accent,
                             noun: spec.title)
            case "ratio_tile", "delta_tile":
                StatTileView(stat: data?.statValue,
                             subtitle: data?.subtitle,
                             unavailable: data?.unavailable, accent: accent)
            case "hour_clock":
                HourClockView(points: shapedPoints, domain: domainParam,
                              accent: accent)
                caption(nightsCaption)
            case "dot_calendar":
                let adherence = stringParam("mode") == "adherence"
                DotCalendarView(points: shapedPoints, adherence: adherence,
                                accent: accent)
                caption(dotCaption(adherence: adherence))
            case "count_bars", "duration_bars":
                CountBarsView(points: shapedPoints, accent: accent)
            case "trend_band":
                TrendBandView(points: shapedPoints, baseline: data?.baseline,
                              unit: data?.unit, accent: accent)
            case "week_heatmap":
                WeekHeatmapView(cells: data?.cells ?? [],
                                dows: data?.dows ?? [], accent: accent)
                deltaCaption
            case "sleep_bands":
                SleepBandsView(nights: nights, accent: accent)
                sleepCaption
            case "room_bars":
                RoomBarsView(rows: roomRows, accent: accent)
            default:
                EmptyView()
            }
        }
    }

    /// "nights with a matching event (2 of 14)" → "2 of the last 14
    /// nights" — the server sentence, re-said like a person.
    private var nightsCaption: String? {
        guard let sub = data?.subtitle,
              let m = sub.firstMatch(of: /\((\d+) of (\d+)\)/) else {
            return data?.subtitle
        }
        let unit = sub.contains("nights") ? "nights" : "days"
        return "\(m.1) of the last \(m.2) \(unit)"
    }

    /// "11 of the last 14 days" / "12 of 14 doses on time" — computed
    /// from the rows so it can never disagree with the dots above it.
    private func dotCaption(adherence: Bool) -> String? {
        let points = shapedPoints
        guard !points.isEmpty else { return nil }
        let withEvent = points.filter { $0.value > 0 }.count
        if adherence {
            return "\(points.count - withEvent) of \(points.count) doses on time"
        }
        return "\(withEvent) of the last \(points.count) days"
    }

    private func caption(_ text: String?) -> some View {
        Group {
            if let text {
                Text(text)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
        }
    }

    /// week_heatmap: current-vs-prior totals from the merged response.
    @ViewBuilder
    private var deltaCaption: some View {
        if let stat = data?.statValue, let cur = Int(stat),
           case .number(let prev)? = data?.prevValue {
            let up = cur > Int(prev)
            let text = Int(prev) == 0
                ? "\(cur) this period, none the period before"
                : "\(up ? "▲" : cur < Int(prev) ? "▼" : "·") \(cur) this period · \(Int(prev)) before"
            // More of a behaviour episode is worse; fewer is better.
            Text(text)
                .font(NemaraFont.caption)
                .foregroundStyle(up ? NemaraColor.terra : NemaraColor.sage)
        }
    }

    @ViewBuilder
    private var sleepCaption: some View {
        if !nights.isEmpty {
            let durations = nights.compactMap(\.durationMinutes)
            let restless = nights.filter { $0.disturbances > 1 }.count
            if !durations.isEmpty {
                let avg = durations.reduce(0, +) / durations.count
                Text("Avg \(avg / 60) h \(avg % 60) m · \(restless) restless night\(restless == 1 ? "" : "s")")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
        }
    }

    // MARK: - Data

    private var shapedPoints: [WidgetDataShaper.SeriesPoint] {
        data.map { WidgetDataShaper.seriesPoints($0) } ?? []
    }

    private var roomRows: [(room: String, count: Double)] {
        (data?.rows ?? []).compactMap { row in
            guard case .string(let room)? = row["bucket"] else { return nil }
            return (room, WidgetDataShaper.number(row["events"]))
        }
    }

    private var domainParam: [String]? {
        guard case .array(let a)? = spec.params["domain"] else { return nil }
        return a.compactMap { if case .string(let s) = $0 { s } else { nil } }
    }

    private func stringParam(_ key: String) -> String? {
        if case .string(let s)? = spec.params[key] { s } else { nil }
    }

    /// The spec's params, with the range picker's window applied.
    private var effectiveSource: [String: JSONValue] {
        var source = spec.params
        if !range.isEmpty {
            let days: Double = switch range {
            case "D": 1
            case "W": 7
            case "M": 30
            case "3M": 90
            default: WidgetDataShaper.number(source["days"])
            }
            source["days"] = .number(days)
            if days >= 60 { source["granularity"] = .string("week") }
        }
        return source
    }

    private func load() async {
        guard !entry.isCollecting else { return }
        do {
            if spec.widget == "sleep_bands" {
                // Served by the dedicated summaries endpoint — this
                // widget type never calls widget-data.
                nights = try await env.api.sleepNights(
                    patientId: entry.detector.patientId,
                    days: range == "M" ? 30 : 7)
            } else {
                data = try await env.api.widgetData(source: effectiveSource)
            }
            failed = false
        } catch {
            if data == nil && nights.isEmpty { failed = true }
        }
    }
}
