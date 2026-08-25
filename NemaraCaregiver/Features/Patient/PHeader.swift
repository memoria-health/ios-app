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
            // Feedback pill removed from the header (Aryaman, Aug 17) —
            // product feedback lives in Patient Settings; the header
            // keeps only help and Home.
            //
            // Same two components and the same gap as the roster header:
            // help was a bordered 12pt chip beside a bare 18pt glyph,
            // separated by an ad-hoc trailing pad rather than the shared
            // spacing, so the pair matched neither each other nor Home.
            HStack(spacing: NemaraHeaderIcon.gap) {
                SupportIconButton()
                NemaraHeaderIcon("house.fill", label: "Home", action: onHome)
            }
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
