import SwiftUI

/// The Nemara brand mark, rendered from a vector asset that mirrors the
/// app icon exactly (Fraunces 144pt Soft "n" outline, terra-rust rounded
/// square). Using a vector image instead of live-rendering Text keeps the
/// in-app mark in pixel-parity with AppIcon at every size and removes any
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
