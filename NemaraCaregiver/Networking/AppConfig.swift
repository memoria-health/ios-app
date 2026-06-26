import Foundation

/// `AppConfig` — single static configuration the app reads at launch.
///
/// Resolution order for every field:
///   1. `LocalAppConfig.<field>` — per-developer override, gitignored via
///      skip-worktree. The right place to point YOUR Debug build at YOUR
///      stack (local Supabase, your Mac's ngrok URL, etc.). Wins because
///      it travels with the binary, so the app works the same whether
///      launched from Xcode or from the home-screen icon.
///   2. `ProcessInfo.processInfo.environment[<KEY>]` — runtime env var,
///      useful for CI/CD or one-off `KEY=val xcrun ...` invocations. Not
///      populated by the bundled scheme anymore.
///   3. `#if DEBUG` fallback — Sunny's Mac via Bonjour. Lets the canonical
///      dev stack run on Sunny's machine without any per-dev setup.
///   4. `#if !DEBUG` (Release) — production Supabase + Railway backend.
///      What real users hit.
enum AppConfig {

    /// Supabase project URL. Override via `LocalAppConfig.supabaseURL`
    /// or `SUPABASE_URL` env. Release builds default to prod Supabase.
    static let supabaseURL: URL? = {
        #if DEBUG
        if let override = LocalAppConfig.supabaseURL {
            return override
        }
        if let fromEnv = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            .flatMap(URL.init) {
            return fromEnv
        }
        // Local Supabase started by `supabase start`, API on port 54341.
        // Bonjour hostname resolves to whichever Mac is currently
        // running nemara-backend on this Wi-Fi network. Tracks Sunny's
        // machine by default; if you're another dev, set
        // `LocalAppConfig.supabaseURL` to your own LAN IP / hostname.
        return URL(string: "http://sunnys-macbook-air.local:54341")
        #else
        // Release / Archive / TestFlight / App Store: ALWAYS prod. Never
        // consult LocalAppConfig (skip-worktree — a dev's local LAN IP must
        // NOT leak into a distribution build) or env vars.
        return URL(string: "https://zgifmvjnggmgzvtnosnu.supabase.co")
        #endif
    }()

    /// Supabase anon (publishable) key. Override via
    /// `LocalAppConfig.supabaseAnonKey` or `SUPABASE_ANON_KEY` env.
    /// Publishable / anon keys are designed to be shipped in client
    /// apps; safe to embed.
    static let supabaseAnonKey: String? = {
        #if DEBUG
        if let override = LocalAppConfig.supabaseAnonKey, !override.isEmpty {
            return override
        }
        if let raw = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
           !raw.isEmpty {
            return raw
        }
        // Local Supabase publishable key, deterministic per supabase-cli
        // version. Refresh via `supabase status -o env | grep
        // PUBLISHABLE_KEY` if a CLI upgrade ever changes it.
        return "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
        #else
        // Release: ALWAYS the prod publishable key; ignore any override.
        return "sb_publishable_OsfCMOdEIb5gvhRWDyNivg_7GriAmyP"
        #endif
    }()

    /// Redirect URL Supabase sends users to after they tap a
    /// password-reset email. Must be on the project's "Redirect URLs"
    /// allow-list. Wiring lands in a later plan.
    static let supabasePasswordResetRedirect = URL(string: "nemara://reset-password")!

    /// nemara-backend API base URL. Override via
    /// `LocalAppConfig.backendURL` or `NEMARA_BACKEND_URL` env. Release
    /// builds default to the Railway production deployment.
    static let backendURL: URL = {
        #if DEBUG
        if let override = LocalAppConfig.backendURL {
            return override
        }
        if let fromEnv = ProcessInfo.processInfo.environment["NEMARA_BACKEND_URL"]
            .flatMap(URL.init) {
            return fromEnv
        }
        // Bonjour/mDNS hostname for Sunny's Mac. If you're another dev,
        // set `LocalAppConfig.backendURL` to your own (e.g. an ngrok
        // URL that publishes your local uvicorn).
        return URL(string: "http://sunnys-macbook-air.local:8002")!
        #else
        // Release / Archive / TestFlight / App Store: ALWAYS the Railway
        // prod backend. Never consult LocalAppConfig (skip-worktree — a
        // dev's local LAN IP / ngrok must NOT leak into a distribution
        // build) or the env var.
        return URL(string: "https://nemara-backend-production.up.railway.app")!
        #endif
    }()

    /// `true` when both Supabase config values are populated. Gate-keeper
    /// for `SupabaseAuthService` — refuses to construct its client if
    /// either is nil so we get a clear error rather than a runtime crash.
    static var isSupabaseConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }

    /// Dev-only feature flag for the data-collection "Capture 15s clip"
    /// button on the Live camera tile. NOT a production feature — it
    /// triggers the wall camera to record a short clip and ship it to a
    /// laptop receiver for detector test data. Off by default so it never
    /// appears in a normal build. Enable per-dev via
    /// `LocalAppConfig.enableClipCapture = true` or the
    /// `NEMARA_ENABLE_CLIP_CAPTURE` env var.
    static let enableClipCapture: Bool = {
        #if DEBUG
        if let override = LocalAppConfig.enableClipCapture {
            return override
        }
        if let raw = ProcessInfo.processInfo.environment["NEMARA_ENABLE_CLIP_CAPTURE"] {
            return (raw as NSString).boolValue
        }
        return false
        #else
        // Release / Archive / TestFlight / App Store: the data-collection clip
        // button is a dev-only research tool and must NEVER ship. Hard-compile it
        // OFF so no leftover `LocalAppConfig.enableClipCapture = true` (that file
        // is skip-worktree, so a dev's local `true` persists on the machine that
        // cuts the build) and no scheme env var can re-enable it in a
        // distribution build. This is the single choke point for the whole clip
        // chain: button → backend → camera `record_trigger`. Off here = the
        // camera is never told to record in production.
        return false
        #endif
    }()
}
