import SwiftUI

/// Front-camera self-enroll — the FaceID-style nose-dial. A mirrored
/// circular preview sits inside the coverage ring; a pulsing target dot
/// shows where to point the nose next, and arcs fill green as each
/// extreme is reached. Captures happen automatically (no shutter).
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
        VStack(spacing: 20) {
            ZStack {
                if authorized && camera.isConfigured {
                    EnrollmentCameraPreview(session: camera.session, mirrored: true)
                        .frame(width: previewSize, height: previewSize)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(NemaraColor.card)
                        .frame(width: previewSize, height: previewSize)
                        .overlay(placeholder)
                }
                CoverageDial(coverage: coverage, lineWidth: 12, showTarget: true)
                    .frame(width: previewSize + 34, height: previewSize + 34)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text(coverage.isComplete
                     ? "All angles captured"
                     : coverage.nextHint(style: .subjectTurns))
                    .font(NemaraFont.title3)
                    .foregroundStyle(coverage.isComplete ? NemaraColor.success : NemaraColor.ink)
                    .multilineTextAlignment(.center)
                    .animation(.default, value: coverage.currentSegment)
                Text("\(coverage.coveredCount) of \(coverage.segmentCount) angles · \(coverage.fullyReachedCount) at full extreme")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 12)
        .onAppear { if authorized { camera.configure(); camera.start() } }
        .onDisappear { camera.stop() }
        .onChange(of: authorized) { _, ok in
            if ok { camera.configure(); camera.start() }
        }
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
            Text(err)
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.terra)
                .multilineTextAlignment(.center)
                .padding(24)
        } else {
            ProgressView()
        }
    }
}
