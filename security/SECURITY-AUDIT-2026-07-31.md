# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-07-31
**Scope:** Static source audit of the `nemara-caregiver-app` repository (native iOS / Swift 6, SwiftUI). No live services, secrets, or backend were accessed.
**Methodology:** [`vibe-security`](https://github.com/raroque/vibe-security-skill) skill — secrets & env, authentication, data access, mobile, AI/LLM integration — adapted from its React-Native/web framing to native iOS.
**Commit audited:** `0eae8a9` (`main`).

---

## Executive summary

This is a **well-engineered app** with a mature security posture for a project of its size. The audit found **no Critical or High severity issues that are substantiated by the client code**. Notably done right:

- **Auth tokens live in the iOS Keychain**, managed by the Supabase SDK — not in `UserDefaults` or plaintext files. Every `UserDefaults` write in the app is non-sensitive (camera-online flags, blur preferences, tutorial state).
- **No hardcoded secret keys.** The only embedded Supabase keys are **anon / publishable** keys, which are designed to ship in clients. No `service_role` key, Stripe secret, JWT signing secret, or DB connection string appears in source or git history.
- **App Transport Security is not disabled.** There is no `NSAllowsArbitraryLoads`; the single exception (`NSAllowsLocalNetworking`) is the correctly-scoped minimum, and cleartext endpoints are gated behind `#if DEBUG`. Release builds are HTTPS-only.
- **Every API request carries a `Bearer` JWT** fetched fresh from the session; there is no client-side trust of prices, roles, or entitlements.

The most important takeaway is a **scope boundary**, not a bug: this client is a thin, correctly-built shell over a Supabase + FastAPI backend. The app freely sends server-controlled identifiers (patient IDs, camera IDs, LiveKit room names, and a `viewer`/`broadcaster` role) and relies entirely on **server-side RLS policies and FastAPI route authorization** to enforce access. That enforcement layer is where any Critical/High vulnerability for this product would live, and it is **outside the reach of this static client audit.** A server-side RLS + authorization review is the single highest-value follow-up (see M3).

The findings below are hardening and hygiene items, ranked by severity.

| # | Severity | Title |
|---|----------|-------|
| M1 | Medium | Password-reset uses a custom URL scheme, not a Universal Link — recovery-code interception risk |
| M2 | Medium | No TLS certificate/public-key pinning on PHI-bearing connections |
| M3 | Medium | Access control is entirely server-side and unverifiable from the client — requires a backend RLS/authz review |
| L1 | Low | Debug entitlements committed in a "revert before PR" stripped state |
| L2 | Low | `#if DEBUG` logging prints response bodies (incl. LiveKit JWT) and the media-server URL |
| L3 | Low | DEBUG builds transmit auth tokens in cleartext over the LAN |
| I1 | Info | Embedded Supabase anon keys & production URLs — reviewed, safe by design |

---

## Medium

### M1 — Password-reset deep link uses a custom URL scheme instead of a Universal Link

**Files:**
- `NemaraCaregiver/Resources/Info.plist:21-31` (registers scheme `nemara`)
- `NemaraCaregiver/Networking/AppConfig.swift:71` (`supabasePasswordResetRedirect = nemara://reset-password`)
- `NemaraCaregiver/App/NemaraCaregiverApp.swift:141-156` (`handleIncomingURL` reads `?code=`)
- `NemaraCaregiver/Services/SupabaseAuthService.swift:182-191` (`exchangeCodeForSession`)

**What it is.** Account recovery redirects to `nemara://reset-password?code=<recovery_code>`. On iOS, **any** app may declare `CFBundleURLSchemes = nemara`; when two apps claim the same scheme the resolution is undefined, so a malicious app installed on the device can be selected to handle the redirect and capture the recovery `code`. Because that code is exchanged for a full authenticated session (`exchangeCodeForSession` → `updateUser(password:)`), an intercepted code is a path toward account takeover of a caregiver account — which gates live camera access and health data for a vulnerable person.

**Why the severity is Medium, not High.** The Supabase Swift SDK defaults to the **PKCE** flow: `resetPasswordForEmail` stores a `code_verifier` in the app's own Keychain, and `exchangeCodeForSession` requires it. An interceptor on the device would capture the `code` but not the verifier, so it cannot complete the exchange in the common same-device flow — this substantially mitigates full takeover and is why this is not rated Critical/High. Residual risk remains: custom-scheme hijacking is a recognized weakness, it enables at minimum a denial/hijack of the reset flow, and any future change to a non-PKCE or cross-device flow would remove the mitigation.

**Fix.** Move the reset redirect to a **Universal Link** (HTTPS `https://<yourdomain>/reset-password?...`) backed by the `com.apple.developer.associated-domains` entitlement and an `apple-app-site-association` file. Universal Links are cryptographically bound to your verified domain and cannot be claimed by another app. Keep the PKCE flow (do not switch `flowType` away from `.pkce`). Custom schemes are acceptable for non-sensitive navigation, but a credential-recovery redirect should not depend on one.

---

### M2 — No TLS certificate / public-key pinning on connections that carry PHI

**Files:**
- `NemaraCaregiver/Services/NemaraAPIClient.swift:102, 1091-1093` (`URLSession.shared`, no `URLSessionDelegate` server-trust handling)
- `NemaraCaregiver/Services/LiveKitClient.swift:206-217` (LiveKit room connect)
- `NemaraCaregiver/Services/SupabaseAuthService.swift:92` (Supabase client)

**What it is.** The app transports highly sensitive data — caregiver identity, patient health/fall events, **live audio/video of a person in their home**, and **biometric face embeddings** (`submitFaceEmbeddings`, `NemaraAPIClient.swift:453`) — to Supabase and the Railway backend over standard `URLSession` with default trust evaluation and no pinning. An attacker who can get a rogue root CA trusted on the device (a malicious/managed MDM configuration profile, a coerced device, a compromised CA) can transparently man-in-the-middle these connections and read or alter the JWT and the health/A-V payloads. ATS guarantees TLS but does **not** defend against a *trusted* malicious certificate.

**Why it matters here.** For a general app this is routine best-practice hardening (Low). For an app streaming in-home video and handling biometric + health data of a vulnerable adult, the confidentiality stakes raise it to Medium.

**Fix.** Pin the server public keys (SPKI) for the API and Supabase hosts. Implement `urlSession(_:didReceive:completionHandler:)` in a `URLSessionDelegate` and validate the leaf/intermediate SPKI against a pinned set (pin two keys — current + backup — to survive rotation). For LiveKit, use the SDK's TLS configuration hooks or pin the media/signaling host similarly. Pair pinning with a remote kill-switch/rotation plan so a key roll doesn't brick installed clients.

---

### M3 — Access control is enforced entirely server-side and cannot be verified from the client

**Files (illustrative — the pattern is app-wide):**
- `NemaraCaregiver/Services/NemaraAPIClient.swift:925-945` — `mintToken` sends a client-chosen `room: "patient_<pid>"` **and** `role: "viewer"|"broadcaster"` for an arbitrary patient UUID.
- `NemaraCaregiver/Services/NemaraAPIClient.swift:361-909` — every patient/camera/detector/event call embeds a client-supplied ID in the path (`/v1/patients/{id}/…`, `/v1/cameras/{id}/…`, `/v1/events/{id}`).
- `NemaraCaregiver/Services/NemaraAPIClient.swift:1171-1176` — Realtime channels subscribe to whole tables (`patients`, `cameras`, `detectors`, `events`) and rely on RLS to filter rows per caregiver.

**What it is.** This is not a client bug — it is the **trust boundary**, and it is called out because it is where the product's real risk concentrates. Per the core "never trust the client" principle: the app lets a signed-in caregiver request a broadcaster token for **any** `patient_<uuid>` room, PATCH/DELETE any resource ID, and subscribe to entire tables. All of this is safe **only if** the backend independently verifies, on every request and every Realtime row, that the authenticated caregiver owns the target resource — and, for LiveKit, that it re-derives the grant/role from the JWT rather than honoring the client-supplied `role`. The code comment at `NemaraAPIClient.swift:929-931` ("server validates the prefix and re-mints with whatever we send") asserts this is handled, but it cannot be confirmed from the client.

**Why it's here.** If any of these server-side checks is missing or weak, the result is an IDOR / broken-access-control vulnerability that would be **Critical** (e.g., viewing or speaking into a stranger's in-home camera). The client gives an attacker everything needed to probe for it.

**Fix / follow-up (server-side, out of this repo's scope).** Commission a review of the nemara-backend confirming, for every route and Realtime-published table:
1. RLS policies gate `SELECT/INSERT/UPDATE/DELETE` on `auth.uid()`-derived caregiver ownership (including the `ui_events`, `cameras`, `events`, `face_embeddings` tables).
2. FastAPI route guards re-check ownership of every path ID rather than trusting it.
3. `/v1/livekit/token` derives `room` authorization and `canPublish` from the caregiver's verified ownership of the patient, ignoring the client-supplied `role` as anything more than a hint.

---

## Low

### L1 — Debug entitlements committed in a "revert before PR" stripped state

**File:** `NemaraCaregiver/Resources/NemaraCaregiver-Debug.entitlements:5-7`

The Debug entitlements file is empty except for a comment: *"TEMP (local fallback — revert before PR): Push (aps-environment) and Hotspot stripped so the app provisions on a personal team…"*. This is a **Debug-only** file (Release entitlements at `NemaraCaregiver-Release.entitlements` are intact with `aps-environment = production`), so there is no production security impact — it only disables push on local debug builds. It is flagged as **hygiene**: a "revert before PR" placeholder reached `main`, which signals the intended revert was skipped. Restore the Debug entitlements to their canonical (sandbox push) state and add a CI check that fails the build if an entitlements file contains a "TEMP"/"revert before" marker.

### L2 — `#if DEBUG` logging prints response bodies and the media-server URL

**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift:1082-1085` (prints raw response body on decode failure — includes the LiveKit JWT from `/v1/livekit/token`), `NemaraCaregiver/Services/NemaraAPIClient.swift:1120-1122` (prints error-response bodies), `NemaraCaregiver/Services/LiveKitClient.swift:208` (prints the LiveKit server URL).

All are wrapped in `#if DEBUG` and are **compiled out of Release** builds, so there is no shipped exposure. The risk is limited to bearer tokens/URLs landing in the Xcode console / device log during development. Acceptable, but prefer redaction (log a token's length or last 4 chars, never the value) so a shared debug session or a screen-recorded demo can't leak a live JWT.

### L3 — DEBUG builds transmit auth tokens in cleartext over the LAN

**Files:** `NemaraCaregiver/Networking/AppConfig.swift:36, 88` (`http://sunnys-macbook-air.local:54341`, `http://sunnys-macbook-air.local:8002`), `project.yml:90-91` (`NSAllowsLocalNetworking`).

In Debug, the app talks to a local backend over plain HTTP, so the Supabase JWT travels unencrypted on the developer's Wi-Fi. This is **development-only** (the code paths are `#if DEBUG`; Release always uses HTTPS production hosts, `AppConfig.swift:41, 94`) and `NSAllowsLocalNetworking` correctly restricts cleartext to non-routable addresses. Impact is confined to a dev's LAN. No action required for production; developers should avoid signing into real accounts against the plaintext local stack on untrusted networks.

---

## Informational

### I1 — Embedded Supabase anon keys and production URLs (reviewed — safe by design)

**Files:** `NemaraCaregiver/Networking/AppConfig.swift:41, 61, 64, 94` — Supabase project URL `https://zgifmvjnggmgzvtnosnu.supabase.co`, anon/publishable keys `sb_publishable_…`, and the Railway backend URL.

These are flagged **only to document that they were reviewed and are not a vulnerability.** Supabase **anon / publishable** keys and backend base URLs are explicitly designed to ship inside client apps; they carry no privileges beyond what RLS grants an unauthenticated request, exactly like a Stripe publishable key or Firebase client config. No `service_role` key, secret key, or signing secret is present anywhere in the source or git history (verified via history scan for `service_role`, `sk_live`/`sk_test`, `AKIA`, `-----BEGIN`, JWT patterns, and tracked `.env`/`.pem`/`.p8` files — all negative). The security of these keys rests on server-side RLS, which is covered by M3.

*(Note: the string `"Mar9aret!"` at `NemaraCaregiver/DesignSystem/Components/NemaraField.swift:149` is a SwiftUI `#Preview` placeholder inside a `#if DEBUG` block, not a credential.)*

---

## Methodology notes & coverage

- **Secrets & env:** full-repo regex scan of `*.swift`, `*.plist`, `*.xcconfig`, `*.json`, `*.yml` + git-history scan. Only anon/publishable keys found (I1).
- **Authentication:** Supabase Auth via SDK; tokens in Keychain; JWT bearer on every request; recovery flow reviewed (M1). No manual JWT decode/verify in client (delegated to SDK/backend) — appropriate.
- **Mobile:** token storage (Keychain ✓), API-key-via-backend-proxy (AI calls go through the backend, see below ✓), deep links (M1), ATS (L3, scoped-safe), pinning (M2).
- **AI / LLM integration:** door detection (`detectDoors`, `NemaraAPIClient.swift:787`) and detector inference (`inferDetector`, `:757`) are **server-proxied** — the app sends a base64 frame / text to the nemara-backend, which holds any model keys. No LLM API key is present client-side, and no LLM output is executed or rendered as HTML. Correct posture.
- **Data access / input validation:** no SQL/ORM in the client (all DB access is server-side via REST/RLS). Client-side input validation (password policy, email) is UX-only and correctly re-enforced server-side.
- **Dependencies:** SPM only — `supabase-swift` (from 2.44.1) and `client-sdk-swift` (from 2.0.0), both reputable first-party SDKs pinned to a floor. No CocoaPods. `from:` ranges allow minor/patch upgrades; consider pinning exact versions + committing `Package.resolved` for reproducible, reviewable dependency bumps (it is currently gitignored).

**Out of scope (recommended follow-ups):** server-side RLS & FastAPI authorization review (M3, highest value), and a dynamic/runtime test of the reset-link and LiveKit token flows against a staging backend.
