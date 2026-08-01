# Security Audit — Nemara / Memoria Caregiver iOS App

**Date:** 2026-08-01
**Scope:** Static source audit of `nemara-caregiver-app` (native iOS / Swift, SwiftUI). No live services, secrets, or network access were used.
**Methodology:** [vibe-security](https://github.com/raroque/vibe-security-skill) skill, mobile-first (secrets, ATS, token storage, cert pinning, deep links, client-side trust), plus authn/authz, injection, dependencies, and AI/LLM usage.
**Commit audited:** `0eae8a9` (branch `main`), app version 1.2.10 (build 36).

---

## Executive Summary

The app is, overall, **well-architected from a security standpoint**. It follows the core "never trust the client" principle: authentication is delegated to Supabase (server-issued JWTs), **all** AI/LLM inference runs behind the backend proxy (no model API keys in the client), session tokens are stored in the iOS **Keychain** (via the Supabase SDK, not `UserDefaults`), and every data mutation goes through an authenticated backend endpoint. The only credentials embedded in the client are Supabase **publishable/anon keys**, which are designed to ship in client apps. **No secret keys, service-role keys, private keys, or `sk_*` tokens were found** in source or in git history.

No **Critical** issues were found. The findings below are led by a real, working set of **demo credentials committed to the repository** and a cluster of **mobile defense-in-depth gaps** (password reset over a hijackable custom URL scheme, no TLS/certificate pinning) that matter more than usual because this app streams live audio/video of vulnerable elderly patients and carries account-takeover-grade tokens.

### Findings at a glance

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | **Medium** | Password reset delivered over a hijackable custom URL scheme (`nemara://`) | `NemaraCaregiverApp.swift:141`, `Info.plist:21` |
| 2 | **Medium** | No TLS / certificate pinning on backend, Supabase, or LiveKit traffic | `NemaraAPIClient.swift:102`, `SupabaseAuthService.swift:92` |
| 3 | **Low** | Working demo account credentials committed to `README.md` | `README.md:62-63` |
| 4 | **Low** | LiveKit room token minted for a client-supplied patient id — authorization is backend-only | `NemaraAPIClient.swift:925-945` |
| 5 | **Low** | Cleartext local-networking ATS exception ships in Release builds | `project.yml:90-91`, `Info.plist:36-40` |
| 6 | **Low / Info** | Realistic password string hardcoded in a SwiftUI `#Preview` | `NemaraField.swift:149` |
| 7 | **Info** | No jailbreak / client-integrity checks | app-wide |

---

## Detailed Findings

### 1. (Medium) Password reset delivered over a hijackable custom URL scheme

**Files:** `NemaraCaregiver/App/NemaraCaregiverApp.swift:141-156`, `NemaraCaregiver/Networking/AppConfig.swift:71`, `NemaraCaregiver/Resources/Info.plist:21-31`

The password-recovery flow routes Supabase's recovery link through the app's **custom URL scheme**:

```swift
// AppConfig.swift:71
static let supabasePasswordResetRedirect = URL(string: "nemara://reset-password")!

// NemaraCaregiverApp.swift:141
private func handleIncomingURL(_ url: URL) {
    guard url.scheme == "nemara" else { return }
    ...
    if let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value {
        pendingResetCode = code            // exchanged for a full session
    }
}
```

The `?code=…` value is a single-use recovery token that `exchangeRecoveryCode(_:)` → `exchangeCodeForSession` trades for a **fully signed-in session** (`SupabaseAuthService.swift:182-210`). On iOS, **custom URL schemes are not exclusive**: any other app installed on the device can also register `nemara://`, and when two apps claim the same scheme the OS resolution is undefined (effectively last-installed-wins). A malicious app that registers `nemara://` can therefore intercept the recovery `code`, exchange it first, and **take over the caregiver's account** — which grants live camera/microphone access into a vulnerable person's home.

This is exactly the case the skill's `mobile.md` warns about: *"Never include sensitive data in deep link URLs (tokens, passwords, user IDs that grant access)."* The app declares only the custom scheme (`Info.plist:21`) and has **no Associated Domains entitlement** (`NemaraCaregiver-Release.entitlements`), so Universal Links — the collision-proof alternative — are not in use.

**Why exploitable:** Account takeover requires (a) a hostile app already on the device claiming the scheme and (b) the victim completing a password reset, but the payoff (full account + home A/V access) is high and the interception is silent.

**Fix:** Deliver the recovery redirect via a **Universal Link** (`https://…` on an `applinks:`-verified domain) instead of `nemara://`. Universal Links are cryptographically bound to the app via `apple-app-site-association` and cannot be claimed by another app. Add the `com.apple.developer.associated-domains` entitlement and set the Supabase redirect to the HTTPS URL. Continue using PKCE so the code is only exchangeable by the client that initiated the request.

---

### 2. (Medium) No TLS / certificate pinning on any network path

**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift:98-110` (`session: URLSession = .shared`), `NemaraCaregiver/Services/SupabaseAuthService.swift:92` (`SupabaseClient(...)`), LiveKit connection at `LiveKitClient.swift:206-228`.

Every network client uses the default `URLSession`/SDK transport with **no certificate or public-key pinning**:

```swift
// NemaraAPIClient.swift
session: URLSession = .shared          // default trust evaluation only
```

TLS is still validated against the system trust store, so this is a **defense-in-depth gap, not a broken-crypto bug**. But the app transmits Supabase JWTs, caregiver PII, patient face embeddings/photos, and live A/V of vulnerable adults. On a device where an attacker (or a coercive party in an elder-care setting) can install a configuration profile with a rogue root CA, all of that traffic — including the bearer token minted on every request (`NemaraAPIClient.swift:1027-1029`) — becomes interceptable and replayable.

**Fix:** Pin the backend, Supabase, and LiveKit hosts. Simplest: add `NSPinnedDomains` under `NSAppTransportSecurity` in `Info.plist` with the leaf/intermediate SPKI hashes. Or implement `URLSessionDelegate.urlSession(_:didReceive:completionHandler:)` to compare the server public key against a bundled pin, and inject that session into `NemaraAPIClient`. Pin to the intermediate CA to survive leaf rotation.

---

### 3. (Low) Working demo account credentials committed to the repository

**File:** `README.md:62-63`

```
- Email: `jane@patel.co`
- Password: `Mar9aret!2024`
```

These are live login credentials for a seeded caregiver account (created by the backend's `make fresh-seed`). If that seed is ever run against — or the account otherwise exists in — the **production** Supabase project (`https://zgifmvjnggmgzvtnosnu.supabase.co`, `AppConfig.swift:41`), anyone with the public repo can sign in and view that patient's data and cameras. Even if it is strictly local-only today, committing real-looking credentials normalizes the practice and they persist in git history permanently.

**Why exploitable:** Directly usable credentials; exploitability hinges on whether the account exists in prod (verify out-of-band — not determinable statically).

**Fix:** Remove the password from `README.md`; document the demo login as "created by `make fresh-seed` locally" without the literal secret. Treat `Mar9aret!2024` as compromised and ensure no production account uses it. Because it is in history, rotating/deleting the account is the only real remediation.

---

### 4. (Low) LiveKit room token minted for a client-supplied patient id

**File:** `NemaraCaregiver/Services/NemaraAPIClient.swift:925-945`

```swift
let body = MintTokenRequest(
    room: "patient_\(pid.uuidString.lowercased())",   // pid comes from the client
    identity: "caregiver_\(caregiverID...)_ios",
    role: role,                                        // "viewer" or "broadcaster"
)
return try await sendJSON(method: "POST", path: "/v1/livekit/token", body: body)
```

The client requests a viewer/broadcaster token for an **arbitrary** `patient_<pid>` room. If the backend does not verify that the authenticated caregiver is authorized for that specific patient, this is an IDOR: a caregiver could mint a token to watch any patient's cameras or (as `broadcaster`) speak audio into any patient's home. The inline comment ("server validates the prefix and re-mints") suggests some server-side checking exists.

**Why this is only Low here:** The vulnerable/safe decision lives entirely in `nemara-backend`, which is **out of scope** for this repo. This cannot be confirmed from the iOS source; it is flagged as an authorization-critical path to verify, per the skill's "enforce server-side" principle.

**Fix (backend, to verify):** In `POST /v1/livekit/token`, resolve the caregiver from the JWT and confirm ownership of `pid` before minting; reject with 403 otherwise. Do not trust the room/identity in the request body for authorization.

---

### 5. (Low) Cleartext local-networking ATS exception ships in Release

**Files:** `project.yml:90-91`, `NemaraCaregiver/Resources/Info.plist:36-40`

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key><true/>
</dict>
```

`project.yml` uses the **same Info.plist for Debug and Release** (`configFiles: Debug/Release → Defaults.xcconfig`), so `NSAllowsLocalNetworking` is present in production builds. This is the **narrow, correct** ATS exception (it only permits cleartext to loopback/`.local`/RFC-1918 addresses and does **not** weaken TLS for public hosts — unlike `NSAllowsArbitraryLoads`). All Release endpoints are hardcoded HTTPS (`AppConfig.swift:41,94`), so real-world exploitability is minimal. It is noted only because the exception exists solely for the developer LAN stack and need not ship.

**Fix (hardening):** Split ATS so `NSAllowsLocalNetworking` applies only to Debug builds (e.g. a separate Release Info.plist or an `#if`-driven build setting), keeping Release fully ATS-strict.

---

### 6. (Low / Informational) Realistic password string hardcoded in a SwiftUI Preview

**File:** `NemaraCaregiver/DesignSystem/Components/NemaraField.swift:149`

```swift
#if DEBUG
#Preview {
    struct Demo: View {
        @State private var password = "Mar9aret!"   // preview seed only
```

Compiled out of Release (`#if DEBUG`), so not shipped. Flagged only because it mirrors the real demo password prefix (`Mar9aret!` vs `Mar9aret!2024`), suggesting credential reuse.

**Fix:** Use an obviously-fake placeholder (e.g. `"Password123!"`) in the preview.

---

### 7. (Informational) No jailbreak / client-integrity checks

The app performs no jailbreak detection or runtime-integrity checks. This is consistent with the skill's guidance that security must be enforced server-side (which this app does), and such checks are trivially bypassable — so their absence is **not a vulnerability**. Given the sensitivity of live A/V into vulnerable adults' homes, a lightweight jailbreak check could be considered as defense-in-depth, with the understanding that it is not a security boundary.

---

## Areas Reviewed With No Issues Found

- **Secret keys / API keys:** None hardcoded. Only Supabase `sb_publishable_*` (anon) keys are embedded — safe by design. No `service_role`, `sk_*`, AWS, Slack, GitHub, or private-key material in source or git history.
- **AI / LLM integration:** All inference is backend-proxied (`/v1/detectors/infer`, `/v1/detect-doors`). No model provider keys or direct LLM calls in the client. Prompt construction happens server-side.
- **Token storage:** Session/JWT stored in the **iOS Keychain** by the Supabase SDK (`SupabaseAuthService.swift:263`). `UserDefaults` holds only non-sensitive UI state (camera "ever online" UUIDs, blur toggles, an onboarding flag).
- **Sensitive logging:** No tokens, passwords, or secrets are logged. Verbose bodies print only under `#if DEBUG`.
- **Injection:** No SQL string-building on the client; all data access is typed REST via `NemaraAPIClient`. No `WKWebView`/`eval`/dynamic code execution of untrusted input.
- **Authentication model:** Server-issued JWT attached as `Bearer` per request; Realtime channels re-auth on every token change (`SupabaseAuthService.swift:99-104`) and are RLS-gated server-side. Password-reset avoids account enumeration (`requestPasswordReset` docs).
- **Dependencies:** Two well-known SDKs pinned with floors (`Supabase from 2.44.1`, `LiveKit from 2.0.0`). No abandoned or typosquat-looking packages. (`Package.resolved` is gitignored, so exact resolved versions were not verifiable statically — recommend committing a lockfile for reproducible, auditable builds.)

---

## Prioritized Remediation Summary

1. **Move password-reset off the custom URL scheme to Universal Links (Medium, #1)** — closes a silent account-takeover path that grants live home A/V access.
2. **Add certificate/public-key pinning (Medium, #2)** — protects JWTs, PII, and patient A/V against rogue-CA MITM.
3. **Remove committed demo credentials and confirm the account cannot log in to prod (Low, #3).**
4. **Verify server-side authorization on `/v1/livekit/token` for the requested patient (Low, #4)** — backend check, out of this repo's scope.
5. **Scope the local-networking ATS exception to Debug (Low, #5)** and use a fake preview password (#6).

_No Critical or High severity issues were identified. The application's server-authoritative design is sound; the recommendations above are hardening steps appropriate to the sensitivity of the data it handles._
