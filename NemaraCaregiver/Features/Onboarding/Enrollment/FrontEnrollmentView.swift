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
        .enrollmentCameraLifecycle(camera: camera, coverage: coverage, authorized: authorized)
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
                        .overlay(EnrollmentPlaceholder(
                            authorized: authorized, error: camera.setupError,
                        ))
                }
                CoverageDial(coverage: coverage, lineWidth: 14)
                    .frame(width: previewSize + 38, height: previewSize + 38)
            }
            .frame(maxWidth: .infinity)

            EnrollmentGuidanceBanner(
                headline: "Slowly turn your head in every direction",
                caption: FaceCoverageModel.caption(for: coverage.guidance, style: .subjectTurns),
            )
            .padding(.horizontal, 20)
        }
        .padding(.top, 16)
    }
}
