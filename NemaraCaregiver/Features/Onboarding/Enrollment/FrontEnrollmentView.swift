import SwiftUI

/// Front-camera self-enroll — the FaceID-style nose-dial. A mirrored
/// circular preview sits inside the coverage ring; the arc you point your
/// nose at charges up and snaps green when captured. On completion the
/// preview is replaced by a locked green-tick + review of the captures.
struct FrontEnrollmentView: View {
    @ObservedObject var coverage: FaceCoverageModel
    let authorized: Bool

    @StateObject private var camera: EnrollmentVisionCamera

    init(coverage: FaceCoverageModel, authorized: Bool) {
        self.coverage = coverage
        self.authorized = authorized
        _camera = StateObject(
            wrappedValue: EnrollmentVisionCamera(facing: .front, coverage: coverage),
        )
    }

    private let previewSize: CGFloat = 300

    var body: some View {
        Group {
            if coverage.isComplete {
                EnrollmentCompleteView()
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
        VStack(spacing: 22) {
            ZStack {
                if authorized && camera.isConfigured {
                    EnrollmentCameraPreview(session: camera.session, mirrored: true)
                        .frame(width: previewSize, height: previewSize)
                        .clipShape(Circle())
                } else {
                    Circle().fill(NemaraColor.card)
                        .frame(width: previewSize, height: previewSize)
                        .overlay(placeholder)
                }
                CoverageDial(coverage: coverage, lineWidth: 14)
                    .frame(width: previewSize + 38, height: previewSize + 38)
            }
            .frame(maxWidth: .infinity)

            Text("Slowly roll your head so your nose fills the ring")
                .font(NemaraFont.title3)
                .foregroundStyle(NemaraColor.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(.top, 16)
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
