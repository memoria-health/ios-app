import AVFoundation
import SwiftUI

/// Guided face-enrollment entry point (replaces the old 12-tap
/// `FaceEnrollmentStepView`). Same call signature — `FaceEnrollmentView(
/// patientId:) { onComplete }` — invoked from onboarding and from
/// PatientSettings re-enrollment.
///
/// Picks a camera: **Rear** (default — the nurse points at the resident
/// and walks around them) or **Front** (self-enroll, mirrored FaceID
/// dial). Both feed one shared `FaceCoverageModel`; on submit we upload
/// the auto-selected, pose-diverse frames through the existing
/// `submitFaceEmbeddings` endpoint.
struct FaceEnrollmentView: View {
    let patientId: UUID
    let onComplete: () -> Void

    @Environment(AppEnvironment.self) private var env

    /// One shared coverage model across camera switches.
    @StateObject private var coverage = FaceCoverageModel()
    @State private var facing: EnrollmentVisionCamera.Facing = .rear
    @State private var auth: AuthState = .unknown
    @State private var isSubmitting = false
    @State private var submitError: String?

    /// Client-side ceiling; keep in step with the backend cap.
    private let maxUpload = 40

    private enum AuthState { case unknown, authorized, denied }

    var body: some View {
        VStack(spacing: 0) {
            header
            picker
            child
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(NemaraColor.paper)
        .onAppear(perform: requestAccess)
    }

    // MARK: sections

    private var header: some View {
        HStack {
            Button(action: onComplete) {
                Text("Skip").font(NemaraFont.bodySmall).foregroundStyle(NemaraColor.ink3)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Face enrollment")
                .font(NemaraFont.bodyLarge.weight(.semibold))
                .foregroundStyle(NemaraColor.ink)
            Spacer()
            Text("Skip").opacity(0).font(NemaraFont.bodySmall)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .bottom)
    }

    private var picker: some View {
        Picker("Camera", selection: $facing) {
            Text("Point at them").tag(EnrollmentVisionCamera.Facing.rear)
            Text("Myself").tag(EnrollmentVisionCamera.Facing.front)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    @ViewBuilder private var child: some View {
        let authorized = auth == .authorized
        switch facing {
        case .front:
            FrontEnrollmentView(coverage: coverage, authorized: authorized).id("front")
        case .rear:
            RearEnrollmentView(coverage: coverage, authorized: authorized).id("rear")
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            ProgressView(value: coverage.progress)
                .tint(NemaraColor.terra)
                .padding(.horizontal, 4)
            if let submitError {
                Text(submitError)
                    .font(NemaraFont.bodySmall).foregroundStyle(NemaraColor.terra)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            NemaraButton(
                isSubmitting ? "Submitting…" : "Save \(coverage.allFrames().count) captures",
                variant: .primary,
                block: true,
                action: submit,
            )
            .disabled(!coverage.isSubmittable || isSubmitting)
            .opacity((!coverage.isSubmittable || isSubmitting) ? 0.5 : 1)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }

    // MARK: actions

    private func requestAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            auth = .authorized
        case .notDetermined:
            Task {
                let ok = await AVCaptureDevice.requestAccess(for: .video)
                auth = ok ? .authorized : .denied
            }
        default:
            auth = .denied
        }
    }

    private func submit() {
        let photos = Array(coverage.allFrames().prefix(maxUpload))
        guard !photos.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        submitError = nil
        Task {
            defer { isSubmitting = false }
            do {
                _ = try await env.api.submitFaceEmbeddings(patientId, photos: photos)
                onComplete()
            } catch {
                submitError = "Submit failed: \(error.localizedDescription)"
                NSLog("[FaceEnrollment] submit failed: %@", "\(error)")
            }
        }
    }
}
