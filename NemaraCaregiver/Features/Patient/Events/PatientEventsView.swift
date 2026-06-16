import SwiftUI

/// "Events" sub-tab. Title + filter chips (All / Unreviewed / Reviewed)
/// + scrolling list of event cards.
struct PatientEventsView: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case unreviewed = "Unreviewed"
        case reviewed = "Reviewed"
        var id: String { rawValue }
    }
    @State private var filter: Filter = .unreviewed
    @State private var openedEvent: DetectionEvent?

    private var events: [DetectionEvent] {
        env.api.eventsByPatient[patientId] ?? []
    }
    private var counts: [Filter: Int] {
        [
            .all: events.count,
            .unreviewed: events.filter { !$0.reviewed }.count,
            .reviewed: events.filter(\.reviewed).count,
        ]
    }
    private var visible: [DetectionEvent] {
        switch filter {
        case .all: events
        case .unreviewed: events.filter { !$0.reviewed }
        case .reviewed: events.filter(\.reviewed)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                titleRow
                if let err = env.api.lastReviewError {
                    reviewErrorBanner(err)
                }
                filterChips
                if visible.isEmpty {
                    emptyState
                } else {
                    ForEach(visible) { ev in
                        Button {
                            if !ev.opened {
                                Task {
                                    _ = try? await env.api.updateEvent(
                                        ev.id, UpdateEventRequest(opened: true),
                                    )
                                }
                            }
                            openedEvent = ev
                        } label: {
                            EventCard(event: ev)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .background(NemaraColor.paper)
        .sheet(item: $openedEvent) { ev in
            NavigationStack {
                EventDetailView(
                    event: ev,
                    patientId: patientId,
                    onReviewSubmitted: { openedEvent = nil },
                )
                .trackScreen("event_detail")
            }
        }
        // Reliability net for the Events feed. Realtime is the instant
        // path, but if the socket is stale (token refresh, a dropped
        // connection) or the app was backgrounded, the INSERT can be
        // missed — Realtime has no replay. Refetch on appear and gently
        // poll while the Events tab is on screen so a new event is never
        // stuck invisible until a relaunch. (The poll is quiet — no
        // spinner — and stops when you leave the tab.)
        .task(id: patientId) {
            while !Task.isCancelled {
                // Pause the refresh while a detail sheet is open: refetching
                // replaces eventsByPatient, which re-renders the open sheet and
                // (historically, with the inline player) killed clip playback
                // mid-watch. Resume the moment the sheet closes.
                if openedEvent == nil {
                    try? await env.api.loadEventsFirstPage(forPatient: patientId)
                }
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
        // APNs deep link terminal step: open the focused event's sheet.
        // `initial: true` fires when the Events tab first appears (cold
        // launch, value already set) and again if it arrives while mounted.
        // Setting `openedEvent` auto-pauses the poll above (its
        // `openedEvent == nil` guard), so this can't re-trigger the
        // refetch that historically killed clip playback.
        .onChange(of: env.deepLink.focusEventId, initial: true) { _, _ in
            guard env.deepLink.focusEventId != nil else { return }
            Task { await openFocusedEvent() }
        }
    }

    /// Resolve and present the deep-linked event, then consume the latch
    /// exactly once. Cache-first (Realtime INSERT / first page); on a miss
    /// (cold launch, or older than the loaded page) fall back to an
    /// authoritative, caregiver-scoped `GET /v1/events/{id}`. On any
    /// failure we simply leave the caregiver on the Events tab — never a
    /// dead tap, never a stuck latch.
    @MainActor
    private func openFocusedEvent() async {
        guard let eid = env.deepLink.focusEventId else { return }
        if let ev = events.first(where: { $0.id == eid }) {
            openedEvent = ev
            env.deepLink.focusEventId = nil
            return
        }
        if let ev = try? await env.api.fetchEvent(eid), ev.patientId == patientId {
            openedEvent = ev
        }
        env.deepLink.focusEventId = nil
    }

    /// Big, centered "nothing here" state shown when the active filter
    /// has no events. Copy adapts to the filter so "all caught up" reads
    /// differently from "nothing has happened yet".
    private var emptyState: some View {
        let copy = emptyCopy
        return VStack(spacing: 10) {
            Image(systemName: copy.icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(NemaraColor.ink3)
            Text(copy.title)
                .font(NemaraFont.title3)
                .foregroundStyle(NemaraColor.ink)
                .kerning(-0.3)
            Text(copy.subtitle)
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private var emptyCopy: (icon: String, title: String, subtitle: String) {
        switch filter {
        case .all:
            return ("tray", "Nothing to see here yet",
                    "When a detector notices something, events will show up here.")
        case .unreviewed:
            return ("checkmark.circle", "All caught up",
                    "No events are waiting for your review.")
        case .reviewed:
            return ("tray", "Nothing reviewed yet",
                    "Events you've reviewed will appear here.")
        }
    }

    private var titleRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("Recent events")
                .font(NemaraFont.title2)
                .foregroundStyle(NemaraColor.ink)
                .kerning(-0.4)
            Spacer()
            Text("Last 7d")
                .font(NemaraFont.mono(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(NemaraColor.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(NemaraColor.paperDim)
                .clipShape(Capsule(style: .continuous))
        }
        .padding(.top, 2)
    }

    private func reviewErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NemaraColor.terra)
                .padding(.top, 1)
            Text(message)
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { env.api.lastReviewError = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(NemaraColor.terraSoft)
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                .strokeBorder(NemaraColor.terra.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases) { f in
                let on = filter == f
                Button { filter = f } label: {
                    HStack(spacing: 6) {
                        Text(f.rawValue)
                            .font(NemaraFont.sans(size: 12.5, weight: .semibold))
                        Text("\(counts[f] ?? 0)")
                            .font(NemaraFont.mono(size: 9, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(on ? NemaraColor.paper : NemaraColor.ink3)
                            .padding(.horizontal, 6)
                            .background(on ? NemaraColor.paper.opacity(0.18) : NemaraColor.paperDim)
                            .clipShape(Capsule(style: .continuous))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .foregroundStyle(on ? NemaraColor.paper : NemaraColor.ink2)
                    .background(on ? NemaraColor.ink : .clear)
                    .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(4)
        .background(NemaraColor.paperDim)
        .clipShape(Capsule(style: .continuous))
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return PatientEventsView(patientId: env.api.patients[0].id)
        .environment(env)
}
#endif
