import SwiftUI

/// The one visualization primitive of the Daily Journal: a 24-hour
/// line that only PLACES recorded timestamps — dots for instants,
/// rounded spans for recorded intervals. It never aggregates.
struct DayStripView: View {
    let strip: JournalStrip
    let accent: Color

    private var labels: (String, String, String) {
        strip.axis == .noon ? ("12p", "12a", "12p") : ("12a", "12p", "12a")
    }

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(NemaraColor.line)
                        .frame(height: 2)
                        .frame(maxHeight: .infinity, alignment: .center)
                    ForEach(Array(strip.spans.enumerated()), id: \.offset) { _, span in
                        if span.count == 2 {
                            let x0 = w * span[0] / 24
                            let x1 = max(x0 + 5, w * span[1] / 24)
                            Capsule()
                                .fill(accent)
                                .frame(width: x1 - x0, height: 9)
                                .offset(x: x0)
                        }
                    }
                    ForEach(Array(strip.marks.enumerated()), id: \.offset) { _, mark in
                        Circle()
                            .fill(accent)
                            .frame(width: 9, height: 9)
                            .offset(x: w * mark / 24 - 4.5)
                    }
                }
            }
            .frame(height: 12)
            HStack {
                Text(labels.0)
                Spacer()
                Text(labels.1)
                Spacer()
                Text(labels.2)
            }
            .font(NemaraFont.caption)
            .foregroundStyle(NemaraColor.ink3)
        }
        .padding(.top, 2)
    }
}

/// One journal entry row — title-led or fact-led per the line's shape.
struct JournalEntryRow: View {
    let entry: JournalEntry
    let accent: Color
    let onReview: (UUID) -> Void

    /// Quiet point lines ("No falls") lead with the fact; everything
    /// else leads with the detector's name and puts the fact trailing.
    private var factLed: Bool { entry.line.primary.hasPrefix("No ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(factLed ? entry.line.primary : entry.title)
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
                    .lineLimit(1)
                if entry.line.status == .ok, factLed, let meta = entry.line.meta {
                    Text("✓ \(meta)")
                        .font(NemaraFont.captionStrong)
                        .foregroundStyle(NemaraColor.sage)
                }
                Spacer(minLength: 8)
                if entry.line.status == .review, let eventId = entry.reviewEventId {
                    Button { onReview(eventId) } label: {
                        Text("Review")
                            .font(NemaraFont.captionStrong)
                            .foregroundStyle(NemaraColor.terra)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(NemaraColor.terraSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if !factLed {
                    Text(trailing)
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(entry.line.status == .ok
                                         ? NemaraColor.sage : NemaraColor.ink3)
                        .lineLimit(1)
                }
            }
            if entry.line.status == .review {
                Text(trailing)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
            }
            if let strip = entry.strip {
                DayStripView(strip: strip, accent: accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var trailing: String {
        if factLed { return entry.line.meta ?? "" }
        let ok = entry.line.status == .ok ? "✓ " : ""
        // An event row's primary is often just the detector name again —
        // repeating it under the title reads like a stutter.
        let primary = entry.line.primary == entry.title ? nil : entry.line.primary
        let parts = [primary, entry.line.meta].compactMap(\.self)
        return ok + parts.joined(separator: " · ")
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(section.category.accent)
                    .frame(width: 8, height: 8)
                NemaraEyebrow(section.category.displayName.uppercased(),
                              color: section.category.accent)
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            NemaraCard(tone: .default, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(section.entries.enumerated()), id: \.element.id) { i, entry in
                        if i > 0 {
                            Divider().overlay(NemaraColor.line.opacity(0.55))
                        }
                        JournalEntryRow(entry: entry,
                                        accent: section.category.accent,
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
