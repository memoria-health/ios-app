import SwiftUI

/// First-open consent sheet asking the caregiver to opt this patient
/// into Memoria's research data-collection program. Presented once —
/// only while `Patient.dataCollectionDecidedAt == nil` — from
/// `PatientShell`. Both choices record a decision so the sheet never
/// re-nags; the Settings card (`DataCollectionCard`) is how the
/// caregiver changes their mind later.
///
/// Mirrors `PairingCodeSheet`'s bottom-sheet chrome (capsule grabber,
/// eyebrow header, paper background) and its `env` / `dismiss` +
/// async-API pattern. "Share recordings" PATCHes
/// `data_collection_enabled: true`; "Not now" PATCHes `false`. The
/// backend stamps `data_collection_decided_at` either way.
struct DataCollectionConsentSheet: View {
    let patientId: UUID
    let patientName: String

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(NemaraColor.line)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("DATA COLLECTION").nemaraEyebrow()
                Text("Help improve care for everyone.")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)
            .padding(.horizontal, 24)

            Spacer(minLength: 8)

            // Single string literal (NOT `+`-concatenated) so SwiftUI renders
            // the markdown bold; `\n\n` gives the paragraph break.
            Text(
                "With your permission, Memoria will **securely store video and audio clips of \(patientName)** to help improve our understanding of elderly health and disease.\n\nThis is optional, never required, and you can turn it off anytime in Settings."
            )
            .font(NemaraFont.body)
            .foregroundStyle(NemaraColor.ink2)
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)

            if let error {
                Text(error)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                NemaraButton(
                    "Share recordings",
                    variant: .primary, size: .lg, block: true,
                    track: "data_collection.consent_share",
                ) {
                    Task { await decide(true) }
                }
                .disabled(busy)

                NemaraButton(
                    "Not now",
                    variant: .secondary, size: .lg, block: true,
                    track: "data_collection.consent_decline",
                ) {
                    Task { await decide(false) }
                }
                .disabled(busy)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(NemaraColor.paper)
    }

    /// PATCH the decision, then dismiss. The backend stamps
    /// `data_collection_decided_at` on either value, so this sheet won't
    /// auto-present again. On error we keep the sheet open and surface
    /// the message rather than recording a phantom decision.
    @MainActor
    private func decide(_ enabled: Bool) async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            _ = try await env.api.updatePatient(
                patientId, UpdatePatientRequest(dataCollectionEnabled: enabled),
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    let p = env.api.patients[0]
    return DataCollectionConsentSheet(patientId: p.id, patientName: p.preferredName)
        .environment(env)
}
#endif
