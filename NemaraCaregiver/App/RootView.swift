import SwiftUI

/// Top-level auth gate.
///
/// - When `auth.currentCaregiver == nil` → signed-out flow (Welcome → SignUp / Login).
/// - Otherwise → signed-in flow (`MainTabView`: Home + Settings tabs).
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.auth.currentCaregiver != nil {
                // Perpetual "Text us" help button. Applied here AND on
                // PatientShell, since the patient is a fullScreenCover that
                // would otherwise hide this presenter-level overlay.
                MainTabView()
                    // Welcome-tour spotlight overlay. Additive footprint-only
                    // host (same pattern as the support button); renders
                    // nothing unless the tour is active.
                    .tutorialOverlay(.root)
            } else {
                NavigationStack {
                    WelcomeView()
                }
                // Auth screens (Welcome → Login / SignUp) have text fields;
                // apply tap-to-dismiss here rather than at the app root, which
                // would wrap MainTabView's TabView and break its tab bar on iOS 17/18.
                .dismissKeyboardOnTap()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: env.auth.currentCaregiver?.id)
        .task {
            await env.auth.restoreSession()
        }
    }
}

#if DEBUG
#Preview("Signed out") {
    let env = AppEnvironment.preview()
    env.auth.currentCaregiver = nil
    return RootView().environment(env)
}
#endif

#if DEBUG
#Preview("Signed in") {
    RootView().environment(AppEnvironment.preview())
}
#endif
