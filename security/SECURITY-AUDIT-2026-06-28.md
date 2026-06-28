# Security Audit — Nemara / Memoria Caregiver iOS App

**Date:** 2026-06-28
**Scope:** Static source review of `nemara-caregiver-app` (native iOS, Swift 6 / SwiftUI).
**Methodology:** [`vibe-security`](https://github.com/raroque/vibe-security-skill) skill, mobile-first
(secrets, App Transport Security, token storage, certificate pinning, deep links, client-side trust),
plus authn/authz, injection, dependencies, and AI/LLM usage.
**Limitations:** Static only. No access to the backend (`nemara-backend` on Railway), the Supabase
project, live secrets, or runtime. Server-side controls (Supabase Row-Level Security, FastAPI
auth/validation, LiveKit token minting) could **not** be verified and are the foundation the client
depends on — see finding L-3.

---

## Executive Summary

This is a well-architected client. The app correctly follows the core mobile-security principle of
**never trusting the client**: it enforces no authorization itself, attaches a Supabase-issued JWT as a
`Bearer` token on every request, and lets the backend + Supabase RLS make all access decisions.
Session tokens are stored in the iOS Keychain (via the Supabase SDK), not `UserDefaults`. LiveKit
access tokens are minted server-side per request. All HTTP bodies are strongly-typed `Encodable`
structs and all path parameters are `UUID`-typed, so there is no client-side injection surface. ATS is
configured the recommended way (local-networking exception only; TLS still enforced for production
hosts). No live secret keys (`service_role`, `sk_*`, private keys) appear in the source or git history.

**No Critical or High severity issues were found in the client code.** The findings below are
defense-in-depth and hardening items, weighted up by the sensitivity of the domain — this app streams
live video of vulnerable elderly patients and uploads facial-recognition embeddings (biometric PII).

| # | Severity | Finding |
|---|----------|---------|
| M-1 | Medium | No TLS certificate/public-key pinning for sensitive health/video/biometric traffic |
| L-1 | Low | Password-reset deep link uses a hijackable custom URL scheme (`nemara://`) instead of Universal Links |
| L-2 | Low | DEBUG builds log full HTTP response bodies (including minted LiveKit tokens and signed media URLs) |
| L-3 | Low / Informational | Whole-app data security rests on server-side RLS that is out of scope and unverifiable here |
| L-4 | Low / Informational | UI-analytics buffer persisted to disk as plaintext JSON |
| I-1 | Informational | Debug entitlements left in a "TEMP — revert before PR" state |

---

## Findings

### M-1 (Medium) — No certificate / public-key pinning on a high-sensitivity data path

**Files:**
- `NemaraCaregiver/Services/NemaraAPIClient.swift:102` (`session: URLSession = .shared`) and `:1054` (`session.data(for:)`)
- `NemaraCaregiver/Services/SupabaseAuthService.swift:92` (`SupabaseClient` default transport)
- `NemaraCaregiver/Services/LiveKitClient.swift:216` (`room.connect(url:token:)`)

**What it is.** Every network path — the FastAPI backend, Supabase Auth/Realtime, and the LiveKit
media connection — uses the platform default TLS trust evaluation with no pinning. There is no
`URLSessionDelegate` implementing `urlSession(_:didReceive:completionHandler:)`, and the Supabase/LiveKit
SDKs are constructed without a pinned trust configuration.

**Why it matters here.** Default ATS protects against passive eavesdropping, but it trusts any
certificate chaining to any CA in the system/user trust store. An attacker who can install a root CA on
the device (corporate MDM, a malicious configuration profile delivered by social engineering, a
jailbroken/compromised device) or who obtains a mis-issued certificate can transparently
man-in-the-middle the connection. The data exposed is unusually sensitive: Supabase session JWTs,
live audio/video of patients in their homes, short-lived signed clip/photo URLs, and uploaded **face
embeddings** (biometric data). This is squarely the "client-side trust on a jailbroken/compromised
device" concern the mobile checklist calls out.

**Exploitability.** Not remotely exploitable on its own — it requires the attacker to already control a
trusted CA on the victim's device or compromise a CA. That keeps it Medium rather than High, but the
sensitivity of the payload warrants treating it as more than a nice-to-have.

**Fix.** Pin the backend and Supabase hosts. Simplest: ship a pin set via `Info.plist`
`NSAppTransportSecurity` → `NSPinnedDomains` (iOS 14+), pinning the leaf/intermediate SPKI hashes with a
backup pin for rotation. For full control, implement a `URLSessionDelegate` that validates the server
public key, and inject that `URLSession` into `NemaraAPIClient` (the client already takes `session` as a
constructor parameter, so this is a localized change). Pin LiveKit's signaling host similarly. Keep at
least one backup pin and a rotation runbook so a cert change doesn't brick the app.

---

### L-1 (Low) — Password-reset deep link relies on a custom URL scheme that any app can claim

**Files:**
- `NemaraCaregiver/App/NemaraCaregiverApp.swift:136-151` (`handleIncomingURL`, parses `?code=`)
- `NemaraCaregiver/Networking/AppConfig.swift:71` (`nemara://reset-password` redirect)
- `NemaraCaregiver/Resources/Info.plist:21-31` (`CFBundleURLSchemes` = `nemara`)
- `NemaraCaregiver/Services/SupabaseAuthService.swift:182-191` (`exchangeRecoveryCode`)

**What it is.** Account recovery is delivered to `nemara://reset-password?code=…`. iOS custom URL
schemes are first-come-but-not-exclusive: any other installed app may also register the `nemara`
scheme, and when multiple apps claim the same scheme the OS resolution is undefined. A malicious app
could therefore receive the recovery `code`.

**Why the impact is limited.** Supabase's `exchangeCodeForSession` is a PKCE exchange — the recovery
`code` is only usable together with the `code_verifier` that the *legitimate* app generated and stored
in its own Keychain. An interceptor app gets the code but not the verifier, so it cannot complete the
exchange. The window is a stolen code that is useless without app-local secret material. This is why the
rating is Low, not High.

**Fix.** Migrate auth deep links to **Universal Links** (`applinks:` Associated Domains +
`apple-app-site-association`), which are cryptographically bound to your domain and cannot be claimed by
another app. Keep the custom scheme only as a non-sensitive fallback. The deep-link parsing in
`handleIncomingURL` already validates the scheme and silently drops malformed input, which is good; the
weakness is solely the choice of transport.

---

### L-2 (Low) — DEBUG builds print full HTTP response bodies, including tokens and signed URLs

**Files:**
- `NemaraCaregiver/Services/NemaraAPIClient.swift:1044-1049` (decode-failure body dump)
- `NemaraCaregiver/Services/NemaraAPIClient.swift:1082-1086` (non-2xx body dump)
- `NemaraCaregiver/Services/LiveKitClient.swift:207-219` (logs the LiveKit `url`)

**What it is.** Under `#if DEBUG`, the client `print`s raw response bodies to the console. Those bodies
include minted LiveKit access tokens (`MintTokenResponse.token`), short-lived signed clip/photo URLs,
and caregiver/patient fields. These statements are compiled out of Release/TestFlight/App Store builds,
so end users are not affected.

**Why it still matters.** Anyone who runs a debug build (a lost/shared dev device, a CI artifact, a
screen-shared session) gets sensitive tokens in plaintext logs that may persist in the unified logging
system. It is also easy for a future change to accidentally widen one of these to a non-DEBUG path.

**Fix.** Redact tokens and signed URLs even in DEBUG (log lengths/IDs, not values), and route diagnostics
through `os.Logger` with `privacy: .private` rather than `print`, so the OS redacts sensitive
interpolations by default.

---

### L-3 (Low / Informational) — Client data security depends entirely on server-side RLS that is out of scope

**Files:**
- `NemaraCaregiver/Networking/AppConfig.swift:41,64,94` (prod Supabase URL + publishable key + Railway URL)
- `NemaraCaregiver/Services/Analytics.swift:249-251` (direct PostgREST `upsert` into `ui_events` from the client)
- `NemaraCaregiver/Services/NemaraAPIClient.swift:1134-1175` (direct Realtime subscriptions to `patients`/`cameras`/`detectors`/`events`)

**What it is — and why it is *not* a vuln by itself.** The Release Supabase project URL
(`https://zgifmvjnggmgzvtnosnu.supabase.co`), the **publishable/anon** key
(`sb_publishable_OsfCMOdEIb5gvhRWDyNivg_7GriAmyP`), and the production backend URL are hardcoded in the
binary. Per the mobile/secrets guidance, **anon/publishable keys are designed to ship in client apps** —
this is expected and correct, not a leaked secret. No `service_role` key, `sk_*` key, or signing secret
appears anywhere in source or git history (verified). The DEBUG default key is a well-known local
`supabase start` value.

**The real point.** Because the app talks to Supabase **directly** for analytics inserts and for
Realtime table subscriptions using only the anon key, the confidentiality and integrity of every
caregiver's data rests *entirely* on Row-Level Security being correctly enabled and scoped on
`patients`, `cameras`, `detectors`, `events`, `ui_events`, the face-embedding tables, and every Storage
bucket — plus correct authz in the FastAPI backend. This is the #1 source of critical vulnerabilities in
this class of app, and it is exactly what this static client-only audit **cannot see**. The code comments
assert RLS filters per-caregiver (e.g. `NemaraAPIClient.swift:1131-1133`), but assertions are not
verification.

**Action (not a code change in this repo).** Out-of-band, confirm for the production Supabase project:
RLS is `ENABLE`d on every table exposed via PostgREST/Realtime; every policy scopes rows to
`auth.uid() = caregiver_id` (no `USING (true)` / `USING (auth.uid() IS NOT NULL)`); INSERT/UPDATE
policies carry matching `WITH CHECK`; Storage buckets (patient photos, face embeddings, clips) have
per-user path policies; and the `ui_events` table cannot be read across caregivers. Treat the hardcoded
publishable key as public and rotate it only if RLS is found misconfigured. Consider proxying the
analytics insert through the backend so the client never writes to a table directly.

---

### L-4 (Low / Informational) — Analytics buffer persisted as plaintext JSON on disk

**File:** `NemaraCaregiver/Services/Analytics.swift:204-224, 267-274`

**What it is.** Buffered UI-interaction events are written to
`Application Support/ui_events_buffer.json` (`.atomic`, unencrypted). Contents are low-sensitivity:
caregiver UUID, session id, monotonic sequence, event/screen names, app build, OS version, device model.
No tokens, passwords, or patient PII are stored here, and the file lives inside the app sandbox.

**Why it's listed.** On a lost/stolen device that is unlocked or has weak data protection, this file is
readable and reveals caregiver identifiers and usage patterns. It is informational because the data is
not credential- or PII-grade.

**Fix.** Write the file with `Data.WritingOptions.completeFileProtection`
(`NSFileProtectionComplete`) so it is encrypted at rest while the device is locked. Optionally drop the
on-disk caregiver UUID in favor of a per-session pseudonym.

---

### I-1 (Informational) — Debug entitlements left in a "TEMP — revert before PR" state

**File:** `NemaraCaregiver/Resources/NemaraCaregiver-Debug.entitlements:5-7`

**What it is.** The Debug entitlements file is an empty `<dict/>` with a comment noting `aps-environment`
and Hotspot were "stripped (revert before PR)" to provision on a personal team. The **Release**
entitlements are correct (`aps-environment = production`, HotspotConfiguration enabled), and only the
Release config ships, so there is no runtime security impact. This is process hygiene: a TEMP local
workaround was committed.

**Fix.** Restore the intended Debug entitlements (or `#include?` a gitignored local override, mirroring
the `Local.xcconfig` pattern already used) so per-developer signing tweaks don't land in version control.

---

## Things checked and found clean (no action needed)

- **Token storage.** Supabase session (access + refresh JWT) is stored in the iOS Keychain by the SDK
  (`SupabaseAuthService.swift:263-273`). `UserDefaults` is used only for non-sensitive UI flags
  (camera "ever online" set, tutorial completion) — `NemaraAPIClient.swift:207-222`,
  `TutorialOverlay.swift`, `NewPatientView.swift`. No tokens in `UserDefaults`.
- **App Transport Security.** Only `NSAllowsLocalNetworking` is set (`Info.plist:36-40`,
  `project.yml`). `NSAllowsArbitraryLoads` is **not** set; production hosts are HTTPS and TLS is still
  enforced. DEBUG-only `http://*.local` URLs fall under the local-networking exception. Correct.
- **Authorization model.** The client enforces nothing locally; the backend + RLS authorize every
  request via the `Bearer` JWT (`NemaraAPIClient.swift:990-992`). The LiveKit `identity` sent at mint
  time is explicitly informational and re-validated server-side (`NemaraAPIClient.swift:888-908`).
- **Injection.** All request bodies are typed `Encodable` structs; all path params are `UUID`-typed and
  lowercased; query items use `URLQueryItem`. No string-concatenated queries, no client-side SQL.
- **AI/LLM.** Detector inference is server-side (`POST /v1/detectors/infer`,
  `NemaraAPIClient.swift:757-759`). No LLM API keys, no client-side model calls, no prompt construction
  on-device. Nothing to exploit client-side.
- **Dev-only data-collection clip capture.** Hard-compiled OFF in Release at a single choke point
  (`AppConfig.swift:112-132`) and the backend route is gated behind `NEMARA_ENABLE_INTERNALS`. Properly
  fenced out of production.
- **Secrets in history.** `git log -S` / `git grep` across all refs for `service_role`, `sk_live`,
  `sk_test`, `sb_secret_`, `AKIA`, `-----BEGIN`, etc. — no live secret material, only the publishable
  keys discussed in L-3.
- **Hardcoded `"Mar9aret!"` password** (`NemaraField.swift:149`) is inside a `#if DEBUG` `#Preview`
  block — a SwiftUI canvas dummy value, never compiled into a shipping build. Not a finding.
- **Dependencies.** Two SPM packages, both reputable and floor-pinned (`supabase-swift` from 2.44.1,
  `livekit/client-sdk-swift` from 2.0.0). No CocoaPods, no vendored binaries. `Package.resolved` is
  gitignored — recommend committing it (or running CI dependency scanning) so the exact resolved
  versions are auditable over time.

---

## Prioritized Recommendations

1. **(M-1)** Add TLS certificate/public-key pinning for the backend, Supabase, and LiveKit hosts, with
   backup pins and a rotation plan. Highest-value hardening given the biometric/video payload.
2. **(L-3)** Out-of-band, **verify production Supabase RLS** on every table, Realtime publication, and
   Storage bucket. The client's whole security model depends on it and it is unverifiable from this repo.
3. **(L-1)** Move password-reset (and any future auth) deep links to Universal Links; keep the custom
   scheme only as a non-sensitive fallback.
4. **(L-2)** Redact tokens/signed URLs from DEBUG logging; prefer `os.Logger` with `.private`.
5. **(L-4)** Apply `completeFileProtection` to the analytics buffer; consider proxying analytics inserts
   through the backend.
6. **(I-1)** Restore committed Debug entitlements; keep per-developer signing in a gitignored override.
