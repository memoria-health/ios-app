import AVFoundation
import SwiftUI

/// Step 2 of the new-patient onboarding flow (and standalone
/// re-enrollment entry from PatientSettings).
///
/// Flow:
///   1. Caregiver sees the live front-camera preview with a circular
///      crop overlay
///   2. A prompt at the top instructs them on the current angle
///      ("Look straight at the camera", "Tilt your head slightly up",
///      etc. — see EnrollmentPrompts.all)
///   3. They tap a capture button; the current frame is snapshotted as
///      JPEG and added to the thumbnail strip
///   4. The prompt advances. When all prompts are captured, the
///      submit button enables. They can also remove individual
///      thumbnails and re-capture
///   5. On submit, all photos are POSTed to the backend. Success
///      dismisses; failure shows an inline error
///
/// The "Skip for now" exit at the header lets caregivers leave
/// enrollment incomplete — the patient row exists, the Re-ID system
/// just stays disabled for them. PatientSettings nags them to come
/// back and finish.
struct FaceEnrollmentStepView: View {
    let patientId: UUID
    /// Called after successful submit OR caregiver-initiated skip.
    /// Parent dismisses or transitions on this callback.
    let onComplete: () -> Void

    @Environment(AppEnvironment.self) private var env
    @StateObject private var camera = CameraPreviewModel()

    @State private var capturedPhotos: [Data] = []
    @State private var currentPromptIndex: Int = 0
    @State private var isCapturing: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var submitError: String?
    @State private var cameraAuthorized: Bool = false

    private var allPromptsCaptured: Bool {
        capturedPhotos.count >= EnrollmentPrompts.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    cameraSection
                    EnrollmentCapturedThumbnails(photos: $capturedPhotos)
                }
                .padding(.vertical, 16)
            }
            footer
        }
        .background(NemaraColor.paper)
        .onAppear(perform: setupCamera)
        .onDisappear { camera.stop() }
    }

    // MARK: - sections

    private var header: some View {
        HStack {
            Button { onComplete() } label: {
                Text("Skip")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink3)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Step 2 of 2 · Face enrollment")
                .font(NemaraFont.bodyLarge.weight(.semibold))
                .foregroundStyle(NemaraColor.ink)
            Spacer()
            // Empty placeholder for symmetry.
            Text("Skip").opacity(0).font(NemaraFont.bodySmall)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .bottom)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("PATIENT IDENTITY", color: NemaraColor.terra)
            Text("Help Memoria recognize \(patientName())")
                .font(NemaraFont.title2)
                .kerning(-0.4)
                .foregroundStyle(NemaraColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(
                "Take \(EnrollmentPrompts.count) photos from a few angles so we can tell them apart from others in their household. The photos stay private to your account.",
            )
            .font(NemaraFont.bodySmall)
            .foregroundStyle(NemaraColor.ink3)
            .lineSpacing(2)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var cameraSection: some View {
        VStack(spacing: 12) {
            ZStack {
                if cameraAuthorized && camera.isConfigured {
                    CameraPreviewView(session: camera.session)
                        .frame(width: 280, height: 280)
                        .clipShape(Circle())
                        .overlay(
                            Circle().strokeBorder(NemaraColor.terra, lineWidth: 3),
                        )
                } else {
                    Circle()
                        .fill(NemaraColor.card)
                        .frame(width: 280, height: 280)
                        .overlay(
                            Circle().strokeBorder(NemaraColor.line, lineWidth: 1),
                        )
                        .overlay(cameraPlaceholderContent)
                }
            }
            .frame(maxWidth: .infinity)

            // Prompt below the preview circle.
            VStack(spacing: 4) {
                if allPromptsCaptured {
                    Text("All angles captured")
                        .font(NemaraFont.title3)
                        .foregroundStyle(NemaraColor.terra)
                } else {
                    Text(EnrollmentPrompts.all[currentPromptIndex])
                        .font(NemaraFont.title3)
                        .foregroundStyle(NemaraColor.ink)
                        .multilineTextAlignment(.center)
                }
                Text("\(capturedPhotos.count) of \(EnrollmentPrompts.count) captured")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
            .padding(.horizontal, 20)

            // Capture button. Disabled mid-capture or when we've
            // reached the prompt count (caregiver can still remove a
            // thumbnail to free up a slot).
            captureButton
                .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var cameraPlaceholderContent: some View {
        if !cameraAuthorized {
            VStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(NemaraColor.ink3)
                Text("Camera access needed")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink3)
            }
        } else if let err = camera.setupError {
            Text(err)
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.terra)
                .padding(.horizontal, 24)
                .multilineTextAlignment(.center)
        } else {
            ProgressView()
        }
    }

    private var captureButton: some View {
        Button(action: capture) {
            HStack(spacing: 10) {
                if isCapturing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "camera.fill")
                }
                Text(isCapturing ? "Capturing…" : "Capture photo")
                    .font(NemaraFont.bodyLarge.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(allPromptsCaptured ? NemaraColor.ink3 : NemaraColor.terra)
            .foregroundStyle(.white)
            .clipShape(
                RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous),
            )
        }
        .buttonStyle(.plain)
        .disabled(!cameraAuthorized || isCapturing || allPromptsCaptured)
        .opacity((cameraAuthorized && !allPromptsCaptured) ? 1 : 0.5)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let submitError {
                Text(submitError)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.terra)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            NemaraButton(
                isSubmitting ? "Submitting…" : "Submit \(capturedPhotos.count) photos",
                variant: .primary,
                block: true,
                action: submit,
            )
            .disabled(capturedPhotos.isEmpty || isSubmitting)
            .opacity((capturedPhotos.isEmpty || isSubmitting) ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }

    // MARK: - actions

    private func patientName() -> String {
        if let patient = env.api.patients.first(where: { $0.id == patientId }) {
            return patient.preferredName
        }
        return "your patient"
    }

    private func setupCamera() {
        Task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .authorized:
                cameraAuthorized = true
            case .notDetermined:
                cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            default:
                cameraAuthorized = false
            }
            if cameraAuthorized {
                camera.configure()
                camera.start()
            }
        }
    }

    private func capture() {
        guard cameraAuthorized, !isCapturing else { return }
        Task {
            isCapturing = true
            defer { isCapturing = false }
            guard let data = await camera.captureJPEG() else {
                submitError = "Could not capture from camera. Try again."
                return
            }
            capturedPhotos.append(data)
            if currentPromptIndex < EnrollmentPrompts.count - 1 {
                currentPromptIndex += 1
            }
        }
    }

    private func submit() {
        guard !capturedPhotos.isEmpty, !isSubmitting else { return }
        Task {
            isSubmitting = true
            submitError = nil
            defer { isSubmitting = false }
            do {
                _ = try await env.api.submitFaceEmbeddings(
                    patientId, photos: capturedPhotos,
                )
                onComplete()
            } catch {
                submitError = "Submit failed: \(error.localizedDescription)"
                NSLog("[FaceEnrollment] submit failed: %@", "\(error)")
            }
        }
    }
}
