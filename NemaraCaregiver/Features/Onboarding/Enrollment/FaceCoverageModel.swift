import Foundation
import SwiftUI

/// Directional pose-coverage engine shared by both enrollment dials
/// (front FaceID-style nose-dial + rear auto-tracking ring).
///
/// A detected face's head pose is mapped to a point on a dial:
///   x = yaw   (turning right = +)      y = pitch (looking up = +)
///   angle     = atan2(y, x)            // which direction the nose points
///   magnitude = hypot(x, y)  (degrees) // how EXTREME the angle is
///
/// The dial is split into `segmentCount` equal arcs. A segment is
/// "covered" once we've captured at least one good-quality frame whose
/// direction lands in that arc AND whose magnitude clears `extremeMinDeg`
/// (so a token tilt doesn't count — we want real profiles). We also take
/// a dedicated frontal capture (magnitude ~ 0). Per segment we keep the
/// `framesPerSegment` MOST EXTREME frames above the quality floor, because
/// the extreme poses are exactly what today's front-selfie gallery lacks.
///
/// Pure logic, no camera/UI/Vision dependency — the camera feeds it
/// `ingest(...)`; the dials render `segments` / `frontalCount` / `progress`.
@MainActor
final class FaceCoverageModel: ObservableObject {

    /// How we phrase the "go here next" nudge.
    ///   - subjectTurns:  front self-enroll — the person turns their head
    ///   - cameraOrbits:  rear enroll — the NURSE walks around the resident
    enum GuidanceStyle { case subjectTurns, cameraOrbits }

    /// One directional arc of the dial.
    struct Segment: Identifiable {
        let id: Int
        /// centre direction of this arc, degrees (0 = right, 90 = up)
        let centreDeg: Double
        /// magnitude (deg) at which this arc is considered fully captured —
        /// deliberately steeper than FaceID so we get near-profile views
        let reachTargetDeg: Double
        /// kept frames, most-extreme first: (jpeg, magnitude, quality)
        fileprivate(set) var frames: [(data: Data, mag: Double, q: Float)] = []
        var covered: Bool { !frames.isEmpty }
        /// best (largest) magnitude captured here — drives a "reach" tint
        var reachedDeg: Double { frames.map(\.mag).max() ?? 0 }
        /// reached a genuinely extreme angle (past the FaceID-ish range)
        var fullyReached: Bool { reachedDeg >= reachTargetDeg }
    }

    // ── tuning ────────────────────────────────────────────────────
    let segmentCount: Int
    /// below this magnitude we treat the pose as "frontal"
    let frontalMaxDeg: Double
    /// a directional capture must clear this magnitude to REGISTER an arc
    let extremeMinDeg: Double
    /// magnitude an arc must reach to count as fully/extremely covered —
    /// steeper than FaceID (which barely leaves near-frontal). Vision's
    /// yaw estimate degrades near true profile (~±70°), so this is the
    /// practical extreme ceiling, tune on device.
    let reachTargetDeg: Double
    /// minimum Vision faceCaptureQuality to keep a frame
    let minQuality: Float
    /// frames retained per segment (most-extreme kept)
    let framesPerSegment: Int
    /// frontal frames retained
    let frontalTarget: Int

    // ── published state the dials observe ─────────────────────────
    @Published private(set) var segments: [Segment]
    @Published private(set) var frontalCount: Int = 0
    /// segment the nose currently points at (for the moving target dot);
    /// nil when frontal.
    @Published private(set) var currentSegment: Int?
    /// live magnitude, for a "turn further" nudge
    @Published private(set) var currentMag: Double = 0

    private var frontal: [Data] = []

    init(
        segmentCount: Int = 12,
        frontalMaxDeg: Double = 10,
        extremeMinDeg: Double = 22,
        reachTargetDeg: Double = 45,
        minQuality: Float = 0.4,
        framesPerSegment: Int = 2,   // 2 most-extreme frames per arc
        frontalTarget: Int = 2
    ) {
        self.segmentCount = segmentCount
        self.frontalMaxDeg = frontalMaxDeg
        self.extremeMinDeg = extremeMinDeg
        self.reachTargetDeg = reachTargetDeg
        self.minQuality = minQuality
        self.framesPerSegment = framesPerSegment
        self.frontalTarget = frontalTarget
        let arc = 360.0 / Double(segmentCount)
        self.segments = (0..<segmentCount).map {
            Segment(id: $0, centreDeg: (Double($0) + 0.5) * arc,
                    reachTargetDeg: reachTargetDeg)
        }
    }

    // ── ingest ────────────────────────────────────────────────────

    /// Feed one detected face. `jpeg` is an autoclosure so the caller
    /// only pays the encode when we actually decide to keep the frame.
    /// Returns true if the frame was captured.
    @discardableResult
    func ingest(
        yawDeg: Double,
        pitchDeg: Double,
        quality: Float,
        jpeg: @autoclosure () -> Data?
    ) -> Bool {
        let mag = (yawDeg * yawDeg + pitchDeg * pitchDeg).squareRoot()
        currentMag = mag

        // frontal
        if mag < frontalMaxDeg {
            currentSegment = nil
            guard frontal.count < frontalTarget, quality >= minQuality,
                  let data = jpeg() else { return false }
            frontal.append(data)
            frontalCount = frontal.count
            return true
        }

        let seg = segmentIndex(yawDeg: yawDeg, pitchDeg: pitchDeg)
        currentSegment = seg
        guard mag >= extremeMinDeg, quality >= minQuality else { return false }

        var kept = segments[seg].frames
        if kept.count < framesPerSegment {
            guard let data = jpeg() else { return false }
            kept.append((data, mag, quality))
        } else {
            // replace the least-extreme stored frame if this one is more so
            guard let minIdx = kept.indices.min(by: { kept[$0].mag < kept[$1].mag }),
                  mag > kept[minIdx].mag, let data = jpeg() else { return false }
            kept[minIdx] = (data, mag, quality)
        }
        kept.sort { $0.mag > $1.mag }
        segments[seg].frames = kept
        return true
    }

    // ── queries the dials + upload use ────────────────────────────

    var coveredCount: Int { segments.filter(\.covered).count }
    /// arcs pushed all the way to the extreme target — the real goal
    var fullyReachedCount: Int { segments.filter(\.fullyReached).count }
    var progress: Double { Double(coveredCount) / Double(segmentCount) }
    var hasFrontal: Bool { frontalCount > 0 }
    /// every arc touched at least to the minimum extreme
    var isComplete: Bool { hasFrontal && coveredCount == segmentCount }
    /// every arc pushed to the steep target — best-case coverage
    var isFullyExtreme: Bool { hasFrontal && fullyReachedCount == segmentCount }
    /// enough to submit usefully (frontal + a majority of the cone)
    var isSubmittable: Bool {
        hasFrontal && coveredCount >= Int(ceil(Double(segmentCount) * 0.5))
    }

    /// Every kept frame for upload — frontal first, then each covered arc.
    func allFrames() -> [Data] { frontal + segments.flatMap { $0.frames.map(\.data) } }

    /// Nudge toward the nearest arc not yet pushed to the extreme target.
    /// `subjectTurns` (front) tells the person to turn; `cameraOrbits`
    /// (rear) tells the NURSE to reposition around the resident.
    func nextHint(style: GuidanceStyle) -> String {
        guard let target = nearestIncomplete() else {
            return style == .cameraOrbits
                ? "All angles captured — you're set"
                : "All angles captured"
        }
        return Self.phrase(forDeg: segments[target].centreDeg, style: style)
    }

    // ── geometry ──────────────────────────────────────────────────

    private func segmentIndex(yawDeg: Double, pitchDeg: Double) -> Int {
        var a = atan2(pitchDeg, yawDeg) * 180 / .pi   // −180…180, 0 = right
        if a < 0 { a += 360 }
        let arc = 360.0 / Double(segmentCount)
        return min(segmentCount - 1, Int(a / arc))
    }

    /// Nearest arc not yet pushed to the steep target (falls back to any
    /// uncovered). Keeps nudging toward extremes, not just first-touch.
    private func nearestIncomplete() -> Int? {
        let pending = segments.filter { !$0.fullyReached }
        guard !pending.isEmpty else { return nil }
        if let cur = currentSegment {
            return pending.min {
                Self.arcDist($0.centreDeg, segments[cur].centreDeg)
                    < Self.arcDist($1.centreDeg, segments[cur].centreDeg)
            }?.id
        }
        return pending.first?.id
    }

    private static func arcDist(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    /// Map a dial direction to a plain-language nudge (8-way compass;
    /// 0° = right, 90° = up). `cameraOrbits` moves the NURSE around the
    /// resident; `subjectTurns` tells the person to turn their own head.
    static func phrase(forDeg deg: Double, style: GuidanceStyle) -> String {
        let d = (deg.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let oct = Int((d + 22.5) / 45) % 8
        switch style {
        case .cameraOrbits:
            switch oct {
            case 0: return "Move around to their right"
            case 1: return "Move to their right and raise the camera"
            case 2: return "Raise the camera above their eye line"
            case 3: return "Move to their left and raise the camera"
            case 4: return "Move around to their left"
            case 5: return "Move to their left and lower the camera"
            case 6: return "Lower the camera below their eye line"
            default: return "Move to their right and lower the camera"
            }
        case .subjectTurns:
            switch oct {
            case 0: return "Turn your head right"
            case 1: return "Look up and to the right"
            case 2: return "Tilt your head up"
            case 3: return "Look up and to the left"
            case 4: return "Turn your head left"
            case 5: return "Look down and to the left"
            case 6: return "Tilt your head down"
            default: return "Look down and to the right"
            }
        }
    }
}
