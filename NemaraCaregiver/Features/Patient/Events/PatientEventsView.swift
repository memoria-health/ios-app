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
                filterChips
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
            }
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
