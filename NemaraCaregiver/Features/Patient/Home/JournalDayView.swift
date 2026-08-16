import SwiftUI

/// The one visualization primitive of the Daily Journal: a 24-hour
/// line that only PLACES recorded timestamps — dots for instants,
/// capsules for recorded intervals. Ticks and labels share one
/// position function with the marks, so they cannot disagree.
struct DayStripView: View {
    let strip: JournalStrip
    let accent: Color

    private var labels: (String, String, String) {
        strip.axis == .noon ? ("12p", "12a", "12p") : ("12a", "12p", "12a")
    }

    /// One mapping for everything drawn: fractional hour → x.
    private func x(_ t: Double, _ width: CGFloat) -> CGFloat {
        let inset: CGFloat = 5
        return inset + (width - 2 * inset) * CGFloat(min(max(t, 0), 24)) / 24
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                // Baseline + quarter ticks.
                Rectangle()
                    .fill(NemaraColor.line)
                    .frame(width: w, height: 2)
                    .offset(y: 5)
                ForEach([0.0, 6, 12, 18, 24], id: \.self) { t in
                    Rectangle()
                        .fill(NemaraColor.line)
                        .frame(width: 1, height: 5)
                        .offset(x: x(t, w) - 0.5, y: 7)
                }
                ForEach(Array(strip.spans.enumerated()), id: \.offset) { _, span in
                    if span.count == 2 {
                        let x0 = x(span[0], w)
                        let x1 = max(x0 + 6, x(span[1], w))
                        Capsule()
                            .fill(accent)
                            .frame(width: x1 - x0, height: 10)
                            .offset(x: x0, y: 1)
                    }
                }
                ForEach(Array(strip.marks.enumerated()), id: \.offset) { _, mark in
                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                        .offset(x: x(mark, w) - 5, y: 1)
                }
                // Labels anchored to their own ticks.
                Text(labels.0)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .offset(x: x(0, w) - 2, y: 14)
                Text(labels.1)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .frame(width: 40)
                    .offset(x: x(12, w) - 20, y: 14)
                Text(labels.2)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .frame(width: 40, alignment: .trailing)
                    .offset(x: x(24, w) - 38, y: 14)
            }
        }
        .frame(height: 30)
        .padding(.top, 4)
    }
}

/// One journal entry row — the artifact's grammar: exactly one
/// semibold lead per row, one short caption beneath it, and at most
/// one chip. Never more.
struct JournalEntryRow: View {
    let entry: JournalEntry
    let accent: Color
    let soft: Color
    let onReview: (UUID) -> Void

    /// Quiet point lines ("No falls") lead with the fact itself.
    private var factLed: Bool {
        entry.line.status == .ok && entry.line.primary.hasPrefix("No ")
    }

    private var lead: String { factLed ? entry.line.primary : entry.title }

    /// One short caption. Records join their two short parts; event
    /// and absence rows show just the meta or the outcome.
    private var caption: String? {
        if factLed { return nil }
        let primary = entry.line.primary == entry.title ? nil : entry.line.primary
        let parts = [primary, entry.line.meta].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private var captionColor: Color {
        switch entry.line.status {
        case .ok: return NemaraColor.sage
        case .review: return NemaraColor.ink2
        case .none: return NemaraColor.ink3
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(soft)
                    .frame(width: 30, height: 30)
                Image(systemName: entry.icon ?? "circle.dashed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(lead)
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    trailingChip
                }
                if let caption {
                    Text(entry.line.status == .ok ? "✓ \(caption)" : caption)
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(captionColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let ratio = entry.ratio {
                    RatioBarView(ratio: ratio, accent: accent)
                }
                if let strip = entry.strip {
                    DayStripView(strip: strip, accent: accent)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var trailingChip: some View {
        switch entry.line.status {
        case .review:
            if let eventId = entry.reviewEventId {
                Button { onReview(eventId) } label: {
                    Text("Review")
                        .font(NemaraFont.captionStrong)
                        .foregroundStyle(NemaraColor.terra)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(NemaraColor.terraSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        case .ok where factLed:
            Text("✓ \(entry.line.meta ?? "")")
                .font(NemaraFont.captionStrong)
                .foregroundStyle(NemaraColor.sage)
        default:
            EmptyView()
        }
    }
}

/// Activity's tug-of-war: active minutes (accent) vs the rest of the
/// observed day. A ratio has no axis to misread.
struct RatioBarView: View {
    let ratio: JournalRatio
    let accent: Color

    var body: some View {
        let total = max(ratio.labeledMinutes, 1)
        let fraction = min(1, CGFloat(ratio.activeMinutes) / CGFloat(total))
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NemaraColor.line)
                    Capsule().fill(accent)
                        .frame(width: max(10, geo.size.width * fraction))
                }
            }
            .frame(height: 12)
            Text("of \(ratio.labeledMinutes / 60) h \(ratio.labeledMinutes % 60) m observed")
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink3)
        }
        .padding(.top, 3)
    }
}

/// One full journal day: category sections + the coverage line.
struct JournalDayView: View {
    let day: JournalDay
    let onReview: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NemaraSpacing.sm) {
            ForEach(day.sections) { section in
                sectionView(section)
            }
            coverage
        }
    }

    private func sectionView(_ section: JournalSection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // The artifact's section heading: category-colored eyebrow
            // with its swatch. Colour + label together, never alone.
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(section.category.accent)
                    .frame(width: 8, height: 8)
                NemaraEyebrow(section.category.displayName.uppercased(),
                              color: section.category.accent)
            }
            .padding(.horizontal, 4)
            .padding(.top, 10)
            NemaraCard(tone: .default, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(section.entries.enumerated()), id: \.element.id) { i, entry in
                        if i > 0 {
                            Divider()
                                .overlay(NemaraColor.line.opacity(0.45))
                                .padding(.leading, 54)
                        }
                        JournalEntryRow(entry: entry,
                                        accent: section.category.accent,
                                        soft: section.category.soft,
                                        onReview: onReview)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var coverage: some View {
        let dark = day.coverageHours == 0
        HStack(spacing: 7) {
            Circle()
                .fill(dark ? NemaraColor.terra : NemaraColor.sage)
                .frame(width: 7, height: 7)
            Text(dark
                 ? "Cameras were not watching this day"
                 : "Cameras watched \(day.coverageHours) of 24 hours")
                .font(NemaraFont.caption)
                .foregroundStyle(dark ? NemaraColor.terra : NemaraColor.ink3)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}
