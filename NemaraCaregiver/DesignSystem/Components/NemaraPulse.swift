import SwiftUI

/// Pulsing dot. Used for the LIVE chip on the camera feed and for the
/// critical-event indicator on patient rows.
///
/// Implementation: a fixed-size colored circle in the center plus an
/// expanding outer ring that scales and fades. Matches the
/// `@keyframes nemaraPulse` from the design canvas.
struct NemaraPulse: View {
    let color: Color
    let size: CGFloat

    @State private var animate = false

    init(color: Color = NemaraColor.terra, size: CGFloat = 8) {
        self.color = color
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .opacity(animate ? 0 : 0.5)
                .scaleEffect(animate ? 2.4 : 0.6)
                .animation(
                    .easeOut(duration: 1.6).repeatForever(autoreverses: false),
                    value: animate
                )
            Circle()
                .fill(color)
                .frame(width: size * 0.6, height: size * 0.6)
        }
        .frame(width: size, height: size)
        .onAppear { animate = true }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 16) {
        NemaraPulse(color: NemaraColor.terra)
        NemaraPulse(color: NemaraColor.terra, size: 12)
        NemaraPulse(color: NemaraColor.action, size: 8)
    }
    .padding()
    .background(NemaraColor.paper)
}
#endif
