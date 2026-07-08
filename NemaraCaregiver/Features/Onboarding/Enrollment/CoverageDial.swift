import SwiftUI

/// The coverage ring shared by both enrollment UIs.
///
/// One idea, one state per arc: an arc is **faint** until captured and
/// **green** once captured. Over the top of the arcs, a **pose needle**
/// points from the centre in the direction the (smoothed) nose faces, its
/// length showing how extreme the angle is. Sweep the needle into a faint
/// arc and it charges `terra`, then snaps green the instant it captures.
/// The needle greys out when the face isn't well-framed — the user's cue
/// that they're not lined up even at a good angle. No counts, no text.
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
                        let frac = coverage.needleFrac
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

                drawNeedle(ctx, centre: centre, radius: radius)
            }
        }
    }

    /// The pose pointer. A fixed **centre hub** marks where the nose should
    /// sit (the pointer's pivot); a thin, gradient shaft grows out of it in
    /// the direction the nose faces, tipped with a haloed bead. Colour
    /// encodes state — grey when the face isn't squared up, terra while
    /// charging an uncovered arc, green when pointing at a captured one — so
    /// no words are needed. On the rear dial the whole thing rides the
    /// tracked face, so the hub sits on the resident's nose automatically.
    private func drawNeedle(
        _ ctx: GraphicsContext, centre: CGPoint, radius: CGFloat,
    ) {
        let color = needleColor()

        // ── centre hub: "line your nose up here" (the pivot) + the frontal
        // target. It greens once the straight-ahead frame is captured, so the
        // hub is part of "everything green" — no invisible completion gate.
        let framed = coverage.wellFramed && coverage.faceVisible
        let hubColor: Color = coverage.hasFrontal
            ? NemaraColor.success
            : (framed ? Color.white.opacity(0.92) : NemaraColor.ink3.opacity(0.8))
        let hubR: CGFloat = 12
        ctx.stroke(
            Path(ellipseIn: CGRect(x: centre.x - hubR, y: centre.y - hubR,
                                   width: hubR * 2, height: hubR * 2)),
            with: .color(hubColor), style: StrokeStyle(lineWidth: 1.5),
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: centre.x - 2.5, y: centre.y - 2.5,
                                   width: 5, height: 5)),
            with: .color(hubColor),
        )

        guard coverage.faceVisible, coverage.needleFrac > 0.05 else { return }

        // model angle (0=right, 90=up) → screen (y-down): negate the y.
        let a = coverage.needleAngleDeg * .pi / 180
        let len = radius * coverage.needleFrac
        // start at the hub rim so shaft + hub read as one connected pointer
        let start = CGPoint(x: centre.x + cos(a) * hubR,
                            y: centre.y - sin(a) * hubR)
        let tip = CGPoint(x: centre.x + cos(a) * len,
                          y: centre.y - sin(a) * len)

        // thin gradient shaft — faint at the hub, vivid at the tip
        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: tip)
        ctx.stroke(
            shaft,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.25), color]),
                startPoint: start, endPoint: tip,
            ),
            style: StrokeStyle(lineWidth: 3, lineCap: .round),
        )

        // tip bead: soft halo + solid dot + crisp white core
        let bead: CGFloat = 6
        ctx.fill(
            Path(ellipseIn: CGRect(x: tip.x - bead - 4, y: tip.y - bead - 4,
                                   width: (bead + 4) * 2, height: (bead + 4) * 2)),
            with: .color(color.opacity(0.18)),
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: tip.x - bead, y: tip.y - bead,
                                   width: bead * 2, height: bead * 2)),
            with: .color(color),
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: tip.x - 2, y: tip.y - 2, width: 4, height: 4)),
            with: .color(.white.opacity(0.9)),
        )
    }

    private func needleColor() -> Color {
        // off frame → grey. Green ONLY when the tip is on an arc that's
        // already captured (a finished edge). Everywhere else — travelling
        // out from the hub, or charging an uncovered arc — it's terra. Green
        // must not appear until the needle actually reaches a done edge.
        if !coverage.wellFramed { return NemaraColor.ink3.opacity(0.75) }
        if let s = coverage.currentSegment, coverage.segments[s].covered {
            return NemaraColor.success
        }
        return NemaraColor.terra
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
