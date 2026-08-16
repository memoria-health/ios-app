# Security Audit — nemara-caregiver-app

**Date:** 2026-08-16
**Scope:** Static source audit of the native iOS (SwiftUI) caregiver app in this repository.
**Methodology:** [`vibe-security`](https://github.com/raroque/vibe-security-skill) skill — secrets & environment, database access control, authentication & authorization, rate limiting, payments, **mobile** (prioritized), AI/LLM integration, deployment, and data-access/input-validation. No live services, secrets, or network access were used; findings are drawn only from committed code and configuration.

---

## Executive Summary

The app is, overall, **well-architected from a security standpoint**. It relies on the correct trust model — server-side enforcement of authorization (Supabase RLS, backend JWT validation, LiveKit token minting) rather than client-side trust — and it gets the common mobile fundamentals right:

- **No production secrets are committed.** The only keys in source are Supabase **publishable/anon** keys, which are designed to ship in clients. No `service_role`, no backend/API secret keys, no private keys. Git history is clean of secret files.
- **Session tokens are stored in the iOS Keychain** (via the Supabase Swift SDK's default storage), not in `UserDefaults`. `UserDefaults` holds only non-sensitive UI state (camera IDs, toggles, tutorial flags).
- **App Transport Security is intact** — no `NSAllowsArbitraryLoads`. Only `NSAllowsLocalNetworking` is enabled (for LAN sensor discovery). Production endpoints are HTTPS-only.
- **AI/LLM calls are proxied through the backend** — no model-provider API keys exist in the app bundle. LLM output is rendered as native SwiftUI markdown `Text`, never in a web view, so there is no HTML/script-execution sink.

No **Critical** or **High** severity issues were found. The findings below are **defense-in-depth hardening** items appropriate to an app that handles unusually sensitive data: live audio/video of vulnerable elderly people, facial-recognition embeddings (biometrics), and caregiver/patient PII.

### Findings at a glance

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | Medium | No TLS certificate/public-key pinning for a biometric/health/live-video app | `NemaraAPIClient.swift`, `Info.plist` |
| 2 | Low | Reusable demo/seed account password committed to `README.md` | `README.md:63` |
| 3 | Low | Third-party dependencies not pinned; `Package.resolved` git-ignored (non-reproducible builds) | `project.yml`, `.gitignore` |
| 4 | Low | No jailbreak / runtime-integrity awareness on a safety-critical app | app-wide |
| 5 | Low | LiveKit room/role is client-asserted — confirm server-side enforcement | `NemaraAPIClient.swift` |
| 6 | Info | DEBUG build targets a hardcoded cleartext internal dev host (compiled out of Release) | `AppConfig.swift:36,88` |
| 7 | Info | LLM prompt-injection surface is server-side; iOS render path is safe | Home/Detector features |

---

## Medium

### 1. No TLS certificate / public-key pinning

**`NemaraCaregiver/Services/NemaraAPIClient.swift:103`** (uses `URLSession.shared`, no pinning delegate) and **`NemaraCaregiver/Resources/Info.plist`** (no `NSPinnedDomains`).

The app transmits an unusually sensitive payload set — live audio/video streams of vulnerable adults, **facial-recognition embeddings** (`submitFaceEmbeddings`), patient/caregiver PII, and the Supabase bearer JWT on every request — to the Railway backend and Supabase over standard system-trust HTTPS. There is no `URLSessionDelegate` implementing `urlSession(_:didReceive:completionHandler:)` for server-trust evaluation, and `Info.plist` declares no `NSPinnedDomains`.

**Why it matters:** iOS default TLS validation trusts the entire system trust store. On a device with a mistakenly- or maliciously-installed CA (a managed/MDM device, a coerced user who installed a configuration profile, or a corporate TLS-inspection proxy), an attacker who can position on-path can transparently intercept traffic — reading the JWT (full account takeover for its lifetime) and the biometric/video data. Pinning removes reliance on the device trust store for the two hosts the app actually talks to. This is defense-in-depth (base TLS still applies), but the data sensitivity here justifies it.

**Fix (Info.plist pinning — no code):**
```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key><true/>
  <key>NSPinnedDomains</key>
  <dict>
    <key>zgifmvjnggmgzvtnosnu.supabase.co</key>
    <dict>
      <key>NSPinnedLeafIdentities</key>
      <array><dict>
        <key>SPKI-SHA256-BASE64</key>
        <string><!-- base64 SHA-256 of the leaf/intermediate SPKI --></string>
      </dict></array>
    </dict>
    <key>nemara-backend-production.up.railway.app</key>
    <dict> <!-- same shape --> </dict>
  </dict>
</dict>
```
Pin at the intermediate-CA SPKI level and ship at least one backup pin so certificate rotation doesn't brick the app. (Alternatively, implement pinning in a `URLSessionDelegate` and construct the client's `URLSession` with it instead of `.shared`.)

---

## Low

### 2. Reusable demo/seed account password committed to `README.md`

**`README.md:63`**
```
- Email: `jane@patel.co`
- Password: `Mar9aret!2024`
```

This is documented as a `make fresh-seed` **local demo** credential, so its immediate blast radius is a developer's local Supabase — genuinely low. It is flagged because (a) it is a real, reusable password now permanent in git history, and (b) the same seed data and password could be applied to a shared/staging environment, at which point the account becomes a known-credential foothold. Password reuse of this string elsewhere would compound it.

**Fix:** Replace the literal with a placeholder and have `fresh-seed` generate/print a random password per run, or read it from an untracked local `.env`. Example:
```
- Email: `jane@patel.co`
- Password: printed by `make fresh-seed` (randomized per seed)
```
Since it is already in history, rotate/retire the value anywhere it may have been reused beyond a throwaway local DB.

### 3. Dependencies not version-pinned; `Package.resolved` is git-ignored

**`project.yml:14,21`** declare open-ended floors:
```yaml
Supabase: { url: https://github.com/supabase/supabase-swift, from: "2.44.1" }
LiveKit:  { url: https://github.com/livekit/client-sdk-swift, from: "2.0.0" }
```
and **`.gitignore`** excludes `Package.resolved`.

`from:` allows any compatible newer minor/patch, and with `Package.resolved` untracked there is no committed lockfile. Builds are therefore **not reproducible**, and a compromised or broken upstream release within the allowed range (a real supply-chain vector for the SDKs that handle the app's auth tokens and live media) can be pulled into a build without any diff to review.

**Fix:** Commit `Package.resolved` (remove it from `.gitignore`) so every build resolves to a reviewed, identical dependency graph, and/or tighten the constraint (e.g. `upToNextMinor` / an exact version) and bump deliberately. Consider enabling GitHub Dependabot/secret-scanning on the repo.

### 4. No jailbreak / runtime-integrity awareness

App-wide: there is no jailbreak detection, anti-hooking, or runtime-integrity check. Because the app correctly enforces authorization **server-side** (RLS + JWT + server-minted LiveKit tokens), a compromised client cannot escalate another user's data, which is why this is Low rather than higher. For a safety-critical caregiving/monitoring app it is still worth a lightweight integrity signal so a rooted/hooked device streaming a vulnerable person's video can be detected and, at minimum, logged.

**Fix:** Add a lightweight jailbreak heuristic (e.g. presence of `/private/var/lib/apple/Library/`, `cydia://` scheme handling, `fork()` success in a sandboxed app) surfaced as a telemetry signal and/or a soft warning. Treat it as a signal, never as the sole security control — server-side enforcement remains the real boundary.

### 5. LiveKit room and role are client-asserted — confirm server-side enforcement

**`NemaraCaregiver/Services/NemaraAPIClient.swift:980-1000`** — the client constructs the token request itself:
```swift
let body = MintTokenRequest(
    room: "patient_\(pid.uuidString.lowercased())",
    identity: "caregiver_\(caregiverID.uuidString.lowercased())_ios",
    role: role,               // "viewer" or "broadcaster" chosen client-side
)
```
The in-code comment states the backend "validates the prefix and re-mints," which is the correct model. From a static iOS-only view this cannot be verified, and the `room` (any patient UUID) and `role` (`broadcaster` grants mic publish) are attacker-controllable request fields.

**Why it matters:** If the backend `POST /v1/livekit/token` ever trusted the supplied `room`/`role`, any authenticated caregiver could mint a **broadcaster** token into **any patient's** room (`patient_<any-uuid>`) and view/speak into a stream they don't own — a cross-tenant authz break. The client is doing the right thing by not being trusted; the enforcement must live server-side.

**Fix (backend — flagged for verification, out of this repo's scope):** Ignore the client-supplied `room`/`role`; derive the room from a server-checked caregiver↔patient ownership lookup, and grant `canPublish` only for roles the caregiver is authorized for. Add an authz test that a caregiver cannot mint a token for a patient they don't own.

---

## Informational

### 6. DEBUG build targets a hardcoded cleartext internal dev host

**`NemaraCaregiver/Networking/AppConfig.swift:36,88`**
```swift
return URL(string: "http://sunnys-macbook-air.local:54341")   // supabase, DEBUG
return URL(string: "http://sunnys-macbook-air.local:8002")!   // backend,  DEBUG
```
These are inside `#if DEBUG` branches; the verified `#else` (Release/Archive/TestFlight/App Store) branches use HTTPS production URLs and never consult `LocalAppConfig` or env vars. So no cleartext endpoint ships to users. The note is that an internal developer hostname is disclosed in committed source, and the cleartext HTTP dev default is permitted only because `NSAllowsLocalNetworking` is on. No action required for shipping security; consider parameterizing the dev host if internal-infra disclosure is a concern.

### 7. LLM prompt-injection surface is server-side; the iOS render path is safe

The app sends free-text and images into backend LLM endpoints — `inferDetector`/`refineDetector` (caregiver-authored detector text), `homeBriefing`/`homeReport` (patient facts), and `detectDoors` (a base64 camera frame). Two reassuring properties from the client side:

1. **No model API keys in the app** — all calls go through the backend proxy (`AppConfig.backendURL`), consistent with the skill's guidance.
2. **LLM output is rendered as native markdown `Text`** (`HomeStatusView.swift` via `Self.md(...)`), not in a `WKWebView` and not executed — so there is no HTML/script/`javascript:`-URL execution sink for injected output.

The injected text here is authored by the same caregiver who reads it (single-tenant data), so cross-user prompt injection is not demonstrable from this codebase. **Recommendation (backend):** keep system and user content in separate message roles, cap per-user/token spend server-side, and validate any structured LLM output (e.g. detector shape/category, door boxes) against an allowlist/schema before persisting — none of which is enforceable in the iOS client.

---

## Areas reviewed with no issues found

- **Secrets & environment:** Only Supabase publishable/anon keys in source (safe to ship); no `service_role`, backend, or provider secret keys; `.gitignore` covers `.env`/`.env.*` and `Local.xcconfig`; git history clean of secret files.
- **Token storage:** Supabase SDK persists the session in the Keychain; `UserDefaults` holds only non-sensitive UI state.
- **App Transport Security:** no arbitrary-loads exception; production is HTTPS-only.
- **Deep links:** the single `nemara://reset-password?code=…` route passes the code to Supabase's server-validated, single-use `exchangeCodeForSession`; no sensitive data is trusted from the URL and no destructive action is taken from deep-link params.
- **Authentication:** password auth + recovery via the Supabase SDK; token refresh is forwarded into Realtime so RLS evaluates `auth.uid()`; no local `jwt.decode`-style trust of unverified tokens.
- **Authorization / data access:** every request carries the bearer JWT; the client relies on server-side RLS and 404-scoping; no raw SQL, no client-trusted role/price/entitlement logic. (Payments: not present in the app.)
- **Logging:** no tokens/passwords/secrets logged; DEBUG logs are limited to error bodies and Realtime table names.

---

*Static audit only. Server-side authorization (Supabase RLS policies, backend JWT validation, and the LiveKit token-minting endpoint) is the app's real security boundary and lives outside this repository; items 5 and 7 should be verified there.*
