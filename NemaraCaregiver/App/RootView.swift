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
                MainTabView()
            } else {
                NavigationStack {
                    WelcomeView()
                }
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
