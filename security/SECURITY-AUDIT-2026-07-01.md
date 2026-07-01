# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-07-01
**Scope:** Static source review of `nemara-caregiver-app` (native iOS / Swift, SwiftUI).
**Methodology:** [`vibe-security`](https://github.com/raroque/vibe-security-skill) skill, with mobile checks prioritized (secrets in bundle, ATS, token storage, transport trust, deep links, dependencies, AI usage).
**Constraints:** Static only. No live services, secrets, or network access were used.

---

## Executive Summary

The codebase is, on the whole, **well-architected from a security standpoint**. The most common and most damaging "vibe-coded" mobile mistakes are **not** present here:

- **No third-party secret keys are embedded in the app.** AI inference (`/v1/detectors/infer`) and LiveKit access tokens (`/v1/livekit/token`) are minted **server-side** and fetched over the authenticated backend — the correct backend-proxy pattern. There is no OpenAI/Anthropic/Gemini/LiveKit *secret* key in the Swift source or Info.plist.
- **The only embedded Supabase key is the publishable/anon key**, which is designed to ship in clients; access is gated by server-side RLS. This is correctly identified and documented in `AppConfig.swift`.
- **Auth session tokens are stored in the iOS Keychain** by the Supabase SDK (its default), not in `UserDefaults`/plaintext. Requests attach the JWT as a `Bearer` header read fresh from the SDK per call.
- **App Transport Security is only relaxed for local networking** (`NSAllowsLocalNetworking`); TLS is still enforced for all routable/production hosts.
- A dev-only "capture clip" data-collection feature is **hard-compiled OFF in Release** (`#if !DEBUG → return false`), with a clear single choke point.
- Password-reset avoids account enumeration; deletion and sign-out de-register push tokens.

No **Critical** or **High** severity issues were found. The findings below are **Medium** and **Low** — hardening opportunities appropriate to a health/eldercare app that streams live audio/video of vulnerable adults and carries a full-account bearer token.

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | Medium | No TLS certificate / public-key pinning on the API + auth channel | `NemaraAPIClient.swift`, `project.yml` |
| 2 | Medium | Loose dependency version floors + `Package.resolved` gitignored (non-reproducible / supply-chain) | `project.yml:13,21`, `.gitignore:17` |
| 3 | Low | Camera credential **hashes** shipped to the client via Realtime | `Models/Camera.swift:113-154` |
| 4 | Low | DEBUG builds log full HTTP response bodies (can include JWTs) | `NemaraAPIClient.swift:1044-1051,1082-1086` |
| 5 | Low | Deep-link recovery code accepted with only a scheme check | `NemaraCaregiverApp.swift:136-151` |
| 6 | Low | Analytics buffer persisted as plaintext JSON on disk | `Services/Analytics.swift:204-224` |

---

## Medium

### 1. No TLS certificate / public-key pinning on the API + auth channel

**Where:** `NemaraCaregiver/Services/NemaraAPIClient.swift` (uses `URLSession.shared`, default trust), `NemaraCaregiver/Networking/AppConfig.swift:94` (prod backend), `project.yml:90-91` (ATS).

**What / why exploitable:** Every authenticated request attaches the Supabase access JWT as `Authorization: Bearer <token>` (`NemaraAPIClient.swift:990-992`) and is sent over a standard `URLSession` that trusts the system/user CA store with no pinning. The same is true of the Supabase Auth and Realtime channels and the LiveKit media connection. For an app whose data is **live audio/video of vulnerable care recipients** plus a token that grants **full access to every patient, camera, and event** for the account, the transport is a high-value target. An attacker positioned on the network who possesses a mis-issued or rogue CA certificate — or who can convince a caregiver to install a malicious configuration profile / enterprise root (a well-known iOS social-engineering vector) — can transparently MitM the connection, capture the bearer JWT, and replay it to read/modify all account data or watch the video feed. TLS alone stops passive sniffing but not an attacker holding a trusted-by-the-device certificate.

**Fix:** Pin the backend and Supabase certificates (or, more maintainably, their intermediate CA / SPKI public-key hash) so a connection presenting any other chain is rejected. Two standard options:

- Declarative ATS pinning via Info.plist `NSPinnedDomains` (`NSPinnedCAIdentities` with the SPKI SHA-256), added to the `NSAppTransportSecurity` dict in `project.yml`.
- A `URLSessionDelegate` implementing `urlSession(_:didReceive:completionHandler:)` that validates the server public key against a pinned set before completing the handshake, and inject that session into `NemaraAPIClient` instead of `.shared`.

Pin to the intermediate/leaf public key with a documented rotation plan so certificate renewal doesn't brick the app.

---

### 2. Loose dependency version floors + `Package.resolved` not committed (non-reproducible builds / supply chain)

**Where:** `project.yml:13` (`Supabase … from: "2.44.1"`), `project.yml:21` (`LiveKit … from: "2.0.0"`), `.gitignore:17` (`Package.resolved`).

**What / why exploitable:** Both Swift Package dependencies are declared with `from:` constraints, which are **minimum** versions — SwiftPM is free to resolve any newer `2.x.y`. Because `Package.resolved` (the lockfile that records the exact resolved commit/version) is **gitignored**, there is no pinned, reviewed record of what actually ships, and two builds from the same commit can pull different dependency versions. This is the classic supply-chain exposure: a compromised, malicious, or simply regressed upstream release of `supabase-swift` or `client-sdk-swift` is pulled into a release build automatically, with no PR/diff to review and no audit trail of what a given App Store build contained. The Supabase SDK sits directly on the auth/token path, so a bad release there is worst-case.

**Fix:**
1. **Commit `Package.resolved`** (remove it from `.gitignore`) so the exact dependency graph is pinned and reviewable, and Dependabot/CI can flag advisories against the locked versions.
2. Tighten the constraints to a reviewed range (e.g. `.upToNextMinor(from:)` / `exact:`) and bump deliberately via PR rather than letting `from:` float.
3. Add a CI step that fails if `Package.resolved` changes unexpectedly, and periodically audit the pinned versions for published advisories.

---

## Low

### 3. Camera credential hashes are shipped to the client via Supabase Realtime

**Where:** `NemaraCaregiver/Models/Camera.swift:113-114, 152-154`.

**What / why:** The `Camera` decoder reads `api_key_hash` and `ingest_token_hash` from the raw DB row that Supabase Realtime broadcasts, uses them to derive `paired`, then drops them. These are only **hashes** (not plaintext credentials), the channel is RLS-scoped to the caregiver's own cameras, and the app never persists or re-transmits them — so real-world impact is limited. However, the backend is exposing the hashed camera-ingest credential columns to every subscribed client, which is unnecessary attack surface: hash values shouldn't leave the server, and a future client bug (or a change in what's logged/persisted) could turn an information leak into something more. This is a server-side Realtime-publication concern surfaced by the client contract.

**Fix (server-side, noted for the backend team):** Exclude `api_key_hash` / `ingest_token_hash` from the `supabase_realtime` publication (or broadcast a derived `paired` boolean instead of the raw row) so credential-hash columns never reach clients. The iOS decoder can then rely solely on the explicit `paired` field.

### 4. DEBUG builds log full HTTP response bodies (can include JWTs)

**Where:** `NemaraCaregiver/Services/NemaraAPIClient.swift:1044-1051` (decode-failure path) and `1082-1086` (`mapStatus` error path).

**What / why:** On a decode failure or a non-2xx status, DEBUG builds `print(...)` the entire response body. The `/v1/livekit/token` response and Supabase session responses contain access tokens, so a malformed/unexpected response could emit a JWT to the device console/log. This is guarded by `#if DEBUG` and therefore absent from App Store/Release builds — but DEBUG and internal/TestFlight-adjacent builds are frequently shared, and console logs can be captured off a connected device.

**Fix:** Redact or omit token-bearing fields before logging, or gate this body-dump behind an explicit opt-in verbose flag rather than plain `#if DEBUG`. At minimum, never log the body of the LiveKit-token / auth endpoints.

### 5. Deep-link recovery code accepted with only a scheme check

**Where:** `NemaraCaregiver/App/NemaraCaregiverApp.swift:136-151`.

**What / why:** `handleIncomingURL` accepts `nemara://reset-password?code=…` from any originating app or web page after checking only `url.scheme == "nemara"`, then hands the `code` straight to `exchangeCodeForSession`. Recovery codes are single-use and delivered to the account's own email, so exploitability is low; still, the handler performs no host allow-listing or parameter validation/sanitization, and treating deep-link input as trusted is exactly the pattern to avoid on this attack surface (any website can invoke a custom-scheme link).

**Fix:** Validate the URL beyond scheme (confirm host, reject unexpected/extra parameters, sanity-check the code format before exchange), and keep the existing behavior of silently ignoring malformed links. Consider Universal Links for recovery instead of a custom scheme so the OS binds the link to your verified domain.

### 6. Analytics buffer persisted as plaintext JSON on disk

**Where:** `NemaraCaregiver/Services/Analytics.swift:204-224, 267-274` (`ui_events_buffer.json` in Application Support).

**What / why:** Buffered UI-analytics events (caregiver UUID, device model, OS version, screen/button names, timestamps) are written unencrypted to Application Support. No auth tokens or health data are stored here, and the file lives in the app sandbox under iOS's default file protection, so exposure requires a jailbroken/unlocked device with filesystem access — hence Low. It is still caregiver-attributable telemetry sitting in cleartext.

**Fix:** Set an explicit `NSFileProtection` level (e.g. `.completeUntilFirstUserAuthentication`) when writing the buffer, and avoid persisting anything more identifying than necessary.

---

## Areas reviewed with no material findings

- **Hardcoded secrets:** none. The only key-shaped strings are Supabase **publishable/anon** keys (safe by design) and a local base64 pagination cursor in test fixtures. The `"Mar9aret!"` string in `NemaraField.swift:149` is a `#if DEBUG` SwiftUI `#Preview` default and is not a real credential (stripped from Release).
- **ATS / transport config:** `NSAllowsLocalNetworking` only; production TLS enforced. `http://` literals are DEBUG-only `.local` dev hosts.
- **Token storage:** Supabase SDK Keychain-backed session; no tokens in `UserDefaults` (only non-sensitive camera UUIDs and a first-connect set).
- **AI/LLM integration:** detector inference and classification go through the authenticated backend; no model API keys client-side; user text is sent to the server, not concatenated into client-side prompts.
- **Authn/authz:** JWT verification and per-caregiver RLS are enforced server-side; the app does not make trust decisions from client-held role/subscription flags. LiveKit identities are treated as informational (server re-mints).
- **Injection:** no SQL/shell construction on the client; all API paths use typed UUIDs and query items.
- **Committed secrets:** no `.env`, `.p8`, `.p12`, `.mobileprovision`, or `Local.xcconfig` tracked in git; `.gitignore` excludes local override config.
- **No TLS-disabling code** (`allowInvalidCertificates` / custom trust-all delegates) anywhere in the source.

---

## Prioritized Recommendations

1. **Add certificate/public-key pinning** for the backend, Supabase, and LiveKit channels (Medium — highest-value hardening for this app's threat model).
2. **Commit `Package.resolved` and tighten dependency constraints** to make builds reproducible and supply-chain-auditable (Medium).
3. **Stop broadcasting camera credential-hash columns** over Realtime (Low, server-side).
4. **Redact token-bearing response bodies from DEBUG logging** (Low).
5. **Harden deep-link handling** with host/parameter validation, ideally Universal Links (Low).
6. **Apply explicit file protection** to the analytics buffer (Low).

*Audit performed statically against the `main` branch checkout. No code was modified; this report is the only added file.*
