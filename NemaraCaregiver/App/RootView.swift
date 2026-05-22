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

#Preview("Signed out") {
    RootView()
        .environment(AppEnvironment(auth: MockAuthService(), mockStore: MockStore()))
}

#Preview("Signed in") {
    let env = AppEnvironment(auth: MockAuthService(), mockStore: MockStore())
    env.auth.currentCaregiver = Caregiver(id: UUID(), displayName: "Jane Patel", email: "jane@patel.co")
    return RootView().environment(env)
}
