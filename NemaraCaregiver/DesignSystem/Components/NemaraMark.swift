import SwiftUI

/// The Memoria brand mark — the black square with the white "m"
/// monogram (brand refresh 2026-08-18; source SVG in Resources/
/// memoria-monogram.svg). An image rather than live-rendered Text so
/// the mark stays in pixel parity at every size.
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
