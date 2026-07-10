# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-07-10
**Scope:** Static source review of `nemara-caregiver-app` (native iOS / SwiftUI, Swift 6).
**Methodology:** `vibe-security` skill (github.com/raroque/vibe-security-skill), with mobile-security
checks prioritized (hardcoded secrets, ATS, token storage, certificate pinning, deep links,
client-side trust), plus committed-secrets, auth/authz, dependencies, and AI/LLM usage.
**Constraint:** Static only. No live services, secrets, or backend source were accessed. The
Supabase project and `nemara-backend` (FastAPI/Railway) are out of scope; findings about
server-enforced controls (RLS, endpoint authz) are noted as **assumptions to verify**, not
confirmed defects.

---

## Executive Summary

The caregiver app is, overall, **well-architected from a security standpoint**. The common
"vibe-coded" failure modes are largely absent: there are **no secret API keys, service-role keys,
or signing secrets in the source or Info.plist**; auth tokens are stored in the **iOS Keychain**
(via the Supabase SDK, not `UserDefaults`); all third-party AI/VLM calls are **proxied through the
backend** (no LLM key on the device); App Transport Security is **not globally disabled**
(only local-network HTTP is allowed, and production hosts are forced to HTTPS); and LiveKit tokens
are **minted server-side**. No Critical or High severity issues were found in the client.

The most important thing to understand about this app's security is architectural: **the client
holds only the Supabase publishable/anon key and relies entirely on server-side Row-Level Security
(RLS) and backend authorization for data protection.** That boundary is correct in principle, but
it means the app is exactly as safe as those server-side policies — which this static client audit
cannot see. Verifying RLS coverage on every table is the single highest-value action (see M1).

The concrete client-side findings are all **Medium/Low** and are defense-in-depth improvements
rather than active exploits.

### Findings at a glance

| # | Severity | Title |
|---|----------|-------|
| M1 | Medium | Data-access security depends entirely on server-side RLS/authz that cannot be verified from the client (verify server-side) |
| M2 | Medium | No TLS certificate pinning on API / Supabase / LiveKit connections |
| L1 | Low | Security-sensitive password reset uses a custom URL scheme (`nemara://`) instead of Universal Links (scheme-hijacking exposure) |
| L2 | Low | No jailbreak / tamper detection on an app streaming live video of vulnerable adults |
| L3 | Low | Analytics buffer persisted unencrypted on disk (device metadata + navigation history) |
| — | Info | Verified-safe items (hardcoded anon key, Keychain storage, AI proxy, ATS scoping, dev-only clip capture) |

---

## Medium

### M1 — App's data-access security rests entirely on server-side RLS/authz (verify server-side)

**Files:** `NemaraCaregiver/Networking/AppConfig.swift:49-66`, `Services/Analytics.swift:233-258`,
`Services/NemaraAPIClient.swift` (all `/v1/...` calls).

The client authenticates to Supabase with only the **publishable/anon key** (`sb_publishable_…`),
and both the Supabase Realtime subscriptions (`openRealtimeChannels`, `NemaraAPIClient.swift:1171`)
and the direct `ui_events` insert (`Analytics.swift:249`) run under that anon key. Every REST call
to `nemara-backend` is authorized only by the caregiver's JWT bearer token
(`NemaraAPIClient.swift:1027`). This is the correct design **only if** every table has RLS policies
that scope rows to `auth.uid()`, and every backend endpoint re-checks ownership.

Why it matters: if RLS is missing or misconfigured on any of `patients`, `cameras`, `detectors`,
`events`, `ui_events`, `face_embeddings`, or the storage buckets, **any authenticated caregiver
could read or subscribe to another caregiver's patients, live-camera identities, or incident
history** — simply by using the shipped anon key, which is (correctly) public. The client code
even relies on RLS for correctness (comment at `NemaraAPIClient.swift:1168-1170`: "RLS policies
filter per-caregiver server-side"; `Analytics.swift:239` "Only the authed user's events are
insertable under RLS").

**This cannot be confirmed or refuted from this repo.** It is flagged as the top action because it
is the app's actual security boundary.

**Fix (server-side, out of this repo):**
- Confirm `ALTER TABLE … ENABLE ROW LEVEL SECURITY` + a `USING (auth.uid() = caregiver_id)`-style
  policy on every table exposed to the anon key and to the `supabase_realtime` publication.
- Confirm every `/v1/...` handler resolves the caregiver from the JWT and filters by ownership
  (the client already assumes this, e.g. `fetchEvent` "caregiver-scoped → 404 for a foreign id",
  `NemaraAPIClient.swift:872`).
- Add an automated RLS test (e.g. `pgTAP` or a Supabase policy test) so a future migration can't
  silently drop a policy.

---

### M2 — No TLS certificate pinning on API / Supabase / LiveKit connections

**Files:** `Services/NemaraAPIClient.swift:102` (`session: URLSession = .shared`),
`Services/SupabaseAuthService.swift:92` (`SupabaseClient(...)`),
`Services/LiveKitClient.swift:206-217` (`room.connect(url:token:)`).

All network traffic uses the default `URLSession.shared` / SDK defaults with **no
`URLSessionDelegate` implementing certificate or public-key pinning**. The app transmits highly
sensitive data — a caregiver's JWT (`Authorization: Bearer …`), live video/audio of vulnerable
adults, patient health/incident events, and uploaded selfies/face-embedding images — and it holds
the `com.apple.developer.networking.HotspotConfiguration` entitlement
(`NemaraCaregiver-Release.entitlements:7`), i.e. it is expected to operate on untrusted/local
Wi-Fi networks where an active man-in-the-middle is more feasible.

Without pinning, an attacker who can present a certificate the device trusts (a
maliciously-installed enterprise/root CA, a compromised network with a mis-issued cert) can
intercept and decrypt this traffic, harvesting the bearer token and patient data. TLS alone still
protects against passive eavesdropping; pinning closes the active-MITM gap that matters for a
health/eldercare app.

**Fix:** Pin the leaf or intermediate public key for the production API, Supabase, and LiveKit
hosts. With `URLSession`, implement
`urlSession(_:didReceive:completionHandler:)` and compare the server public key/SPKI hash against
a bundled pin set (with a backup pin for rotation). Alternatively adopt Apple's declarative
`NSPinnedDomains` in Info.plist for the fixed production domains. Keep the DEBUG local-stack path
exempt so developer builds against `*.local` still work.

---

## Low

### L1 — Password reset uses a custom URL scheme instead of Universal Links

**Files:** `App/NemaraCaregiverApp.swift:136-151` (`handleIncomingURL`),
`Resources/Info.plist:21-31` (`CFBundleURLSchemes: [nemara]`),
`Services/SupabaseAuthService.swift:164-191`.

The recovery flow sends `nemara://reset-password?code=…` and the app exchanges that `code` for a
session (`exchangeRecoveryCode`, `SupabaseAuthService.swift:182`). Custom URL schemes are **not
exclusive** — any other app installed on the device can also register `nemara://`, and iOS resolves
the conflict non-deterministically, so a malicious app can intercept the recovery link. The
security-sensitive password-reset channel should use **Universal Links** (an
`applinks:` Associated Domain), which are cryptographically bound to the domain and cannot be
claimed by another app.

Real-world exploitability here is **limited** because the Supabase Swift SDK uses a PKCE flow: the
`code_verifier` generated at `resetPasswordForEmail` time is stored locally on the legitimate
device, so an intercepted `code` alone is not sufficient to complete an account takeover on the
attacker's device. It is nonetheless a weaker transport than the flow warrants, and any app can
also trigger `nemara://reset-password?…` to pop the reset cover over the UI.

**Fix:** Migrate the recovery (and any future auth-callback / pairing) deep links to Universal
Links with an Associated Domains entitlement and an `apple-app-site-association` file; keep the
custom scheme only for non-sensitive navigation, and continue validating/percent-decoding all
parameters as `handleIncomingURL` already does.

---

### L2 — No jailbreak / runtime-tamper detection

**Files:** app-wide (no `LocalAuthentication`, no integrity/jailbreak checks present).

The app renders live camera feeds of care recipients and holds a Keychain session token, but
performs no jailbreak/root or debugger/tamper detection. On a jailbroken device, Keychain items and
in-memory tokens are more exposed, and hooks (Frida/objection) can bypass client-side gates. This
is a **defense-in-depth** gap, not an active vulnerability — client-side checks can always be
patched out — but it is worth a lightweight integrity check plus refusing to render live video on a
detected-compromised device, given the sensitivity of the content.

**Fix:** Add a lightweight jailbreak heuristic (suspicious paths, `fork()` success, sandbox
write-outside-container) as one signal, and — more robustly — adopt App Attest / DeviceCheck so the
backend can gate sensitive operations (LiveKit token minting, clip URLs) on an attested device
rather than trusting the client.

---

### L3 — Analytics buffer persisted unencrypted on disk

**File:** `Services/Analytics.swift:204-224, 267-274` (`ui_events_buffer.json` in Application
Support).

Buffered analytics events are written to `Application Support/ui_events_buffer.json` with
`JSONEncoder` and no encryption (`persist()`, `Analytics.swift:204`). Each row contains the
caregiver's UUID, device model/OS/build, session id, and a full **screen-navigation history**
(`Event`, `Analytics.swift:44-57`). This is **not credentials or tokens** (those remain in the
Keychain), so impact is low, but the file is readable via an unencrypted device backup or on a
compromised device and leaks behavioral metadata about the caregiver.

**Fix:** Write the buffer with `Data.WritingOptions.completeFileProtection` (NSFileProtection) so
it is encrypted at rest and unreadable while the device is locked, and exclude it from iCloud/iTunes
backup (`URLResourceValues.isExcludedFromBackup = true`). Minimize retained fields where possible.

---

## Informational — Verified-Safe (positive findings)

These were checked and found to be handled correctly. They are recorded so the team knows they were
reviewed and to prevent regressions.

- **Hardcoded Supabase key is safe by design.** `AppConfig.swift:61,64` embeds
  `sb_publishable_…` keys. Supabase publishable/anon keys are explicitly intended to ship in
  client apps and carry no privileges beyond RLS; **no `service_role` key, `sk_…` secret, JWT
  signing secret, or DB connection string appears anywhere** in source, Info.plist, or entitlements
  (verified by pattern scan). Protection depends on RLS — see **M1**.
- **Auth tokens stored in the Keychain.** The Supabase SDK persists the session in the Keychain and
  auto-restores it (`SupabaseAuthService.swift:263-273`); `UserDefaults` is used only for
  non-sensitive UI flags (`camerasEverOnline` UUIDs, tutorial flags). No token is written to
  `UserDefaults` or logged.
- **AI/LLM calls are backend-proxied.** Door detection and detector inference go through
  `POST /v1/detect-doors` and `POST /v1/detectors/infer` (`NemaraAPIClient.swift:757,787`); the VLM
  provider key lives only on the server. No OpenAI/Anthropic/etc. key is present in the app.
- **App Transport Security is correctly scoped.** Only `NSAllowsLocalNetworking` is set
  (`Info.plist:36-40`); `NSAllowsArbitraryLoads` is **absent**. Every plaintext `http://` URL is
  inside an `#if DEBUG` branch pointing at a LAN dev host (`AppConfig.swift:36,88`); Release builds
  hardcode HTTPS production hosts and never consult local/dev overrides
  (`AppConfig.swift:37-42, 89-95`).
- **Dev-only data-collection is hard-compiled off in Release.** The "capture 15s clip" research
  feature is forced `false` under `#if !DEBUG` with no override path (`AppConfig.swift:121-131`),
  so the camera-record chain cannot be enabled in a distribution build.
- **Push-notification deep links are server-scoped.** A notification tap carries only `event_id` /
  `patient_id` strings (`AppDelegate.swift:95-107`); the app fetches by id through the
  caregiver-scoped endpoint, which 404s for a foreign id (`NemaraAPIClient.swift:872-880`), so a
  spoofed push cannot surface another caregiver's data.
- **LiveKit identity is not trusted.** The client sends an informational identity; the comment and
  flow confirm the server validates and re-mints the token (`NemaraAPIClient.swift:925-945`).
- **Dependencies** are two reputable SDKs pinned to a floor (`supabase-swift` 2.44.1+,
  `client-sdk-swift` 2.0.0+) via SwiftPM (`project.yml:3-21`). No CocoaPods/vendored binaries. Keep
  them current; no known-vulnerable pin was identified statically.

---

## Prioritized Recommendations

1. **(M1) Verify server-side RLS + endpoint authorization** on every table and `/v1` route — this
   is the app's real security boundary and the highest-value action. Add automated policy tests.
2. **(M2) Add TLS certificate/public-key pinning** for the production API, Supabase, and LiveKit
   hosts (with a backup pin), given the sensitive video/health data and hotspot/untrusted-network
   usage.
3. **(L1) Move password-reset (and future auth) deep links to Universal Links.**
4. **(L3) Apply `completeFileProtection` + backup exclusion** to the analytics buffer.
5. **(L2) Add device integrity signals** (App Attest/DeviceCheck server-side gating; optional
   client jailbreak heuristic).

---

*Static audit performed with the `vibe-security` methodology. No app code was modified; this report
is the only file added. Server-side components (Supabase RLS, `nemara-backend`) were not in scope
and should be reviewed separately — especially the RLS policies that M1 depends on.*
