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

    // Reworded 2026-08-17 (Aryaman): lead with the plain expectation
    // ("100% accuracy is not guaranteed") instead of the mechanism
    // ("reads small, fine details") — the old wording also misdescribed
    // whole-person detectors like choking, which now carry this notice.
    private static let full =
        "100% accuracy is not guaranteed. How well this detector works "
        + "depends on sensor distance, lighting, and angle, and it can miss "
        + "events or misread them. Treat any alert as a reason to check in, "
        + "not as proof that something did or did not happen."
    private static let short =
        "100% accuracy not guaranteed. Depends on sensor distance, lighting, and angle."

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NemaraColor.warning)
                .padding(.top, 1)
            // Ink on a warning-tinted wash, never yellow text — the
            // same container language as the wandering activation hint.
            Text(compact ? Self.short : Self.full)
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 10 : 12)
        .background(NemaraColor.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md,
                                    style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            compact
                ? nil
                : RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NemaraColor.warning.opacity(0.12))
        )
    }
}
