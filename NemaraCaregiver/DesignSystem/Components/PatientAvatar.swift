import SwiftUI

/// `NemaraAvatar` wrapper that resolves a patient's signed photo URL
/// on appear and re-resolves when `patient.photoStorageKey` flips.
///
/// Centralizes the "fetch the URL once when the avatar appears" logic
/// so every callsite (roster row, patient header, settings header,
/// event-detail nav) gets photo support automatically. Failure /
/// loading / no-photo all fall through to the serif-initial
/// placeholder built into `NemaraAvatar`.
struct PatientAvatar: View {
    let patient: Patient
    let size: CGFloat
    let ring: Color?

    @Environment(AppEnvironment.self) private var env
    @State private var photoURL: URL?

    init(patient: Patient, size: CGFloat = 40, ring: Color? = nil) {
        self.patient = patient
        self.size = size
        self.ring = ring
    }

    var body: some View {
        NemaraAvatar(
            letter: patient.avatarLetter,
            size: size,
            ring: ring,
            photoURL: photoURL,
        )
        .task(id: refreshKey) {
            photoURL = nil
            guard patient.photoStorageKey != nil else { return }
            photoURL = try? await env.api.patientPhotoURL(patient.id)
        }
    }

    /// Re-runs the task whenever the patient identity OR the storage
    /// key changes — covers both "switched to a different patient" and
    /// "same patient just uploaded a new photo".
    private var refreshKey: String {
        "\(patient.id.uuidString)|\(patient.photoStorageKey ?? "")"
    }
}
