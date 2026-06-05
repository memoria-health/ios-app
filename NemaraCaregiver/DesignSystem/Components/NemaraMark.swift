import SwiftUI

/// The Memoria brand mark — the terra-rust square with the cream "m",
/// mirroring the app icon. Using an image instead of live-rendering Text keeps
/// the in-app mark in pixel-parity with AppIcon at every size and removes any
/// runtime font-registration risk.
struct NemaraMark: View {
    let size: CGFloat

    init(size: CGFloat = 44) {
        self.size = size
    }

    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            // The asset is an opaque square (no alpha channel), so its corners
            // render as a hard square on any background. Clip to a continuous
            // rounded rect (the iOS app-icon squircle ratio) so the mark reads
            // as a rounded square, matching the previous brand mark.
            .clipShape(
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            )
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
