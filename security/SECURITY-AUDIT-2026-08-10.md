# Security Audit — nemara-caregiver-app

**Date:** 2026-08-10
**Scope:** Static source review of the `nemara-caregiver-app` iOS (Swift/SwiftUI) client at commit `2a84e0a`.
**Methodology:** [`vibe-security`](https://github.com/raroque/vibe-security-skill) skill — mobile-first, plus secrets, authN/Z, injection, dependencies, and AI/LLM usage.
**Constraints:** Static only. No access to live services, the `nemara-backend` API, or the Supabase project. Server-side controls (Postgres RLS, backend authorization) could not be verified and are called out where the client's security depends on them.

---

## Executive Summary

The app is, on the whole, **soundly built from a security standpoint**. It gets the fundamentals right where AI-generated mobile apps usually fail:

- **Session tokens are stored in the Keychain**, not `UserDefaults` — the Supabase Swift SDK persists the auth session in the Keychain by default, and the app relies on that (`SupabaseAuthService.restoreSession()`). No auth token is ever written to `UserDefaults`.
- **Only publishable/anon keys ship in the binary** (`AppConfig.supabaseAnonKey`) — these are designed to be client-side. No `service_role` key, Stripe secret, JWT signing secret, or third-party API secret was found in source, resources, or git history.
- **No App Transport Security bypass.** ATS is left enforced; the only exception is `NSAllowsLocalNetworking` (for LAN camera setup), which does **not** weaken TLS for production hosts. Release builds always use HTTPS endpoints.
- **Authorization is delegated server-side.** Every API call attaches the caller's Supabase JWT as a `Bearer` token; the client makes no trust decisions of its own (no client-side pricing, roles, or feature entitlements that matter). Dev-only features (`enableClipCapture`) are hard-compiled **off** in Release.
- **Biometric face data is handled server-side** — raw 512-dim embeddings are computed on the backend and never returned to or stored on the device (`FaceEmbedding.swift`).

No **Critical** issues were found. The findings below are one Medium credential-hygiene issue, one Medium defense-in-depth gap (no certificate pinning) that matters given the sensitivity of the data (live video/audio of vulnerable patients + PHI), and several Low/informational items.

**The single most important caveat:** because the client correctly pushes all authorization to the server, the real security boundary of this system is the **backend's authorization and Supabase RLS policies**, which are outside this repo and were **not** reviewed. A clean client does not imply a clean system — the backend must be audited separately.

### Severity ranking

| # | Severity | Finding | Location |
|---|----------|---------|----------|
| 1 | Medium | Committed demo/seed account credentials | `README.md:63` |
| 2 | Medium | No TLS certificate/public-key pinning | `NemaraAPIClient.swift`, `SupabaseAuthService.swift:92` |
| 3 | Low | Production infra identifiers hardcoded (expected, but concentrates trust server-side) | `AppConfig.swift:41,64,94` |
| 4 | Low | Internal developer hostname disclosed in source & docs | `AppConfig.swift:36,88`; `README.md` |
| 5 | Low | Debug logging prints full HTTP response bodies (potential PHI) | `NemaraAPIClient.swift:1197,1235` |
| 6 | Low | Analytics enabled by default; PII buffer persisted to disk | `Analytics.swift:11,209,267` |

---

## Medium

### 1. Committed demo/seed account credentials — `README.md:63`

The README publishes a working caregiver login:

```
## Demo login
- Email: `jane@patel.co`
- Password: `Mar9aret!2024`
```

**Why it's exploitable.** These are real, usable credentials committed to git — they cannot be revoked by deleting the line, because they remain in history. The README frames them as a *local* seed (`make fresh-seed`), which limits the blast radius **only if** that account never exists on a reachable, non-local backend. But the app ships the **production** Supabase project URL and anon key (`AppConfig.swift:41,64`) and points Release builds at prod. If this seed account was ever provisioned against the production (or any shared/staging) Supabase project — or if the same seed script is run there — anyone with the repo can sign in as a real caregiver and read that caregiver's patient PHI: live camera access, detection-event history, and the patient's face gallery. Password reuse of `Mar9aret!2024` across environments compounds this.

**Concrete fix.**
- Remove the password from `README.md`; document the demo flow without a real secret (e.g. "run `make fresh-seed`; credentials are printed by the seed script").
- Rotate the password on any environment where `jane@patel.co` exists, and confirm the seed account is **never** created in production/staging.
- Since the secret is in git history, treat it as compromised — rotating is mandatory, not optional.

```diff
  ## Demo login

  After backend `make fresh-seed`:

- - Email: `jane@patel.co`
- - Password: `Mar9aret!2024`
+ The seed script prints the demo caregiver's email and a freshly generated
+ password to the console. Never commit real credentials to the repo.
```

### 2. No TLS certificate / public-key pinning — `NemaraAPIClient.swift`, `SupabaseAuthService.swift:92`

The HTTP client uses `URLSession.shared` with no `URLSessionDelegate` and no server-trust evaluation (`NemaraAPIClient.init(..., session: URLSession = .shared)`), and the `SupabaseClient` is constructed with defaults (`SupabaseClient(supabaseURL: url, supabaseKey: key)`). No `NSPinnedDomains` entry exists in the Info.plist ATS block. A repo-wide search for `serverTrust`, `SecTrust`, `URLSessionDelegate`, `NSPinnedDomains`, and `pinn*` returned nothing.

**Why it matters here.** Standard TLS still protects ordinary users, so this is defense-in-depth, not an open door. But this app carries an unusually sensitive payload: bearer JWTs plus live video/audio and health/behavioral events of vulnerable patients (a HIPAA-adjacent posture). An attacker who can present a certificate the device already trusts — a maliciously issued/mis-issued CA cert, or an MDM/enterprise root installed on the device (common on managed or family-shared devices) — can transparently MITM the API and Supabase traffic, capturing the caregiver's session token and all PHI in flight. Pinning removes that entire class of attack.

**Concrete fix.** Pin the backend and Supabase domains. The lowest-friction option is declarative ATS pinning in the Info.plist (SPKI hashes), which also covers the Supabase SDK's own `URLSession`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key><true/>
  <key>NSPinnedDomains</key>
  <dict>
    <key>nemara-backend-production.up.railway.app</key>
    <dict>
      <key>NSPinnedCAIdentities</key>
      <array>
        <dict><key>SPKI-SHA256-BASE64</key><string><!-- leaf/intermediate SPKI hash --></string></dict>
        <dict><key>SPKI-SHA256-BASE64</key><string><!-- backup pin --></string></dict>
      </array>
    </dict>
    <key>zgifmvjnggmgzvtnosnu.supabase.co</key>
    <dict> <!-- same shape --> </dict>
  </dict>
</dict>
```

Always ship a **backup pin** and a rotation plan so a certificate change doesn't brick the app. (Note: Railway/Supabase manage their own certs, so prefer pinning the intermediate CA's SPKI over the leaf.)

---

## Low / Informational

### 3. Production infrastructure identifiers hardcoded — `AppConfig.swift:41,64,94`

Release builds embed the production Supabase URL (`https://zgifmvjnggmgzvtnosnu.supabase.co`), the prod publishable key (`sb_publishable_OsfCMOdEIb5gvhRWDyNivg_7GriAmyP`), and the Railway backend (`https://nemara-backend-production.up.railway.app`). **This is expected and acceptable for a mobile app** — publishable/anon keys are meant to ship, and the URLs are discoverable from network traffic regardless. It is listed here only to make the consequence explicit: with these values public, the *entire* security of user data rests on server-side controls (Supabase RLS + backend authZ). **Action:** none in the client, but treat a separate audit of backend authorization and RLS as a prerequisite before relying on this app in production.

### 4. Internal developer hostname disclosed — `AppConfig.swift:36,88`; `README.md`

The DEBUG fallback hardcodes a specific developer's machine (`http://sunnys-macbook-air.local:54341` / `:8002`) and the README documents LAN IP examples. This is compiled out of Release (`#else` branch), so it never ships to users. Minor internal-topology disclosure and a single-point-of-failure for the team's dev flow. **Fix (optional):** default the DEBUG fallback to `localhost`/simulator and keep per-developer hostnames only in the gitignored `LocalAppConfig.swift`.

### 5. Debug logging prints full HTTP response bodies — `NemaraAPIClient.swift:1197,1235`

On decode failure and on non-2xx responses, the client prints the raw response body to the console. Both sites are wrapped in `#if DEBUG`, so **nothing is logged in Release**. During development, however, this writes API payloads — which may include patient PHI — to the device/Xcode console. **Fix (optional):** redact or truncate bodies, or gate behind an explicit verbose flag, so PHI doesn't land in developer logs/crash captures.

### 6. Analytics enabled by default; PII buffer persisted to disk — `Analytics.swift:11,209,267`

`AnalyticsConfig.enabled = true` ships on. The buffer — which includes `caregiver_id`, session id, device model, OS version, and a screen/interaction history — is flushed hourly to a Supabase `ui_events` table and persisted to `Application Support/ui_events_buffer.json` for crash safety. iOS applies its default data-protection class (`CompleteUntilFirstUserAuthentication`) to that file, so at-rest exposure is limited, and the data is telemetry rather than credentials — hence Low. **Fix (optional):** set an explicit `.completeFileProtection` on the write, and confirm this collection is covered by the app's privacy manifest (`PrivacyInfo.xcprivacy`) and user consent, since it associates an identifier (`caregiver_id`) with behavioral data by default.

---

## Areas checked with no findings

- **Secrets scan** (source, `.plist`, `.xcconfig`, `.yml`, and full git history): no `service_role` key, `sk_live`/`sk_test`, private keys, AWS keys, or JWT signing secrets. The one committed password is finding #1. `.env`/`.env.*` are correctly gitignored and none are tracked.
- **App Transport Security:** no `NSAllowsArbitraryLoads`; only `NSAllowsLocalNetworking`. No cleartext HTTP to routable hosts in Release.
- **Token storage:** auth session in Keychain via the SDK; `UserDefaults` holds only non-sensitive UI state (camera-online flags, blur toggles, tutorial/ack flags).
- **Deep links:** `nemara://reset-password?code=…` is validated by scheme, parsed via `URLComponents`, and the code is exchanged server-side (`exchangeCodeForSession`); no destructive action fires from link params without the user setting a new password. No sensitive data is placed in outbound deep-link URLs.
- **AuthN/Z:** all mutating/reading endpoints attach the Supabase `Bearer` JWT; no client-side authorization gating of security-relevant actions; dev-only clip capture hard-compiled off in Release.
- **AI/LLM usage:** the `home-briefing` / `home-report` endpoints are backend LLM proxies — no AI provider API key is present in the client, and LLM output is rendered as plain SwiftUI `Text` (no HTML/web-view injection sink).
- **Dependencies:** only Supabase Swift (`from: 2.44.1`) and LiveKit (`from: 2.0.0`) via SPM, both reputable and reasonably pinned. No CocoaPods. `Package.resolved` is gitignored (consider committing it to lock exact transitive versions for reproducible, audited builds).
- **Injection:** no raw SQL, no string-built queries, no web views executing untrusted content; all server paths use typed, URL-encoded UUID path components.

---

## Prioritized remediation

1. **Remove and rotate the committed demo password (#1, Medium).** Confirm the seed account does not exist in production/staging; scrub from docs and rotate wherever it lives.
2. **Add certificate pinning for the backend and Supabase domains (#2, Medium),** with a backup pin and rotation plan — high value given the PHI/live-media sensitivity.
3. **Audit the backend + Supabase RLS separately (#3).** The client correctly trusts the server; that trust must be verified where it lives.
4. **Optional hardening (#4–#6):** default DEBUG to localhost, redact PHI from debug logs, set explicit file protection on the analytics buffer and confirm consent/privacy-manifest coverage.

---

*Generated by [Claude Code](https://claude.ai/code) using the vibe-security methodology. Static review only; no code was modified other than adding this report. Server-side controls were not in scope and must be audited independently.*
