import SwiftUI

/// The coverage ring shared by both enrollment UIs.
///
/// One idea, one state per arc: an arc is **faint** until captured and
/// **green** once captured. The single arc your nose points at right now
/// (`currentSegment`) is the *active* arc — it **charges** (fills from one
/// edge, `terra`) as you turn further toward it, then snaps to green the
/// instant it captures. So the direction you point is always the arc that
/// reacts, and green always means "got it." No counts, no second tier.
struct CoverageDial: View {
    @ObservedObject var coverage: FaceCoverageModel
    var lineWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let radius = min(size.width, size.height) / 2 - lineWidth
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let arcSpan = 360.0 / Double(coverage.segmentCount)
            let gapDeg = 5.0

            Canvas { ctx, _ in
                for seg in coverage.segments {
                    let half = arcSpan / 2 - gapDeg / 2
                    // model: 0°=right, 90°=up (CCW). Screen is y-down, so
                    // negate → "up" renders at the top.
                    let startDeg = -(seg.centreDeg + half)
                    let endDeg = -(seg.centreDeg - half)

                    if seg.covered {
                        stroke(ctx, centre, radius, startDeg, endDeg,
                               NemaraColor.success, lineWidth)
                    } else if coverage.currentSegment == seg.id {
                        // faint base + a charging fill that grows as you turn
                        stroke(ctx, centre, radius, startDeg, endDeg,
                               NemaraColor.line, lineWidth * 0.65)
                        let frac = min(1.0, coverage.currentMag / coverage.extremeMinDeg)
                        if frac > 0.02 {
                            let fillEnd = startDeg + (endDeg - startDeg) * frac
                            stroke(ctx, centre, radius, startDeg, fillEnd,
                                   NemaraColor.terra, lineWidth)
                        }
                    } else {
                        stroke(ctx, centre, radius, startDeg, endDeg,
                               NemaraColor.line, lineWidth * 0.55)
                    }
                }
            }
        }
    }

    private func stroke(
        _ ctx: GraphicsContext, _ centre: CGPoint, _ radius: CGFloat,
        _ startDeg: Double, _ endDeg: Double, _ color: Color, _ width: CGFloat,
    ) {
        var path = Path()
        path.addArc(center: centre, radius: radius,
                    startAngle: .degrees(startDeg), endAngle: .degrees(endDeg),
                    clockwise: false)
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

/// Big spring-in green tick shown when enrollment completes. Replaces the
/// live preview so the finished state reads as locked, not still-running.
struct EnrollmentCompleteBadge: View {
    var diameter: CGFloat = 300
    @State private var appear = false

    var body: some View {
        ZStack {
            Circle()
                .fill(NemaraColor.success.opacity(0.12))
                .overlay(Circle().strokeBorder(NemaraColor.success, lineWidth: 3))
            Image(systemName: "checkmark")
                .font(.system(size: diameter * 0.32, weight: .bold))
                .foregroundStyle(NemaraColor.success)
                .scaleEffect(appear ? 1 : 0.4)
                .opacity(appear ? 1 : 0)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appear = true }
        }
    }
}

/// Locked completion state: green tick + confirmation. Capturing has
/// stopped, the camera toggle is disabled, and only Done remains.
struct EnrollmentCompleteView: View {
    var body: some View {
        VStack(spacing: 20) {
            EnrollmentCompleteBadge(diameter: 240)
            Text("Enrollment complete")
                .font(NemaraFont.title3)
                .foregroundStyle(NemaraColor.success)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }
}
