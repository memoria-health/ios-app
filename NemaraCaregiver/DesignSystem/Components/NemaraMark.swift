import SwiftUI

/// The Nemara brand mark — a terra-rust rounded square with a Fraunces "n".
/// This is Logo 01 from the design system. There are no alternates.
///
/// Glyph specification (all proportional, scale together):
/// - container radius     = `22.4%` of side (iOS app-icon squircle)
/// - glyph (Fraunces 144pt Soft, weight 500, SOFT 75) size = `69%` of side
/// - glyph y-offset       = `+4.5%` of side (optical-center, intentionally
///   below the geometric middle so the "n" reads as visually centered)
/// - kerning              = `-1.6%` of side
///
/// The `+4.5%` downward offset is not a quirk to fix — Fraunces's
/// lowercase "n" has a heavy top arch and a light baseline; pushing
/// it slightly below center balances the visual weight and matches
/// the canonical mark in the design system.
struct NemaraMark: View {
    let size: CGFloat

    init(size: CGFloat = 44) {
        self.size = size
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.224, style: .continuous)
                .fill(NemaraColor.terra)

            Text("n")
                .font(NemaraFont.serif(size: size * 0.69, weight: .medium))
                .foregroundStyle(NemaraColor.terraInk)
                .kerning(-size * 0.016)
                .offset(y: size * 0.045)
        }
        .frame(width: size, height: size)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 24) {
        NemaraMark(size: 28)
        NemaraMark(size: 44)
        NemaraMark(size: 80)
        NemaraMark(size: 120)
        NemaraMark(size: 180)
    }
    .padding()
    .background(NemaraColor.paper)
}
#endif
