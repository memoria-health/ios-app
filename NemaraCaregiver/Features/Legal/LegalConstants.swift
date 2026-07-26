import Foundation

/// Single source of truth for the legal-document acceptance gate.
///
/// Keep `currentTosVersion` in sync with the web app's `CURRENT_TOS_VERSION`
/// and the backend's `KNOWN_TOS_VERSIONS` allowlist — the server rejects any
/// other value. `documents` are bundled PDFs (Resources/Legal/); swap those
/// files for the finalized docs when ready.
enum LegalConstants {
    static let currentTosVersion = "2026-07-26-placeholder"

    struct Doc: Identifiable, Sendable {
        let id: String
        let title: String
        /// Bundle resource name (without the .pdf extension).
        let resource: String
    }

    static let documents: [Doc] = [
        Doc(id: "terms", title: "Terms of Service", resource: "terms"),
        Doc(id: "privacy", title: "Privacy Notice", resource: "privacy"),
    ]
}
