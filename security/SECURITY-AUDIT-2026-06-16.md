# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-06-16
**Scope:** Static source review of `nemara-caregiver-app` (native SwiftUI / iOS 17+ caregiver app).
**Methodology:** `vibe-security` skill (Chris Raroque), mobile-prioritized.
**Constraints:** Static only. No access to live services, the `nemara-backend` repo, the Supabase project, or any secrets. Backend authorization (RLS policies, LiveKit token minting, FastAPI route authz) could not be verified and is explicitly out of scope — several findings below depend on it and are flagged as such.

---

## Executive Summary

This is a well-architected, security-conscious codebase. The fundamentals that the `vibe-security` methodology most often catches are handled correctly:

- **No exposed secret keys.** The only embedded Supabase keys are publishable/anon keys (`sb_publishable_…`), which Supabase designs for client distribution. No `service_role`, `sk_…`, signing secrets, private keys, or `.p8` material is present in the repo.
- **Tokens are stored in the Keychain**, not `UserDefaults` — the Supabase SDK manages the session in the Keychain, and `UserDefaults` is used only for non-sensitive UI flags (tutorial state, "camera ever online" set).
- **App Transport Security is intact.** The only ATS exception is `NSAllowsLocalNetworking` (for LAN dev), which does not weaken TLS for production hosts. There is no `NSAllowsArbitraryLoads`.
- **Deep links are handled safely** — only `nemara://reset-password?code=…` is wired, the code is a single-use token exchanged server-side, and no destructive action is taken from link parameters.
- **Trust is placed server-side.** The client relies on Supabase RLS and backend authorization rather than client-side checks; LiveKit tokens are minted and authorized by the backend.

**No Critical or High severity issues were found.** The findings are one Medium (no TLS certificate pinning — defense-in-depth for a product that streams patient video and health-adjacent data) and several Low / Informational items. The most important non-finding to act on is operational: the app's security ultimately rests on the **backend's RLS and authorization being correctly configured**, which this static iOS review cannot confirm.

| # | Severity | Title |
|---|----------|-------|
| 1 | Medium | No TLS certificate / public-key pinning on backend & Supabase traffic |
| 2 | Low | Demo account credentials committed in `README.md` |
| 3 | Low | No jailbreak detection; Keychain tokens extractable on a compromised device |
| 4 | Low | DEBUG builds log full HTTP response bodies (may include signed URLs / tokens) |
| 5 | Low | Analytics buffer persisted unencrypted to Application Support (backed up) |
| 6 | Info | Production Supabase URL + anon key embedded — safe by design, but security hinges on RLS |
| 7 | Info | LiveKit room & role are client-requested — must be authorized server-side |
| 8 | Info | README signing identity (bundle ID / team) inconsistent with build config |

---

## Medium

### 1. No TLS certificate / public-key pinning on backend & Supabase traffic

**Where:** `NemaraCaregiver/Services/NemaraAPIClient.swift:102` (uses `URLSession.shared`); all REST traffic via `makeRequest` / `runDataTask` (`:950`–`:1043`); Supabase SDK client (`SupabaseAuthService.swift:86`) and Realtime; LiveKit SDK (`LiveKitClient.swift`).

**What's wrong:** Every network call goes through a default `URLSession` (`session: URLSession = .shared`) with no `URLSessionDelegate` implementing `urlSession(_:didReceive:completionHandler:)` for server-trust evaluation. There is no certificate or public-key pinning anywhere in the app.

**Why it's exploitable:** This app carries the caregiver's Supabase access JWT in an `Authorization: Bearer` header (`NemaraAPIClient.swift:967`) and fetches short-lived signed URLs for **patient video clips and avatars**, plus live A/V via LiveKit. An attacker who can get a CA trusted by the device — a malicious/compromised MDM profile, a corporate TLS-intercepting proxy, or a user socially-engineered into installing a configuration profile — can transparently MITM all of this: steal the bearer token (then impersonate the caregiver against the backend until it expires/refreshes), read patient PII and media URLs, and observe the full API surface. For a product handling vulnerable-adult monitoring data, pinning is an expected defense-in-depth control.

**Severity rationale:** Medium, not High — exploitation requires the attacker to first install/trust a CA on the victim's device (it does not defeat normal TLS), and the backend (RLS) still scopes data to the authenticated user. It is a defense-in-depth gap, not an open door.

**Fix:** Pin the backend and Supabase certificates (or, better, their public keys / SPKI hashes, which survive cert rotation if you pin the CA or leaf-key intermediate). Inject a non-shared `URLSession` with a pinning delegate into `NemaraAPIClient`, and configure pinning for the Supabase and LiveKit SDKs where supported.

```swift
// Sketch — pin the leaf public key (SPKI SHA-256) for routable hosts.
final class PinningDelegate: NSObject, URLSessionDelegate {
    let pinnedSPKIHashes: Set<String>   // base64 SHA-256 of SubjectPublicKeyInfo
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              SecTrustEvaluateWithError(trust, nil),
              let hash = spkiSHA256(of: trust), pinnedSPKIHashes.contains(hash) else {
            return completionHandler(.cancelAuthenticationChallenge, nil)   // fail closed
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
// Use a session built with this delegate instead of `.shared`, and keep
// NSAllowsLocalNetworking so #if DEBUG LAN dev still works (pin prod only).
```

---

## Low

### 2. Demo account credentials committed in `README.md`

**Where:** `README.md:62-63`

```
- Email: `jane@patel.co`
- Password: `Mar9aret!2024`
```

**What's wrong:** A working email/password pair is committed to the repository (and its git history). The README frames it as a local seed account created by the backend's `make fresh-seed`, so against a fresh local stack it is harmless. The risk is that the **same** `jane@patel.co` identity is also used as production preview/demo data (`AppEnvironment.swift:122`), and the production Supabase project URL is known (`AppConfig.swift:38`). If this seed is ever run against a shared/staging/internet-reachable Supabase project, these become valid live credentials that anyone with the repo can use to sign in.

**Why it matters:** Credentials in source control are permanent (history), and "local-only" seed accounts have a habit of being created in shared environments. Once committed, the password should be treated as burned.

**Fix:** Remove the literal password from the README (link to the seed script or describe how to obtain it instead). Ensure `jane@patel.co` exists only in throwaway local databases, never in staging/production. If the seed has ever been applied to a shared project, rotate/delete that account.

```diff
 ## Demo login
 After backend `make fresh-seed`:
-- Email: `jane@patel.co`
-- Password: `Mar9aret!2024`
+- Use the credentials printed by `make fresh-seed` (local-only seed account).
+- Never run the seed against a shared/staging/production Supabase project.
```

### 3. No jailbreak detection; Keychain tokens extractable on a compromised device

**Where:** App-wide. Session JWT/refresh token live in the Keychain (managed by the Supabase SDK; restored in `SupabaseAuthService.restoreSession()` at `:257`).

**What's wrong:** There is no jailbreak/root detection and no Secure-Enclave-backed gating of the stored session. On a jailbroken device, app-sandbox Keychain items and on-disk files are readable, so the caregiver's session token could be exfiltrated and replayed.

**Why this is Low:** The Keychain is the correct place for these tokens (not `UserDefaults`), data access is still scoped server-side by RLS, and physical/jailbreak access is a high bar. Jailbreak detection is also inherently bypassable (it raises cost, it doesn't prevent). This is a hardening opportunity, not a concrete vulnerability.

**Fix (optional hardening):** Consider `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for sensitive items so they don't migrate via backup, and — for the highest-value actions — a Secure-Enclave challenge/response (server nonce signed by a hardware key) rather than trusting a local boolean. Add jailbreak heuristics only as telemetry, not as a sole gate.

### 4. DEBUG builds log full HTTP response bodies

**Where:** `NemaraCaregiver/Services/NemaraAPIClient.swift:1020-1025` (decode-failure body dump) and `:1058-1062` (non-2xx body dump); plus numerous `#if DEBUG print(...)` of LiveKit identities/URLs in `LiveKitClient.swift`.

**What's wrong:** On decode failure or any error status, the raw response body is printed to the console. Response bodies can include short-lived **signed media URLs**, error payloads echoing tokens, or patient data. These reach the device console / Xcode logs.

**Why this is Low:** All of this is wrapped in `#if DEBUG`, so it is stripped from Release/TestFlight/App Store builds. The exposure is limited to developer machines and debug builds.

**Fix:** Keep it DEBUG-only (already the case). Optionally redact obvious secrets (Authorization headers, `?token=`/signed-URL query strings) even in debug output, so shared debug builds don't leak.

### 5. Analytics buffer persisted unencrypted to Application Support

**Where:** `NemaraCaregiver/Services/Analytics.swift:204-211` (write), `:215-224` (load), `:267-274` (`fileURL` → `applicationSupportDirectory/ui_events_buffer.json`).

**What's wrong:** Buffered UI-analytics events are written to a plaintext JSON file in Application Support with no file protection class specified and no exclusion from backups. The file contains `caregiver_id` (UUID), session id, OS/device model, and screen/button names.

**Why this is Low:** The buffer contains **no auth tokens and no patient health data / PII** — only coarse UI telemetry and an opaque caregiver UUID. The file lives in the app sandbox. The exposure is limited to device backups (iCloud/Finder) and on-device compromise.

**Fix:** Set a data-protection class on the write and exclude the file from backup:

```swift
try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
var u = url; var rv = URLResourceValues(); rv.isExcludedFromBackup = true
try? u.setResourceValues(rv)
```

---

## Informational

### 6. Production Supabase URL + anon key embedded — safe by design, but security hinges on RLS

**Where:** `NemaraCaregiver/Networking/AppConfig.swift:38` (`https://zgifmvjnggmgzvtnosnu.supabase.co`) and `:58-61` (`sb_publishable_…` keys).

These are **publishable/anon keys**, which Supabase explicitly designs to ship in client apps — this matches the `vibe-security` guidance ("Supabase anon key" belongs client-side) and is **not** a vulnerability. It is recorded here only to make the dependency explicit: because the anon key + project URL are public, **all data protection depends entirely on Supabase Row-Level Security being correctly configured server-side**. That is the single highest-leverage thing to verify, and it is outside the scope of this iOS-only static review. Recommend a dedicated audit of the `nemara-backend` RLS policies and FastAPI route authorization (confirm every `/v1/...` handler authenticates the JWT and authorizes resource ownership, and that the `supabase_realtime` publication is gated by per-caregiver RLS as the code comments at `NemaraAPIClient.swift:1108` assume).

### 7. LiveKit room & role are client-requested — must be authorized server-side

**Where:** `NemaraCaregiver/Services/NemaraAPIClient.swift:864-884` (`mintToken` sends `room: "patient_<pid>"` and `role: "viewer"|"broadcaster"`).

The client chooses the room and requests a role; the code comment states the server "validates the prefix and re-mints." If the backend trusts the client-supplied `room` or `role` without verifying the caregiver actually owns that patient and is allowed to publish, a user could request a `broadcaster` token for an arbitrary `patient_<id>` room (audio injection / cross-tenant access). This cannot be confirmed statically here — flag for backend verification that `/v1/livekit/token` authorizes both the patient relationship and the requested role.

### 8. README signing identity inconsistent with build config

**Where:** `README.md:37` states bundle ID `co.elephantlabs.nemara` / team `V8N59CF74G` (Elephant Labs), while `Defaults.xcconfig:5,12` set `co.sunny.nemara.caregiver` / team `2RM3SKJN35` (Darda and Cui, Inc), and `Info.plist`/`project.yml` use the `co.sunny.nemara` URL name. Not a security vulnerability, but the documentation drift around signing identity is worth reconciling to avoid confusion about which Apple team/APNs environment a build is provisioned against.

---

## Positive Observations (verified, no action needed)

- **Token storage:** session kept in Keychain via the Supabase SDK; `UserDefaults` holds only non-sensitive UI flags (`NemaraAPIClient.swift:50-51`, `TutorialOverlay.swift`, `NewPatientView.swift:485`).
- **ATS:** only `NSAllowsLocalNetworking` is set; no arbitrary-loads exception (`project.yml:90-91`, `Info.plist:36-40`). Production hosts use HTTPS (`AppConfig.swift:38,86`); plaintext HTTP is confined to `#if DEBUG` LAN hostnames.
- **No injection surface:** the app is a pure HTTP client; no raw SQL, no `eval`/dynamic code, no WebView/`WKWebView` rendering of remote HTML. Path parameters are typed `UUID`s lowercased into URLs (`NemaraAPIClient.swift`), not free-form strings.
- **Auth flows** use the Supabase SDK throughout (`signIn`/`signUp`/`resetPasswordForEmail`/`exchangeCodeForSession`); password-reset is a single-use code exchanged server-side; reset email enumeration is intentionally avoided (`SupabaseAuthService.swift:153-157`).
- **Realtime auth** is refreshed on every token change so RLS evaluates against the live user (`SupabaseAuthService.swift:93-98`).
- **No AI/LLM API keys in the client.** Detector inference (`/v1/detectors/infer`) is correctly proxied through the backend; no model-provider keys appear in the app.
- **Secrets hygiene:** `.gitignore` excludes `Local.xcconfig`; no `.env`, `.p8`, private keys, or `service_role`/`sk_`/secret-format keys are tracked.
- **Dependencies** are mainstream and reasonably pinned (Supabase `from: 2.44.1`, LiveKit `from: 2.0.0` in `project.yml`); no abandoned or typo-squat-looking packages. (Exact resolved versions are not committed — `Package.resolved` is gitignored — so a CVE check against the locked versions should be run in CI.)

---

## Prioritized Recommendations

1. **(Medium) Add TLS certificate/public-key pinning** for the Railway backend and Supabase, failing closed for routable hosts. Biggest concrete improvement for a product handling patient video/PII.
2. **(Low) Scrub the demo password from `README.md`** and confirm the seed account never lands in a shared/production Supabase project; rotate if it has.
3. **(Info → action) Audit the backend** (`nemara-backend`) separately: RLS policies, per-route JWT auth/ownership checks, and `/v1/livekit/token` room+role authorization. The client's whole security model rests on these, and they are not verifiable from the iOS source.
4. **(Low) Harden local data at rest:** file-protection class + backup exclusion on the analytics buffer; consider `…ThisDeviceOnly` Keychain accessibility for the session.
5. **(Low) Run a dependency CVE scan in CI** against resolved SPM versions (since `Package.resolved` is gitignored, pin and scan it in the pipeline).

*Static review only; no live systems were contacted. Backend-dependent items (RLS, route authz, LiveKit token authorization) require a separate review of `nemara-backend`.*
