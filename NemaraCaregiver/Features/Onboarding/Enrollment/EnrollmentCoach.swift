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
