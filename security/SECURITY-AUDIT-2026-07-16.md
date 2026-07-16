# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-07-16
**Scope:** Static source review of `nemara-caregiver-app` (native iOS / Swift 6, SwiftUI).
**Methodology:** [`vibe-security`](https://github.com/raroque/vibe-security-skill) skill, mobile-prioritized (secrets, ATS, token storage, certificate pinning, deep links, client-side trust), plus committed-secret, authn/authz, injection, dependency, and AI/LLM checks.
**Constraint:** Static only — no live services or secrets were accessed; no external connections were made.

---

## Executive Summary

Overall the app is **in good security shape**. Authentication and authorization are correctly delegated server-side (Supabase Auth + a FastAPI backend + Supabase Row-Level Security), session tokens are stored in the iOS Keychain by the Supabase SDK (not `UserDefaults`), all AI/LLM calls are proxied through the backend (no model-provider keys on device), and only **publishable/anon** keys are embedded in the binary — which is by design and safe.

**No Critical or High severity issues were found.** The findings below are hardening / defense-in-depth items, all Low or Informational. The two most worth acting on are adding TLS certificate pinning for the live-video and API traffic of an at-risk population, and migrating the password-reset callback from a hijackable custom URL scheme to a Universal Link.

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | Low | Password-reset recovery code delivered over a hijackable custom URL scheme (`nemara://`) | `AppConfig.swift:71`, `NemaraCaregiverApp.swift:136`, `Info.plist:21` |
| 2 | Low | No TLS certificate / public-key pinning on API, Realtime, or LiveKit traffic | `NemaraAPIClient.swift:102`, app-wide |
| 3 | Low | Camera credential hashes (`api_key_hash`, `ingest_token_hash`) shipped to the client via Realtime | `Models/Camera.swift:125` |
| 4 | Low | Analytics buffer persisted unencrypted on disk with account/device identifiers | `Services/Analytics.swift:267` |
| 5 | Info | Debug-only logging prints full HTTP response bodies (patient PII, signed URLs) | `NemaraAPIClient.swift:1082` |
| 6 | Info | `NSAllowsLocalNetworking` allows cleartext HTTP to local addresses in Release | `project.yml:90`, `Info.plist:36` |
| 7 | Info | Debug entitlements ship stripped with a "revert before PR" TODO | `Resources/NemaraCaregiver-Debug.entitlements` |

**Explicitly reviewed and confirmed NOT vulnerable** (see [Positive Findings](#positive-findings)): hardcoded Supabase keys (publishable/anon — safe to ship), token storage, AI key exposure, SQL/URL injection, and ATS for production hosts.

---

## Findings

### Low

#### 1. Password-reset recovery code delivered over a hijackable custom URL scheme

**Files:** `NemaraCaregiver/Networking/AppConfig.swift:71`, `NemaraCaregiver/App/NemaraCaregiverApp.swift:136-151`, `NemaraCaregiver/Resources/Info.plist:21-31`

The forgot-password flow asks Supabase to email a recovery link that targets a **custom URL scheme**:

```swift
// AppConfig.swift:71
static let supabasePasswordResetRedirect = URL(string: "nemara://reset-password")!
```

```swift
// NemaraCaregiverApp.swift:136
private func handleIncomingURL(_ url: URL) {
    guard url.scheme == "nemara" else { return }
    ...
    if let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value {
        pendingResetCode = code   // → ResetPasswordView → exchangeRecoveryCode(code)
    }
}
```

Custom URL schemes are **not exclusive** on iOS. Any other app installed on the device may also register `nemara://`; when two apps claim the same scheme, which one the OS launches is undefined. A malicious app could therefore receive the `?code=…` recovery parameter from the email link.

**Why the impact is Low (not High):** the Supabase Swift SDK uses the **PKCE** flow by default, and the exchange (`exchangeCodeForSession(authCode:)`, `SupabaseAuthService.swift:183`) requires the `code_verifier` that was generated and stored in *this app's* Keychain when `resetPasswordForEmail` was called. An app that only intercepts the `code` does **not** possess the verifier, so it cannot complete the exchange — account takeover is blocked by PKCE. The residual risk is confused-deputy / denial-of-service (a hijacking app can consume/burn the one-time code so the legitimate app's reset fails).

**Escalation condition — read before dismissing:** if the auth `flowType` is ever changed from `.pkce` to `.implicit`, or if any future deep link is made to carry a bearer token/session directly instead of a PKCE code, this immediately becomes a **Critical** account-takeover vector.

**Fix:** Use a **Universal Link** (HTTPS, `apple-app-site-association`-verified associated domain) for the auth callback instead of a custom scheme. Universal Links are cryptographically bound to a domain you control and cannot be claimed by another app.

```swift
// After — domain-verified Universal Link, not a claimable scheme
static let supabasePasswordResetRedirect = URL(string: "https://nemara.app/auth/reset-password")!
```
…backed by an `associated-domains` entitlement (`applinks:nemara.app`) and the AASA file on the host. Keep `flowType` at `.pkce`.

---

#### 2. No TLS certificate / public-key pinning

**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift:102` (`session: URLSession = .shared`), plus the Supabase and LiveKit clients

All network traffic — the caregiver API (`NemaraAPIClient` over `URLSession.shared`), Supabase Auth/Realtime, and LiveKit media — relies on default system TLS trust with **no certificate or public-key pinning**. Default trust means any CA in the device trust store (including an enterprise/MDM root or a user-installed configuration profile) can terminate TLS, enabling a man-in-the-middle to read/alter API responses and JWTs.

This app streams **live video of an at-risk adult inside their home** and carries health-adjacent detection events, so the confidentiality bar is higher than a typical app; pinning is the standard hardening for this data class.

**Fix:** Implement public-key pinning via a `URLSessionDelegate` `urlSession(_:didReceive:completionHandler:)` challenge handler (pin the SPKI hash of the leaf/intermediate) for the backend, and configure pinning on the Supabase client's session. Pin to the intermediate CA's public key (not the leaf) so certificate rotation doesn't brick the app, and ship a backup pin.

---

#### 3. Camera credential hashes shipped to the client via Realtime

**File:** `NemaraCaregiver/Models/Camera.swift:120-167`

Supabase Realtime broadcasts the **raw `cameras` DB row**, which includes `api_key_hash` and `ingest_token_hash`. The client decodes them only to derive the `paired` boolean and then discards them:

```swift
// Camera.swift:125-126
case apiKeyHash = "api_key_hash"
case ingestTokenHash = "ingest_token_hash"
```

RLS scopes these rows to the owning caregiver and the values are hashes (not the plaintext credentials), so real-world impact is limited. Still, camera authentication material — even hashed — should not be transmitted to a client that never needs it (data minimization; a leaked hash aids offline cracking if the hashing is weak).

**Fix:** Exclude these columns from the client's read path. Either drop `api_key_hash`/`ingest_token_hash` from the `supabase_realtime` publication's column list for `cameras`, or expose a dedicated Realtime view/column set that carries `paired` directly (the REST shape already does), so the hashes never leave the server.

---

#### 4. Analytics buffer persisted unencrypted on disk with identifiers

**File:** `NemaraCaregiver/Services/Analytics.swift:44-57, 204-274`

The UI-analytics buffer is written to Application Support as plaintext JSON (`ui_events_buffer.json`) and contains `caregiver_id`, `session_id`, device model, OS version, and screen/navigation flow:

```swift
// Analytics.swift:267-273
private static var fileURL: URL? {
    ...
    return dir.appendingPathComponent("ui_events_buffer.json")
}
```

No credentials are stored, so severity is Low. However, the account identifier plus behavioral/usage trail is written unencrypted and is included in iTunes/iCloud device backups, exposing it on a jailbroken or backed-up device.

**Fix:** Set data protection on the file (`FileProtectionType.completeUntilFirstUserAuthentication` or stronger via `write(options: .completeFileProtection)`), and exclude it from backup (`URLResourceValues.isExcludedFromBackup = true`). Prefer not persisting `caregiver_id` at rest, or minimize the retained window.

---

### Informational

#### 5. Debug-only logging prints full HTTP response bodies and decode failures

**File:** `NemaraCaregiver/Services/NemaraAPIClient.swift:1081-1088, 1119-1123`

Under `#if DEBUG`, decode failures and non-2xx responses print the raw response body to the console — which for this app can include patient PII, narratives, and short-lived signed clip/photo URLs. This is compiled out of Release builds, so it does not ship to users. Called out only so it stays that way: never wrap these logs so they run in Release, and avoid logging `Authorization` headers.

#### 6. `NSAllowsLocalNetworking` permits cleartext HTTP to local addresses in Release

**Files:** `project.yml:90-91`, `Info.plist:36-40`

```xml
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsLocalNetworking</key><true/></dict>
```

This ATS key ships in **both** Debug and Release. It only relaxes cleartext for non-routable/local destinations (loopback, `*.local`, RFC-1918, link-local) — **not** arbitrary internet hosts — and the app legitimately uses local networking to discover nearby cameras (`NSLocalNetworkUsageDescription` is set), so this is largely intentional. Note it as a conscious decision: production backend/Supabase/LiveKit hosts are HTTPS and remain TLS-enforced by ATS. If on-LAN camera setup does not require cleartext in production, consider scoping this exception to Debug only.

#### 7. Debug entitlements ship stripped with a "revert before PR" TODO

**File:** `NemaraCaregiver/Resources/NemaraCaregiver-Debug.entitlements`

The Debug entitlements file has APNs (`aps-environment`) and Hotspot capabilities removed with an inline note: *"TEMP (local fallback — revert before PR) … revert before PR."* The **Release** entitlements are correct (`aps-environment = production`), so distribution builds are unaffected. This is a build-hygiene leftover, not a security defect — flagged so the temporary local change isn't forgotten.

---

## Positive Findings

Confirmed handled correctly (documented to show coverage and prevent false positives):

- **Embedded Supabase keys are safe.** `AppConfig.swift:41-65` ships the production Supabase project URL and a `sb_publishable_…` **anon/publishable** key. Per the vibe-security guidance, publishable/anon keys are explicitly designed to be embedded in client apps; RLS is the security boundary. **No `service_role` key, Stripe secret, JWT signing secret, or database connection string** appears anywhere in the repo.
- **Session tokens live in the Keychain**, not `UserDefaults`. The Supabase SDK persists and auto-restores the session (`SupabaseAuthService.swift:262-273`); the only `UserDefaults` writes are non-sensitive UI flags (camera "ever online" set, tutorial flags).
- **AI/LLM calls are backend-proxied.** Door detection and detector inference (`NemaraAPIClient.detectDoors`, `inferDetector`) POST to the app's own backend; no OpenAI/Anthropic/Google key exists on device. LLM output (detected doors) is used only to position UI overlays — never rendered as HTML or executed.
- **Authorization is server-side.** Every request attaches the Supabase JWT (`makeRequest`, `NemaraAPIClient.swift:1027`); the client performs no trust-bearing authorization decisions. LiveKit room tokens are minted server-side (`/v1/livekit/token`) — no LiveKit API secret on device.
- **No injection surface.** All path interpolation uses server-issued UUIDs (`.uuidString`); query values go through `URLQueryItem`; multipart boundaries/filenames are constant. No `WKWebView`/`UIWebView`, no `evaluateJavaScript`, no raw SQL.
- **ATS enforces TLS for production hosts.** The only relaxation is `NSAllowsLocalNetworking` (see #6); there is no `NSAllowsArbitraryLoads`.
- **Dependencies** are two reputable SDKs pinned to a floor (`Supabase 2.44.1+`, `LiveKit 2.0.0+`, `project.yml:3-21`). Keep them updated; re-run a vulnerability check when `Package.resolved` changes.

---

## Prioritized Recommendations

1. **(Low) Add TLS certificate/public-key pinning** for the API, Supabase, and LiveKit traffic — highest-value hardening given the live-video and at-risk-user context. Pin to an intermediate SPKI with a backup pin. *(Finding 2)*
2. **(Low) Move the password-reset callback to a Universal Link** and keep the auth `flowType` at `.pkce`. Removes the scheme-hijack DoS today and forecloses a takeover vector if the flow ever changes. *(Finding 1)*
3. **(Low) Stop shipping `api_key_hash` / `ingest_token_hash` to the client** — filter them out of the Realtime publication. *(Finding 3)*
4. **(Low) Apply file protection + backup exclusion to the analytics buffer** (or minimize stored identifiers). *(Finding 4)*
5. **(Info) Keep the DEBUG-only body logging DEBUG-only**, scope `NSAllowsLocalNetworking` to Debug if production doesn't need cleartext LAN, and restore the Debug entitlements before release. *(Findings 5–7)*

---

*Static audit only; no dynamic testing, runtime instrumentation, or backend/RLS-policy review was performed. Server-side authorization (FastAPI + Supabase RLS) is the primary control for this client and should be audited separately in its own repository.*
