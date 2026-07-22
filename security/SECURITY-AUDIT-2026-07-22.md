# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-07-22
**Auditor:** Automated security review (scheduled agent)
**Methodology:** [`vibe-security`](https://github.com/raroque/vibe-security-skill) skill, mobile-prioritized
**Scope:** Static analysis of `nemara-caregiver-app` at commit `02def0e` (native iOS / SwiftUI, Swift 6). No live services, secrets, or backend source examined.
**Backend (`nemara-backend`) and Supabase RLS policies are OUT OF SCOPE** — they are not in this repository and could not be verified. See "Scope limitations."

---

## Executive Summary

This is a well-constructed app with a **strong security posture**. The audit found **no Critical or High severity issues**. The team has correctly applied the security fundamentals that AI-assisted mobile apps most often get wrong:

- **No hardcoded secret keys.** The only embedded credentials are Supabase *publishable/anon* keys, which are designed to ship in clients and are gated by server-side RLS.
- **Auth tokens live in the Keychain** (Supabase SDK default), not `UserDefaults`/plaintext.
- **App Transport Security is not globally weakened** — the only exception is `NSAllowsLocalNetworking` for LAN development; production TLS is fully enforced.
- **The trust model is server-side.** Every mutating call carries the Supabase JWT as a Bearer token; the client makes no security-relevant authorization decisions locally.
- **All verbose logging is `#if DEBUG`-gated**; no tokens, JWTs, or PII are written to release logs.
- **A dev-only "record clip" data-collection feature is hard-compiled OFF in release builds** at a single choke point.

The findings below are **Low severity / defense-in-depth** items, plus scope caveats that matter for a complete assessment. The single most important recommendation is not a code change in this repo at all: **the app's entire authorization model rests on Supabase RLS + backend JWT verification that live in `nemara-backend`. That code — the #1 source of critical vulnerabilities in this class of app — must be audited separately.**

### Findings at a glance

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | Low | Password-recovery code delivered via interceptable custom URL scheme (no Universal Links) | `NemaraCaregiverApp.swift:141`, `Info.plist` (`CFBundleURLTypes`) |
| 2 | Low | No certificate pinning for HTTPS carrying auth tokens + patient PHI | `NemaraAPIClient.swift`, `SupabaseAuthService.swift` |
| 3 | Low | Analytics telemetry buffer persisted unencrypted to disk | `Analytics.swift:204`, `Analytics.swift:267` |
| 4 | Low | `Package.resolved` git-ignored → non-reproducible builds, floating dependency versions | `.gitignore`, `project.yml` |

Plus three **backend-directed observations** (Section: Scope limitations & backend-directed observations) that cannot be resolved in this repo but should be confirmed server-side.

---

## Detailed Findings

### 1. (Low) Password-recovery code delivered via an interceptable custom URL scheme

**Files:**
- `NemaraCaregiver/App/NemaraCaregiverApp.swift:141-156` (`handleIncomingURL`)
- `NemaraCaregiver/Resources/Info.plist` — `CFBundleURLTypes` registers scheme `nemara`
- `NemaraCaregiver/Networking/AppConfig.swift:71` — `supabasePasswordResetRedirect = nemara://reset-password`
- `NemaraCaregiver/Services/SupabaseAuthService.swift:182-190` (`exchangeRecoveryCode`)

**What the code does.** The forgot-password flow asks Supabase to email a recovery link that redirects to `nemara://reset-password?code=<recovery_code>`. The app registers the `nemara` **custom URL scheme** and, in `handleIncomingURL`, extracts the `code` query item and exchanges it for a session:

```swift
// NemaraCaregiverApp.swift:141
private func handleIncomingURL(_ url: URL) {
    guard url.scheme == "nemara" else { return }
    let host = url.host(percentEncoded: false)
    switch host {
    case "reset-password":
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value {
            pendingResetCode = code        // → ResetPasswordView → exchangeRecoveryCode(code)
        }
    ...
```

**Why it's a concern.** iOS custom URL schemes are **not exclusive** — any app installed on the device can also register `nemara`, and iOS behavior when two apps claim the same scheme is undefined (roughly "last/first installed wins"). A malicious app that claims `nemara://` could intercept the recovery `code`. The `vibe-security` mobile guidance is explicit: *"Never include sensitive data in deep link URLs (tokens, passwords, user IDs that grant access)."* A recovery code is a bearer credential for a password reset — i.e., account takeover if usable in isolation.

**Why it is only Low.** The Supabase Swift SDK defaults to the **PKCE** authorization-code flow. `exchangeCodeForSession(authCode:)` requires the `code_verifier` that was generated during `resetPasswordForEmail(...)` and stored in the originating app's Keychain. A different app cannot read that value (iOS app sandbox), so intercepting the `code` alone does not let an attacker complete the reset. The custom-scheme delivery is a weakness, but PKCE + sandboxing substantially mitigate real-world exploitability.

**Fix.** Migrate the recovery (and any future auth-callback) deep links to **Universal Links** with an `applinks:` Associated Domains entitlement and an `apple-app-site-association` file on the Supabase redirect domain. Universal Links are cryptographically bound to your domain and cannot be hijacked by another app claiming a scheme.

```xml
<!-- NemaraCaregiver.entitlements (add) -->
<key>com.apple.developer.associated-domains</key>
<array><string>applinks:auth.nemara.co</string></array>
```
```swift
// Then set redirectTo to an https:// URL on that domain and route it via
// .onOpenURL, keeping the same code-extraction + PKCE exchange.
static let supabasePasswordResetRedirect = URL(string: "https://auth.nemara.co/reset-password")!
```
Until then, keep the PKCE flow enabled (do not switch the SDK to the implicit flow), since PKCE is what currently blunts this.

---

### 2. (Low) No certificate pinning for HTTPS carrying auth tokens and patient PHI

**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift` (uses `URLSession.shared`), `NemaraCaregiver/Services/SupabaseAuthService.swift` (default `SupabaseClient`).

**What the code does.** All backend and Supabase traffic goes over standard `URLSession`/SDK HTTPS with no `URLSessionDelegate` implementing `urlSession(_:didReceive challenge:)` for public-key/certificate pinning. This traffic includes the Supabase access JWT (`Authorization: Bearer …`), patient PII (names, dates of birth, home addresses — see the model in `AppEnvironment.swift:133`), health/detection events, and short-lived signed URLs to recorded video clips of the person under care.

**Why it's a concern.** ATS enforces valid TLS, which defeats passive eavesdroppers. It does **not** defeat an *active* man-in-the-middle who possesses a certificate the device already trusts — e.g., an enterprise MDM root, a user-installed configuration profile, or a compromised public CA. For an eldercare app moving PHI-like data and live/recorded video, pinning is a meaningful defense-in-depth control.

**Why it is only Low.** Exploitation requires the attacker to already control a CA the device trusts (or to socially engineer profile installation). ATS + valid TLS already stop the common cases. Certificate pinning also carries real operational cost (rotation/outage risk), which is why it is defense-in-depth rather than a baseline requirement. Teams handling PHI may reasonably choose to prioritize it higher.

**Fix.** Pin the leaf/intermediate public keys for the two production hosts (`*.up.railway.app` backend and `*.supabase.co`) via a `URLSessionDelegate`, or adopt a maintained library (e.g. TrustKit). Pin to the **SPKI public key**, not the certificate, and include a backup pin to survive rotation. Supabase permits injecting a custom `URLSession`; the backend client already accepts an injected `session` (`NemaraAPIClient.init(session:)`), so this is a localized change.

---

### 3. (Low) Analytics telemetry buffer persisted unencrypted to disk

**Files:** `NemaraCaregiver/Services/Analytics.swift:204-211` (`persist`), `:267-274` (`fileURL`).

**What the code does.** UI telemetry (`caregiver_id`, session id, screen names, button/toggle names, device model, OS version) is buffered and written as plaintext JSON to `Application Support/ui_events_buffer.json`:

```swift
// Analytics.swift:204
guard let data = try? JSONEncoder().encode(buffer) else { return }
Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
```

**Why it's a concern / why Low.** The data is low-sensitivity (no passwords, tokens, or health events — only interaction telemetry plus a caregiver UUID) and never leaves the device except via an authenticated, RLS-scoped Supabase insert. iOS default file protection (`CompleteUntilFirstUserAuthentication`) applies. The residual risk is minor: on a jailbroken/backed-up device the file reveals the caregiver's UUID and usage patterns.

**Fix (optional, low priority).** Write with explicit `NSFileProtection` and/or scrub the file on sign-out:

```swift
try? data.write(to: url, options: [.atomic, .completeFileProtection])
```
Consider deleting `ui_events_buffer.json` in the `onSignedOut` teardown so residual telemetry for a signed-out caregiver isn't left on a shared device.

---

### 4. (Low) `Package.resolved` is git-ignored — non-reproducible builds, floating dependency versions

**Files:** `.gitignore` (`Package.resolved`), `project.yml` (`Supabase from: "2.44.1"`, `LiveKit from: "2.0.0"`).

**What the code does.** Dependencies use SwiftPM `from:` (minimum-version) ranges, and the lockfile that records the exact resolved versions is git-ignored. Each `swift package update` (or a fresh CI resolve) can pull a newer minor/patch of Supabase or LiveKit than was last tested.

**Why it's a concern / why Low.** No *currently* vulnerable version is pinned — `Supabase 2.44.1+` and `LiveKit 2.x` are recent and clean. But without a committed lockfile, a future compromised or regressed upstream release enters release builds without an explicit, reviewable change, and builds are not reproducible across machines/CI. These SDKs handle auth tokens and live A/V, so their supply chain matters.

**Fix.** Commit `Package.resolved` (remove it from `.gitignore`) so dependency bumps are explicit, reviewable diffs, and enable a dependency-audit step (e.g. GitHub Dependabot / `osv-scanner`) in CI.

---

## Scope limitations & backend-directed observations

These are **not defects in this repository**, but they are essential to a complete security picture and should be confirmed in `nemara-backend` / Supabase.

- **Authorization is entirely server-side and unverifiable here (highest priority to audit next).** The client relies on Supabase Row-Level Security and backend JWT verification for every read/write and every Realtime channel (`NemaraAPIClient.swift:1168` notes *"RLS policies filter per-caregiver server-side"*). Broken RLS is the #1 critical vulnerability in vibe-coded apps. **Confirm that every table (`patients`, `cameras`, `detectors`, `events`, `ui_events`, face embeddings, device tokens) has RLS enforcing `caregiver_id = auth.uid()` ownership, and that every FastAPI route re-derives the caregiver from the JWT rather than from any client-supplied id.**

- **LiveKit `role` is client-supplied in the token request.** `mintToken(role:)` (`NemaraAPIClient.swift:926`) sends `role: "viewer" | "broadcaster"` in the POST body; `mintBroadcasterToken` requests publish rights. The in-code comment states *"server validates the prefix and re-mints with whatever we send."* The backend **must** independently authorize (a) that the caregiver owns the target `patient_<id>` room and (b) that it is entitled to the requested role/grants — never mint `canPublish` purely because the client asked. Verify server-side.

- **Client-supplied `bundleId` on device registration.** `registerDeviceToken(bundleId:)` (`NemaraAPIClient.swift:324`) defaults `bundleId` but sends it from the client; ensure the backend treats APNs routing metadata as untrusted and scopes device-token rows to the authenticated caregiver (the delete path at `:343` is already caller-scoped, which is good).

- **AI/LLM usage is correctly server-proxied.** `detectDoors` (base64 camera frame → VLM) and `inferDetector` (free-text → model) both POST to `nemara-backend`; no AI provider key exists in the client. Prompt-injection handling, per-user usage caps, and output validation are backend concerns — confirm they exist there. LLM-generated narratives are rendered via SwiftUI `Text` (no HTML/JS sink), so there is no client-side injection surface.

---

## Areas reviewed with no issues found

- **Secrets scan (source + full git history):** no `sk_live`/`sk_test`, AWS keys, private keys, service-role keys, or DB connection strings. The `"Mar9aret!"` string is a SwiftUI `#Preview` mock password, not a credential.
- **Embedded Supabase keys are publishable/anon (`sb_publishable_…`)** — designed to be shipped in clients; the correct key type for a mobile app (`AppConfig.swift:60-70`).
- **Token storage:** Supabase session is stored in the iOS Keychain (SDK default; no insecure storage override). No auth tokens in `UserDefaults` — the only `UserDefaults` usage is non-sensitive UI state (ever-online camera IDs, blur toggles, tutorial flags).
- **App Transport Security:** only `NSAllowsLocalNetworking` (LAN dev); no `NSAllowsArbitraryLoads` and no per-domain TLS downgrade. Production HTTPS is enforced.
- **Logging:** every `print`/verbose log is `#if DEBUG`-gated (verified in `LiveKitClient.swift`, `NemaraAPIClient.swift`); no tokens or PII in release logs. Release `NSLog` calls carry only error descriptions.
- **Dev-only data collection is fenced off:** `AppConfig.enableClipCapture` is hard-compiled to `false` in release at a single documented choke point (`AppConfig.swift`), so the camera-record chain cannot ship enabled.
- **Deep-link surface is minimal and input-validated:** only `nemara://reset-password` is handled; all ids from deep links and push payloads are parsed through `UUID(uuidString:)` and dropped if malformed (`AppDelegate.swift:96`, `DeepLinkRouter.swift`). No destructive action is taken directly from unvalidated deep-link parameters.
- **Wi-Fi provisioning does not expose home credentials:** sensor setup uses iOS's native `NEHotspotConfiguration` + the OS captive portal; the app never reads or transmits the home Wi-Fi password (`SensorSetupWizard.swift`).
- **HTTP client hygiene:** paths use lowercased UUIDs and `URLComponents`; no string-concatenated SQL or shell (all persistence is via Supabase/PostgREST and the backend). No client-side price/role/entitlement trust (the app has no payment surface).

---

## Prioritized recommendations

1. **Audit `nemara-backend` RLS + route-level authorization separately** — the one control this client-only audit cannot verify, and the highest-impact area. (Scope caveat)
2. **Move auth deep links to Universal Links** and keep the PKCE flow enabled. (Finding 1)
3. **Add certificate pinning** for the backend and Supabase hosts, pinning SPKI with a backup pin. (Finding 2)
4. **Commit `Package.resolved`** and add a CI dependency-vulnerability scan. (Finding 4)
5. **Apply file protection to / scrub the analytics buffer** on sign-out. (Finding 3)

---

*This audit is static and limited to the checked-out iOS client. It does not cover the backend, Supabase configuration, infrastructure, or runtime behavior. Absence of a finding is not proof of absence of a vulnerability.*
