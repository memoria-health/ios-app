import PhotosUI
import SwiftUI
import UIKit

/// "Settings" sub-tab. Profile, feedback entry, remove patient.
///
/// Monitoring (pause/resume all cameras) is owned solely by the Live
/// tab's "Disconnect all cameras" button — both drove the same
/// patient-level pause flag, so the duplicate Settings toggle was
/// removed.
///
/// Previously also hosted the detectors list + cameras list — both
/// moved to their own dedicated tabs (`PatientDetectorsView`,
/// `PatientCamerasView`) so this tab now stays focused on
/// patient-level configuration.
struct PatientSettingsView: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var showingFeedback = false

    // Photo upload state. selectedItem drives PhotosPicker, which fires
    // .onChange when the caregiver picks something; the upload runs on
    // the main actor and surfaces failures via photoUploadError.
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoUploadError: String?
    @State private var isUploadingPhoto = false

    // Patient deletion state. Two-step (confirm + execute) so a single
    // mis-tap can't cascade-delete a patient's entire history. The
    // delete itself is idempotent in the API client (404 = local
    // state was stale, treated as success), so we don't surface
    // errors here.
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false

    // Face enrollment status surface. Loaded on appear and on
    // dismiss of the re-enrollment cover so the counts stay fresh.
    @State private var enrollmentSummary: FaceEnrollmentSummary?
    @State private var showingReEnrollment = false

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                profileCard
                identityCard
                PatientEmailAlertsCard(patientId: patientId)
                feedbackEntry

                NemaraButton(
                    isDeleting ? "Removing…" : "Remove this patient",
                    variant: .ghost, size: .sm,
                ) {
                    showingDeleteConfirm = true
                }
                .foregroundStyle(NemaraColor.terra)
                .disabled(isDeleting || patient == nil)
                .padding(.top, 8)
                // Clear the floating tab bar. 40 sits comfortably above
                // the Liquid Glass bar without leaving dead space.
                .padding(.bottom, 40)
            }
            .padding(.top, 12)
        }
        .background(NemaraColor.paper)
        .alert("Remove patient?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await deletePatient() }
            }
        } message: {
            if let p = patient {
                Text(
                    "\(p.preferredName)'s cameras, detectors, and event history "
                    + "will be permanently removed. This cannot be undone.",
                )
            } else {
                Text("This will permanently remove the patient and all data.")
            }
        }
        .navigationDestination(isPresented: $showingFeedback) {
            FeedbackView()
                .trackScreen("feedback")
        }
        .fullScreenCover(isPresented: $showingReEnrollment) {
            FaceEnrollmentStepView(patientId: patientId) {
                showingReEnrollment = false
                Task { await loadEnrollmentSummary() }
            }
            .environment(env)
            .trackScreen("face_enrollment")
        }
        .task { await loadEnrollmentSummary() }
    }

    /// Fetch the patient's face-enrollment status so the identity
    /// card can render the same numbers the web dashboard shows.
    /// Best-effort: a transient failure leaves the card in its
    /// previous state.
    private func loadEnrollmentSummary() async {
        do {
            enrollmentSummary = try await env.api.faceEnrollmentSummary(patientId)
        } catch {
            NSLog("[PatientSettings] enrollment summary load failed: %@", "\(error)")
        }
    }

    // MARK: - sections

    /// Re-ID enrollment status card. The wording renders three states
    /// matched byte-for-byte with the web dashboard's
    /// PatientIdentityStatus card so a caregiver flipping between
    /// devices sees the same language.
    private var identityCard: some View {
        let state = identityState
        let name = patient?.preferredName ?? patient?.fullName ?? "this patient"
        // Not-enrolled is an action the caregiver needs to take, so the
        // card pops with a terra (warning) tint + border and an
        // exclamation indicator instead of the neutral dashed circle.
        let urgent = state == .notEnrolled
        return NemaraCard(
            tone: urgent ? .terra : .default,
            padding: 14,
            borderColor: urgent ? NemaraColor.terra : nil,
        ) {
            HStack(spacing: 12) {
                identityIndicator(state)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(identityCardTitle(state: state, name: name))
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink)
                }
                Spacer()
                Button {
                    showingReEnrollment = true
                } label: {
                    Text(state == .enrolled ? "Re-enroll" : "Enroll")
                        .font(NemaraFont.bodySmallStrong)
                        .foregroundStyle(NemaraColor.terra)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }

    private enum IdentityCardState { case loading, enrolled, processing, notEnrolled }

    private var identityState: IdentityCardState {
        guard let s = enrollmentSummary else { return .loading }
        if s.isProcessing { return .processing }
        if s.isEnrolled { return .enrolled }
        return .notEnrolled
    }

    private func identityCardTitle(state: IdentityCardState, name: String) -> String {
        switch state {
        case .loading:      return "Patient identity"
        case .enrolled:     return "\(name)'s face enrollment is complete"
        case .processing:   return "\(name)'s face enrollment is in progress"
        case .notEnrolled:  return "\(name)'s face enrollment is incomplete"
        }
    }

    @ViewBuilder
    private func identityIndicator(_ state: IdentityCardState) -> some View {
        switch state {
        case .enrolled:
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .foregroundStyle(NemaraColor.success)
        case .processing:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(NemaraColor.terra)
        case .notEnrolled:
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(NemaraColor.terra)
        case .loading:
            Image(systemName: "circle.dashed")
                .resizable()
                .foregroundStyle(NemaraColor.ink3)
        }
    }

    private var profileCard: some View {
        NemaraCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    if let p = patient {
                        ZStack(alignment: .bottomTrailing) {
                            PatientAvatar(patient: p, size: 56)
                            PhotosPicker(
                                selection: $selectedPhotoItem,
                                matching: .images,
                                photoLibrary: .shared(),
                            ) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(NemaraColor.actionInk)
                                    .frame(width: 22, height: 22)
                                    .background(NemaraColor.action)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle().strokeBorder(NemaraColor.paper, lineWidth: 2),
                                    )
                            }
                            .accessibilityLabel("Change photo")
                            .disabled(isUploadingPhoto)
                        }
                    } else {
                        NemaraAvatar(letter: "?", size: 56)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(patient?.fullName ?? "")
                            .font(NemaraFont.title2)
                            .foregroundStyle(NemaraColor.ink)
                            .kerning(-0.4)
                        if let p = patient {
                            Text("\(p.relation.displayName) · Goes by \(p.preferredName) · \(p.age) yrs")
                                .font(NemaraFont.caption)
                                .foregroundStyle(NemaraColor.ink3)
                        }
                    }
                    Spacer()
                    NemaraButton("Edit", variant: .ghost, size: .sm, systemImage: "pencil") {}
                }
                if patient?.photoStorageKey != nil {
                    NemaraButton(
                        "Remove photo",
                        variant: .ghost,
                        size: .sm,
                        systemImage: "trash",
                    ) {
                        Task { await removePhoto() }
                    }
                }
                if let err = photoUploadError {
                    Text(err)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.terra)
                }
            }
        }
        .padding(.horizontal, 16)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadPickedPhoto(newItem) }
        }
    }

    // MARK: - Photo upload

    /// Load the picked item as JPEG bytes (down-sampling to ≤1024px
    /// longest edge), then upload via the API. Errors land in
    /// `photoUploadError` for inline display.
    private func uploadPickedPhoto(_ item: PhotosPickerItem) async {
        guard let patient else { return }
        isUploadingPhoto = true
        photoUploadError = nil
        defer { isUploadingPhoto = false; selectedPhotoItem = nil }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                photoUploadError = "Couldn't read the selected photo."
                return
            }
            let jpeg = Self.downsampledJPEG(from: raw, maxDimension: 1024, quality: 0.8)
            guard let jpeg else {
                photoUploadError = "That image format isn't supported."
                return
            }
            try await env.api.uploadPatientPhoto(
                patient.id, imageData: jpeg, contentType: "image/jpeg",
            )
        } catch {
            photoUploadError = error.localizedDescription
        }
    }

    private func removePhoto() async {
        guard let patient else { return }
        photoUploadError = nil
        do {
            try await env.api.deletePatientPhoto(patient.id)
        } catch {
            photoUploadError = error.localizedDescription
        }
    }

    // MARK: - Patient deletion

    /// Confirm-then-execute. The API client handles 404 idempotently
    /// (treats it as "already gone, clean up local state"), so a
    /// silent try? is the right call here — there's no failure mode
    /// the caregiver needs to recover from. On any other API error,
    /// we still dismiss; the next pull-to-refresh will resync state.
    private func deletePatient() async {
        guard let id = patient?.id else { return }
        isDeleting = true
        defer { isDeleting = false }
        try? await env.api.deletePatient(id)
        dismiss()
    }

    /// Down-sample to a max-longest-edge box and re-encode as JPEG.
    /// 1024px is comfortably above the on-screen size and small
    /// enough to fit the backend's 1 MiB cap with room to spare.
    private static func downsampledJPEG(
        from data: Data, maxDimension: CGFloat, quality: CGFloat,
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        let scale: CGFloat = longest > maxDimension ? maxDimension / longest : 1.0
        let target = CGSize(width: w * scale, height: h * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    // `detectorsSection` and `camerasSection` lived here previously.
    // Moved to their own tabs — PatientDetectorsView and
    // PatientCamerasView — so each gets the full screen and a
    // navigation stack of its own. See PatientShell.swift for tab
    // routing.

    private var feedbackEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("HELP US IMPROVE")
                .padding(.horizontal, 16)
            NemaraCard(padding: 0) {
                Button { showingFeedback = true } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(NemaraColor.terraSoft)
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(NemaraColor.terra)
                        }
                        .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Feedback & support")
                                .font(NemaraFont.bodySmallStrong)
                                .foregroundStyle(NemaraColor.ink)
                            Text("Send feedback, contact the team, or share Memoria")
                                .font(NemaraFont.caption)
                                .foregroundStyle(NemaraColor.ink3)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack {
        PatientSettingsView(patientId: env.api.patients[0].id)
    }
    .environment(env)
}
#endif
