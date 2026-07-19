# Security Audit — Nemara Caregiver (iOS)

**Date:** 2026-07-19
**Scope:** Static source audit of the `nemara-caregiver-app` repository (native iOS / SwiftUI / Swift 6). No live services, secrets, or backend code were accessed. The backend (`nemara-backend`, FastAPI + Supabase) and the wall-phone app are out of scope except where the client depends on their behavior.
**Methodology:** [`vibe-security`](https://github.com/raroque/vibe-security-skill) skill, with mobile checks prioritized (hardcoded secrets, App Transport Security, token storage, deep links, client-side trust, dependencies, AI/LLM usage).

---

## Executive summary

This is a well-built client. It follows the most important mobile rule — **never trust the client** — by delegating all authentication, authorization, and data access to the backend (Supabase Auth JWTs + server-enforced RLS). The audit found **no Critical or High severity issues**: no exposed secret keys, no plaintext token storage, no client-side price/role/authorization logic, no direct third-party API calls from the app, and no AI API keys in the bundle.

The findings below are **defense-in-depth improvements**, not active breaches. The most significant is that the password-reset recovery code is delivered over a **custom URL scheme** (`nemara://`), which is interceptable by a malicious co-installed app.

| # | Severity | Finding | Location |
|---|----------|---------|----------|
| 1 | Medium | Password-reset recovery code delivered via hijackable custom URL scheme | `NemaraCaregiverApp.swift:141`, `AppConfig.swift:71` |
| 2 | Low | No TLS certificate / public-key pinning for health + live-video traffic | `NemaraAPIClient.swift:102`, `SupabaseAuthService.swift:92` |
| 3 | Low | Hardcoded sample password in a DEBUG-only SwiftUI preview | `NemaraField.swift:149` |
| 4 | Info | Verbose `#if DEBUG` diagnostic logging of connection metadata | `LiveKitClient.swift`, `NemaraAPIClient.swift` |

A **"Controls verified"** section at the end documents the protections that were checked and found correct, so the reader knows the clean areas were actually examined.

---

## Findings

### Medium

#### 1. Password-reset recovery code is delivered over a hijackable custom URL scheme

**Files:** `NemaraCaregiver/App/NemaraCaregiverApp.swift:141-156` (handler), `NemaraCaregiver/Networking/AppConfig.swift:71` (redirect), `NemaraCaregiver/Resources/Info.plist:21-31` (scheme registration).

The forgot-password flow asks Supabase to email a recovery link pointing at the custom scheme `nemara://reset-password?code=…` (`AppConfig.supabasePasswordResetRedirect`). The app parses the `code` query item and exchanges it for a **full authenticated session** via `exchangeCodeForSession` (`SupabaseAuthService.swift:182`).

```swift
// NemaraCaregiverApp.swift:145
case "reset-password":
    let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    if let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value {
        pendingResetCode = code            // → exchangeCodeForSession → live session
    }
```

**Why it's exploitable:** iOS custom URL schemes are **not exclusive** — any app can register `nemara://`, and when two apps claim the same scheme iOS resolves it non-deterministically (no origin verification). A malicious app installed on the victim's device can register `nemara://` and intercept the recovery link the victim taps from their email. The recovery `code` is a single-use credential that trades directly for a session → **account takeover** (access to the care recipient's live camera feeds, health events, and PII). The impact is high; likelihood is moderated by the need for a co-installed malicious app and winning the scheme-resolution race, hence **Medium**.

**Fix:** Deliver the recovery redirect over a **Universal Link** (verified HTTPS deep link) instead of a custom scheme. Universal Links are cryptographically bound to the app's associated domain via `apple-app-site-association`, so no other app can claim them.

```
1. Host  https://<your-domain>/.well-known/apple-app-site-association  with this app's appID.
2. Add the Associated Domains entitlement:  applinks:<your-domain>
3. Set the Supabase redirect to an https:// URL on that domain and add it to
   Auth → URL Configuration → Redirect URLs.
4. Route it in .onOpenURL exactly as today (the ?code= parsing is unchanged).
```

Keep the `nemara://` scheme only for non-sensitive navigation if needed. As a smaller hardening step, the code is already single-use and short-lived server-side; Universal Links close the interception vector itself.

---

### Low

#### 2. No TLS certificate / public-key pinning

**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift:102` (`session: URLSession = .shared`), `NemaraCaregiver/Services/SupabaseAuthService.swift:92` (default `SupabaseClient`).

All backend and Supabase traffic uses the default `URLSession.shared` with no `URLSessionDelegate` performing certificate or public-key pinning. Transport is HTTPS (ATS is correctly enforced — see Controls verified), so this is **not** a plaintext exposure.

**Why it matters:** The app transmits health-adjacent PII and mints tokens for **live video of vulnerable adults**. Without pinning, an attacker who can present a certificate trusted by the device — most realistically via a malicious MDM/enterprise root profile socially engineered onto the device, or a compromised CA — can MITM the session and read/modify traffic. Pinning removes reliance on the device trust store. Rated **Low** because it requires the attacker to already control the device's trust anchors.

**Fix:** Pin the leaf or intermediate public key for the backend (`nemara-backend-production.up.railway.app`) and Supabase (`*.supabase.co`) hosts. Inject a custom `URLSession` (the client already takes one via its initializer) whose delegate validates the server public-key hash in `urlSession(_:didReceive:completionHandler:)`, with a documented backup pin and rotation plan so a cert roll doesn't brick the app. Note Supabase Realtime/WebSocket connections would need equivalent handling.

#### 3. Hardcoded sample password in a DEBUG-only SwiftUI preview

**File:** `NemaraCaregiver/DesignSystem/Components/NemaraField.swift:149`

```swift
#if DEBUG
#Preview {
    struct Demo: View {
        @State private var password = "Mar9aret!"
```

The literal `"Mar9aret!"` is inside an `#if DEBUG` `#Preview` block, so it is **compiled out of release builds** and is not a live credential. It is flagged only because credential-shaped literals in source are a smell that can normalize the practice and occasionally get copied into real defaults. **Fix:** replace with an obviously-fake placeholder such as `"••••••••"` or `"Password123!"` that no reader could mistake for a real secret. No release-build impact.

---

### Informational

#### 4. Verbose DEBUG diagnostic logging

**Files:** `LiveKitClient.swift` (e.g. `:207` logs room + connection URL), `NemaraAPIClient.swift:1082-1121` (prints response bodies on decode/HTTP errors), various `print(...)` sites.

All such logging is wrapped in `#if DEBUG` and is stripped from release builds. Notably, **auth tokens and LiveKit JWTs are never logged** (the connect log prints `url` and `roomName` only, not `token`), and error-body dumps are DEBUG-only. No action required for production; noted so a future change that logs a token or an event body would be caught. Keep the `#if DEBUG` guards in place and avoid adding token/PII to any log line.

---

## Controls verified (no issue found)

These were specifically checked and are implemented correctly:

- **No exposed secret keys.** The only embedded Supabase keys are the **publishable/anon** keys (`sb_publishable_…`, `AppConfig.swift:61,64`), which are designed to ship in client apps and are gated by server-side RLS. No `service_role` key, no `sk_…`, no JWT signing secret, no DB connection string, no LiveKit API secret anywhere in source or git history.
- **Token storage uses the Keychain.** Sessions are persisted by the Supabase SDK's default Keychain-backed storage (`SupabaseAuthService.swift:263-268`); tokens are read fresh per request via `currentAccessToken()`. `UserDefaults` is used only for non-sensitive UI state (camera "ever online" set, blur toggles, tutorial flags) — no tokens or credentials.
- **App Transport Security is correctly configured.** `NSAppTransportSecurity` sets only `NSAllowsLocalNetworking: true` (`Info.plist:36-40`, `project.yml:90-91`), which permits plaintext **only** to link-local/RFC1918 addresses for the DEBUG local dev stack. Production hosts (`https://…railway.app`, `https://…supabase.co`) still require TLS. No blanket `NSAllowsArbitraryLoads`.
- **Environment separation is enforced at compile time.** Release builds hard-compile production URLs/keys and ignore `LocalAppConfig` and env overrides (`AppConfig.swift:37-42, 62-65, 89-95`); the dev-only clip-capture research feature is compiled `false` in release (`AppConfig.swift:120-131`).
- **Server-side authorization.** The client holds no role/permission/price logic. Every request carries the Supabase JWT as a Bearer token (`NemaraAPIClient.swift:1027`); patient/camera/event scoping is enforced server-side (RLS + backend), and LiveKit token identity is re-validated and re-minted by the backend (`NemaraAPIClient.swift:925-945`).
- **No client-side AI/LLM keys.** Detector inference and door detection call the app's own backend (`/v1/detectors/infer`, `/v1/detect-doors` — `NemaraAPIClient.swift:757,787`); no OpenAI/Anthropic/Google key or endpoint is present in the app (the only "OpenAI" reference is prose in the privacy policy).
- **Deep-link input is validated.** APNs and reset deep links parse identifiers strictly via `UUID(uuidString:)` and drop malformed input (`AppDelegate.swift:96-107`, `NemaraCaregiverApp.swift:143-155`); no destructive action is taken directly from link parameters.
- **Dependencies.** Only two well-maintained first-party SDKs, pinned to major-version floors: `supabase-swift` (from 2.44.1) and `livekit/client-sdk-swift` (from 2.0.0) (`project.yml:3-21`). No CocoaPods, no vendored/forked native libraries. (Exact resolved versions aren't pinned via a committed `Package.resolved` — it's gitignored — so confirm the resolved graph in CI against known-good advisories.)

---

## Prioritized remediation

1. **(Medium) Move the password-reset redirect to a Universal Link** to eliminate custom-scheme interception of the recovery code — the one finding with account-takeover impact.
2. **(Low) Add certificate/public-key pinning** for backend + Supabase hosts, given the sensitivity of live-video and health data.
3. **(Low) Replace the preview password literal** with an obvious placeholder.
4. **(Info) Keep DEBUG log guards** and never add tokens/PII to log lines; pin dependency versions in CI.

*Static audit only. It cannot observe runtime behavior or backend enforcement (Supabase RLS policies, backend authz, LiveKit grant validation); those should be verified server-side separately, as the client's security posture depends on them.*
