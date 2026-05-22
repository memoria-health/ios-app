import SwiftUI

/// Shared patient header — Avatar + preferred name + relation subtitle +
/// Home button on the right. No back chevron (per design — the patient
/// bundle uses the Home button instead of stacked nav).
struct PHeader: View {
    let patient: Patient
    let onHome: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NemaraAvatar(letter: patient.avatarLetter, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(patient.preferredName)
                    .font(NemaraFont.serif(size: 19, weight: .regular))
                    .kerning(-0.3)
                    .foregroundStyle(NemaraColor.ink)
                Text(patient.relation.displayName)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
            Spacer()
            Button(action: onHome) {
                Image(systemName: "house.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return PHeader(patient: env.api.patients[0], onHome: {})
        .background(NemaraColor.paper)
        .environment(env)
}
