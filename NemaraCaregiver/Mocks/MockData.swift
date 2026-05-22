import Foundation
import Observation

/// **All v0 in-memory mock data lives here.** Delete this file (and
/// `MockAuthService.swift`) when real services land. The compile errors
/// in views that reference `env.mockStore` mark every place that needs
/// to be re-wired to the real backend.
///
/// `MockStore` is `@Observable` so view writes (toggle a detector, add a
/// patient, mark an event reviewed) animate live across the app.
@MainActor
@Observable
final class MockStore {

    // MARK: - Roster

    /// All patients the signed-in caregiver looks after.
    var patients: [Patient]

    /// Per-patient cameras.
    var cameras: [UUID: [Camera]]

    /// Per-patient detectors.
    var detectors: [UUID: [Detector]]

    /// Per-patient events.
    var events: [UUID: [DetectionEvent]]

    // MARK: - App settings

    /// Caregiver-level notification toggles surfaced on AppSettings.
    var pushEnabled: Bool = true
    var callEnabled: Bool = true
    var dailyEmailEnabled: Bool = false

    init() {
        let now = Date()
        let cal = Calendar.current

        // ── Margaret ────────────────────────────────────────
        let margaretId = UUID()
        let margaret = Patient(
            id: margaretId,
            fullName: "Margaret O'Brien",
            preferredName: "Maggie",
            dateOfBirth: cal.date(from: DateComponents(year: 1951, month: 3, day: 18)) ?? now,
            gender: "Female",
            relation: .parent,
            homeAddress: "84 Birch Lane, Cambridge MA",
            state: .critical,
            statusLine: "Possible fall, living room",
            lastEventAt: cal.date(byAdding: .minute, value: -42, to: now),
            batteryPercent: 82
        )

        // ── Eleanor ─────────────────────────────────────────
        let eleanorId = UUID()
        let eleanor = Patient(
            id: eleanorId,
            fullName: "Eleanor Vance",
            preferredName: "Eleanor",
            dateOfBirth: cal.date(from: DateComponents(year: 1947, month: 9, day: 2)) ?? now,
            gender: "Female",
            relation: .other,
            homeAddress: nil,
            state: .critical,
            statusLine: "Distress in kitchen",
            lastEventAt: cal.date(byAdding: .minute, value: -14, to: now),
            batteryPercent: 18
        )

        // ── Henry ───────────────────────────────────────────
        let henryId = UUID()
        let henry = Patient(
            id: henryId,
            fullName: "Henry Gold",
            preferredName: "Henry",
            dateOfBirth: cal.date(from: DateComponents(year: 1940, month: 11, day: 14)) ?? now,
            gender: "Male",
            relation: .other,
            homeAddress: nil,
            state: .calm,
            statusLine: "Resting in living room",
            lastEventAt: cal.date(byAdding: .hour, value: -4, to: now),
            batteryPercent: 91
        )

        // ── Sam ─────────────────────────────────────────────
        let samId = UUID()
        let sam = Patient(
            id: samId,
            fullName: "Sam Whitaker",
            preferredName: "Sam",
            dateOfBirth: cal.date(from: DateComponents(year: 1946, month: 1, day: 20)) ?? now,
            gender: "Male",
            relation: .client,
            homeAddress: nil,
            state: .offline,
            statusLine: "Cameras offline",
            lastEventAt: cal.date(byAdding: .day, value: -1, to: now),
            batteryPercent: nil
        )

        self.patients = [margaret, eleanor, henry, sam]

        // ── Cameras (Margaret only; others can fall back to her layout) ──
        let margaretCams: [Camera] = [
            .init(id: 1, room: "Living room", iconName: "tv",         online: true),
            .init(id: 2, room: "Kitchen",     iconName: "fork.knife", online: true),
            .init(id: 3, room: "Bedroom",     iconName: "bed.double", online: true),
            .init(id: 4, room: "Hallway",     iconName: "door.left.hand.open", online: true),
        ]
        self.cameras = [
            margaretId: margaretCams,
            eleanorId:  margaretCams,
            henryId:    margaretCams,
            samId:      margaretCams.map { var c = $0; c.online = false; return c },
        ]

        // ── Detectors (Margaret) ────────────────────────────
        let detectors: [Detector] = [
            .init(id: UUID(), name: "Falls",
                  iconName: "figure.fall",
                  description: "Sudden fall events across all rooms.",
                  category: .safety, source: .preset,
                  shape: .pointInTime, whereScope: "ALL ROOMS",
                  whenScope: "ALWAYS", sensitivity: .standard, isOn: true),
            .init(id: UUID(), name: "Agitation",
                  iconName: "figure.walk.motion",
                  description: "Pacing or restless body language sustained over time.",
                  category: .safety, source: .preset,
                  shape: .state, whereScope: "ALL ROOMS",
                  whenScope: "ALWAYS", sensitivity: .high, isOn: true),
            .init(id: UUID(), name: "Wandering",
                  iconName: "door.left.hand.open",
                  description: "Main door opening — front entry only.",
                  category: .safety, source: .preset,
                  shape: .pointInTime, whereScope: "HALLWAY",
                  whenScope: "ALWAYS", sensitivity: .standard, isOn: true),
            .init(id: UUID(), name: "Medication adherence",
                  iconName: "pills",
                  description: "Confirms the morning and evening pill routine at the kitchen counter.",
                  category: .routine, source: .preset,
                  shape: .pointInTime, whereScope: "KITCHEN",
                  whenScope: "8 AM, 8 PM ±1H", sensitivity: .standard, isOn: true),
            .init(id: UUID(), name: "Long inactivity",
                  iconName: "circle.dotted",
                  description: "No movement in the living room for more than 2 hours.",
                  category: .safety, source: .custom,
                  shape: .state, whereScope: "LIVING ROOM",
                  whenScope: "DAYTIME", sensitivity: .off, isOn: false),
            .init(id: UUID(), name: "Late kitchen visits",
                  iconName: "moon.stars",
                  description: "Kitchen activity between 11 PM and 6 AM.",
                  category: .safety, source: .custom,
                  shape: .pointInTime, whereScope: "KITCHEN",
                  whenScope: "11 PM – 6 AM", sensitivity: .standard, isOn: true),
        ]
        self.detectors = [margaretId: detectors]

        // ── Events (Margaret) ───────────────────────────────
        let margaretEvents: [DetectionEvent] = [
            .init(id: UUID(), patientId: margaretId, detectorId: nil,
                  category: .safety, source: .preset,
                  iconName: "figure.fall",
                  title: "Possible fall", location: "Living room",
                  time: "14:32", ago: "42 min ago",
                  hasClip: true,
                  narrative: "A sharp downward motion at 14:32, followed by three minutes of stillness on the floor near the coffee table. No spoken response when we tried room audio at 14:33.",
                  opened: false, reviewed: false,
                  reviewChoice: nil, reviewNotes: nil),
            .init(id: UUID(), patientId: margaretId, detectorId: nil,
                  category: .safety, source: .preset,
                  iconName: "figure.walk.motion",
                  title: "Agitation episode", location: "Bedroom",
                  time: "13:10", ago: "2h ago",
                  hasClip: true,
                  narrative: "Maggie paced from the doorway to the window for about four minutes around 13:10. Voice raised twice without clear words. Settled with the radio.",
                  opened: true, reviewed: false,
                  reviewChoice: nil, reviewNotes: nil),
            .init(id: UUID(), patientId: margaretId, detectorId: nil,
                  category: .routine, source: .preset,
                  iconName: "pills",
                  title: "Medication", location: "Kitchen",
                  time: "08:05", ago: "7h ago",
                  hasClip: false,
                  narrative: "Maggie took her morning pills at 08:05, with tea, sitting at the kitchen counter — exactly her usual pattern.",
                  opened: false, reviewed: false,
                  reviewChoice: nil, reviewNotes: nil),
            .init(id: UUID(), patientId: margaretId, detectorId: nil,
                  category: .safety, source: .custom,
                  iconName: "moon.stars",
                  title: "Late kitchen visit", location: "Kitchen",
                  time: "Yesterday 02:30", ago: "13h ago",
                  hasClip: true,
                  narrative: "Brief light in the kitchen at 02:30. Maggie got a glass of water and returned to bed within four minutes.",
                  opened: true, reviewed: true,
                  reviewChoice: .correct, reviewNotes: nil),
            .init(id: UUID(), patientId: margaretId, detectorId: nil,
                  category: .safety, source: .preset,
                  iconName: "door.left.hand.open",
                  title: "Front door opened", location: "Hallway",
                  time: "Yesterday 16:15", ago: "23h ago",
                  hasClip: true,
                  narrative: "Front door opened at 16:15. Maggie greeted someone (the home aide on her usual Tuesday visit), they came in, door closed within 20 seconds.",
                  opened: true, reviewed: true,
                  reviewChoice: .correct, reviewNotes: nil),
            .init(id: UUID(), patientId: margaretId, detectorId: nil,
                  category: .routine, source: .preset,
                  iconName: "pills",
                  title: "Medication", location: "Kitchen",
                  time: "Yesterday 20:05", ago: "1d ago",
                  hasClip: false,
                  narrative: "Evening pills taken at 20:05.",
                  opened: true, reviewed: true,
                  reviewChoice: .correct, reviewNotes: nil),
            .init(id: UUID(), patientId: margaretId, detectorId: nil,
                  category: .safety, source: .preset,
                  iconName: "figure.walk.motion",
                  title: "Agitation episode", location: "Living room",
                  time: "Mon 16:42", ago: "3d ago",
                  hasClip: true,
                  narrative: "A brief pacing episode around the news hour — calmed within five minutes.",
                  opened: true, reviewed: true,
                  reviewChoice: .correct, reviewNotes: nil),
        ]
        self.events = [margaretId: margaretEvents]
    }

    // MARK: - Mutations exposed to views

    func addPatient(_ p: Patient) {
        patients.append(p)
        if cameras[p.id] == nil { cameras[p.id] = [] }
        if detectors[p.id] == nil { detectors[p.id] = [] }
        if events[p.id] == nil { events[p.id] = [] }
    }

    func removePatient(_ id: UUID) {
        patients.removeAll { $0.id == id }
        cameras[id] = nil
        detectors[id] = nil
        events[id] = nil
    }

    func toggleDetector(_ patientId: UUID, _ detectorId: UUID) {
        guard var list = detectors[patientId],
              let idx = list.firstIndex(where: { $0.id == detectorId }) else { return }
        list[idx].isOn.toggle()
        detectors[patientId] = list
    }

    func setSensitivity(_ patientId: UUID, _ detectorId: UUID, _ level: Detector.Sensitivity) {
        guard var list = detectors[patientId],
              let idx = list.firstIndex(where: { $0.id == detectorId }) else { return }
        list[idx].sensitivity = level
        detectors[patientId] = list
    }

    func setCamerasPaused(_ patientId: UUID, _ paused: Bool) {
        guard let idx = patients.firstIndex(where: { $0.id == patientId }) else { return }
        patients[idx].camerasPaused = paused
    }

    func addDetector(_ patientId: UUID, _ detector: Detector) {
        var list = detectors[patientId] ?? []
        list.append(detector)
        detectors[patientId] = list
    }

    func markOpened(_ patientId: UUID, _ eventId: UUID) {
        guard var list = events[patientId],
              let idx = list.firstIndex(where: { $0.id == eventId }) else { return }
        list[idx].opened = true
        events[patientId] = list
    }

    func submitReview(
        _ patientId: UUID,
        _ eventId: UUID,
        choice: DetectionEvent.ReviewChoice,
        notes: String?
    ) {
        guard var list = events[patientId],
              let idx = list.firstIndex(where: { $0.id == eventId }) else { return }
        list[idx].opened = true
        list[idx].reviewed = true
        list[idx].reviewChoice = choice
        list[idx].reviewNotes = notes
        events[patientId] = list
    }
}
