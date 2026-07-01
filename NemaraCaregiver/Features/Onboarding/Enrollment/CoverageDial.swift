import SwiftUI

/// The segmented coverage ring shared by both enrollment UIs.
///
/// Each arc is a pose direction from `FaceCoverageModel`. An arc is faint
/// when uncovered, `terra` once registered (past `extremeMinDeg`), and
/// `success` (green) once pushed to the steep `reachTargetDeg` — so the
/// user can literally watch the extremes fill in. The arc the nose points
/// at right now glows (`terraSoft`). Optionally shows a pulsing target dot
/// at the next arc still needing an extreme (front nose-dial).
struct CoverageDial: View {
    @ObservedObject var coverage: FaceCoverageModel
    var lineWidth: CGFloat = 12
    var showTarget: Bool = false

    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let radius = min(size.width, size.height) / 2 - lineWidth
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)

            ZStack {
                Canvas { ctx, _ in
                    let arc = 360.0 / Double(coverage.segmentCount)
                    let gapDeg = 4.0
                    for seg in coverage.segments {
                        let half = arc / 2 - gapDeg / 2
                        // model: 0°=right, 90°=up (CCW). Screen is y-down,
                        // so negate to put "up" at the top.
                        let start = Angle(degrees: -(seg.centreDeg + half))
                        let end = Angle(degrees: -(seg.centreDeg - half))
                        var path = Path()
                        path.addArc(center: centre, radius: radius,
                                    startAngle: start, endAngle: end,
                                    clockwise: false)
                        ctx.stroke(
                            path,
                            with: .color(color(for: seg)),
                            style: StrokeStyle(
                                lineWidth: seg.covered ? lineWidth : lineWidth * 0.55,
                                lineCap: .round,
                            ),
                        )
                    }
                }

                if showTarget, let target = nextTarget {
                    targetDot(centreDeg: target, radius: radius, origin: centre)
                }
            }
        }
        .onAppear { pulse = true }
    }

    private func color(for seg: FaceCoverageModel.Segment) -> Color {
        if seg.fullyReached { return NemaraColor.success }
        if seg.covered { return NemaraColor.terra }
        if coverage.currentSegment == seg.id { return NemaraColor.terraSoft }
        return NemaraColor.line
    }

    /// Direction of the next arc still short of the steep target.
    private var nextTarget: Double? {
        coverage.segments.first(where: { !$0.fullyReached })?.centreDeg
    }

    private func targetDot(centreDeg: Double, radius: CGFloat, origin: CGPoint) -> some View {
        let rad = CGFloat(-centreDeg * .pi / 180)
        let p = CGPoint(x: origin.x + radius * cos(rad),
                        y: origin.y + radius * sin(rad))
        return Circle()
            .fill(NemaraColor.terra)
            .frame(width: 18, height: 18)
            .scaleEffect(pulse ? 1.25 : 0.85)
            .opacity(pulse ? 1.0 : 0.6)
            .position(p)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
    }
}
