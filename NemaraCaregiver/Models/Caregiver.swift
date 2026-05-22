import Foundation

/// The authenticated user of the Nemara caregiver app. Identified by a
/// Supabase user id once real auth ships; for now any non-empty `email`
/// + `displayName` constitutes a signed-in caregiver.
struct Caregiver: Identifiable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var email: String
}
