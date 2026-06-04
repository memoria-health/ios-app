import SwiftUI

/// Mock "wall-mounted phone camera" feed. Renders a warm radial gradient
/// with simple rectangular furniture silhouettes — enough to suggest a
/// room without pretending to be a real video frame. Replace with a
/// LiveKit (or HLS) player when real feeds land.
///
/// `hue` shifts the lighting per room so different rooms feel distinct.
///
/// `loading` overlays a scrim + spinner for the window where the camera is
/// expected-online but the track hasn't landed yet. The spinner is deliberately
/// PURE SwiftUI (see `NemaraLoadingSpinner`), NOT `ProgressView` — a UIKit
/// `UIActivityIndicatorView` animating next to the LiveKit `VideoView` in the
/// tile background risked the nil→track swap happening mid-animation and leaving
/// the new video UIView unpainted. A SwiftUI shape animating a scoped
/// `rotationEffect` keeps the animation contained and adds no sibling UIView.
struct NemaraCamFeedPlaceholder: View {
    let hue: Double
    let lit: Bool
    let loading: Bool

    init(hue: Double = 30, lit: Bool = true, loading: Bool = false) {
        self.hue = hue
        self.lit = lit
        self.loading = loading
    }

    var body: some View {
        ZStack {
            if lit {
                LinearGradient(
                    colors: [
                        Color(hue: hue / 360, saturation: 0.32, brightness: 0.72),
                        Color(hue: (hue + 6) / 360, saturation: 0.36, brightness: 0.56),
                        Color(hue: max(0, (hue - 4) / 360), saturation: 0.30, brightness: 0.34),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                FurnitureSilhouette()
                    .blendMode(.multiply)
                    .opacity(0.4)
            } else {
                NemaraColor.ink
                RadialGradient(
                    colors: [Color(red: 60/255, green: 50/255, blue: 40/255).opacity(0.6), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 220
                )
            }
            if loading {
                // Darken the mock room so the spinner reads as "loading" rather
                // than pretending the silhouettes are the live feed.
                Color.black.opacity(0.3)
                NemaraLoadingSpinner()
            }
        }
    }
}

/// Pure-SwiftUI loading spinner — a trimmed circle rotating forever. Used
/// instead of `ProgressView` on purpose: `ProgressView(.circular)` is a UIKit
/// `UIActivityIndicatorView`, and an always-animating UIKit view sitting beside
/// the LiveKit `VideoView` in the tile background risks the nil→track swap
/// committing mid-animation (new video UIView never paints). This keeps the
/// animation scoped to a `rotationEffect(value:)` so it can't wrap that swap.
private struct NemaraLoadingSpinner: View {
    @State private var spinning = false

    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(
                    Color.white.opacity(0.92),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round),
                )
                .frame(width: 26, height: 26)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    .linear(duration: 0.9).repeatForever(autoreverses: false),
                    value: spinning,
                )
            Text("Loading")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .onAppear { spinning = true }
    }
}

private struct FurnitureSilhouette: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                // Floor
                Rectangle()
                    .fill(Color(red: 58/255, green: 42/255, blue: 28/255))
                    .frame(width: w, height: h * 0.32)
                    .offset(y: h * 0.68)
                // Couch
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 90/255, green: 63/255, blue: 42/255))
                    .frame(width: w * 0.31, height: h * 0.30)
                    .offset(x: w * 0.12, y: h * 0.40)
                // Chest
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 107/255, green: 74/255, blue: 48/255))
                    .frame(width: w * 0.28, height: h * 0.40)
                    .offset(x: w * 0.56, y: h * 0.30)
                // Window
                Rectangle()
                    .fill(Color(red: 205/255, green: 184/255, blue: 142/255).opacity(0.6))
                    .frame(width: w * 0.25, height: h * 0.42)
                    .offset(x: w * 0.75)
            }
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 14) {
        NemaraCamFeedPlaceholder(hue: 30)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        NemaraCamFeedPlaceholder(hue: 200, lit: false)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    .padding()
    .background(NemaraColor.paper)
}
#endif
