import PhotosUI
import SwiftUI
import UIKit

/// "Settings" sub-tab. Profile summary, detector list, cameras list,
/// feedback entry, and the destructive "Remove patient" action at the
/// bottom.
struct PatientSettingsView: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddDetector = false
    @State private var showingFeedback = false
    @State private var pairingRoomDraft = ""
    @State private var showingRoomPrompt = false
    @State private var showingPairingCode = false
    @State private var pairingRoom = ""

    // Photo upload state. selectedItem drives PhotosPicker, which fires
    // .onChange when the caregiver picks something; the upload runs on
    // the main actor and surfaces failures via photoUploadError.
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoUploadError: String?
    @State private var isUploadingPhoto = false

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }
    private var detectors: [Detector] {
        env.api.detectorsByPatient[patientId] ?? []
    }
    private var cameras: [Camera] {
        env.api.camerasByPatient[patientId] ?? []
    }
    private var activeCount: Int { detectors.filter(\.isOn).count }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                profileCard
                monitoringCard
                detectorsSection
                NemaraButton("Add a detector", variant: .secondary, block: true, systemImage: "plus") {
                    showingAddDetector = true
                }
                .padding(.horizontal, 16)
                camerasSection
                NemaraButton("Pair a new phone", variant: .ghost, size: .sm, systemImage: "plus") {
                    pairingRoomDraft = nextDefaultRoomName()
                    showingRoomPrompt = true
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                feedbackEntry
                NemaraButton("Remove this patient", variant: .ghost, size: .sm) {
                    guard let id = patient?.id else { return }
                    Task {
                        try? await env.api.deletePatient(id)
                        dismiss()
                    }
                }
                .foregroundStyle(NemaraColor.terra)
                .padding(.top, 4)
            }
            .padding(.top, 12)
        }
        .background(NemaraColor.paper)
        .sheet(isPresented: $showingAddDetector) {
            AddDetectorView(patientId: patientId)
        }
        .alert("Name the new camera", isPresented: $showingRoomPrompt) {
            TextField("Room", text: $pairingRoomDraft)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Generate code") {
                pairingRoom = pairingRoomDraft.trimmingCharacters(in: .whitespaces)
                guard !pairingRoom.isEmpty else { return }
                showingPairingCode = true
            }
        } message: {
            Text("e.g. Kitchen, Living room, Bedroom")
        }
        .sheet(isPresented: $showingPairingCode) {
            PairingCodeSheet(
                patientId: patientId,
                room: pairingRoom,
                iconName: defaultIcon(for: pairingRoom),
            )
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(isPresented: $showingFeedback) {
            FeedbackView()
        }
    }

    // ── Pairing helpers ───────────────────────────────────────────

    /// Suggested next room name: "Camera N" where N is the next free
    /// integer. Caregiver typically renames to something semantic
    /// like "Kitchen" before tapping Generate.
    private func nextDefaultRoomName() -> String {
        "Camera \(cameras.count + 1)"
    }

    /// Best-guess SF Symbol for a room. Caregiver can override later
    /// (Phase 1: surface in CameraRow). Falls back to `tv` for unknown
    /// rooms.
    private func defaultIcon(for room: String) -> String {
        let lower = room.lowercased()
        if lower.contains("kitchen") { return "fork.knife" }
        if lower.contains("bed") { return "bed.double" }
        if lower.contains("bath") { return "shower" }
        if lower.contains("living") || lower.contains("family") { return "tv" }
        if lower.contains("hall") || lower.contains("entry") || lower.contains("door") {
            return "door.left.hand.open"
        }
        if lower.contains("garage") { return "car" }
        return "tv"
    }

    // MARK: - sections

    /// Big "Monitoring" toggle. When off, every camera in the patient's
    /// home stops streaming and detectors stop firing — surfaces as a
    /// PAUSED pill on the roster row and a paused-overlay on the Live
    /// tab. Persists until the caregiver flips it back on.
    private var monitoringCard: some View {
        let paused = patient?.camerasPaused ?? false
        return NemaraCard(
            tone: paused ? .alt : .default,
            padding: 14,
            borderColor: paused ? NemaraColor.line : NemaraColor.line
        ) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(paused ? NemaraColor.paperDim : NemaraColor.actionSoft)
                    Image(systemName: paused ? "video.slash.fill" : "video.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(paused ? NemaraColor.ink3 : NemaraColor.action)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(paused ? "Monitoring paused" : "Monitoring on")
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink)
                    Text(paused
                         ? "Every camera in the home is off. No detection, no live feed."
                         : "All cameras are streaming and detectors are running.")
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                NemaraToggle(isOn: Binding(
                    get: { !(patient?.camerasPaused ?? false) },
                    set: { newValue in
                        guard let id = patient?.id else { return }
                        Task {
                            _ = try? await env.api.updatePatient(
                                id, UpdatePatientRequest(camerasPaused: !newValue),
                            )
                        }
                    }
                ))
            }
        }
        .padding(.horizontal, 16)
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

    private var detectorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                NemaraEyebrow("DETECTORS")
                Spacer()
                NemaraChip("\(activeCount) active", tone: .action)
            }
            .padding(.horizontal, 16)

            NemaraCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(detectors.indices, id: \.self) { i in
                        DetectorRow(
                            patientId: patientId,
                            detector: detectors[i],
                            isLast: i == detectors.count - 1
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var camerasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("CAMERAS · \(cameras.count) PHONES")
                .padding(.horizontal, 16)
            NemaraCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(cameras.indices, id: \.self) { i in
                        let cam = cameras[i]
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(NemaraColor.paperDim)
                                Image(systemName: cam.iconName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(NemaraColor.ink2)
                            }
                            .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cam.room).font(NemaraFont.bodySmallStrong).foregroundStyle(NemaraColor.ink)
                                Text("CAM \(String(format: "%02d", cam.displayId)) · \(cam.online ? "ONLINE" : "OFFLINE")")
                                    .font(NemaraFont.monoSmall)
                                    .foregroundStyle(NemaraColor.ink3)
                            }
                            Spacer()
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(NemaraColor.ink3)
                        }
                        .padding(12)
                        if i < cameras.count - 1 {
                            NemaraColor.line.frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

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
                            Text("Send feedback, contact the team, or share Nemara")
                                .font(NemaraFont.caption)
                                .foregroundStyle(NemaraColor.ink3)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack {
        PatientSettingsView(patientId: env.api.patients[0].id)
    }
    .environment(env)
}
