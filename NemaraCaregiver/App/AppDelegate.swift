import UIKit
import UserNotifications

/// UIKit lifecycle shim used only for APNs hooks. SwiftUI 18's
/// `@main` doesn't expose `application(_:didRegisterForRemoteNotifications…)`
/// or `UNUserNotificationCenterDelegate` directly, so we bind a
/// minimal `UIApplicationDelegate` via `@UIApplicationDelegateAdaptor`
/// in `NemaraCaregiverApp` and route the data the SwiftUI layer needs
/// through two `@MainActor` callback hooks.
///
/// Two responsibilities:
///   1. Forward the APNs device token to whoever last set
///      `didReceiveAPNsToken` (set from `NemaraCaregiverApp.init` to a
///      closure that POSTs `/v1/me/devices`).
///   2. Buffer a notification tap (`event_id` + `patient_id` from the
///      payload root) so the SwiftUI navigation stack can deep-link into
///      the event — see `DeepLinkRouter.drainPendingTap()`.
///
/// Both hooks are `nil`-safe and the tap is *buffered* (not just a live
/// closure) — the app survives a push that lands before the SwiftUI tree
/// has installed handlers, including a cold launch from a terminated app.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Called from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
    /// with the hex-encoded token string ready to ship to the backend.
    static var didReceiveAPNsToken: ((String) -> Void)?

    /// Cold-launch-safe buffer for a notification tap. `didReceive`
    /// writes here unconditionally; the SwiftUI layer drains it (warm:
    /// via `onEventTap`; cold: when the signed-in surface mounts). Both
    /// ids are payload-root strings (src/services/push.py:build_event_payload).
    @MainActor static var pendingEventTap: (eventId: UUID, patientId: UUID)?

    /// Optional nudge so a running app drains `pendingEventTap`
    /// immediately instead of waiting for the next lifecycle tick.
    static var onEventTap: (() -> Void)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Self.didReceiveAPNsToken?(hex)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        NSLog("[APNs] registration failed: %@", error.localizedDescription)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Foreground presentation. Without this hook iOS suppresses
    /// notifications while the app is open — for a caregiver app
    /// where a fall fires while you're reading the patient's status
    /// line, that would be the wrong default.
    ///
    /// `nonisolated` to satisfy Swift 6 strict-concurrency: the
    /// protocol method is not main-actor-isolated, so the conformance
    /// can't assume @MainActor either. The completion-handler form
    /// avoids the async-method's Sendable-parameter check.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Tap handler. Pulls `event_id` + `patient_id` from the userInfo
    /// dict (set by `src/services/push.py:build_event_payload`), buffers
    /// them, and nudges the SwiftUI layer to drain. Buffering (not a bare
    /// closure call) is what makes a cold-launch tap survive: the buffer
    /// outlives the window before `onEventTap` is installed.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        func uuid(_ key: String) -> UUID? {
            guard let raw = userInfo[key] as? String else { return nil }
            return UUID(uuidString: raw)
        }
        let eventId = uuid("event_id")
        let patientId = uuid("patient_id")
        if let eventId, let patientId {
            Task { @MainActor in
                Self.pendingEventTap = (eventId: eventId, patientId: patientId)
                Self.onEventTap?()
            }
        }
        completionHandler()
    }
}
