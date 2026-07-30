import SwiftUI

/// Per-patient "Blur people" toggle (device-local; see `PeopleBlurStore`).
/// Mirrors `PrivacyModeCard`'s layout, but writes a local preference instead of
/// a server PATCH — flipping it swaps this device's live tiles between the
/// normal video and the on-device person-blur renderer. Reversible + local.
struct PeopleBlurCard: View {
    let patientId: UUID
    @ObservedObject private var store = PeopleBlurStore.shared

    private var enabled: Bool { store.isEnabled(patientId) }

    var body: some View {
        NemaraCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(enabled ? NemaraColor.actionSoft : NemaraColor.paperDim)
                    Image(systemName: enabled ? "person.fill" : "person")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(enabled ? NemaraColor.action : NemaraColor.ink3)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Blur people")
                            .font(NemaraFont.bodySemibold)
                            .foregroundStyle(NemaraColor.ink)
                        InfoDot("Blurs people in the live feed on this device only. The room stays visible; recording and what others see are unchanged.")
                    }
                }
                Spacer()
                NemaraToggle(isOn: Binding(
                    get: { enabled },
                    set: { store.setEnabled($0, for: patientId) }
                ), track: "people_blur.toggle")
            }
        }
        .padding(.horizontal, 16)
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return PeopleBlurCard(patientId: env.api.patients[0].id)
        .environment(env)
        .padding(.vertical)
        .background(NemaraColor.paper)
}
#endif
