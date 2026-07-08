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
/// `framesPerSegment` MOST EXTREME frames above the quality floor.
///
/// Guidance is **visual, not verbal**: the model exposes a pose `needle`
/// (direction + how-far) that the dial draws as a pointer the user steers
/// into the arcs. Capture reads the RAW pose so a held angle registers
/// instantly (smoothing the capture signal just made it feel slow). The
/// needle's *rendering* is smoothed on its own so the pointer glides, and
/// text jitter is tamed by a debounce — neither touches capture speed.
/// Capture requires the face to be fully in frame — a half-cut face can't
/// green an arc — and `wellFramed` going false surfaces the recenter hint.
///
/// Pure logic, no camera/UI/Vision dependency — the camera feeds it
/// `ingest(...)`; the dials render `segments` / `needle*` / `guidance`.
@MainActor
final class FaceCoverageModel: ObservableObject {

    /// Front self-enroll (person turns) vs rear (nurse orbits) — only
    /// affects the wording of the minimal caption.
    enum GuidanceStyle { case subjectTurns, cameraOrbits }

    /// Coarse, debounced state for the single caption line. Kept
    /// dwell-filtered so the text never strobes. The low-quality states
    /// (`tooFar`/`tooDark`/`holdStill`) are ACTIONABLE — they name the
    /// likely fixable cause instead of a bare "hold still". `frontalNeeded`
    /// is the terminal nudge: every arc is filled but the straight-ahead
    /// (hub) frame is still missing, so completion is one face-on away.
    enum Guidance {
        case searching, tooFar, tooDark, holdStill, active, frontalNeeded, done
    }

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
    /// Vision faceCaptureQuality floor for a FRONTAL frame — kept strict so
    /// the most-used pose is high quality. Profiles are relaxed toward
    /// `minQualityFloor` (see `qualityFloor`): faceCaptureQuality is
    /// intrinsically lower for turned faces, so a flat high bar would reject
    /// every profile even in perfect light — and make a "get better light"
    /// message a lie. The ramp keeps "low quality" meaning a fixable cause.
    let minQuality: Float
    /// The relaxed end of the ramp — the floor at a full extreme angle.
    /// Below this, even a profile is too poor to keep.
    let minQualityFloor: Float
    /// frames retained per segment (most-extreme kept)
    let framesPerSegment: Int
    /// frontal frames retained
    let frontalTarget: Int
    /// how long a coarse guidance state must persist before the caption
    /// commits to it (seconds) — kills flicker on transient pose noise.
    let guidanceDwell: TimeInterval

    // ── published state the dials observe ─────────────────────────
    @Published private(set) var segments: [Segment]
    @Published private(set) var frontalCount: Int = 0
    /// arc the nose currently points at; nil when frontal.
    @Published private(set) var currentSegment: Int?
    /// live RAW magnitude (deg). Feeds the capture threshold + guidance; the
    /// dial's charge fill uses `needleFrac` (the smoothed value), not this.
    @Published private(set) var currentMag: Double = 0
    /// live Vision capture quality of the current face (0…1).
    @Published private(set) var currentQuality: Float = 0
    /// whether a face is being detected right now.
    @Published private(set) var faceVisible = false
    /// whether the current face is well-framed enough to capture (centered
    /// + fully in frame). When false the needle greys out — the user's cue
    /// that they're not lined up, even at a good angle.
    @Published private(set) var wellFramed = false

    // ── the visual needle (what replaces the per-arc text) ────────
    /// smoothed nose direction, model degrees (0 = right, 90 = up).
    @Published private(set) var needleAngleDeg: Double = 0
    /// how far the needle reaches toward the rim, 0…1 (1 = capture angle).
    @Published private(set) var needleFrac: Double = 0

    /// coarse, debounced caption state (see `caption(for:style:)`).
    @Published private(set) var guidance: Guidance = .searching

    private var frontal: [Data] = []

    // guidance-debounce state (jitter is calmed HERE, in the text — not by
    // smoothing the capture signal, which only made capture slow). Timed on
    // MONOTONIC uptime, not wall-clock Date(), so an NTP/clock jump mid-
    // enrollment can't freeze or strobe the caption.
    private var guidanceCandidate: Guidance = .searching
    private var guidanceCandidateSince = ProcessInfo.processInfo.systemUptime

    // needle-RENDERING-only pose smoothing (see ingest). Purely cosmetic —
    // capture reads the raw pose, so this adds zero capture lag.
    private var needleYaw = 0.0
    private var needlePitch = 0.0
    private var haveNeedle = false
    private let needleAlpha = 0.4

    // latest diagnostic signals from the camera, used to explain a
    // low-quality frame (see instantGuidance).
    private var lastBrightness: Float = 1     // 0…1 scene luma
    private var lastFaceHeight: Double = 1    // face box height / frame
    /// face smaller than this (fraction of frame height) reads as "too far"
    private let tooFarHeight = 0.28
    /// scene luma below this reads as "too dark"
    private let darkLuma: Float = 0.28

    init(
        segmentCount: Int = 12,
        frontalMaxDeg: Double = 10,
        extremeMinDeg: Double = 22,
        reachTargetDeg: Double = 45,
        minQuality: Float = 0.4,
        minQualityFloor: Float = 0.25,
        framesPerSegment: Int = 2,   // 2 most-extreme frames per arc
        frontalTarget: Int = 2,
        guidanceDwell: TimeInterval = 0.3
    ) {
        self.segmentCount = segmentCount
        self.frontalMaxDeg = frontalMaxDeg
        self.extremeMinDeg = extremeMinDeg
        self.reachTargetDeg = reachTargetDeg
        self.minQuality = minQuality
        self.minQualityFloor = minQualityFloor
        self.framesPerSegment = framesPerSegment
        self.frontalTarget = frontalTarget
        self.guidanceDwell = guidanceDwell
        let arc = 360.0 / Double(segmentCount)
        self.segments = (0..<segmentCount).map {
            Segment(id: $0, centreDeg: (Double($0) + 0.5) * arc,
                    reachTargetDeg: reachTargetDeg)
        }
    }

    // ── ingest ────────────────────────────────────────────────────

    /// Feed one detected face. `framed` is the camera's facing-aware
    /// framing verdict (centered + fully in frame). `jpeg` is an
    /// autoclosure so the caller only pays the encode when we keep the
    /// frame. Returns true if the frame was captured.
    @discardableResult
    func ingest(
        yawDeg: Double,
        pitchDeg: Double,
        quality: Float,
        framed: Bool,
        brightness: Float,
        faceHeight: Double,
        jpeg: @autoclosure () -> Data?
    ) -> Bool {
        // Read the RAW pose directly — a held angle registers instantly.
        // (Smoothing the capture signal added lag = "wait longer in every
        // direction". Jitter is calmed in the debounced caption instead.)
        let mag = (yawDeg * yawDeg + pitchDeg * pitchDeg).squareRoot()
        currentMag = mag
        currentQuality = quality
        faceVisible = true
        wellFramed = framed
        lastBrightness = brightness
        lastFaceHeight = faceHeight

        // Needle RENDERING only: smooth the pose so the pointer glides
        // instead of twitching. Capture uses the raw `mag` above, so this
        // adds zero lag — the mistake before was smoothing the signal that
        // GATES capture; this smooths only the one that DRAWS the needle.
        if haveNeedle {
            needleYaw += needleAlpha * (yawDeg - needleYaw)
            needlePitch += needleAlpha * (pitchDeg - needlePitch)
        } else {
            needleYaw = yawDeg
            needlePitch = pitchDeg
            haveNeedle = true
        }
        let needleMag = (needleYaw * needleYaw + needlePitch * needlePitch).squareRoot()
        needleAngleDeg = atan2(needlePitch, needleYaw) * 180 / .pi
        needleFrac = min(1.0, needleMag / extremeMinDeg)

        var captured = false
        if mag < frontalMaxDeg {
            currentSegment = nil
            if framed, frontal.count < frontalTarget, quality >= qualityFloor(forMag: mag),
               let data = jpeg() {
                frontal.append(data)
                frontalCount = frontal.count
                captured = true
            }
        } else {
            let seg = segmentIndex(yawDeg: yawDeg, pitchDeg: pitchDeg)
            currentSegment = seg
            if framed, mag >= extremeMinDeg, quality >= qualityFloor(forMag: mag) {
                var kept = segments[seg].frames
                if kept.count < framesPerSegment {
                    if let data = jpeg() { kept.append((data, mag, quality)); captured = true }
                } else if let minIdx = kept.indices.min(by: { kept[$0].mag < kept[$1].mag }),
                          mag > kept[minIdx].mag, let data = jpeg() {
                    // replace the least-extreme stored frame with this steeper one
                    kept[minIdx] = (data, mag, quality)
                    captured = true
                }
                if captured {
                    kept.sort { $0.mag > $1.mag }
                    segments[seg].frames = kept
                }
            }
        }
        commitGuidance(instantGuidance())
        return captured
    }

    /// The camera detected no face this frame — collapse the live cursor +
    /// needle so the dial reads "no target." Captured frames are kept.
    func noteFaceLost() {
        faceVisible = false
        wellFramed = false
        currentSegment = nil
        currentMag = 0
        currentQuality = 0
        needleFrac = 0
        haveNeedle = false
        commitGuidance(instantGuidance())
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

    // ── minimal, debounced caption ────────────────────────────────

    /// Quality floor for a pose magnitude — strict when frontal, ramping
    /// down toward `minQualityFloor` as the face turns, matching how
    /// faceCaptureQuality naturally drops for profiles. `nonisolated` so the
    /// camera thread can gate its JPEG encode on the same floor the model
    /// captures with (reads only immutable `let`s).
    nonisolated func qualityFloor(forMag mag: Double) -> Float {
        guard mag > frontalMaxDeg else { return minQuality }
        let span = max(1.0, reachTargetDeg - frontalMaxDeg)
        let t = Float(min(1.0, (mag - frontalMaxDeg) / span))
        return minQuality - t * (minQuality - minQualityFloor)
    }

    /// Instantaneous coarse state, before debouncing.
    private func instantGuidance() -> Guidance {
        if isComplete { return .done }
        if !faceVisible || !wellFramed { return .searching }

        // Quality below the (angle-aware) floor blocks capture — name the
        // likely FIXABLE cause instead of a bare "hold". This must cover the
        // straight-ahead frame too: in a dim room the frontal capture can't
        // clear the strict 0.4 floor, and without this it would silently
        // stall on "look straight ahead to finish" with no reason given.
        let onUncoveredArc = (currentSegment.map { !segments[$0].covered } ?? false)
            && currentMag >= extremeMinDeg
        let seekingFrontal = !hasFrontal && currentMag < frontalMaxDeg
        if onUncoveredArc || seekingFrontal,
           currentQuality < qualityFloor(forMag: currentMag) {
            if lastFaceHeight < tooFarHeight { return .tooFar }
            if lastBrightness < darkLuma { return .tooDark }
            return .holdStill   // distance + light are fine → motion/blur
        }

        // all arcs done, only the straight-ahead (hub) frame is missing
        if coveredCount == segmentCount && !hasFrontal { return .frontalNeeded }
        return .active
    }

    /// Only let the caption change once a new state has persisted for
    /// `guidanceDwell` (completion snaps immediately).
    private func commitGuidance(_ instant: Guidance) {
        let now = ProcessInfo.processInfo.systemUptime
        if instant != guidanceCandidate {
            guidanceCandidate = instant
            guidanceCandidateSince = now
        }
        guard guidance != guidanceCandidate else { return }
        if guidanceCandidate == .done || now - guidanceCandidateSince >= guidanceDwell {
            guidance = guidanceCandidate
        }
    }

    /// The single caption shown under the static instruction. Most of the
    /// time it's nil — the needle carries the guidance. Only the two
    /// "stuck" states speak up, and only after they've settled.
    static func caption(for g: Guidance, style: GuidanceStyle) -> String? {
        switch g {
        case .searching:
            // front: the recovery line — shown whenever the face is cut off
            // or the needle can't go green (not framed). Names the hub so
            // it's unambiguous which of the two circles to line up with.
            return style == .cameraOrbits ? "Point the camera at their face"
                                          : "Re-center your face on the inner circle"
        case .tooFar:
            return style == .cameraOrbits ? "Move a little closer to them"
                                          : "Move a little closer"
        case .tooDark:
            return style == .cameraOrbits ? "Move them into better light"
                                          : "Find brighter light"
        case .holdStill:
            return "Hold still"
        case .frontalNeeded:
            return style == .cameraOrbits ? "Now face them head-on to finish"
                                          : "Now look straight ahead to finish"
        case .active, .done:
            return nil
        }
    }

    // ── geometry ──────────────────────────────────────────────────

    private func segmentIndex(yawDeg: Double, pitchDeg: Double) -> Int {
        var a = atan2(pitchDeg, yawDeg) * 180 / .pi   // −180…180, 0 = right
        if a < 0 { a += 360 }
        let arc = 360.0 / Double(segmentCount)
        return min(segmentCount - 1, Int(a / arc))
    }
}
