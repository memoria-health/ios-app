# Security Audit — NemaraCaregiver (iOS)

**Date:** 2026-06-10
**Scope:** Static source review of the `nemara-caregiver-app` repository (native iOS / SwiftUI / Swift 6).
**Methodology:** `vibe-security` skill (Chris Raroque), adapted from its web/React-Native framing to a native iOS client. Static only — no live services, secrets, or network access were used.
**Reviewer:** Automated security audit (Claude, scheduled remote agent).

---

## Executive Summary

NemaraCaregiver is a thin native-iOS client over a FastAPI backend (`nemara-backend` on Railway), Supabase (Auth + Postgres + Realtime), and LiveKit Cloud (live audio/video). It handles sensitive data: PII of caregivers and care-recipients, in-home camera video/audio of (often elderly/vulnerable) patients, push tokens, and health-adjacent "detection events."

The good news: the client is well-architected from a security standpoint. **No exploitable Critical or High vulnerabilities were found in the client code.** All authorization is delegated to the backend (JWT + Supabase RLS), session tokens are stored in the iOS Keychain (via the Supabase SDK) rather than `UserDefaults`, the only secrets embedded in the binary are Supabase **publishable** keys (designed to ship in clients), and the LLM detector-inference call is proxied through the backend — there is no AI provider key on the device.

The findings below are **hardening / defense-in-depth** items rather than active breaches. The two most material are: (1) password-reset recovery is delivered over a hijackable custom URL scheme rather than Universal Links, and (2) the app does no TLS certificate pinning despite carrying in-home video and PII. Several backend-dependent behaviors (LiveKit room/role authorization) cannot be confirmed statically and are flagged for verification.

| # | Severity | Title |
|---|----------|-------|
| 1 | Medium | Password-reset recovery code delivered over a hijackable custom URL scheme (no Universal Links) |
| 2 | Medium | No TLS certificate / public-key pinning for a health + in-home-video app |
| 3 | Low | LiveKit token `room` and `role` are fully client-controlled — backend authorization must be verified |
| 4 | Low | Verbose DEBUG logging of raw HTTP response bodies |
| 5 | Info | Items reviewed and confirmed **not** vulnerable (documented to show coverage) |

---

## Medium

### 1. Password-reset recovery code is delivered over a hijackable custom URL scheme (no Universal Links)

**Files:**
- `NemaraCaregiver/Resources/Info.plist:21-31` (registers the `nemara` custom scheme)
- `NemaraCaregiver/App/NemaraCaregiverApp.swift:113-128` (`handleIncomingURL` → extracts `?code=` from `nemara://reset-password`)
- `NemaraCaregiver/Services/SupabaseAuthService.swift:158-185` (`requestPasswordReset` sets `redirectTo: nemara://reset-password`; `exchangeRecoveryCode` trades the code for a session)
- `NemaraCaregiver/Resources/NemaraCaregiver-Release.entitlements` (no `com.apple.developer.associated-domains` — confirmed absent)

**What the code does.** The forgot-password flow asks Supabase to email a recovery link whose `redirectTo` is the **custom URL scheme** `nemara://reset-password?code=…` (`AppConfig.supabasePasswordResetRedirect`, `AppConfig.swift:67`). When the user taps the email link, iOS routes the URL to whichever installed app claims the `nemara` scheme; the app pulls the `code` query param and exchanges it for a recovery session, after which the user can set a new password.

**Why this is a risk.** Custom URL schemes are **not exclusive** on iOS — any other installed app may register `nemara://`, and when two apps claim the same scheme the OS resolution is undefined (in practice often "last installed wins"). A malicious app on the same device can therefore intercept the recovery deep link and capture the `code`. If that code alone were sufficient to mint a recovery session, this would be a full **account-takeover** path — and given the account grants live audio/video into a vulnerable person's home, the impact would be severe.

**Mitigating factor (why Medium, not High).** The Supabase Swift SDK defaults to the **PKCE** flow, and the client is constructed with no overriding options (`SupabaseAuthService.swift:86` → `SupabaseClient(supabaseURL:supabaseKey:)`). Under PKCE, the `code_verifier` is generated on the device that *initiated* the reset and stored in that app's sandboxed Keychain. An intercepting app cannot read the legitimate app's Keychain and so cannot complete `exchangeCodeForSession` with the stolen code. PKCE thus blocks the takeover as currently configured. The residual risk is: (a) interception still lets a hostile app deny/observe the reset, (b) the protection silently evaporates if anyone ever sets `flowType` to `.implicit`, and (c) custom schemes are a non-best-practice attack surface for an app of this sensitivity.

**Fix.** Migrate the recovery redirect to a **Universal Link** (HTTPS, ownership-verified via Apple App Site Association), which only the rightful app can claim:

```diff
# Release.entitlements (add)
+ <key>com.apple.developer.associated-domains</key>
+ <array>
+   <string>applinks:nemara.app</string>
+ </array>
```
```swift
// AppConfig.swift — point the reset redirect at an https Universal Link
- static let supabasePasswordResetRedirect = URL(string: "nemara://reset-password")!
+ static let supabasePasswordResetRedirect = URL(string: "https://nemara.app/reset-password")!
```
Host `/.well-known/apple-app-site-association` and update the handler to parse the link from `.onContinueUserActivity`/`webpageURL`. Until then: **do not disable PKCE**, and keep the redirect on the project's Supabase allow-list so arbitrary redirects can't be injected.

---

### 2. No TLS certificate / public-key pinning for a health + in-home-video app

**Files:**
- `NemaraCaregiver/Services/NemaraAPIClient.swift:102` (`session: URLSession = .shared`), `:1028-1041` (all requests via `session.data(for:)`)
- `NemaraCaregiver/Services/SupabaseAuthService.swift:86` (default `SupabaseClient`), `LiveKitClient.swift` (default LiveKit `Room`)
- No `URLSessionDelegate` / `urlSession(_:didReceive:)` / `SecTrust` evaluation anywhere (confirmed by grep)

**What the code does.** Every network call — backend REST (PII, JWTs, signed media URLs), Supabase Auth/Realtime, and LiveKit signaling — goes over standard `URLSession`/SDK TLS with **no certificate or public-key pinning**. Trust relies entirely on the system CA store.

**Why this is a risk.** Standard TLS protects against passive eavesdroppers, but not against an attacker who can present a CA-trusted certificate: a user-installed/MDM root profile, a compromised or coerced public CA, or a corporate TLS-inspection proxy. Such an adversary can MITM the connection and read or alter the caregiver's Bearer JWT, the patient roster and detection events, signed clip/photo URLs, and LiveKit join tokens — i.e. gain access to live in-home audio/video of a vulnerable person. The `vibe-security` mobile checklist explicitly calls out missing certificate pinning; for an eldercare surveillance + health-adjacent app, this is a meaningful defense-in-depth gap rather than a "nice to have."

**Fix.** Pin the backend and Supabase hosts. The lowest-friction option is declarative pinning in `Info.plist` via ATS `NSPinnedDomains` (iOS 14+), keyed to the SPKI hash of the leaf/intermediate, with a backup pin to allow rotation:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSPinnedDomains</key>
  <dict>
    <key>nemara-backend-production.up.railway.app</key>
    <dict>
      <key>NSPinnedCAIdentities</key>
      <array>
        <dict><key>SPKI-SHA256-BASE64</key><string>BASE64_PRIMARY_PIN==</string></dict>
        <dict><key>SPKI-SHA256-BASE64</key><string>BASE64_BACKUP_PIN==</string></dict>
      </array>
    </dict>
  </dict>
</dict>
```
For finer control (and to cover the LiveKit/Supabase SDK sockets), implement a `URLSessionDelegate` that evaluates `serverTrust` against pinned SPKI hashes and inject it into `NemaraAPIClient`'s `URLSession`. Always ship a backup pin and a rotation plan to avoid bricking the app on cert renewal.

---

## Low

### 3. LiveKit token `room` and `role` are fully client-controlled — backend authorization must be verified

**File:** `NemaraCaregiver/Services/NemaraAPIClient.swift:852-882` (`mintViewerToken` / `mintBroadcasterToken` / `mintToken`)

**What the code does.** The client decides both the room (`"patient_\(pid)"`) and the privilege level (`role: "viewer"` vs `role: "broadcaster"`, the latter granting `canPublish`) and POSTs them to `/v1/livekit/token`. The inline comment states the server "validates the prefix and re-mints," but the `pid` and `role` originate entirely from the client.

**Why this is a risk (backend-dependent).** Per the core principle — *never trust the client* — every value that gates access must be enforced server-side. If `/v1/livekit/token` does not verify that the authenticated caregiver actually owns the `patient_<pid>` room, any caregiver could mint a token for **another caregiver's patient** and subscribe to that patient's in-home cameras (IDOR). Likewise, if `role` is honored without an ownership/permission check, a viewer could escalate to `broadcaster` and inject audio into a patient's room. This cannot be confirmed from the client alone.

**Fix (server-side).** In the `/v1/livekit/token` handler: resolve the caregiver from the JWT, verify they own `pid` (and that `pid` is well-formed), and derive `canPublish` from server-side policy — never echo the client-supplied `role` into the grant without authorization. Add an automated test that a caregiver requesting a token for a patient they don't own receives 403.

---

### 4. Verbose DEBUG logging of raw HTTP response bodies

**File:** `NemaraCaregiver/Services/NemaraAPIClient.swift:1018-1024` (decode-failure body dump) and `:1056-1060` (non-2xx body dump)

**What the code does.** On decode failure or any non-2xx status, the client prints the full raw response body to the console. Both sites are wrapped in `#if DEBUG`, so they are compiled out of Release/TestFlight/App Store builds. The `Authorization: Bearer …` header is not logged.

**Why this is a (minor) risk.** Response bodies for this API can contain PII and signed media URLs. In DEBUG, these land in the device/Xcode console and could be captured during shared debugging or on a connected machine. Because it is DEBUG-only, real-world exposure is limited.

**Fix.** Keep the `#if DEBUG` gates (good), and avoid logging full bodies even in DEBUG for endpoints that return signed URLs or personal data — log status + a truncated/ redacted summary instead. Confirm no auth tokens or signed URLs ever reach `os_log`/`NSLog` in Release.

---

## Informational — reviewed and confirmed NOT vulnerable

Documented to show audit coverage and to prevent these from being re-flagged later:

- **Embedded Supabase keys are publishable, not secret** — `AppConfig.swift:38, 58-61` hardcode the Supabase project URL and `sb_publishable_…` anon keys (prod + local). Supabase publishable/anon keys are explicitly designed to ship in clients; they are gated by Row-Level Security, not secrecy. No `service_role` / `sk_`/`sb_secret_` key, DB connection string, JWT signing secret, or third-party API secret appears anywhere in the source or git history (verified). **Not a finding.**
- **Auth tokens are stored in the iOS Keychain, not `UserDefaults`** — the Supabase SDK persists the session in the Keychain (`SupabaseAuthService.swift:254`). The app's own `UserDefaults` usage is limited to non-sensitive data: a set of camera UUIDs (`NemaraAPIClient.swift:208-222`) and an onboarding-seen flag (`NewPatientView.swift:464-467`). This matches the skill's "use Keychain, never plaintext storage" guidance. **Not a finding.**
- **ATS exception is narrow** — `Info.plist:36-40` / `project.yml:86-87` set only `NSAllowsLocalNetworking: true`, which permits cleartext to non-routable/local addresses for dev. It does **not** add `NSAllowsArbitraryLoads` and does not weaken TLS for routable production hosts. **Acceptable.**
- **LLM detector inference is server-proxied** — `AddDetectorView` → `NemaraAPIClient.inferDetector` (`:731-733`) sends the user's free-text prompt to `/v1/detectors/infer`; the LLM provider key lives on the backend. There is **no AI API key in the bundle**, matching the AI-integration guidance. (Prompt-injection handling and per-user usage caps remain a backend concern, out of scope for this client review.)
- **Hardcoded password string is preview-only** — `NemaraField.swift:149` contains `password = "Mar9aret!"` but is inside `#if DEBUG` / `#Preview`; it is a sample value for rendering the password-strength checklist, not a real credential, and is stripped from Release. **Not a finding.**
- **Deep-link handler is scheme/host-validated** — `handleIncomingURL` (`NemaraCaregiverApp.swift:113-128`) checks `scheme == "nemara"`, switches on host, and silently drops anything else; it performs no destructive action directly from link parameters (the reset code is exchanged server-side). The push-tap handler (`AppDelegate.swift:84-103`) parses only `event_id`/`patient_id` as UUIDs and the targeted event is re-fetched JWT-scoped (404 for foreign ids). See Finding 1 for the scheme-exclusivity caveat. **Otherwise sound.**
- **`.gitignore` and committed config** — `Local.xcconfig` (per-dev overrides) is gitignored; `LocalAppConfig.swift` ships with all-`nil` defaults; no `.env` or secret file is tracked (verified via `git ls-files`). **Acceptable.**
- **`mintToken` identity is informational** — the LiveKit participant identity embeds the caregiver UUID for audit legibility; the server re-mints the authoritative token. Low information value, not sensitive. **Not a finding.**

---

## Prioritized Recommendations

1. **(Medium) Move password-reset to Universal Links** and confirm PKCE stays enabled — closes the custom-scheme interception surface and removes the latent account-takeover path. (Finding 1)
2. **(Medium) Add TLS pinning** (`NSPinnedDomains` and/or a pinning `URLSessionDelegate`) for the backend and Supabase, with backup pins and a rotation plan — protects in-home video, PII, and JWTs from CA-trusted MITM. (Finding 2)
3. **(Low) Verify server-side authorization on `/v1/livekit/token`** — ensure caregivers can only mint tokens for patients they own and that `canPublish` is server-derived, not client-supplied. Add a 403 regression test. (Finding 3)
4. **(Low) Tighten DEBUG logging** — never dump full PII/signed-URL response bodies; confirm Release logs no tokens. (Finding 4)

---

*Static review only. Backend authorization (Supabase RLS policies, FastAPI route guards, LiveKit grant minting), AI usage caps, and rate limiting could not be assessed from this repository and should be audited separately against the `nemara-backend` source.*
