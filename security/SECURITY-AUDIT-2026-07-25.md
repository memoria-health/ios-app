# Security Audit — Nemara Caregiver App

**Date:** 2026-07-25
**Scope:** Static source audit of the `nemara-caregiver-app` iOS repository (native SwiftUI, Supabase Auth + Realtime, LiveKit, FastAPI backend on Railway).
**Methodology:** `vibe-security` skill (github.com/raroque/vibe-security-skill) — mobile, secrets/env, authentication, data-access, AI-integration reference tracks.
**Constraints:** Static only. No live services, secrets, or network access were used.

---

## Executive Summary

The codebase is in **good security shape**. It follows the single most important rule for this class of app — *never trust the client* — correctly: authorization is enforced server-side via Supabase Row-Level Security and backend JWT validation, LiveKit access tokens are minted server-side and scoped to a per-patient room, and session tokens are stored in the iOS Keychain (via the Supabase SDK) rather than `UserDefaults`.

**No Critical or High severity issues were found.** In particular:

- **No hardcoded secrets.** The only embedded credentials are Supabase **publishable/anon keys** (`sb_publishable_…`), which are explicitly designed to ship in client apps. There is **no** `service_role` key, Stripe secret, database connection string, LiveKit API secret, or LLM API key anywhere in the source or bundle.
- **Clean git history.** A full-history scan (`git log --all -p`) surfaced no leaked secrets — the only `eyJ…` matches are base64 pagination cursors (`{"occurred_at":2}`), not JWTs.
- **App Transport Security is intact.** The only ATS exception is `NSAllowsLocalNetworking` (scoped to non-routable dev addresses); production hosts still require TLS. There is no `NSAllowsArbitraryLoads`.
- **No client-side AI keys.** All AI/VLM work (`/v1/detect-doors`, `/v1/detectors/infer`) is proxied through the backend; the app only sends images/text and receives results.

The findings below are **defense-in-depth / hardening** items — two Medium and three Low. None represents an active exploit path on its own, but the two Medium items are worth addressing for an app that streams live video of care-dependent adults and handles their PII.

| # | Severity | Title |
|---|----------|-------|
| 1 | Medium | Password-reset recovery code delivered over a hijackable custom URL scheme (`nemara://`) |
| 2 | Medium | No TLS certificate / public-key pinning on backend, Supabase, or LiveKit connections |
| 3 | Low | DEBUG builds log full HTTP response bodies (including LiveKit JWTs) and connection URLs |
| 4 | Low | UI-analytics buffer persisted as unencrypted plaintext on disk |
| 5 | Low | APNs deep-link tap trusts payload UUIDs with no local validation |

---

## Medium

### 1. Password-reset recovery code delivered over a hijackable custom URL scheme

**Files:**
- `NemaraCaregiver/Resources/Info.plist:21-31` — declares the `nemara` custom URL scheme
- `NemaraCaregiver/App/NemaraCaregiverApp.swift:141-156` — `handleIncomingURL` extracts `?code=…`
- `NemaraCaregiver/Networking/AppConfig.swift:71` — `supabasePasswordResetRedirect = nemara://reset-password`
- `NemaraCaregiver/Services/SupabaseAuthService.swift:164-191` — request + exchange

**What it is.** The forgot-password flow asks Supabase to email a recovery link pointing at `nemara://reset-password?code=<recovery-code>`. When tapped, iOS routes it to the app via `.onOpenURL`, and the app exchanges the `code` for a session.

**Why it matters.** Custom URL schemes (`nemara://`) are **not exclusively owned** by one app on iOS. Any other app installed on the device can register the same `nemara` scheme, and when two apps claim it, iOS's choice of which one receives the link is undefined. A malicious app that registers `nemara` could receive the recovery `code` intended for this app.

**Mitigating factor (why this is Medium, not High/Critical).** The Supabase Swift SDK defaults to the **PKCE** auth flow, in which the `code` alone is useless without the `code_verifier` that this app generated and stored locally when it requested the reset. So interception of the `code` by another app does **not** by itself yield account takeover. The residual risk is real but bounded: (a) it is defense-in-depth that silently breaks if the flow type is ever changed away from PKCE, (b) a hijacking app can still deny the legitimate app the link (recovery DoS) or use the interaction for a phishing hand-off, and (c) the code transits a channel the app does not control.

**Fix.** Migrate auth deep links from a custom scheme to **Universal Links** (HTTPS `applinks:` via an Associated Domains entitlement + `apple-app-site-association` on the Supabase redirect domain). Universal Links are cryptographically bound to your domain and cannot be claimed by another app.

```
// Info.plist — remove the auth scheme's role in recovery; keep custom scheme
// only for links that carry no sensitive material.

// Entitlements — add Associated Domains
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:nemara.co</string>
</array>

// AppConfig.swift
static let supabasePasswordResetRedirect =
    URL(string: "https://nemara.co/auth/reset-password")!   // Universal Link
```

Keep the flow on PKCE regardless.

---

### 2. No TLS certificate / public-key pinning

**Files:**
- `NemaraCaregiver/Services/NemaraAPIClient.swift:103,1091-1093` — `URLSession.shared`, no pinning delegate
- `NemaraCaregiver/Services/SupabaseAuthService.swift:92` — `SupabaseClient` with default transport
- `NemaraCaregiver/Services/LiveKitClient.swift:216` — `room.connect(url:token:)` with default transport

**What it is.** All network traffic — backend REST (`nemara-backend-production.up.railway.app`), Supabase (Auth + Realtime + Storage), and the LiveKit media/signaling connection — relies on the system's default TLS trust store. No certificate or public-key pinning is applied (`URLSession.shared` is used with no `URLSessionDelegate` implementing `urlSession(_:didReceive:completionHandler:)`).

**Why it matters.** Standard TLS trusts any certificate chaining to a CA in the device trust store. That includes CAs added by a **user-installed configuration profile** or **corporate MDM proxy**. On such a device an attacker positioned in the middle can transparently decrypt and modify all traffic: caregiver JWTs, patient PII (names, home addresses, health-relevant event narratives), LiveKit tokens, and the live video/audio of a vulnerable adult. For a healthcare-adjacent monitoring product this is a meaningful confidentiality/integrity exposure.

**Fix.** Pin the leaf or intermediate public key for the backend and Supabase hosts. For `URLSession`, implement a pinning `URLSessionDelegate` that compares the server public-key hash against a bundled pin set (with a backup pin for rotation). Prefer pinning an intermediate/CA-level SPKI so certificate renewals don't brick the app. LiveKit Cloud connections can be pinned similarly at the SDK's transport layer where supported, or accepted as a documented residual risk if not.

```swift
// Sketch — replace `.shared` with a pinned session
final class PinnedSessionDelegate: NSObject, URLSessionDelegate {
    let pinnedSPKIHashes: Set<String>   // base64 SHA-256 of SubjectPublicKeyInfo
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge,
        completionHandler h: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let trust = c.protectionSpace.serverTrust,
              validate(trust, against: pinnedSPKIHashes) else {
            return h(.cancelAuthenticationChallenge, nil)   // fail closed
        }
        h(.useCredential, URLCredential(trust: trust))
    }
}
```

---

## Low

### 3. DEBUG builds log full HTTP response bodies and connection details

**Files:**
- `NemaraCaregiver/Services/NemaraAPIClient.swift:1081-1087, 1119-1123` — prints response bodies on decode failure and on non-2xx
- `NemaraCaregiver/Services/LiveKitClient.swift:207-219, 340, 436` — prints room URLs and audio-track state

**What it is.** Under `#if DEBUG`, the API client prints raw HTTP response bodies (which for `POST /v1/livekit/token` and auth paths contain short-lived JWTs and session material) to the console, and the LiveKit client prints connection URLs.

**Why it's Low.** All of this is compiled out of Release/TestFlight/App Store builds via `#if DEBUG`, so it does not reach production users. The exposure is limited to developer machines and any DEBUG build that leaves an authorized device. Worth a quick hygiene pass to redact tokens even in debug output (they can leak into shared logs, screen recordings, or CI artifacts).

**Fix.** Redact token-bearing fields before logging (e.g. print only the first/last few characters, or log status + byte-length instead of the body for endpoints known to return credentials).

---

### 4. UI-analytics buffer persisted as unencrypted plaintext on disk

**File:** `NemaraCaregiver/Services/Analytics.swift:204-224, 267-274`

**What it is.** The analytics buffer is written to `Application Support/ui_events_buffer.json` as plaintext JSON. Each record contains the caregiver UUID, session id, device model, app build, OS version, and a history of screen names / button labels.

**Why it's Low.** No credentials, tokens, passwords, or patient PHI are stored here — it is UI telemetry plus an opaque caregiver UUID. iOS app-container files are already sandboxed and protected by the default `NSFileProtection` class at rest. The residual risk is on a jailbroken device or via an unencrypted local backup, where navigation history and the caregiver identifier become readable.

**Fix.** Write the buffer with an explicit `.completeFileProtection` option, and consider excluding it from iTunes/iCloud backup (`URLResourceValues.isExcludedFromBackup = true`). Optionally scrub free-text button labels of anything user-identifying.

```swift
try? data.write(to: url, options: [.atomic, .completeFileProtection])
```

---

### 5. APNs deep-link tap trusts payload UUIDs with no local validation

**Files:**
- `NemaraCaregiver/App/AppDelegate.swift:90-109` — reads `event_id` / `patient_id` from the push payload
- `NemaraCaregiver/App/DeepLinkRouter.swift:42-53` — routes to that patient/event

**What it is.** On a notification tap, the app reads `event_id` and `patient_id` straight from the push `userInfo` and navigates into that patient's shell / event.

**Why it's Low.** APNs payloads originate from Apple's push service driven by the backend, and the subsequent data fetch (`GET /v1/events/{id}`) is caregiver-scoped server-side — a foreign or forged id returns 404 rather than leaking another caregiver's data. The values are parsed strictly as `UUID`, so they can't be used for path traversal. The only observable effect of a malformed/foreign payload is a no-op navigation. Noted for completeness: continue to rely on the server's ownership check (never render event/patient content from the payload itself).

**Fix.** None required beyond the existing server-side scoping. Keep navigation gated on the authenticated fetch result; do not populate UI directly from push payload fields.

---

## Areas Reviewed — No Issue Found

- **Hardcoded secrets / API keys** — only publishable/anon Supabase keys (safe to ship); no `service_role`, `sk_*`, LiveKit secret, DB DSN, or LLM key. (`AppConfig.swift`)
- **Committed secrets** — full git-history scan clean.
- **App Transport Security** — only `NSAllowsLocalNetworking` (dev, non-routable); production TLS enforced; no arbitrary-loads. (`Info.plist`, `project.yml`)
- **Token storage** — Supabase session persisted to Keychain by the SDK, not `UserDefaults`; the only `UserDefaults` usage is a set of camera UUIDs (`camerasEverOnline`), which is non-sensitive. (`SupabaseAuthService.swift`, `NemaraAPIClient.swift:207-222`)
- **Authorization** — enforced server-side: backend validates the JWT on every request; Supabase RLS filters Realtime rows per caregiver; LiveKit identity is server-validated and re-minted; tokens scoped to `patient_<id>` rooms. Client sends intent, server decides. (`NemaraAPIClient.swift:925-957`, `openRealtimeChannels`)
- **AI / LLM integration** — no client-side model keys; door detection and detector inference go through the backend proxy. (`NemaraAPIClient.swift:757, 787`)
- **Dev-only data-collection ("Capture 15s clip")** — hard-compiled OFF in Release via `#if DEBUG` with no override path; verified the single choke point cannot be re-enabled in a distribution build. (`AppConfig.swift:112-132`)
- **`.gitignore`** — `Local.xcconfig` (per-dev signing/URLs) is ignored; no `.env`-style secret files are tracked.
- **Injection / input validation** — no SQL is constructed client-side; all path parameters are typed `UUID`s interpolated after `.uuidString`, so no injection surface in request paths.

---

## Prioritized Recommendations

1. **(Medium)** Move password-reset (and any future auth) deep links from the `nemara://` custom scheme to **Universal Links**, and keep the Supabase flow on PKCE. *Prevents recovery-link interception by a scheme-squatting app.*
2. **(Medium)** Add **certificate / public-key pinning** (with a backup pin for rotation) for the backend and Supabase hosts, failing closed on mismatch. *Blocks MitM via user-installed or MDM root CAs on the caregiver's device.*
3. **(Low)** Redact token-bearing fields from DEBUG log output.
4. **(Low)** Persist the analytics buffer with `.completeFileProtection` and exclude it from backup.
5. **(Low)** Keep push-driven navigation gated on the authenticated server fetch (already the case) — no change needed.

---

*Static audit performed with the `vibe-security` methodology. Findings are limited to what is observable in source; a dynamic/runtime assessment (traffic capture on a jailbroken device, backend RLS policy review) is recommended to confirm the server-side controls this report assumes are in place.*
