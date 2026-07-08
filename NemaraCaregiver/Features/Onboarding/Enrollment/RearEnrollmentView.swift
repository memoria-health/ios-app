import SwiftUI

/// Rear-camera enroll — the nurse points the phone at the resident and
/// walks around them. A coverage ring **locks onto and tracks** the
/// resident's face (eased so it glides), each arc snapping green as its
/// angle is captured. The hint tells the NURSE where to move next. On
/// completion the feed is replaced by a locked green-tick + review.
struct RearEnrollmentView: View {
    @ObservedObject var coverage: FaceCoverageModel
    let authorized: Bool

    @StateObject private var camera: EnrollmentVisionCamera

    init(coverage: FaceCoverageModel, authorized: Bool) {
        self.coverage = coverage
        self.authorized = authorized
        _camera = StateObject(
            wrappedValue: EnrollmentVisionCamera(facing: .rear, coverage: coverage),
        )
    }

    var body: some View {
        Group {
            if coverage.isComplete {
                EnrollmentCompleteView()
                    .background(NemaraColor.paper)
            } else {
                capturing
            }
        }
        .onAppear { if authorized { camera.configure(); camera.start() } }
        .onDisappear { camera.stop() }
        .onChange(of: authorized) { _, ok in if ok { camera.configure(); camera.start() } }
        .onChange(of: coverage.coveredCount) { old, new in
            // suppress the arc buzz when this capture also completes —
            // the completion haptic below is the sole cue for that moment
            if new > old && !coverage.isComplete { EnrollmentHaptics.arcCaptured() }
        }
        .onChange(of: coverage.frontalCount) { old, new in
            if new > old && !coverage.isComplete { EnrollmentHaptics.arcCaptured() }
        }
        .onChange(of: coverage.isComplete) { _, done in
            if done { camera.stop(); EnrollmentHaptics.completed() }
        }
    }

    private var capturing: some View {
        ZStack {
            if authorized && camera.isConfigured {
                EnrollmentCameraPreview(session: camera.session, mirrored: false)
                    .ignoresSafeArea()
            } else {
                NemaraColor.card.ignoresSafeArea().overlay(placeholder)
            }

            // ring anchored to the tracked face
            GeometryReader { geo in
                if let box = camera.faceBox, camera.faceVisible {
                    let rect = EnrollmentGeometry.viewRect(
                        normVision: box, in: geo.size, mirrored: false,
                    )
                    let dia = max(rect.width, rect.height) * 1.9
                    CoverageDial(coverage: coverage, lineWidth: 12)
                        .frame(width: dia, height: dia)
                        .position(x: rect.midX, y: rect.midY)
                        .animation(.easeOut(duration: 0.18), value: camera.faceBox)
                }
            }

            VStack {
                hintBanner
                Spacer()
            }
        }
    }

    // Fixed instruction + a calm, debounced caption. The live guidance is
    // the tracked pose needle on the dial, not text.
    private var hintBanner: some View {
        EnrollmentGuidanceBanner(
            headline: "Slowly move around to every side of them",
            caption: FaceCoverageModel.caption(for: coverage.guidance, style: .cameraOrbits),
            onDark: true,
        )
    }

    @ViewBuilder private var placeholder: some View {
        if !authorized {
            VStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 30)).foregroundStyle(NemaraColor.ink3)
                Text("Camera access needed")
                    .font(NemaraFont.bodySmall).foregroundStyle(NemaraColor.ink3)
            }
        } else if let err = camera.setupError {
            Text(err).font(NemaraFont.caption).foregroundStyle(NemaraColor.terra)
                .multilineTextAlignment(.center).padding(24)
        } else {
            ProgressView()
        }
    }
}
