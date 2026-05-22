import Foundation

/// `AppConfig` — single static configuration the app reads at launch.
///
/// All deployment-specific values are sourced from process environment
/// variables, so the same binary works for local dev, staging, and
/// production. Set the env vars in the Xcode scheme (Run → Arguments →
/// Environment Variables); the bundled scheme already points at the
/// local nemara-backend + Supabase stack so a fresh clone runs out of
/// the box.
///
/// Recognized variables:
/// - `SUPABASE_URL`        — e.g. `http://127.0.0.1:54341` (local) or
///                            `https://<project>.supabase.co`
/// - `SUPABASE_ANON_KEY`   — the publishable anon key
/// - `NEMARA_BACKEND_URL`  — e.g. `http://127.0.0.1:8002` (local) or
///                            production URL
enum AppConfig {

    /// Supabase project URL. Env-var first, then a Debug-only baked-in
    /// fallback pointing at the local stack. Release builds must have
    /// `SUPABASE_URL` set — no fallback.
    static let supabaseURL: URL? = {
        if let fromEnv = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            .flatMap(URL.init) {
            return fromEnv
        }
        #if DEBUG
        return URL(string: "http://127.0.0.1:54341")
        #else
        return nil
        #endif
    }()

    /// Supabase anon (publishable) key. Env-var first, then a Debug-only
    /// fallback. Publishable / anon keys are designed to be shipped in
    /// client apps; safe to embed.
    static let supabaseAnonKey: String? = {
        if let raw = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
           !raw.isEmpty {
            return raw
        }
        #if DEBUG
        // Local-Supabase legacy anon JWT, generated deterministically
        // from the well-known local JWT secret. Identical across every
        // developer's `supabase start`. Not a real secret.
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        #else
        return nil
        #endif
    }()

    /// Redirect URL Supabase sends users to after they tap a
    /// password-reset email. Must be on the project's "Redirect URLs"
    /// allow-list. Wiring lands in a later plan.
    static let supabasePasswordResetRedirect = URL(string: "nemara://reset-password")!

    /// nemara-backend API base URL.
    static let backendURL: URL = {
        if let fromEnv = ProcessInfo.processInfo.environment["NEMARA_BACKEND_URL"]
            .flatMap(URL.init) {
            return fromEnv
        }
        #if DEBUG
        return URL(string: "http://127.0.0.1:8002")!
        #else
        // Production domain TBD — placeholder so Release builds fail
        // loudly if the env var isn't wired in CI.
        return URL(string: "https://api.nemara.app")!
        #endif
    }()

    /// `true` when both Supabase config values are populated. Gate-keeper
    /// for `SupabaseAuthService` — refuses to construct its client if
    /// either is nil so we get a clear error rather than a runtime crash.
    static var isSupabaseConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }
}
