# Security Audit — nemara-caregiver-app

**Date:** 2026-06-22
**Scope:** Static source review of the `nemara-caregiver-app` iOS (SwiftUI) client only. No live services, secrets, or backend (`nemara-backend`) were accessed. Backend authorization (RLS policies, ownership checks, LiveKit token validation) is **out of scope** and is assumed-but-not-verified where the client delegates to it.
**Methodology:** `vibe-security` skill (Chris Raroque), adapted from its React Native/Expo guidance to native iOS Swift. Categories covered: secrets & environment, mobile token storage, App Transport Security, certificate pinning, deep links / URL schemes, authentication & session handling, client-side trust, AI/LLM usage, dependencies, and input handling.

---

## Executive Summary

The app is generally well-architected from a security standpoint. **No Critical or High severity issues were found.** Notably:

- **No third-party API secret keys are bundled.** All AI/detector inference, LiveKit token minting, and email sending go through the backend (`/v1/...`); the client never holds an OpenAI/Anthropic/LiveKit/Resend secret. This is exactly the "backend proxy" pattern the methodology prescribes.
- **Auth tokens are stored in the iOS Keychain** (the Supabase Swift SDK's default), not `UserDefaults`. The only `UserDefaults` writes are non-sensitive UI flags and camera UUIDs.
- **No SQL/string-built queries** exist on the client; all data access is typed REST against the backend.
- **ATS is configured correctly** — plaintext HTTP is allowed only for non-routable local-network addresses (dev), and TLS is still enforced for all routable/production hosts.
- **The password-reset deep link uses the PKCE code-exchange path** (`exchangeCodeForSession`), which binds the recovery code to a locally-stored verifier and defeats naive URL-scheme interception.

The findings below are hardening gaps and hygiene issues, ranked Medium and below. The two most actionable items are committed demo credentials (combined with committed production Supabase identifiers) and the absence of TLS certificate pinning for an app that streams live audio/video of vulnerable patients and carries PHI.

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | Medium | Working demo credentials committed alongside live production Supabase identifiers | `README.md:62-63`, `AppConfig.swift:38,60` |
| 2 | Medium | No TLS certificate / public-key pinning for a PHI + live-A/V app | `NemaraAPIClient.swift`, `LiveKitClient.swift`, app-wide |
| 3 | Low | Password-reset via custom URL scheme instead of Universal Links | `NemaraCaregiverApp.swift:103-139`, `Info.plist:21-31` |
| 4 | Low | Analytics buffer persisted as unencrypted JSON in the app container | `Analytics.swift:204-211,267-274` |
| 5 | Low | DEBUG logging prints full HTTP request/response bodies (may include PHI) | `NemaraAPIClient.swift:1020-1025,1058-1062` |
| 6 | Low | No jailbreak / client-integrity awareness (defense-in-depth) | app-wide |
| 7 | Info | Production Supabase anon (publishable) key committed in source | `AppConfig.swift:38,60` |
| 8 | Info | Client supplies `room`/`patient_<id>` to token mint — server-side ownership must be enforced | `NemaraAPIClient.swift:864-884` |

---

## Medium

### 1. Working demo credentials committed alongside live production Supabase identifiers

**`README.md:62-63`** ships a real, well-formed account credential:

```
- Email: `jane@patel.co`
- Password: `Mar9aret!2024`
```

On its own this is documented as a `make fresh-seed` (local dev) account. The risk is the **combination** with committed production connection details in `AppConfig.swift`:

```swift
// AppConfig.swift:38  (Release Supabase project URL)
return URL(string: "https://zgifmvjnggmgzvtnosnu.supabase.co")
// AppConfig.swift:60  (Release Supabase publishable/anon key)
return "sb_publishable_OsfCMOdEIb5gvhRWDyNivg_7GriAmyP"
```

**Why it matters:** Anyone with the repo has a production Supabase URL, a valid publishable key, and a complete username/password pair. If the same seed (`jane@patel.co`) was ever provisioned in the production or any shared/staging project — a common drift in early-stage products — these credentials grant a working sign-in to a caregiver account, exposing patient PII/PHI, event history, and live camera/audio access. Even if it is currently dev-only, committing a real password is a credential-hygiene failure: it will be copied into staging by someone eventually.

**Fix:**
- Remove the literal password from the README; reference an environment variable or a "ask a teammate" note instead.
- Confirm `jane@patel.co` does **not** exist in production/staging Supabase; if it does, rotate/delete it.
- Treat the demo account as ephemeral, recreated per local seed, never reused across environments.

```diff
- ## Demo login
- - Email: `jane@patel.co`
- - Password: `Mar9aret!2024`
+ ## Demo login
+ After `make fresh-seed`, a demo caregiver is created locally. Get the
+ throwaway credentials from the seed output or a teammate — they are not
+ committed and must never be reused outside a local stack.
```

### 2. No TLS certificate / public-key pinning

The app talks to the backend and Supabase over `URLSession.shared` (`NemaraAPIClient.swift:107`, `makeRequest`/`sendRequest`) and to LiveKit via the SDK, relying solely on the system trust store. There is no `URLSessionDelegate` implementing `urlSession(_:didReceive:completionHandler:)` for server-trust evaluation, and no pinning configuration anywhere in the codebase.

**Why it matters:** This app handles authentication JWTs, PHI (patient profiles, health/event narratives, face-enrollment images), and **live audio/video of vulnerable people in their homes**. Without pinning, an attacker who can present a certificate trusted by the device — a mis-issued/compromised CA, a corporate or maliciously-installed MDM/root profile, or a hostile Wi-Fi captive portal that convinced the user to trust a cert — can transparently MITM all traffic, capturing bearer tokens and patient data. The sensitivity of the data raises this above a generic "nice to have."

**Fix:** Pin the backend and Supabase leaf or intermediate public keys (SPKI hashes) via a `URLSessionDelegate` doing `SecTrustEvaluateWithError` plus a key-hash allowlist, or adopt a vetted library (e.g. TrustKit). Ship at least two pins (current + backup) and a kill-switch/expiry plan so a cert rotation can't brick the app.

```swift
// Sketch — server-trust pinning on the session backing NemaraAPIClient
final class PinningDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession,
                    didReceive ch: URLAuthenticationChallenge,
                    completionHandler done: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let trust = ch.protectionSpace.serverTrust,
              SecTrustEvaluateWithError(trust, nil),
              pinnedSPKIHashes.contains(spkiSHA256(of: trust)) else {
            return done(.cancelAuthenticationChallenge, nil)   // reject on mismatch
        }
        done(.useCredential, URLCredential(trust: trust))
    }
}
```

---

## Low

### 3. Password-reset uses a custom URL scheme rather than Universal Links

`Info.plist:21-31` registers the `nemara://` custom scheme, and `NemaraCaregiverApp.swift:124-139` routes `nemara://reset-password?code=…` into the recovery flow.

Custom URL schemes are not exclusive — any app on the device can also declare `nemara://`, and iOS does not guarantee which app wins, so a malicious app could attempt to intercept the recovery deep link.

**This is rated Low, not High, because the flow is mitigated:** `SupabaseAuthService.exchangeRecoveryCode` calls `client.auth.exchangeCodeForSession(authCode:)` — the PKCE path. The recovery `code` is useless without the code-verifier stored in the originating app's Keychain, so an interceptor cannot complete the exchange or take over the account. The residual risk is information disclosure (a leaked one-time code) and reliance on PKCE staying enabled.

**Fix (defense-in-depth):** Migrate security-sensitive links (password reset, any future auth callback) to **Universal Links** with an `apple-app-site-association` file and the Associated Domains entitlement. Universal Links are bound to a domain you control and cannot be claimed by another app. Keep `flowType` on PKCE explicitly so a future SDK/config change can't silently fall back to the implicit (token-in-URL) flow.

### 4. Analytics buffer persisted as unencrypted JSON in the app container

`Analytics.swift:204-211` writes the in-memory event buffer to `Application Support/ui_events_buffer.json` (`fileURL`, line 267-274) with `.atomic` but no encryption / Data Protection class. Buffered events include `caregiver_id`, `session_id`, screen names, app build, OS version, and device model (`Event`, lines 44-57).

**Why it matters:** The data is low-sensitivity (no tokens, no PHI), and on a non-jailbroken device the container is sandboxed. But the file can surface in unencrypted iTunes/Finder backups and is readable on a jailbroken/forensic device, leaking a behavioral trail tied to a caregiver id.

**Fix:** Write the file with `Data.WritingOptions.completeFileProtection` (or `.completeUnlessOpen`) so it is encrypted at rest when the device is locked:

```swift
try? data.write(to: url, options: [.atomic, .completeFileProtection])
```

### 5. DEBUG logging prints full request/response bodies

`NemaraAPIClient.swift:1020-1025` (decode-failure path) and `:1058-1062` (HTTP-error path) `print(...)` the raw response body, and various LiveKit/Realtime logs are verbose. These are all guarded by `#if DEBUG`, so they are stripped from Release/TestFlight/App Store builds.

**Why it matters:** Only in development the device console can capture PHI (patient names, event narratives, face-enrollment responses) and error payloads. The release-build guard keeps this out of users' hands, so it is Low.

**Fix:** Keep the `#if DEBUG` guards (good), and prefer redacting or logging only status codes / byte counts rather than full bodies even in debug, to avoid shoulder-surfing and accidental log capture during demos.

### 6. No jailbreak / client-integrity awareness

The app performs no jailbreak detection and has no biometric/local-auth gate before showing patient data or live feeds. The methodology's mobile guidance notes that simple client-side trust checks are bypassable and that real assurance comes from server-side enforcement — which this app correctly leans on (Keychain tokens + backend RLS). As such this is purely defense-in-depth and Low.

**Fix (optional):** Consider an optional Face ID/Touch ID gate (`LAContext`) on launch/foreground for an app that exposes live home video, and basic jailbreak heuristics to raise the bar for casual device-level attackers. Do not treat either as a security boundary.

---

## Informational

### 7. Production Supabase anon (publishable) key committed in source

`AppConfig.swift:60` hardcodes the Release publishable key (`sb_publishable_...`). Per Supabase's model — and the audit methodology's own guidance — **anon/publishable keys are designed to be shipped in client apps** and are not secret. No rotation is required. This is flagged only to record that the app's security therefore rests entirely on **server-side Row-Level Security**, which is out of scope here and must be independently verified in `nemara-backend`. If any service-role key ever appears client-side, that would be Critical — none was found.

### 8. Client supplies `room` / `patient_<id>` to the token-mint endpoint

`NemaraAPIClient.mintToken` (`:864-884`) sends `room: "patient_<pid>"` chosen client-side; `startTalk`/`recordClip`/photo/face-embedding endpoints likewise take a client-chosen `patientId`. The code comments indicate the server validates the prefix and re-mints, and all requests carry the caregiver JWT. This is correct **only if** the backend authorizes that the JWT's caregiver actually owns the target patient/room before issuing a LiveKit token or acting. Verify ownership enforcement on every `/v1/patients/{id}/...`, `/v1/cameras/{id}/...`, and `/v1/livekit/token` route server-side; the client cannot and should not be the enforcement point.

---

## Positives Observed

- AI/LLM and all secret-bearing third-party calls are backend-proxied; no secret keys in the bundle (`NemaraAPIClient` calls `/v1/detectors/infer`, `/v1/livekit/token`, `/v1/support`, `/v1/feedback`).
- Auth/session tokens kept in Keychain via the Supabase SDK; `currentAccessToken()` reads from the live session, not persisted plaintext.
- ATS exception is correctly scoped to `NSAllowsLocalNetworking` only; routable hosts still require TLS (`project.yml:90-91`, `Info.plist:36-40`).
- Push-notification deep links validate `event_id`/`patient_id` as UUIDs and fetch JWT-scoped (`AppDelegate.swift:89-101`, `NemaraAPIClient.fetchEvent`), returning 404 for foreign ids.
- Per-config APNs entitlements (sandbox vs production) are correctly separated.
- Typed `Encodable` request bodies throughout — no mass-assignment of raw dictionaries into requests.
- `PrivacyInfo.xcprivacy` declares required-reason APIs accurately.

---

## Prioritized Remediation

1. **(Medium) Demo credentials + prod identifiers** — remove the password from `README.md`; verify `jane@patel.co` is absent from prod/staging; never reuse seed accounts across environments.
2. **(Medium) Certificate pinning** — pin backend + Supabase SPKI hashes for an app carrying PHI and live A/V; ship backup pins.
3. **(Low) Universal Links** — move password-reset (and future auth callbacks) off the `nemara://` custom scheme; keep PKCE explicit.
4. **(Low) Encrypt analytics-at-rest** — add `.completeFileProtection` to the buffer write.
5. **(Low) Debug logging** — redact bodies even in DEBUG.
6. **(Info) Verify backend RLS / ownership** — the client's safety depends on it; confirm in `nemara-backend`.

*No secrets requiring rotation were identified (publishable keys are public by design). The single credential of concern is the committed demo password.*
