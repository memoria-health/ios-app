import SwiftUI

/// Rear-camera enroll — the nurse points the phone at the resident and
/// walks around them. A coverage ring **locks onto and tracks** the
/// resident's face (Vision face box → view coords, eased so it glides),
/// filling arcs as each angle is captured. The hint guides the NURSE to
/// reposition ("Move around to their left") rather than asking the
/// resident to move. Captures are automatic.
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
        ZStack {
            if authorized && camera.isConfigured {
                EnrollmentCameraPreview(session: camera.session, mirrored: false)
                    .ignoresSafeArea()
            } else {
                NemaraColor.card.ignoresSafeArea().overlay(placeholder)
            }

            // tracking ring anchored to the detected face
            GeometryReader { geo in
                if let box = camera.faceBox, camera.faceVisible {
                    let rect = EnrollmentGeometry.viewRect(
                        normVision: box, in: geo.size, mirrored: false,
                    )
                    let dia = max(rect.width, rect.height) * 1.9
                    CoverageDial(coverage: coverage, lineWidth: 10, showTarget: false)
                        .frame(width: dia, height: dia)
                        .position(x: rect.midX, y: rect.midY)
                        .animation(.easeOut(duration: 0.18), value: camera.faceBox)
                }
            }

            VStack {
                hintBanner
                Spacer()
                if !camera.faceVisible && camera.isConfigured {
                    Text("Point the camera at the resident's face")
                        .font(NemaraFont.bodyLarge.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 28)
                }
            }
        }
        .onAppear { if authorized { camera.configure(); camera.start() } }
        .onDisappear { camera.stop() }
        .onChange(of: authorized) { _, ok in
            if ok { camera.configure(); camera.start() }
        }
    }

    private var hintBanner: some View {
        VStack(spacing: 4) {
            Text(coverage.isComplete
                 ? "All angles captured"
                 : coverage.nextHint(style: .cameraOrbits))
                .font(NemaraFont.title3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .animation(.default, value: coverage.currentSegment)
            Text("\(coverage.coveredCount) of \(coverage.segmentCount) angles · \(coverage.fullyReachedCount) at full extreme")
                .font(NemaraFont.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.4))
    }

    @ViewBuilder private var placeholder: some View {
        if !authorized {
            VStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(NemaraColor.ink3)
                Text("Camera access needed")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink3)
            }
        } else if let err = camera.setupError {
            Text(err).font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.terra)
                .multilineTextAlignment(.center).padding(24)
        } else {
            ProgressView()
        }
    }
}
