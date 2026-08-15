import Charts
import SwiftUI

/// Shapes the loose widget-data envelope into chart-ready points.
enum WidgetDataShaper {

    struct SeriesPoint: Identifiable {
        let bucket: String
        let value: Double
        var id: String { bucket }
    }

    static func number(_ v: JSONValue?) -> Double {
        switch v {
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        default: return 0
        }
    }

    static func seriesPoints(
        _ data: NemaraAPIClient.WidgetData, term: String? = nil
    ) -> [SeriesPoint] {
        guard let rows = data.rows else { return [] }
        let key = term ?? data.terms?.first ?? "events"
        return rows.compactMap { row in
            guard case .string(let bucket)? = row["bucket"] else { return nil }
            return SeriesPoint(bucket: bucket, value: number(row[key]))
        }
    }

    /// "2026-08-13" → "13", for sparse daily x-axis labels.
    static func dayLabel(_ bucket: String) -> String {
        String(bucket.suffix(2))
    }

    /// "02:00" → 2. Hour buckets come back zero-padded 24h.
    static func hour(_ bucket: String) -> Int {
        Int(bucket.prefix(2)) ?? 0
    }

    /// Sparse x-axis labels for categorical (string) day buckets:
    /// `.automatic(desiredCount:)` does NOT thin string axes, it mashes
    /// every label together. Pick ~5, always including the ends.
    static func sparseLabels(_ points: [SeriesPoint]) -> [String] {
        guard points.count > 6 else { return points.map { dayLabel($0.bucket) } }
        let step = max(1, points.count / 4)
        var picks = Set(stride(from: 0, to: points.count, by: step))
        picks.insert(points.count - 1)
        return picks.sorted().map { dayLabel(points[$0].bucket) }
    }
}

// MARK: - Tiles

/// streak_tile / ratio_tile — the stat IS the widget; no plot.
struct StatTileView: View {
    let stat: String?
    let subtitle: String?
    let unavailable: String?
    let accent: Color

    /// The server subtitle is a full sentence ("days since the last
    /// Fall (Aug 13) · longest gap 61d") — too long for a half-width
    /// tile. Split on the separator and drop the parenthetical: unit
    /// line + a small second line.
    private var lines: [String] {
        (subtitle ?? "").components(separatedBy: " · ").map {
            $0.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "",
                                    options: .regularExpression)
        }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let stat {
                Text(stat)
                    .font(NemaraFont.largeTitle)
                    .foregroundStyle(NemaraColor.ink)
                    .monospacedDigit()
                if let unit = lines.first {
                    Text(unit)
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink2)
                        .lineLimit(2)
                }
                if lines.count > 1 {
                    Text(lines[1])
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .lineLimit(1)
                }
            } else {
                // daysSince with no events ever — the good outcome.
                Text("None yet")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink2)
                Text(unavailable ?? "Nothing recorded")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink3)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Bars over time (count_bars / duration_bars)

struct CountBarsView: View {
    let points: [WidgetDataShaper.SeriesPoint]
    let accent: Color

    private var average: Double {
        points.isEmpty ? 0 :
            points.map(\.value).reduce(0, +) / Double(points.count)
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                BarMark(
                    x: .value("Day", WidgetDataShaper.dayLabel(p.bucket)),
                    y: .value("Count", p.value),
                )
                .foregroundStyle(accent)
                .cornerRadius(3)
            }
            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(NemaraColor.ink3)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(average, format: .number.precision(.fractionLength(0...1)))")
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.ink3)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: WidgetDataShaper.sparseLabels(points)) {
                AxisValueLabel().font(NemaraFont.caption)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(NemaraColor.line)
                AxisValueLabel().font(NemaraFont.caption)
            }
        }
        .frame(height: 110)
    }
}

// MARK: - hour_clock

struct HourClockView: View {
    let points: [WidgetDataShaper.SeriesPoint]   // 24 hourly buckets
    /// Axis window from the detector's when_scope, e.g. ["22:00","06:00"].
    let domain: [String]?
    let accent: Color

    /// Hours in display order — the when_scope window (wrapping past
    /// midnight) when one exists, else the full day.
    private var hours: [Int] {
        guard let domain, domain.count == 2,
              let start = Int(domain[0].prefix(2)),
              let end = Int(domain[1].prefix(2)), start != end else {
            return Array(0..<24)
        }
        if start < end { return Array(start..<end) }
        return Array(start..<24) + Array(0..<end)
    }

    private func label(_ h: Int) -> String {
        let hr = h % 12 == 0 ? 12 : h % 12
        return "\(hr)\(h < 12 ? "a" : "p")"
    }

    var body: some View {
        let byHour = Dictionary(uniqueKeysWithValues: points.map {
            (WidgetDataShaper.hour($0.bucket), $0.value)
        })
        Chart(hours, id: \.self) { h in
            BarMark(
                x: .value("Hour", label(h)),
                y: .value("Events", byHour[h] ?? 0),
            )
            .foregroundStyle(accent)
            .cornerRadius(3)
        }
        .chartXScale(domain: hours.map(label))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) {
                AxisValueLabel().font(NemaraFont.caption)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(NemaraColor.line)
                AxisValueLabel().font(NemaraFont.caption)
            }
        }
        .frame(height: 100)
    }
}

// MARK: - dot_calendar

struct DotCalendarView: View {
    let points: [WidgetDataShaper.SeriesPoint]   // daily buckets, ascending
    /// Adherence inverts the read: these detectors fire on a MISSED
    /// deadline, so a day WITHOUT an event is the good (filled) dot.
    let adherence: Bool
    let accent: Color

    private func filled(_ value: Double) -> Bool {
        adherence ? value == 0 : value > 0
    }

    var body: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 6),
            count: min(max(points.count, 1), 14))
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(points) { p in
                Circle()
                    .fill(filled(p.value) ? accent : .clear)
                    .strokeBorder(
                        filled(p.value) ? .clear : NemaraColor.ink4,
                        lineWidth: 1.5)
                    .frame(height: 10)
                    .accessibilityLabel(
                        "\(p.bucket): \(filled(p.value) ? "yes" : "no")")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - trend_band

struct TrendBandView: View {
    let points: [WidgetDataShaper.SeriesPoint]
    let baseline: NemaraAPIClient.WidgetData.Baseline?
    let unit: String?
    let accent: Color

    var body: some View {
        Chart {
            if let baseline {
                ForEach(points) { p in
                    AreaMark(
                        x: .value("Day", WidgetDataShaper.dayLabel(p.bucket)),
                        yStart: .value("Low", baseline.lo),
                        yEnd: .value("High", baseline.hi),
                    )
                    .foregroundStyle(accent.opacity(0.14))
                }
            }
            ForEach(points) { p in
                LineMark(
                    x: .value("Day", WidgetDataShaper.dayLabel(p.bucket)),
                    y: .value("Value", p.value),
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(
                    x: .value("Day", WidgetDataShaper.dayLabel(last.bucket)),
                    y: .value("Value", last.value),
                )
                .foregroundStyle(accent)
                .annotation(position: .topTrailing) {
                    Text("\(Int(last.value))\(unit ?? "")")
                        .font(NemaraFont.captionStrong)
                        .foregroundStyle(NemaraColor.ink2)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: WidgetDataShaper.sparseLabels(points)) {
                AxisValueLabel().font(NemaraFont.caption)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(NemaraColor.line)
                AxisValueLabel().font(NemaraFont.caption)
            }
        }
        .frame(height: 120)
    }
}

// MARK: - sleep_bands

/// Apple-Health-style sleep chart: one column per night against a
/// clock axis (9 PM top → 9 AM bottom). Top of a bar is bedtime,
/// bottom is wake; disturbances render as ticks on the bar.
struct SleepBandsView: View {
    let nights: [NemaraAPIClient.SleepNight]
    let accent: Color

    /// Clock time → hours since 9 PM (0…12 window). Morning times
    /// (before noon) belong to the next day.
    private func offset(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        let sinceNine = (h < 12 ? h + 24 : h) - 21
        return min(max(sinceNine, 0), 12)
    }

    private func dayLetter(_ night: String) -> String {
        String(night.suffix(2))
    }

    var body: some View {
        Chart(nights, id: \.night) { n in
            if let bed = n.bedtime, let wake = n.wakeTime {
                BarMark(
                    x: .value("Night", dayLetter(n.night)),
                    // Inverted: y grows downward on the clock axis.
                    yStart: .value("Bed", 12 - offset(bed)),
                    yEnd: .value("Wake", 12 - offset(wake)),
                    width: .ratio(0.55),
                )
                .foregroundStyle(accent)
                .cornerRadius(6)
            }
        }
        .chartYScale(domain: 0...12)
        .chartYAxis {
            // 12-offset space: 9 (=12 AM), 5 (=4 AM), 1 (=8 AM).
            AxisMarks(values: [9.0, 5.0, 1.0]) { value in
                AxisGridLine().foregroundStyle(NemaraColor.line)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v == 9 ? "12 AM" : v == 5 ? "4 AM" : "8 AM")
                            .font(NemaraFont.caption)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisValueLabel().font(NemaraFont.caption)
            }
        }
        .frame(height: 140)
    }
}

// MARK: - week_heatmap

/// Day × time-of-day cells, single-hue opacity ramp. Rows are 4-hour
/// bands from noon to midnight (where sundowning lives); counts from
/// other hours fold into the nearest band edge.
struct WeekHeatmapView: View {
    let cells: [NemaraAPIClient.WidgetData.HeatCell]
    let dows: [String]
    let accent: Color

    private static let bands: [(label: String, range: Range<Int>)] = [
        ("12–4p", 12..<16), ("4–8p", 16..<20), ("8–12a", 20..<24),
    ]

    private func count(dow: Int, band: Range<Int>) -> Int {
        cells.filter { $0.dow == dow && band.contains($0.h) }
            .map(\.n).reduce(0, +)
    }

    private var maxCount: Int {
        max(Self.bands.flatMap { band in
            (1...7).map { count(dow: $0, band: band.range) }
        }.max() ?? 1, 1)
    }

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(Self.bands, id: \.label) { band in
                GridRow {
                    Text(band.label)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .frame(width: 44, alignment: .leading)
                    ForEach(1...7, id: \.self) { dow in
                        let n = count(dow: dow, band: band.range)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(accent.opacity(
                                n == 0 ? 0.08 : 0.25 + 0.75 * Double(n) / Double(maxCount)))
                            .frame(height: 22)
                            .accessibilityLabel("\(dows.indices.contains(dow - 1) ? dows[dow - 1] : "") \(band.label): \(n)")
                    }
                }
            }
            GridRow {
                Color.clear.frame(width: 44, height: 1)
                ForEach(1...7, id: \.self) { dow in
                    Text(dows.indices.contains(dow - 1) ? dows[dow - 1] : "")
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                }
            }
        }
    }
}

// MARK: - room_bars

struct RoomBarsView: View {
    let rows: [(room: String, count: Double)]
    let accent: Color

    var body: some View {
        Chart(rows, id: \.room) { r in
            BarMark(
                x: .value("Events", r.count),
                y: .value("Room", r.room),
            )
            .foregroundStyle(accent)
            .cornerRadius(3)
            .annotation(position: .trailing) {
                Text("\(Int(r.count))")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks {
                AxisValueLabel().font(NemaraFont.caption)
            }
        }
        .frame(height: CGFloat(max(rows.count, 1)) * 26 + 8)
    }
}
