import SwiftUI

/// The patient Home tab — a per-patient insights dashboard.
///
/// Every card is the widget the backend compiled for one detector
/// (widget = f(detector), decided at detector-write time, never here).
/// Layout is deterministic via DashboardBuilder: category sections in
/// fixed order, only categories with an active detector, severe-first.
/// Insights only — alerts stay on the roster and the Events tab.
struct PatientHomeView: View {
    @Environment(AppEnvironment.self) private var env

    let patientId: UUID

    private var detectors: [Detector] {
        env.api.detectorsByPatient[patientId] ?? []
    }

    private var cameras: [Camera] {
        env.api.camerasByPatient[patientId] ?? []
    }

    var body: some View {
        // ScrollView also keeps short content top-aligned — without it
        // the shell's VStack centers a sparse dashboard mid-screen.
        ScrollView {
            VStack(alignment: .leading, spacing: NemaraSpacing.md) {
                sensingLine
                let sections = DashboardBuilder.sections(from: detectors)
                if sections.isEmpty {
                    emptyState
                } else {
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, NemaraSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { try? await env.api.refresh() }
    }

    // MARK: - Sensing line

    /// One quiet row of camera truth. Every chart below is blind
    /// without it, so it turns loud when coverage drops.
    @ViewBuilder
    private var sensingLine: some View {
        let active = cameras.filter { !$0.disabled }
        let online = active.filter(\.online).count
        let allDark = !active.isEmpty && online == 0
        HStack(spacing: 7) {
            Circle()
                .fill(allDark ? NemaraColor.terra : NemaraColor.sage)
                .frame(width: 7, height: 7)
            Text(active.isEmpty
                 ? "No sensors yet"
                 : allDark
                 ? "All sensors offline — charts may be stale"
                 : "\(online) of \(active.count) sensor\(active.count == 1 ? "" : "s") watching")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(allDark ? NemaraColor.terra : NemaraColor.ink3)
        }
        .padding(.top, 2)
    }

    // MARK: - Sections

    private func sectionView(_ section: DashboardSection) -> some View {
        VStack(alignment: .leading, spacing: NemaraSpacing.sm) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(section.category.accent)
                    .frame(width: 8, height: 8)
                NemaraEyebrow(section.category.displayName.uppercased(),
                              color: section.category.accent)
                Spacer()
                Text("\(section.entries.count) detector\(section.entries.count == 1 ? "" : "s")")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
            .padding(.top, 4)

            // Tiles pack two-up; wide widgets take the full width.
            let tiles = section.entries.filter { $0.spec.size == .tile }
            let wides = section.entries.filter { $0.spec.size == .wide }
            if !tiles.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: NemaraSpacing.sm),
                              GridItem(.flexible())],
                    spacing: NemaraSpacing.sm,
                ) {
                    ForEach(tiles) { DashboardWidgetView(entry: $0) }
                }
            }
            ForEach(wides) { DashboardWidgetView(entry: $0) }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        DashboardEmptyStateView(
            hasDetectors: detectors.contains { $0.dashboardWidget != nil })
    }
}

/// Centered middle-of-page empty state — an icon mark with a few words
/// under it, no card. Worded apart for "all switched off" vs "none yet".
struct DashboardEmptyStateView: View {
    let hasDetectors: Bool

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(NemaraColor.card)
                    .frame(width: 92, height: 92)
                Circle()
                    .strokeBorder(NemaraColor.line, lineWidth: 1)
                    .frame(width: 92, height: 92)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(NemaraColor.ink3)
            }
            VStack(spacing: 5) {
                Text("Nothing to see yet")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
                Text(hasDetectors
                     ? "Turn on a detector and its chart appears here."
                     : "Add a detector and its chart appears here.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink3)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}
