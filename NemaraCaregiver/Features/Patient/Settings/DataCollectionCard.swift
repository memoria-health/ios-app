import SwiftUI

/// Per-patient data-collection toggle, mirroring the web dashboard's
/// `DataCollectionSettings` and the iOS `PatientEmailAlertsCard` master
/// row. Lets the caregiver turn research clip contribution on/off at any
/// time after the first-open consent sheet has recorded a decision.
///
/// Same optimistic-via-server-PATCH pattern as the email card: every
/// flip PATCHes `data_collection_enabled` through
/// `NemaraAPIClient.updatePatient`, which writes the canonical row back
/// into `env.api.patients` so this view re-derives `enabled` and the
/// parent re-renders. On error we surface the message inline; the
/// toggle snaps back because it's bound to the (unchanged) server state.
struct DataCollectionCard: View {
    @Environment(AppEnvironment.self) private var env
    let patientId: UUID

    @State private var busy = false
    @State private var error: String?

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }
    private var enabled: Bool { patient?.dataCollectionEnabled ?? false }
    private var name: String { patient?.preferredName ?? "this patient" }

    var body: some View {
        NemaraCard(padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                masterRow

                if let error {
                    Text(error)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var masterRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(enabled ? NemaraColor.actionSoft : NemaraColor.paperDim)
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(enabled ? NemaraColor.action : NemaraColor.ink3)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Contribute recordings to research")
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
                Text(enabled
                     ? "Memoria is securely storing video and audio clips of \(name) to help improve our understanding of elderly health and disease."
                     : "Memoria will securely store video and audio clips of \(name) to help improve our understanding of elderly health and disease.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            NemaraToggle(isOn: Binding(
                get: { enabled },
                set: { newValue in Task { await toggle(to: newValue) } }
            ), track: "data_collection.toggle")
            .disabled(busy)
        }
    }

    // MARK: - Mutation (optimistic via server PATCH, rollback on error)

    private func toggle(to next: Bool) async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            _ = try await env.api.updatePatient(
                patientId, UpdatePatientRequest(dataCollectionEnabled: next),
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return DataCollectionCard(patientId: env.api.patients[0].id)
        .environment(env)
        .padding(.vertical)
        .background(NemaraColor.paper)
}
#endif
