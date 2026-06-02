import Foundation

/// Per-developer overrides for `AppConfig`. All-nil = "no override, use the
/// AppConfig defaults" (which fall through ProcessInfo env, then a Debug
/// fallback hardcoded for Sunny's Mac, then the Release production URLs).
///
/// This file is committed once with nil defaults so the build never breaks
/// on a fresh clone. After your first checkout, mark it skip-worktree so
/// your personal edits are silently ignored by git:
///
///   git update-index --skip-worktree NemaraCaregiver/Networking/LocalAppConfig.swift
///
/// Then edit the values below to point a Debug build at YOUR stack
/// (your Mac's IP/hostname, your ngrok URL, your local Supabase, etc.).
/// The binary built from your edits will hit YOUR backend whether launched
/// from Xcode or from the home-screen icon — no scheme env vars required.
///
/// To pull upstream changes (e.g. a new override field added here), undo
/// the skip-worktree, pull, re-apply your overrides, then re-skip:
///
///   git update-index --no-skip-worktree NemaraCaregiver/Networking/LocalAppConfig.swift
///   git pull
///   <re-apply your overrides>
///   git update-index --skip-worktree NemaraCaregiver/Networking/LocalAppConfig.swift
enum LocalAppConfig {
    /// Override for `AppConfig.supabaseURL`. Typical local value:
    /// `URL(string: "http://<your-mac-lan-ip>:54341")`.
    static let supabaseURL: URL? = nil

    /// Override for `AppConfig.supabaseAnonKey`. The well-known local
    /// publishable key works for every dev's `supabase start`, so this
    /// is rarely needed — leave nil unless you're pointing at a non-
    /// local Supabase project.
    static let supabaseAnonKey: String? = nil

    /// Override for `AppConfig.backendURL`. Typical local value when
    /// publishing your local uvicorn via ngrok:
    /// `URL(string: "https://<your-ngrok-subdomain>.ngrok-free.dev")`.
    static let backendURL: URL? = nil

    /// Override for `AppConfig.enableClipCapture`. Dev-only data-collection
    /// flag for the "Capture 15s clip" button on the Live tile — set to
    /// `true` to show it in your Debug build. nil = use the default (off).
    static let enableClipCapture: Bool? = nil
}
