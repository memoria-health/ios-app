import SwiftUI
import UIKit

/// Minimal guidance text shared by both enrollment dials.
///
/// Guidance is now visual — the dial's pose needle shows direction and how
/// far, colouring itself through the states. So this is just a fixed
/// instruction plus one **debounced** caption that only speaks up for the
/// two "stuck" states (no clear face / holding for a sharp frame). The
/// caption comes from `FaceCoverageModel.guidance`, which dwell-filters
/// its transitions, so the text never strobes the way the old per-arc
/// coaching did.
struct EnrollmentGuidanceBanner: View {
    /// fixed instruction — never changes, so it can't jitter
    let headline: String
    /// optional debounced caption (nil most of the time)
    let caption: String?
    /// true when drawn over the live rear-camera video (light on dark).
    var onDark: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            Text(headline)
                .font(NemaraFont.title3.weight(.semibold))
                .foregroundStyle(onDark ? Color.white : NemaraColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Captions only appear when the user needs to DO something
            // (recover framing, hold still, finish face-on), so give them
            // attention weight + colour rather than a faint grey footnote.
            Text(caption ?? " ")
                .font(NemaraFont.bodySmall.weight(.semibold))
                .foregroundStyle(onDark ? Color.white.opacity(0.95) : NemaraColor.terra)
                .multilineTextAlignment(.center)
                .opacity(caption == nil ? 0 : 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(onDark ? Color.black.opacity(0.4) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: caption)
    }
}

/// Shared no-camera placeholder for both enrollment dials. Prompts for
/// access and — when access was DENIED — offers a deep-link into Settings
/// so the caregiver can recover without abandoning the flow. Paired with
/// the scene-phase re-check in `FaceEnrollmentView`, granting access in
/// Settings and returning re-enables the camera automatically.
struct EnrollmentPlaceholder: View {
    let authorized: Bool
    let error: String?

    var body: some View {
        if !authorized {
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 30)).foregroundStyle(NemaraColor.ink3)
                Text("Camera access needed")
                    .font(NemaraFont.bodySmall).foregroundStyle(NemaraColor.ink3)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(NemaraFont.bodySmall.weight(.semibold))
                .foregroundStyle(NemaraColor.terra)
            }
        } else if let error {
            Text(error).font(NemaraFont.caption).foregroundStyle(NemaraColor.terra)
                .multilineTextAlignment(.center).padding(24)
        } else {
            ProgressView()
        }
    }
}

/// Camera start/stop + milestone-haptics wiring shared by the front and rear
/// dials (previously duplicated byte-for-byte in both). Starts on appear /
/// when access is granted, stops on disappear + completion, and fires the
/// capture / completion haptics — the arc buzz suppressed on the capture that
/// also completes, so completion is a single clean cue.
private struct EnrollmentCameraLifecycle: ViewModifier {
    let camera: EnrollmentVisionCamera
    @ObservedObject var coverage: FaceCoverageModel
    let authorized: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { if authorized { camera.configure(); camera.start() } }
            .onDisappear { camera.stop() }
            .onChange(of: authorized) { _, ok in if ok { camera.configure(); camera.start() } }
            .onChange(of: coverage.coveredCount) { old, new in
                if new > old && !coverage.isComplete { EnrollmentHaptics.arcCaptured() }
            }
            .onChange(of: coverage.frontalCount) { old, new in
                if new > old && !coverage.isComplete { EnrollmentHaptics.arcCaptured() }
            }
            .onChange(of: coverage.isComplete) { _, done in
                if done { camera.stop(); EnrollmentHaptics.completed() }
            }
    }
}

extension View {
    /// Attach the shared enrollment camera lifecycle + milestone haptics.
    func enrollmentCameraLifecycle(
        camera: EnrollmentVisionCamera,
        coverage: FaceCoverageModel,
        authorized: Bool,
    ) -> some View {
        modifier(EnrollmentCameraLifecycle(
            camera: camera, coverage: coverage, authorized: authorized,
        ))
    }
}

/// Light haptic feedback for enrollment milestones. Kept out of the pure,
/// UI-free `FaceCoverageModel` so the model stays testable and headless.
enum EnrollmentHaptics {
    /// A single arc (or the frontal frame) was just captured.
    static func arcCaptured() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    /// Every angle captured — enrollment complete.
    static func completed() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
