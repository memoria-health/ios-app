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
    /// `signUpPhone` is non-nil only on the signUp path (provisioned into the
    /// caregiver row); nil on signIn / restore (the existing row is fetched).
    var onAuthenticated: ((_ signUpDisplayName: String?, _ signUpPhone: String?, _ signUpTosVersion: String?) async throws -> Caregiver)?

    /// Called at the START of sign-out, while the Supabase session is
    /// still valid (so authed calls still work). AppEnvironment wires
    /// this to de-register this device's APNs token, so a signed-out
    /// caregiver stops receiving pushes on a device they've left.
    var onWillSignOut: (() async -> Void)?

    /// Called when the user signs out. AppEnvironment wires this to
    /// `NemaraAPIClient.teardown()` so cached observable state is
    /// cleared and any open Realtime channels close.
    var onSignedOut: (() async -> Void)?

    /// Called when the user permanently deletes their account.
    /// AppEnvironment wires this to `NemaraAPIClient.deleteAccount()`
    /// (DELETE /v1/me), keeping the API client out of this class's
    /// dependency graph exactly like `onAuthenticated` / `onSignedOut`.
    var onDeleteAccount: (() async throws -> Void)?

    /// Underlying Supabase client. Shared with `NemaraAPIClient` for
    /// Realtime subscriptions.
    let client: SupabaseClient

    /// Long-running consumer of `client.auth.authStateChanges`. Pumps
    /// every token change into `realtimeV2.setAuth(...)` so RLS policies
    /// on subscribed channels evaluate `auth.uid()` against the
    /// signed-in user instead of `NULL`. Without this, Realtime
    /// silently drops every row that any RLS policy gates on the
    /// caregiver (events, analyses, …).
    ///
    /// No explicit cancellation: this service lives for the entire app
    /// lifetime (one instance, from launch to termination), so the
    /// task is implicitly torn down with the process. Adding a deinit
    /// cancel under Swift 6's strict concurrency would require
    /// nonisolated reads of an actor-isolated property — not worth
    /// the friction for a no-op cleanup.
    private var authStateTask: Task<Void, Never>?

    init() {
        guard let url = AppConfig.supabaseURL,
              let key = AppConfig.supabaseAnonKey,
              !key.isEmpty
        else {
            fatalError("Supabase isn't configured. Set SUPABASE_URL + SUPABASE_ANON_KEY (or run in DEBUG with the bundled local-stack defaults).")
        }
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: key)

        // Forward every auth state change (signedIn / signedOut /
        // tokenRefreshed / userUpdated / initialSession) to the
        // Realtime client so subscribed channels carry the user JWT.
        // The SDK fires this on cold launch with the cached session
        // too, which covers the restoreSession path automatically.
        let c = client
        authStateTask = Task {
            for await (_, session) in c.auth.authStateChanges {
                await c.realtimeV2.setAuth(session?.accessToken)
            }
        }
    }

    // MARK: - Sign up

    func signUp(displayName: String, email: String, password: String, phone: String, tosVersion: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let response = try await client.auth.signUp(email: email, password: password)
            // Email-confirmation projects don't return a session here.
            guard response.session != nil else {
                throw APIError.other(message: "Check your email to confirm your account.")
            }
            currentCaregiver = try await onAuthenticated?(displayName, phone, tosVersion)
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
            currentCaregiver = try await onAuthenticated?(nil, nil, nil)
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

    // MARK: - Password reset

    /// Step 1 of the forgot-password flow. Asks Supabase to email the
    /// user a recovery link. The link points at
    /// `nemara://reset-password?code=…`; the deep-link handler in
    /// `NemaraCaregiverApp` routes that into `ResetPasswordView`,
    /// which calls `exchangeRecoveryCode(_:)` + `updatePassword(_:)`
    /// to finish the flow.
    ///
    /// Supabase returns success whether or not the email is registered
    /// (privacy). We mirror that in the UI — never reveal whether the
    /// address has an account.
    ///
    /// The `redirectTo` must be on the project's Auth → URL
    /// Configuration allow-list or Supabase silently drops the link.
    func requestPasswordReset(email: String) async throws {
        do {
            try await client.auth.resetPasswordForEmail(
                email,
                redirectTo: AppConfig.supabasePasswordResetRedirect,
            )
        } catch let authError as AuthError {
            throw mapAuthError(authError)
        } catch {
            throw APIError.other(message: error.localizedDescription)
        }
    }

    /// Step 2: trade the `?code=…` from the recovery deep link for a
    /// recovery session. The SDK puts the result into the auth client
    /// so the next `updateUser(password:)` call is authorized as the
    /// recovering user. Returns the email of the recovering account so
    /// the UI can show "Reset password for jane@…" for confirmation.
    func exchangeRecoveryCode(_ code: String) async throws -> String? {
        do {
            let session = try await client.auth.exchangeCodeForSession(authCode: code)
            return session.user.email
        } catch let authError as AuthError {
            throw mapAuthError(authError)
        } catch {
            throw APIError.other(message: error.localizedDescription)
        }
    }

    /// Step 3: set the new password against the active recovery
    /// session. After this resolves, the recovery session is a fully-
    /// signed-in session and `onAuthenticated` should run so views
    /// populate.
    func updatePassword(_ newPassword: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            _ = try await client.auth.update(user: UserAttributes(password: newPassword))
            currentCaregiver = try await onAuthenticated?(nil, nil, nil)
        } catch let apiError as APIError {
            throw apiError
        } catch let authError as AuthError {
            throw mapAuthError(authError)
        } catch {
            throw APIError.other(message: error.localizedDescription)
        }
    }

    // MARK: - Email change

    /// Asks Supabase Auth to change the user's email. Triggers a
    /// confirmation link to the new address (and, depending on the
    /// project's Secure-Email-Change setting, also to the old one).
    /// Until the user clicks it, `auth.users.email` is unchanged and
    /// the DB trigger that mirrors into `caregivers.email` does not
    /// fire — so `currentCaregiver.email` keeps returning the old
    /// value, which is the correct behavior to display.
    func requestEmailChange(_ newEmail: String) async throws {
        do {
            _ = try await client.auth.update(user: UserAttributes(email: newEmail))
        } catch let authError as AuthError {
            throw mapAuthError(authError)
        } catch {
            throw APIError.other(message: error.localizedDescription)
        }
    }

    // MARK: - Sign out

    func signOut() async {
        // De-register the device token FIRST, while the session is still
        // valid (the authed DELETE needs a live token). Best-effort.
        await onWillSignOut?()
        try? await client.auth.signOut()
        currentCaregiver = nil
        await onSignedOut?()
    }

    // MARK: - Delete account

    /// Permanently delete the account. Runs the backend delete (via the
    /// injected `onDeleteAccount` closure → DELETE /v1/me), then tears
    /// down the now-dead local session exactly like `signOut`. The
    /// Supabase sign-out is best-effort (`try?`) because the auth user no
    /// longer exists once the backend call succeeds. Throws if the
    /// backend delete fails — the caller keeps the user signed in and
    /// surfaces the error rather than leaving a half-deleted account.
    func deleteAccount() async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        try await onDeleteAccount?()
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
            currentCaregiver = try await onAuthenticated?(nil, nil, nil)
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
