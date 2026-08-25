import SwiftUI

/// Last night's sleep, at the top of Home.
///
/// Sleep fires no events, so it never appears in the alert stream and a
/// caregiver had no way to see it except a line buried in the day
/// journal. This is its own surface: the hours, the shape of the night,
/// and how it compares to the last two weeks.
///
/// The band is the night drawn to scale, broken where the person was
/// awake. It is the one part worth looking at from across a room — a
/// solid bar is a good night and a shredded one is not, without reading
/// a single number.
struct SleepCard: View {
    let night: SleepNight
    /// Recent complete nights, used only for the comparison line.
    let history: [SleepNight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if night.isComplete {
                SleepBand(night: night)
                clockRow
                if let line = comparison {
                    Text(line)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink2)
                }
            } else {
                Text(night.incompleteReason ?? "No sleep recorded")
                    .font(NemaraFont.body)
                    .foregroundStyle(NemaraColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NemaraColor.card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NemaraColor.ink2)
            Text("Last night")
                .font(NemaraFont.bodySemibold)
                .foregroundStyle(NemaraColor.ink)
            Spacer(minLength: 8)
            if let d = night.durationText {
                Text(d)
                    .font(NemaraFont.bodyLarge)
                    .foregroundStyle(NemaraColor.ink)
            }
        }
    }

    // MARK: - Times

    private var clockRow: some View {
        HStack(spacing: 0) {
            stat("Asleep", Self.clock(night.sleepOnset))
            Spacer(minLength: 0)
            stat("Woke", Self.clock(night.wakeTime))
            Spacer(minLength: 0)
            // Windows, not a bare count, is what the summariser stores —
            // but the count is the glanceable form and the windows are a
            // tap away in the journal.
            stat("Wake-ups", night.disturbances == 0
                 ? "None" : "\(night.disturbances)")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink2)
            Text(value)
                .font(NemaraFont.bodySemibold)
                .foregroundStyle(NemaraColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Comparison

    /// "1h 5m more than usual", against the median of recent COMPLETE
    /// nights. Median, not mean: one 14-hour night after an illness
    /// would drag a mean for a fortnight. Needs at least three nights,
    /// because "usual" from one night is not a usual.
    private var comparison: String? {
        let past = history
            .filter { $0.night != night.night && $0.isComplete }
            .compactMap(\.durationMinutes)
            .sorted()
        guard past.count >= 3, let mine = night.durationMinutes else { return nil }
        let median = past[past.count / 2]
        let delta = mine - median
        if abs(delta) < 20 { return "About the same as usual" }
        let mag = abs(delta) < 60 ? "\(abs(delta))m"
            : "\(abs(delta) / 60)h \(abs(delta) % 60)m"
        return delta > 0 ? "\(mag) more than usual" : "\(mag) less than usual"
    }

    static func clock(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}

/// The night drawn to scale: one bar from falling asleep to waking,
/// with a gap cut out of it for every wake-up.
///
/// Geometry mirrors `journal/day.py:_sleep_spans` on the backend, which
/// already splits the night band the same way for the journal row. Same
/// shape, bigger, and at the top of the page instead of inside a list.
private struct SleepBand: View {
    let night: SleepNight

    private var bounds: (start: Date, end: Date)? {
        guard let a = night.sleepOnset, let b = night.wakeTime,
              b > a else { return nil }
        return (a, b)
    }

    var body: some View {
        GeometryReader { geo in
            if let (start, end) = bounds {
                let total = end.timeIntervalSince(start)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NemaraColor.ink.opacity(0.10))
                    ForEach(Array(segments(start, end).enumerated()), id: \.offset) { _, seg in
                        Capsule()
                            .fill(NemaraColor.plum)
                            .frame(width: max(2, geo.size.width * seg.width))
                            .offset(x: geo.size.width * seg.start)
                    }
                }
                .frame(height: 10)
                .accessibilityLabel(
                    "Asleep \(SleepCard.clock(start)) to \(SleepCard.clock(end)), "
                    + (night.disturbances == 0 ? "no wake-ups"
                       : "\(night.disturbances) wake-ups"))
                .accessibilityHidden(total <= 0)
            }
        }
        .frame(height: 10)
    }

    /// Asleep stretches as fractions of the whole night, i.e. the band
    /// minus each wake-up window. A window that cannot be parsed is
    /// skipped rather than guessed at — a fabricated gap would be a
    /// wake-up that never happened.
    private func segments(_ start: Date, _ end: Date) -> [(start: Double, width: Double)] {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return [] }
        let gaps: [(Double, Double)] = night.outOfBedEvents.compactMap { w in
            guard let wEnd = w.end else { return nil }
            let a = w.start.timeIntervalSince(start) / total
            let b = wEnd.timeIntervalSince(start) / total
            guard b > 0, a < 1, b > a else { return nil }
            return (max(0, a), min(1, b))
        }.sorted { $0.0 < $1.0 }

        var out: [(start: Double, width: Double)] = []
        var cursor = 0.0
        for (a, b) in gaps {
            if a > cursor { out.append((cursor, a - cursor)) }
            cursor = max(cursor, b)
        }
        if cursor < 1 { out.append((cursor, 1 - cursor)) }
        return out
    }
}
