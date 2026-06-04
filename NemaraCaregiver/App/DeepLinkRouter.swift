import Foundation
import Observation

/// Single source of truth for "which patient shell is open" and "which
/// event (if any) to deep-link into". Replaces the per-view
/// `openPatientId` @State in RosterView + AppSettingsView so exactly one
/// `PatientShell` `fullScreenCover` can ever be presented (from
/// `MainTabView`), and an APNs tap has one lever to pull.
///
/// Why durable state instead of the old `NotificationCenter` post: a tap
/// is an event, but a navigation target must survive the async windows
/// between tap and a UI that can act on it (auth gate, bootstrap, cover
/// presentation). The tap *sets* state here; each nav layer *reconciles
/// toward* it when it's ready. Mirrors the intent-vs-reality model the
/// camera layer already uses.
@MainActor
@Observable
final class DeepLinkRouter {
    /// Drives `MainTabView`'s single `PatientShell` cover. nil = none open.
    var openPatientId: UUID?

    /// When set alongside `openPatientId`, `PatientShell` jumps to the
    /// Events tab and `PatientEventsView` opens this event (fetching it
    /// by id if it isn't cached), then clears it — consume-exactly-once.
    var focusEventId: UUID?

    /// Manual navigation (roster / settings row tap). No event focus.
    func openPatient(_ id: UUID) { route(patient: id, focusEvent: nil) }

    /// Drain a buffered notification tap (`AppDelegate.pendingEventTap`).
    /// Idempotent (read-and-clear) so the warm nudge and the cold
    /// mount-time drain can both call it without double-navigating.
    func drainPendingTap() {
        guard let tap = AppDelegate.pendingEventTap else { return }
        AppDelegate.pendingEventTap = nil
        route(patient: tap.patientId, focusEvent: tap.eventId)
    }

    /// SwiftUI can't hot-swap a presented `fullScreenCover(item:)` to a
    /// new id in a single tick — when a DIFFERENT patient is already
    /// open, dismiss first, then present on the next runloop.
    private func route(patient pid: UUID, focusEvent eid: UUID?) {
        if let current = openPatientId, current != pid {
            openPatientId = nil
            Task { @MainActor in
                self.focusEventId = eid
                self.openPatientId = pid
            }
        } else {
            focusEventId = eid
            openPatientId = pid
        }
    }
}
