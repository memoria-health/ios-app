import SwiftUI
import UIKit
import UserNotifications

/// `@main` — Nemara caregiver iOS app entry point.
///
/// Builds the `AppEnvironment` once and injects it into the view tree
/// via the modern `@Observable`-based environment pattern. Read it in
/// any view with `@Environment(AppEnvironment.self) private var env`.
@main
struct NemaraCaregiverApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment

    init() {
        let env = AppEnvironment.live()
        _environment = State(initialValue: env)

        // Wire the AppDelegate's APNs callbacks back into the
        // SwiftUI/observable world. The closures are weak via the
        // captured `env` reference's `api`, so the delegate doesn't
        // pin AppEnvironment alive past app death.
        AppDelegate.didReceiveAPNsToken = { [weak api = env.api] hexToken in
            Task { @MainActor in
                guard let api else { return }
                do {
                    try await api.registerDeviceToken(
                        apnsToken: hexToken,
                        environment: Self.currentAPNsEnvironment,
                    )
                } catch {
                    NSLog("[APNs] registerDeviceToken failed: %@", "\(error)")
                }
            }
        }
        AppDelegate.didTapEventPush = { eventId in
            // Surface the tap on a NotificationCenter channel so any
            // SwiftUI view can subscribe and navigate. RootView reads
            // this and drives the nav stack.
            NotificationCenter.default.post(
                name: .nemaraEventPushTapped,
                object: nil,
                userInfo: ["event_id": eventId],
            )
        }

        #if DEBUG
        NemaraFont.logRegisteredFonts()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .preferredColorScheme(.light)   // design is light-only
                .tint(NemaraColor.terra)
                .background(NemaraColor.paper)
                .task {
                    await Self.requestPushAuthorization()
                }
        }
    }

    /// Ask the OS for alert + sound + badge permission. If granted,
    /// register for remote notifications; iOS will then call back
    /// into `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
    /// with the device token, which we forward to `/v1/me/devices`.
    ///
    /// Safe to call repeatedly — `requestAuthorization` is idempotent
    /// once the user has answered the system prompt, and
    /// `registerForRemoteNotifications()` short-circuits if the token
    /// is already cached.
    private static func requestPushAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            NSLog("[APNs] auth request failed: %@", "\(error)")
        }
    }

    /// Compile-time APNs environment selector. Apple's APNs entitlement
    /// value is set at codesign time (development for Xcode builds,
    /// production for distribution); the device-token registry has to
    /// match or APNs returns BadDeviceToken on dispatch. `#if DEBUG`
    /// is the deterministic seam — debug builds ship with the
    /// development entitlement, release builds get re-signed with the
    /// production one by Xcode's archive step.
    private static var currentAPNsEnvironment: APNsEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }
}

extension Notification.Name {
    /// Posted when the caregiver taps an APNs banner / lock-screen
    /// alert. `userInfo["event_id"]` is the UUID of the detector
    /// event to deep-link into.
    static let nemaraEventPushTapped = Notification.Name("co.sunny.nemara.eventPushTapped")
}
