import Foundation

/// Per-patient "Blur people" preference — DEVICE-LOCAL, mirrors the web
/// dashboard's per-patient localStorage toggle. When on, this device renders
/// that patient's live tiles through `BlurredVideoView` (on-device Vision
/// person segmentation → blur) instead of the plain `LiveKitVideoView`.
///
/// Intentionally NOT server-backed: it's a viewing preference for THIS phone,
/// changes nothing about recording/insights or what other devices see, and is
/// fully reversible (off → the untouched normal video path). Backed by
/// `UserDefaults`; published so SwiftUI live tiles swap the instant it flips.
@MainActor
final class PeopleBlurStore: ObservableObject {
    static let shared = PeopleBlurStore()

    private let key = "peopleBlur.enabledPatientIDs"
    @Published private(set) var enabledIDs: Set<String>

    private init() {
        enabledIDs = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func isEnabled(_ patientId: UUID) -> Bool {
        enabledIDs.contains(patientId.uuidString)
    }

    func setEnabled(_ on: Bool, for patientId: UUID) {
        if on { enabledIDs.insert(patientId.uuidString) }
        else { enabledIDs.remove(patientId.uuidString) }
        UserDefaults.standard.set(Array(enabledIDs), forKey: key)
    }
}
