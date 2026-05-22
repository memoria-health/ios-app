import Foundation
import Observation

/// Top-level dependency container. Lives once for the lifetime of the
/// app, injected via `.environment(_:)` from `NemaraCaregiverApp`.
///
/// In v0 it holds:
/// - `auth`        — the authentication seam (`MockAuthService`)
/// - `mockStore`   — all patient / event / detector data in memory
///
/// When real services land, add them here alongside (or in place of)
/// the mocks.
@MainActor
@Observable
final class AppEnvironment {
    let auth: AuthService
    let mockStore: MockStore

    init(auth: AuthService, mockStore: MockStore) {
        self.auth = auth
        self.mockStore = mockStore
    }

    /// Build the live environment used by `@main`. Today this is just
    /// the mock services; when Supabase ships, branch on a config flag
    /// here.
    static func live() -> AppEnvironment {
        let env = AppEnvironment(auth: MockAuthService(), mockStore: MockStore())
        #if DEBUG
        // `-prefillCaregiver` launch arg starts the app already signed in
        // as "Jane Patel" — useful for verifying signed-in screens without
        // having to type through the auth flow each time.
        if ProcessInfo.processInfo.arguments.contains("-prefillCaregiver") {
            env.auth.currentCaregiver = Caregiver(
                id: UUID(),
                displayName: "Jane Patel",
                email: "jane@patel.co"
            )
        }
        // `-pauseFirst` — for screenshot verification of the paused state.
        if ProcessInfo.processInfo.arguments.contains("-pauseFirst"),
           let id = env.mockStore.patients.first?.id {
            env.mockStore.setCamerasPaused(id, true)
        }
        #endif
        return env
    }
}
