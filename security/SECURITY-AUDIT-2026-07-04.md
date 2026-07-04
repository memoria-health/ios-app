# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-07-04
**Scope:** Static source review of `nemara-caregiver-app` (native iOS / SwiftUI, Swift 6).
**Methodology:** [vibe-security](https://github.com/raroque/vibe-security-skill) skill, mobile-prioritized. Static only — no live services, secrets, or network access were used.
**Reviewer:** Automated security-audit routine.

---

## Executive Summary

The codebase is, overall, in good security shape. Secrets are handled correctly, session tokens are stored in the Keychain, all third-party calls that require secret keys are proxied through the backend, App Transport Security is not weakened for production hosts, the dev-only clip-capture feature is hard-compiled off in release, and Supabase Realtime is RLS-scoped server-side. No committed secrets, no `NSAllowsArbitraryLoads`, no client-side authorization decisions, and no client-embedded AI/LLM keys were found.

Two genuine, substantiated issues remain, both hardening gaps rather than active breaches:

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | **Medium** | Password-reset recovery code delivered over a hijackable custom URL scheme | `NemaraCaregiverApp.swift:136`, `Info.plist` `CFBundleURLTypes` |
| 2 | **Low** | No TLS certificate / public-key pinning on backend + Supabase connections carrying biometric/PII data | `NemaraAPIClient.swift`, `SupabaseAuthService.swift` |

There are **no Critical or High findings.** Given the sensitivity of the data this app handles (live audio/video into a vulnerable person's home, patient face-embedding biometrics, health-adjacent event history), addressing finding #1 is the recommended priority.

---

## Findings

### Medium

#### 1. Password-reset recovery code delivered over a hijackable custom URL scheme

**Files:**
- `NemaraCaregiver/App/NemaraCaregiverApp.swift:136-151` (`handleIncomingURL`)
- `NemaraCaregiver/Services/SupabaseAuthService.swift:164-191` (`requestPasswordReset` / `exchangeRecoveryCode`)
- `NemaraCaregiver/Networking/AppConfig.swift:71` (`supabasePasswordResetRedirect = nemara://reset-password`)
- `NemaraCaregiver/Resources/Info.plist:21-31` — `CFBundleURLTypes` registers the `nemara` scheme

**What the code does.** The forgot-password flow asks Supabase to email the user a recovery link that points at `nemara://reset-password?code=<recovery_code>`. When the user taps it, `.onOpenURL` → `handleIncomingURL` extracts the `code` query parameter and passes it to `exchangeRecoveryCode(_:)`, which calls `client.auth.exchangeCodeForSession(authCode:)` — trading the code for a **fully-authenticated session** and then allowing a password change.

**Why it's exploitable.** Custom URL schemes on iOS are not exclusive: any app may declare the same `nemara` scheme in its own `CFBundleURLTypes`, and iOS's choice of which app receives the link when more than one claims it is undefined. A malicious app installed on the same device can therefore register `nemara://` and intercept the recovery link (and its `code`) when the victim taps it from their email. Because the `code` is a bearer credential that `exchangeCodeForSession` turns into a live session, interception yields **full account takeover** — including live camera/mic access into the care recipient's home. This is precisely the "never put tokens in deep-link URLs / validate deep links" concern in the mobile reference, compounded by the scheme being unauthenticated.

**Concrete fix.** Deliver security-sensitive callbacks over **Universal Links** (HTTPS `https://<verified-domain>/reset-password?code=…`) instead of a custom scheme. Universal Links are cryptographically bound to a domain you control via an `apple-app-site-association` file and cannot be claimed by another app.

```
// 1. Add an Associated Domains entitlement:
//    NemaraCaregiver-Release.entitlements
<key>com.apple.developer.associated-domains</key>
<array><string>applinks:nemara.co</string></array>

// 2. Host https://nemara.co/.well-known/apple-app-site-association
//    binding /reset-password to this app's App ID.

// 3. Point the Supabase redirect at the HTTPS URL:
static let supabasePasswordResetRedirect = URL(string: "https://nemara.co/reset-password")!

// 4. Handle it in .onContinueUserActivity(NSUserActivityTypeBrowsingWeb)
//    (or keep .onOpenURL — it also fires for universal links) and
//    reject any nemara:// recovery link that arrives via the custom scheme.
```

If a custom scheme must remain for other flows, at minimum stop routing the password-reset `code` through it.

---

### Low

#### 2. No TLS certificate / public-key pinning on data-plane connections

**Files:**
- `NemaraCaregiver/Services/NemaraAPIClient.swift:103-110` — uses `URLSession.shared` with no `URLSessionDelegate` / pinning
- `NemaraCaregiver/Services/SupabaseAuthService.swift:92` — `SupabaseClient` created with default (unpinned) transport

**What the code does.** All backend traffic (`nemara-backend-production.up.railway.app`) and all Supabase traffic — including patient avatar uploads, **face-embedding biometrics**, signed clip URLs, live-session tokens, and the caregiver's JWT — flows over a stock, unpinned `URLSession` / Supabase transport.

**Why it matters.** Standard iOS ATS already enforces TLS for these routable HTTPS hosts (correctly configured here — see Notes), so this is **not** a plaintext-exposure bug and is defense-in-depth only. However, without pinning the app trusts any certificate chaining to a system-trusted root. An attacker able to install a rogue trusted root (malicious configuration profile, compromised/hostile MDM, or a mis-issued CA certificate) could man-in-the-middle the connection and read/modify this sensitive data. For an app carrying biometric and in-home A/V data, pinning is a recommended hardening.

**Concrete fix.** Pin the leaf or intermediate public key for the backend and Supabase hosts. With a custom `URLSession`, implement `urlSession(_:didReceive:completionHandler:)` and compare the server key against a bundled SPKI hash; for Supabase, inject a session configured the same way. Prefer pinning the intermediate/public key (not the leaf) and ship a backup pin so certificate rotation doesn't brick the app.

```swift
final class PinningDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge,
                    completionHandler ch: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let trust = c.protectionSpace.serverTrust,
              pinnedSPKIHashes.contains(spkiSHA256(of: trust)) else {
            return ch(.cancelAuthenticationChallenge, nil)   // reject unknown chains
        }
        ch(.useCredential, URLCredential(trust: trust))
    }
}
```

---

## Notes — Reviewed and Confirmed *Not* Vulnerabilities

These were checked explicitly and are **correct** (documented to show coverage and avoid re-flagging):

- **Hardcoded Supabase URL + anon/publishable keys** (`AppConfig.swift:41,61,64,94`). The `sb_publishable_*` keys and project/backend URLs are *designed* to ship in clients; the anon key's authority is bounded entirely by Row-Level Security. No `service_role` key, `sk_*` secret, JWT signing secret, or DB connection string appears anywhere in the source. **Not a finding.**
- **Session-token storage.** No auth token is written to `UserDefaults`. The Supabase SDK persists the session in the iOS **Keychain** (`SupabaseAuthService.swift:263`). `UserDefaults` is used only for non-sensitive UI flags (ever-online camera UUIDs, onboarding/tutorial booleans). **Correct.**
- **App Transport Security.** `Info.plist` sets only `NSAllowsLocalNetworking` (for LAN dev stacks). There is **no** `NSAllowsArbitraryLoads`; production hosts remain TLS-enforced. **Correct.**
- **AI / LLM integration.** Detector inference (`inferDetector`, `NemaraAPIClient.swift:757`) is proxied through the backend (`POST /v1/detectors/infer`). No OpenAI/Anthropic/other model key is embedded in the app. **Correct — matches the "backend proxy" guidance.**
- **Dev-only clip capture.** The camera-recording research tool is compile-gated `false` under `#if !DEBUG` (`AppConfig.swift:122-131`), so it cannot be re-enabled in a distribution build by any leftover local flag or env var. **Correct.**
- **Supabase Realtime.** Channels rely on server-side RLS to filter rows per caregiver (`NemaraAPIClient.swift:1134`), and the JWT is pushed into `realtimeV2.setAuth` on every auth-state change. **Correct — no client-side trust.**
- **`"Mar9aret!"` string** (`NemaraField.swift:149`). A placeholder inside a `#if DEBUG` SwiftUI `#Preview`, not a real credential; excluded from release. **Not a finding.**
- **Committed files.** No `.env`, `.p8`/`.p12`, `.mobileprovision`, `GoogleService-Info.plist`, or key material is tracked. `Local.xcconfig` (per-dev signing overrides) is git-ignored. **Correct.**

## Recommendations Requiring Backend Confirmation (not statically verifiable here)

- **LiveKit token role authorization.** The client requests `role: "broadcaster"` vs `"viewer"` when minting a room token (`NemaraAPIClient.swift:884-908`). The client comment states the server validates and re-mints; ensure the backend independently authorizes that the caller owns the target `patient_<id>` room and is entitled to publish — never trust the client-supplied role/identity. (Cannot be confirmed from the iOS source alone.)
- **Password policy on reset.** `ResetPasswordView` enforces only `count >= 8` client-side (`ResetPasswordView.swift:32-34`); confirm Supabase's server-side password policy is at least as strong.

---

### Summary

1. **Password-reset code over a custom URL scheme (Medium):** move the recovery callback to Universal Links so a rogue app can't intercept the code and take over accounts.
2. **No TLS pinning (Low):** add certificate/public-key pinning to the backend and Supabase transports to protect biometric/PII data against rogue-CA MITM.

Everything else reviewed (secrets, token storage, ATS, AI proxying, RLS, deep-link routing surface, committed files) is handled correctly.
