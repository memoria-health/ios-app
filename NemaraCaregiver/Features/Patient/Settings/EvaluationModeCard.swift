import SwiftUI

/// "Evaluation mode" — the caregiver-facing face of the event gate.
///
/// When it is on, this patient's alerts are held for a few seconds before
/// the family is notified, and a Memoria reviewer sees a masked clip and
/// can drop the alert if it is a false alarm. Backed by
/// `patients.event_gate_enabled` through the ordinary patient PATCH.
///
/// ON by default, which is the reason the explainer matters. A household
/// that never opts in is still being reviewed, so the sheet behind the ⓘ
/// is doing the work of a disclosure, not a nice-to-have. It is also why
/// `Patient.eventGateEnabled` decodes a missing field as `true`: an older
/// backend that does not send the key must not render this as off and
/// tell the caregiver something untrue about their own account.
///
/// Same optimistic-via-server-PATCH pattern as `DataCollectionCard`: the
/// flip PATCHes, the canonical row comes back into `env.api.patients`,
/// and this view re-derives `enabled`. On error the toggle snaps back
/// because it is bound to the (unchanged) server state.
struct EvaluationModeCard: View {
    @Environment(AppEnvironment.self) private var env
    let patientId: UUID

    @State private var busy = false
    @State private var error: String?
    @State private var showingInfo = false

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }
    private var enabled: Bool { patient?.eventGateEnabled ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            recommendedTag
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
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showingInfo) {
            EvaluationModeInfoSheet()
        }
    }

    /// Sits ABOVE the card rather than inside it, so the row itself keeps
    /// the same shape as every other settings toggle.
    private var recommendedTag: some View {
        Text("RECOMMENDED")
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(NemaraColor.action)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(NemaraColor.actionSoft)
            )
    }

    private var masterRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(enabled ? NemaraColor.actionSoft : NemaraColor.paperDim)
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(enabled ? NemaraColor.action : NemaraColor.ink3)
            }
            .frame(width: 38, height: 38)

            HStack(spacing: 6) {
                Text("Evaluation mode")
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
                // A full sheet, not the usual InfoDot popover: this
                // explanation has to carry an image and enough text to
                // actually inform a decision.
                Button { showingInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(NemaraColor.ink4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About evaluation mode")
            }
            Spacer()
            NemaraToggle(isOn: Binding(
                get: { enabled },
                set: { newValue in Task { await toggle(to: newValue) } }
            ), track: "evaluation_mode.toggle")
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
                patientId, UpdatePatientRequest(eventGateEnabled: next),
            )
        } catch {
            self.error = "Could not change this setting. Please try again."
        }
    }
}
