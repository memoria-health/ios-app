import Foundation
import Observation

/// `AuthService` — the seam between the iOS app and (eventually) Supabase.
///
/// **Why this is a class, not a protocol.** SwiftUI's `@Observable`
/// tracks property changes through *concrete* types. Observation through
/// `any SomeProtocol` does not reliably trigger view updates. So this is
/// a non-final `@Observable` base class; subclasses (`MockAuthService`
/// for v0, future `SupabaseAuthService`) override the network methods.
///
/// In v0 only `MockAuthService` is wired up. When real auth lands, add
/// `SupabaseAuthService` alongside it and pick one in `AppEnvironment`.
@MainActor
@Observable
class AuthService {

    /// The currently-authenticated caregiver. `nil` when no session exists.
    var currentCaregiver: Caregiver?

    /// `true` while a sign-up / sign-in / restore call is in flight.
    var isAuthenticating: Bool = false

    /// Fires after `currentCaregiver` is set to non-nil — once per
    /// successful `signUp`, `signIn`, or `restoreSession`. Used by
    /// `AppEnvironment` to trigger first-launch flows (e.g. permission
    /// prompts) at a moment when the session is live.
    var onAuthenticated: ((Caregiver) async -> Void)?

    // MARK: - Override points (subclasses provide bodies)

    func signUp(displayName: String, email: String, password: String) async throws {
        fatalError("AuthService.signUp must be overridden by a subclass.")
    }

    func signIn(email: String, password: String) async throws {
        fatalError("AuthService.signIn must be overridden by a subclass.")
    }

    func signOut() async {
        currentCaregiver = nil
    }

    /// Called once at app launch. If a persisted session exists, hydrate
    /// `currentCaregiver`. No-op by default — Mock never persists.
    func restoreSession() async {}
}

/// Lightweight error type for v0. Mock returns these for invalid input;
/// the real Supabase service will map auth-SDK errors into the same set.
enum AuthError: Error, LocalizedError {
    case invalidCredentials
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Email or password didn't match."
        case .message(let m):     m
        }
    }
}
