import SwiftUI

/// Beta marker for CUSTOM detectors — the ones a caregiver wrote
/// themselves, as opposed to the presets we tuned and tested.
///
/// Deliberately separate from `AccuracyCaveatNotice`, which answers a
/// different question. That one is about the SUBJECT being hard to see
/// (fine detail, small motion) and is server-computed per detector. This
/// one is about the DETECTOR being newly generated from a sentence the
/// caregiver typed, which we have never evaluated. A detector can be
/// both, so the two are allowed to appear together.
///
/// Same amber "heads up" language as its sibling: sets expectations,
/// does not read as an error.
struct CustomDetectorBetaNotice: View {
    /// `compact` = one-line caption for dense lists; the full notice is
    /// the default (create review + detail sheet).
    var compact: Bool = false

    private static let full =
        "Custom detectors are in beta. This one was built from your own "
        + "description, so it has not been tested the way our built-in "
        + "detectors have and its accuracy can vary. Treat any alert as a "
        + "reason to check in rather than something to rely on."
    private static let short =
        "Beta. Built from your description, so accuracy can vary."

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NemaraColor.terra)
                .padding(.top, 1)
            Text(compact ? Self.short : Self.full)
                .font(NemaraFont.caption)
                .foregroundStyle(compact ? NemaraColor.terra : NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 0 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            compact
                ? nil
                : RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NemaraColor.terra.opacity(0.12))
        )
    }
}

/// Larger BETA badge for sticking onto a button. `NemaraChip` is 9pt mono,
/// which disappears at that size against a full-width control, so this is
/// its own thing rather than a chip with a bigger font.
struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(NemaraColor.terraInk)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous).fill(NemaraColor.terra)
            )
            .accessibilityLabel("Beta feature")
    }
}
