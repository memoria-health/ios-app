import Foundation
import Observation
import Supabase

/// Real Supabase Auth — the only auth implementation in the app.
///
/// Owns one `SupabaseClient` (used here for auth and shared with
/// `NemaraAPIClient` for Realtime). Surfaces `currentCaregiver` and
/// `isAuthenticating` for SwiftUI to observe.
///
/// **Why a concrete class, not a protocol.** SwiftUI's `@Observable`
/// (iOS 17 Observation framework) tracks property changes only through
/// concrete types — observation through `any SomeProtocol` existentials
/// does not reliably trigger view updates. We had this exact problem in
/// range and learned the hard way. Single concrete class avoids that.
///
/// **Why no base class.** Range needed `AuthService` (base) +
/// `SupabaseAuthService` (subclass) + `MockAuthService` (subclass)
/// because it had two real impls. Nemara only has one — Supabase. No
/// abstraction needed.
///
/// The actual provisioning of a caregiver row (POST /v1/me) and the
/// initial data load (`api.bootstrap()`) is owned by `AppEnvironment`
/// via the `onAuthenticated` closure. That keeps this class strictly
/// about Supabase Auth and leaves the API client out of its dependency
/// graph.
@Observable
@MainActor
final class SupabaseAuthService {

    /// The currently-signed-in caregiver. `nil` ⇒ the welcome / sign-in
    /// flow renders; non-nil ⇒ RootView swaps to MainTabView.
    var currentCaregiver: Caregiver?

    /// `true` while a sign-up / sign-in / restore call is in flight.
    var isAuthenticating: Bool = false

    /// Called after a Supabase session is live. AppEnvironment wires
    /// this to:
    /// - signUp path (`displayName` non-nil): POST /v1/me, then bootstrap.
    /// - signIn / restoreSession path (`displayName` nil): GET /v1/me,
    ///   then bootstrap.
    /// Returns the caregiver row, which this service caches as
    /// `currentCaregiver`. Throws if provisioning or fetch fails.
    var onAuthenticated: ((_ signUpDisplayName: String?) async throws -> Caregiver)?

    /// Called when the user signs out. AppEnvironment wires this to
    /// `NemaraAPIClient.teardown()` so cached observable state is
    /// cleared and any open Realtime channels close.
    var onSignedOut: (() async -> Void)?

    /// Underlying Supabase client. Shared with `NemaraAPIClient` for
    /// Realtime subscriptions.
    let client: SupabaseClient

    init() {
        guard let url = AppConfig.supabaseURL,
              let key = AppConfig.supabaseAnonKey,
              !key.isEmpty
        else {
            fatalError("Supabase isn't configured. Set SUPABASE_URL + SUPABASE_ANON_KEY (or run in DEBUG with the bundled local-stack defaults).")
        }
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    // MARK: - Sign up

    func signUp(displayName: String, email: String, password: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let response = try await client.auth.signUp(email: email, password: password)
            // Email-confirmation projects don't return a session here.
            guard response.session != nil else {
                throw APIError.other(message: "Check your email to confirm your account.")
            }
            currentCaregiver = try await onAuthenticated?(displayName)
        } catch let apiError as APIError {
            throw apiError
        } catch let authError as AuthError {
            throw mapAuthError(authError)
        } catch {
            throw APIError.other(message: error.localizedDescription)
        }
    }

    // MARK: - Sign in

    func signIn(email: String, password: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            _ = try await client.auth.signIn(email: email, password: password)
            currentCaregiver = try await onAuthenticated?(nil)
        } catch let apiError as APIError {
            // Backend-side error after Supabase succeeded — surface so
            // the UI can show it. User is signed in server-side.
            throw apiError
        } catch let authError as AuthError {
            throw mapAuthError(authError)
        } catch {
            throw APIError.other(message: error.localizedDescription)
        }
    }

    // MARK: - Sign out

    func signOut() async {
        try? await client.auth.signOut()
        currentCaregiver = nil
        await onSignedOut?()
    }

    // MARK: - Restore session

    /// Called once at app launch. The SDK auto-restores any cached
    /// session from Keychain in its init; we just check whether the
    /// session is alive and, if so, run the same `onAuthenticated`
    /// path so views get a populated roster on cold launch.
    func restoreSession() async {
        do {
            _ = try await client.auth.session  // throws if no session
            currentCaregiver = try await onAuthenticated?(nil)
        } catch {
            // No session on disk — user is signed out. No-op.
        }
    }

    // MARK: - Token provider

    /// Current Supabase access JWT. Read by `NemaraAPIClient` before
    /// every authenticated request. Returns nil when no session exists.
    func currentAccessToken() async -> String? {
        do {
            let session = try await client.auth.session
            return session.accessToken
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func mapAuthError(_ error: AuthError) -> APIError {
        if error.errorDescription?.localizedCaseInsensitiveContains("invalid login") == true
            || error.errorDescription?.localizedCaseInsensitiveContains("invalid credentials") == true {
            return .unauthorized
        }
        return .other(message: error.errorDescription ?? "Sign-in failed.")
    }
}
