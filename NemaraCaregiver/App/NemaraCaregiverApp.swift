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
    @Environment(\.scenePhase) private var scenePhase

    /// Set when the user taps a `nemara://reset-password?code=…` link
    /// from a password-recovery email. Triggers a full-screen
    /// `ResetPasswordView` cover on top of whatever's currently
    /// rendered (welcome screen if signed out, dashboard if signed
    /// in). Cleared when the cover dismisses.
    @State private var pendingResetCode: String?

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
        AppDelegate.onEventTap = { [weak deepLink = env.deepLink] in
            // Warm nudge: drain the buffered tap into the durable router
            // state, which MainTabView observes to present the patient +
            // event. Cold launches drain on mount instead (see MainTabView).
            Task { @MainActor in deepLink?.drainPendingTap() }
        }

        // App-start analytics. AppEnvironment.live() (above) has already
        // configured Analytics, so this lands in the buffer immediately. A
        // synchronous, non-throwing append — no effect on launch behavior.
        Analytics.shared.logLifecycle("app_launch")

        #if DEBUG
        NemaraFont.logRegisteredFonts()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // NOTE: dismissKeyboardOnTap is intentionally NOT applied here.
                // Wrapping the whole tree (which contains MainTabView's TabView)
                // in a tap gesture swallows the tab-bar taps on iOS 17/18 — it's
                // applied per-screen instead (MainTabView tab content + the
                // signed-out auth flow), where the text fields actually live.
                .environment(environment)
                .preferredColorScheme(.light)   // design is light-only
                .tint(NemaraColor.terra)
                .background(NemaraColor.paper)
                .task {
                    await Self.requestPushAuthorization()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // The Supabase socket is severed while suspended and Realtime
                    // has no replay, so on foreground we: (1) refetch everything
                    // missed (resync), (2) rebuild the Realtime channels with the
                    // current token so instant push resumes, and (3) (re)start the
                    // 1s state poll — the backstop that keeps camera badges within
                    // ~1s of backend truth even if Realtime stays dead. On
                    // background we stop the poll (the app is suspended anyway).
                    // All three no-op before the first bootstrap / when signed out.
                    switch newPhase {
                    case .active:
                        Analytics.shared.logLifecycle("app_foreground")
                        Task {
                            await environment.api.resync()
                            await environment.api.rebuildRealtimeChannels()
                            environment.api.startStatePolling()
                        }
                    case .background:
                        Analytics.shared.logLifecycle("app_background")
                        // Snapshot to disk + best-effort flush while we still
                        // have a moment before suspension. Fire-and-forget.
                        Analytics.shared.persistAndFlush()
                        environment.api.stopStatePolling()
                    default:
                        break
                    }
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .fullScreenCover(
                    isPresented: Binding(
                        get: { pendingResetCode != nil },
                        set: { presented in if !presented { pendingResetCode = nil } },
                    ),
                ) {
                    if let code = pendingResetCode {
                        ResetPasswordView(code: code)
                            .environment(environment)
                            .trackScreen("reset_password")
                    }
                }
        }
    }

    /// Route `nemara://` deep links to the right surface. Today only
    /// `reset-password?code=…` is wired; future flows (auth-callback,
    /// pairing, etc.) branch off the host component below.
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "nemara" else { return }
        let host = url.host(percentEncoded: false)
        switch host {
        case "reset-password":
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            // Supabase puts the recovery token in `?code=…`. Without
            // it there's nothing to exchange, so we silently drop the
            // open — RootView's existing UI is the right fallback.
            if let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value {
                pendingResetCode = code
            }
        default:
            break
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
