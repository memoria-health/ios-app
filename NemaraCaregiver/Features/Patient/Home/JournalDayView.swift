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
                            .frame(width: x1 - x0, height: 8)
                            .offset(x: x0, y: 2)
                    }
                }
                ForEach(Array(strip.marks.enumerated()), id: \.offset) { _, mark in
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                        .offset(x: x(mark, w) - 4, y: 2)
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

/// One journal entry row. Hierarchy carried by size and ink, not
/// weight: small tinted icon says the category, a quiet title names
/// the detector, the fact below it wraps at full width, and the only
/// emphasis on the page is a status chip.
struct JournalEntryRow: View {
    let entry: JournalEntry
    let accent: Color
    let soft: Color
    let onReview: (UUID) -> Void

    /// Eventful lines read in full ink; quiet/record lines recede.
    private var eventful: Bool {
        entry.line.status == .review || !(entry.strip?.marks.isEmpty ?? true)
    }

    /// Quiet point lines ("No falls") already ARE the fact — showing
    /// title + "No falls" would say it twice.
    private var value: String {
        let primary = entry.line.primary == entry.title ? nil : entry.line.primary
        let meta = entry.line.status == .ok && entry.line.primary.hasPrefix("No ")
            ? nil : entry.line.meta
        return [primary, meta].compactMap(\.self).joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(soft)
                    .frame(width: 30, height: 30)
                Image(systemName: entry.icon ?? "circle.dashed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.title)
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink3)
                    Spacer(minLength: 8)
                    trailingChip
                }
                if !value.isEmpty {
                    Text(value)
                        .font(NemaraFont.bodyLarge)
                        .foregroundStyle(eventful ? NemaraColor.ink : NemaraColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
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
        case .ok:
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                if entry.line.primary.hasPrefix("No "), let meta = entry.line.meta {
                    Text(meta).font(NemaraFont.caption)
                }
            }
            .foregroundStyle(NemaraColor.sage)
        case .none:
            EmptyView()
        }
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
            // Section names are real headings — serif, larger than any
            // body text — with the category swatch as reinforcement.
            HStack(spacing: 8) {
                Circle()
                    .fill(section.category.accent)
                    .frame(width: 9, height: 9)
                Text(section.category.displayName)
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
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
