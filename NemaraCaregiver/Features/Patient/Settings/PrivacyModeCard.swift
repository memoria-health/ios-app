import SwiftUI

/// Per-patient Privacy mode toggle. While on, Memoria stores no clips,
/// severs the live video+audio feed to caregivers (enforced server-side
/// at the SFU), and strips clips from event insights — while the text
/// insights keep flowing. Mirrors `DataCollectionCard`'s
/// optimistic-via-server-PATCH pattern: every flip PATCHes
/// `privacy_mode_enabled`, which writes the canonical row back into
/// `env.api.patients` so this view re-derives `enabled`.
///
/// Privacy SUSPENDS data collection without changing the stored consent
/// decision, so `DataCollectionCard` shows itself as suspended (not
/// flipped off) while this is on.
struct PrivacyModeCard: View {
    @Environment(AppEnvironment.self) private var env
    let patientId: UUID

    @State private var busy = false
    @State private var error: String?

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }
    private var enabled: Bool { patient?.privacyModeEnabled ?? false }
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
                Image(systemName: enabled ? "eye.slash.fill" : "eye.slash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(enabled ? NemaraColor.action : NemaraColor.ink3)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Privacy mode")
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
                Text(enabled
                     ? "Privacy mode is on. No one can watch or listen to \(name)'s live feed, and nothing is being recorded. You still receive insights on your phone."
                     : "Hide \(name)'s live video and audio and stop all recording. You still receive insights on your phone. This preserves their dignity at all times.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            NemaraToggle(isOn: Binding(
                get: { enabled },
                set: { newValue in Task { await toggle(to: newValue) } }
            ), track: "privacy_mode.toggle")
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
                patientId, UpdatePatientRequest(privacyModeEnabled: next),
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return PrivacyModeCard(patientId: env.api.patients[0].id)
        .environment(env)
        .padding(.vertical)
        .background(NemaraColor.paper)
}
#endif
