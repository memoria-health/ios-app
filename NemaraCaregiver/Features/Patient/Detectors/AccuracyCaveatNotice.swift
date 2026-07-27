import SwiftUI

/// Expectations notice for fine-detail detectors (small motion like
/// seizure/choking, small objects like medication/stove). Shown at the
/// enroll moment and in the detail sheet so a caregiver knows accuracy
/// varies with distance and lighting BEFORE they rely on it.
///
/// Driven by `Detector.showsAccuracyCaveat` (server-computed). Amber
/// "heads up" styling so it stands out from the surrounding UI, but it
/// only sets expectations — it is not an alarm or an error.
struct AccuracyCaveatNotice: View {
    /// `compact` = one-line caption for dense lists; the full notice is
    /// the default (enroll flow + detail sheet).
    var compact: Bool = false

    private static let full =
        "This detector reads small, fine details, so how reliably it works "
        + "depends on how far away the camera is, the lighting, and the angle. "
        + "It can miss events or misread them. Treat any alert as a reason to "
        + "check in, not a guarantee that something did or did not happen."
    private static let short =
        "Reads fine detail. Accuracy depends on camera distance, lighting, and angle."

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NemaraColor.warning)
                .padding(.top, 1)
            Text(compact ? Self.short : Self.full)
                .font(NemaraFont.caption)
                .foregroundStyle(compact ? NemaraColor.warning : NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 0 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            compact
                ? nil
                : RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NemaraColor.warning.opacity(0.12))
        )
    }
}
