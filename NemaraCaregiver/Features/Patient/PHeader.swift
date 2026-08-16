import SwiftUI

/// Shared patient header — Avatar + preferred name + relation subtitle +
/// a "Feedback" pill and the Home button on the right. No back chevron (per
/// design — the patient bundle uses the Home button instead of stacked nav).
struct PHeader: View {
    let patient: Patient
    /// When false, the avatar + name + relation are hidden and only the
    /// Feedback + Home buttons remain. Used on the Settings tab, where the
    /// profile card already shows the patient's identity — so the top bar
    /// would otherwise repeat it.
    var showsIdentity: Bool = true
    /// Optional — when set, a "Feedback" pill appears to the LEFT of Home so
    /// the caregiver can reach the feedback form from any patient sub-tab.
    var onFeedback: (() -> Void)? = nil
    let onHome: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if showsIdentity {
                PatientAvatar(patient: patient, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(patient.preferredName)
                        .font(NemaraFont.serif(size: 19, weight: .regular))
                        .kerning(-0.3)
                        .foregroundStyle(NemaraColor.ink)
                }
            }
            Spacer()
            SupportIconButton()
                .padding(.trailing, 10)
            if let onFeedback {
                Button(action: onFeedback) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Feedback")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(NemaraColor.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule(style: .continuous).fill(NemaraColor.paperDim))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(NemaraColor.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Give feedback")
                // Deliberate gap so Feedback and Home are well separated and
                // not easily fat-fingered together (12 here + HStack's 12 = 24pt).
                .padding(.trailing, 12)
            }
            Button(action: onHome) {
                Image(systemName: "house.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Home")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return PHeader(patient: env.api.patients[0], onFeedback: {}, onHome: {})
        .background(NemaraColor.paper)
        .environment(env)
}
#endif
