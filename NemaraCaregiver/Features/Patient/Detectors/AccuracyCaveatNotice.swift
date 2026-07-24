import SwiftUI

/// Expectations notice for fine-detail detectors (small motion like
/// seizure/choking, small objects like medication/stove). Shown at the
/// enroll moment and in the detail sheet so a caregiver knows accuracy
/// varies with distance and lighting BEFORE they rely on it.
///
/// Driven by `Detector.showsAccuracyCaveat` (server-computed). Info
/// styling, not alarm: it sets expectations, it is not an error.
struct AccuracyCaveatNotice: View {
    /// `compact` = one-line caption for dense lists; the full notice is
    /// the default (enroll flow + detail sheet).
    var compact: Bool = false

    private static let full =
        "This detector reads fine visual detail. Accuracy varies with camera "
        + "distance, lighting, and viewing angle, and events can be missed or "
        + "misread. Treat alerts as a prompt to check in, not a certainty."
    private static let short = "Accuracy varies with distance and lighting."

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NemaraColor.info)
                .padding(.top, 1)
            Text(compact ? Self.short : Self.full)
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 0 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            compact
                ? nil
                : RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NemaraColor.skySoft)
        )
    }
}
