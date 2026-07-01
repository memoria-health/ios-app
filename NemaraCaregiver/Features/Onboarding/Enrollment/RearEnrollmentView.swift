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
                EnrollmentCompleteView(frames: coverage.allFrames())
                    .background(NemaraColor.paper)
            } else {
                capturing
            }
        }
        .onAppear { if authorized { camera.configure(); camera.start() } }
        .onDisappear { camera.stop() }
        .onChange(of: authorized) { _, ok in if ok { camera.configure(); camera.start() } }
        .onChange(of: coverage.isComplete) { _, done in if done { camera.stop() } }
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
    }

    private var hintBanner: some View {
        Text(coverage.nextHint(style: .cameraOrbits))
            .font(NemaraFont.title3)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .animation(.default, value: coverage.currentSegment)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.4))
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
