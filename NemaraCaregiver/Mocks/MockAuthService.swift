import Foundation

/// In-memory `AuthService` for v0. Sign-up and sign-in always succeed
/// and produce a caregiver named from the provided `displayName` /
/// `email`. There is no persistence; relaunching the app returns the
/// user to the Welcome screen.
///
/// This entire file goes away when real auth lands. See `Mocks/`
/// containment rule in the README.
@MainActor
final class MockAuthService: AuthService {

    /// Tiny delay so the in-flight spinner is briefly visible — gives
    /// the UI a chance to demonstrate its loading state during demos.
    private static let mockLatency: Duration = .milliseconds(450)

    override func signUp(displayName: String, email: String, password: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }

        try? await Task.sleep(for: Self.mockLatency)

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName  = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !trimmedName.isEmpty else {
            throw AuthError.message("Name and email are required.")
        }

        let caregiver = Caregiver(
            id: UUID(),
            displayName: trimmedName,
            email: trimmedEmail
        )
        currentCaregiver = caregiver
        await onAuthenticated?(caregiver)
    }

    override func signIn(email: String, password: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }

        try? await Task.sleep(for: Self.mockLatency)

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            throw AuthError.invalidCredentials
        }

        // Derive a display name from the email local-part so the post-
        // login UI has something to greet the user with. When real auth
        // lands, this comes from the caregiver row instead.
        let local = trimmedEmail.split(separator: "@").first.map(String.init) ?? "Caregiver"
        let firstName = local
            .split(whereSeparator: { ".+_-".contains($0) })
            .first
            .map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Jane"

        let caregiver = Caregiver(
            id: UUID(),
            displayName: String(firstName),
            email: trimmedEmail
        )
        currentCaregiver = caregiver
        await onAuthenticated?(caregiver)
    }
}
