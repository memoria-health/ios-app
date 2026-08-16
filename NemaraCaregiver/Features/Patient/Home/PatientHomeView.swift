import SwiftUI

/// The patient Home tab — the Daily Journal (teardown placeholder).
///
/// The chart dashboard was removed 2026-08-16 (see nemara-backend
/// docs/plans/2026-08-16-daily-journal.md). The journal day page lands
/// in the next commits; until then this renders the sensing line and
/// the quiet empty state so the tab stays honest, never broken.
struct PatientHomeView: View {
    @Environment(AppEnvironment.self) private var env

    let patientId: UUID

    private var cameras: [Camera] {
        env.api.camerasByPatient[patientId] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NemaraSpacing.md) {
                sensingLine
                DashboardEmptyStateView(hasDetectors: true)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, NemaraSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { try? await env.api.refresh() }
    }

    /// One quiet row of camera truth; turns loud when coverage drops.
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
                 ? "All sensors offline"
                 : "\(online) of \(active.count) sensor\(active.count == 1 ? "" : "s") watching")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(allDark ? NemaraColor.terra : NemaraColor.ink3)
        }
        .padding(.top, 2)
    }
}

/// Centered middle-of-page empty state — an icon mark with a few words
/// under it, no card.
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
                Image(systemName: "book.closed")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(NemaraColor.ink3)
            }
            VStack(spacing: 5) {
                Text("Nothing to see yet")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
                Text(hasDetectors
                     ? "Turn on a detector and its day appears here."
                     : "Add a detector and its day appears here.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink3)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}
