# Security Audit — NemaraCaregiver (iOS)

**Date:** 2026-07-07
**Scope:** Static source audit of the `nemara-caregiver-app` repository (native iOS / Swift, SwiftUI, SwiftPM). No live services, secrets, or backend code were accessed. Methodology follows the `vibe-security` skill, prioritized for mobile.
**Commit basis:** `main` @ `0aca8e2` (v1.2.7, build 32).

---

## Executive summary

The app is generally well-architected from a security standpoint. It stores auth sessions in the iOS **Keychain** (via the Supabase SDK, not `UserDefaults`), keeps all verbose request/response logging behind `#if DEBUG`, ships only **publishable/anon** Supabase keys (which are designed to be client-embedded), enforces ATS/TLS for production hosts, and routes every third-party call through the caregiver's own backend rather than embedding third-party secret keys in the bundle. **No Critical issues were found** — there is no exposed `service_role`/secret key, no client-side auth bypass, and no plaintext token storage.

The findings below are **Medium and lower**, and cluster around three themes: (1) an OAuth-style password‑recovery `code` delivered over a hijackable **custom URL scheme**, (2) **committed demo credentials** whose blast radius depends on whether the seed reaches production, and (3) **client-supplied identifiers** (patient/room ids) in privileged requests that must be authorized server-side — the classic "never trust the client" boundary. Because the app's security model leans heavily on **Supabase RLS** and **backend authorization** (both out of scope for this static iOS audit), the single most valuable follow-up is to confirm those server-side controls are actually enforced.

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | Medium | Password-recovery `code` delivered via hijackable custom URL scheme (`nemara://`) | `App/NemaraCaregiverApp.swift:136`, `Resources/Info.plist:21` |
| 2 | Medium | Real demo/caregiver credentials committed to the repo | `README.md:62`, `DesignSystem/Components/NemaraField.swift:149` |
| 3 | Medium | Privileged requests key off client-supplied patient/room ids — authorization must be server-enforced | `Services/NemaraAPIClient.swift:888`, `:938` |
| 4 | Medium | No TLS certificate pinning for health/video traffic (defense-in-depth) | `Services/NemaraAPIClient.swift:102`, `Services/LiveKitClient.swift:216` |
| 5 | Low | No device-integrity / jailbreak awareness around a Keychain-backed session | `Services/SupabaseAuthService.swift:266` |
| 6 | Low | Production Supabase URL + anon key hardcoded — safe only if RLS is enforced | `Networking/AppConfig.swift:41`, `:64` |
| 7 | Info | Debug entitlements committed with a "revert before PR" TODO | `Resources/NemaraCaregiver-Debug.entitlements:5` |

---

## Medium

### 1. Password-recovery `code` is delivered over a hijackable custom URL scheme

**`NemaraCaregiver/App/NemaraCaregiverApp.swift:136–151`, `NemaraCaregiver/Resources/Info.plist:21–31`**

The forgot-password flow emails the user a link of the form `nemara://reset-password?code=…`. `handleIncomingURL` extracts the `code` query item and hands it to `SupabaseAuthService.exchangeRecoveryCode(_:)` → `exchangeCodeForSession`, which trades it for a **recovery session** that authorizes a password change.

```swift
// NemaraCaregiverApp.swift:145
if let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value {
    pendingResetCode = code            // → exchangeCodeForSession(code)
}
```

The transport is a **custom URL scheme** (`nemara`), registered in `Info.plist` under `CFBundleURLSchemes`. On iOS, custom schemes are not exclusive: any other app on the device may also register `nemara://`, and the OS resolution is not deterministic. A malicious app that claims the scheme can intercept the recovery `code`, exchange it itself, and take over the account (the code grants a recovery session that can set a new password). This is why Apple recommends **Universal Links** (verified via `apple-app-site-association`) for anything security-sensitive — they cannot be claimed by another app.

Impact: account takeover of a caregiver, which exposes patient PII, home address, health events, and live camera/audio feeds.

Fix: migrate the auth callback / recovery link from the custom scheme to a **Universal Link** (an `applinks:` Associated Domain plus a hosted AASA file), and treat any inbound `code` on the raw custom scheme as untrusted. Keep the current single-use / short-expiry behavior of the Supabase recovery code (that limits the window but does not close the interception vector on its own).

```swift
// Before — custom scheme, any app can register nemara://
CFBundleURLSchemes = ["nemara"]           // Info.plist
.onOpenURL { url in handleIncomingURL(url) }

// After — Universal Link, ownership of the domain is verified by iOS
// Entitlements: com.apple.developer.associated-domains = ["applinks:auth.nemara.co"]
.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
    guard let url = activity.webpageURL, url.host == "auth.nemara.co" else { return }
    handleIncomingURL(url)
}
```

---

### 2. Real demo/caregiver credentials are committed to the repository

**`README.md:62–63`, `NemaraCaregiver/DesignSystem/Components/NemaraField.swift:149`**

`README.md` publishes a working login:

```
- Email: `jane@patel.co`
- Password: `Mar9aret!2024`
```

and the same password stem is hardcoded as a SwiftUI preview default:

```swift
// NemaraField.swift:149  (inside #if DEBUG #Preview)
@State private var password = "Mar9aret!"
```

Committed credentials are a standing liability: they live in git history forever (rotation, not deletion, is the only remedy), and if this repository is ever made public or shared, anyone can attempt the login. `AppConfig.swift:41` points **release** builds at a **production** Supabase project (`https://zgifmvjnggmgzvtnosnu.supabase.co`).

- If the `jane@patel.co` seed account exists **only** in a local `make fresh-seed` database (as the README implies), the practical impact is Low.
- If that seed — or that password — has ever been applied to the **production** project, this is effectively **Critical**: anyone with the repo can sign in as a real caregiver and read a patient's health events, home address, and live feeds.

Fix: remove the credentials from `README.md` (describe the seed flow without a real password), rotate the `jane@patel.co` password, and confirm the demo account does not exist in production. Move the preview default to an obviously-fake, non-reused value (e.g. `"Preview1!"`). Consider `gitleaks` in CI to catch future credential commits.

---

### 3. Privileged requests key off client-supplied patient/room ids — authorization must be enforced server-side

**`NemaraCaregiver/Services/NemaraAPIClient.swift:888–908` (LiveKit token), `:938–953` (Talk), and every `/v1/patients/{id}/…` call**

The LiveKit token endpoint is called with a room name derived directly from a client-provided patient id, and the caregiver identity is likewise client-supplied:

```swift
// NemaraAPIClient.swift:895
let body = MintTokenRequest(
    room: "patient_\(pid.uuidString.lowercased())",     // client picks the room
    identity: "caregiver_\(caregiverID.uuidString.lowercased())_ios",
    role: role,                                          // "viewer" | "broadcaster"
)
return try await sendJSON(method: "POST", path: "/v1/livekit/token", body: body)
```

The code comment notes "server validates the prefix and re-mints," which is the right instinct — but the audit cannot see the backend, so this is a boundary to **verify, not assume**. If `/v1/livekit/token` does not check that the authenticated caregiver actually owns `pid`, any authenticated caregiver could mint a viewer (or broadcaster) token for **any** patient's room and watch/speak into a stranger's home. The same applies to `startTalk`, `endTalk`, `clipURL`, `patientPhotoURL`, and the whole `/v1/patients/{id}/…` surface: the client sends an id, and only server-side ownership checks (and RLS on the Realtime channels — see `NemaraAPIClient.swift:1134`) prevent horizontal access.

This is the core "never trust the client" principle from the audit methodology. The iOS code is not itself vulnerable, but it is the reason the server-side check is load-bearing.

Fix (server-side, tracked here for completeness): on every `/v1/livekit/token`, `/v1/patients/{id}/*`, and `/v1/events/{id}/*` handler, resolve the caregiver from the JWT and assert ownership of the referenced patient/room/event before acting; ignore the client-supplied `identity` beyond logging. Confirm RLS policies on `patients`, `cameras`, `detectors`, and `events` gate on `auth.uid()`.

---

### 4. No TLS certificate pinning for health / live-video traffic

**`NemaraCaregiver/Services/NemaraAPIClient.swift:102` (`session: URLSession = .shared`), `Services/LiveKitClient.swift:216` (`room.connect`)**

All backend HTTP goes through `URLSession.shared` with no `URLSessionDelegate` performing certificate/public-key pinning, and the LiveKit/Supabase SDKs use default trust evaluation. TLS is enforced (good — ATS is intact for routable hosts), but default trust accepts any certificate chaining to a system-trusted or user/MDM-installed root. On a device with a rogue configuration profile or a corporate MITM proxy, an attacker can intercept caregiver ↔ backend traffic, including bearer JWTs, patient PII, and clip/photo signed URLs.

For an app streaming live audio/video of vulnerable patients and carrying health events, certificate pinning is worthwhile defense-in-depth (OWASP MASVS-NETWORK). This is Medium rather than higher because it requires the attacker to already control a trusted anchor on the device.

Fix: pin the backend (and, where the SDK allows, Supabase) leaf or intermediate public key via a `URLSession` delegate implementing `urlSession(_:didReceive:completionHandler:)`, with a documented key-rotation/backup-pin plan so a cert rollover doesn't brick the app.

```swift
final class PinningDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // evaluate challenge.protectionSpace.serverTrust against pinned SPKI hash(es)
    }
}
```

---

## Low

### 5. No device-integrity awareness around the Keychain-backed session

**`NemaraCaregiver/Services/SupabaseAuthService.swift:266–273`**

Session restoration relies on the Supabase SDK's Keychain-cached session (`client.auth.session`). Keychain is the correct choice and protects the token at rest on a healthy device. However, on a jailbroken device the Keychain can be dumped and the app offers no tamper/jailbreak awareness and no re-authentication step for sensitive actions (e.g. account deletion, adding an email-alert recipient). The `PrivacyPolicyView.swift:221` copy advertises "Secure authentication token storage in iOS Keychain," so users are being told this is a protected boundary.

Fix (defense-in-depth): add a lightweight jailbreak/tamper heuristic and gate destructive/account actions behind a fresh biometric (`LAContext`) check. Keep expectations realistic — client-side integrity checks are bypassable and must not become the only control.

---

### 6. Production Supabase URL + anon key hardcoded — safe only if RLS is enforced

**`NemaraCaregiver/Networking/AppConfig.swift:41`, `:64`**

```swift
return URL(string: "https://zgifmvjnggmgzvtnosnu.supabase.co")          // :41
return "sb_publishable_OsfCMOdEIb5gvhRWDyNivg_7GriAmyP"                  // :64
```

This is **not** a vulnerability on its own — `sb_publishable_…` is the anon/publishable key, which the audit methodology explicitly lists as safe to ship in a client, and the project URL is public. It is flagged only to make the dependency explicit: because the app opens Supabase Realtime channels directly (`NemaraAPIClient.swift:1134`) using this key, **all** row-level protection comes from server-side RLS. If any RLS policy is missing or misconfigured, this key lets anyone read/subscribe to that table. No client change is needed; verify RLS server-side and confirm no `service_role` key is ever shipped to the client (none was found).

---

## Informational

### 7. Debug entitlements committed with a "revert before PR" TODO

**`NemaraCaregiver/Resources/NemaraCaregiver-Debug.entitlements:5`**

```xml
<!-- TEMP (local fallback — revert before PR): Push (aps-environment) and
     Hotspot stripped so the app provisions on a personal team … -->
```

The **Debug** entitlements file has been emptied for a local provisioning workaround and left committed. This is a hygiene issue, not a security flaw: it only affects local Debug builds, and the **Release** entitlements (`NemaraCaregiver-Release.entitlements`) correctly declare `aps-environment = production`. Restore the intended Debug entitlements so the committed state matches the documented build, and consider keeping such local overrides in the already-gitignored `Local.xcconfig` pattern the project uses elsewhere.

### Notes on things checked and found acceptable

- **Token storage:** Keychain via the Supabase SDK; no `UserDefaults`/plaintext token storage. The only `UserDefaults` usage stores non-sensitive UI state (camera "ever online" set, tutorial flags).
- **ATS:** `NSAppTransportSecurity` only sets `NSAllowsLocalNetworking` (for the dev LAN/Bonjour stack); it does **not** disable ATS globally. Routable production hosts still require TLS. Debug HTTP fallbacks (`http://sunnys-macbook-air.local`) are `#if DEBUG`-compiled out of release builds.
- **Logging:** All request/response-body and token-adjacent `print()`s are behind `#if DEBUG`; release builds do not log bodies or tokens.
- **Secrets scan:** No `sk_live`/`sk_test`/`service_role`/AWS/private-key material in Swift, plists, xcconfig, or entitlements. No third-party AI/LLM API keys in the bundle — detector inference is proxied through the backend (`/v1/detectors/infer`).
- **Injection:** No SQL/string-built queries on the client; all data access is typed REST + PostgREST via the SDK.
- **Deep-link payloads:** APNs tap handling parses only `event_id`/`patient_id` as `UUID` (`AppDelegate.swift:96`) and performs no destructive action from the payload — targets are re-fetched caregiver-scoped from the backend.

---

## Prioritized remediation

1. **Verify server-side authorization + RLS (Finding 3, 6)** — the app's entire access-control model depends on it; confirm `/v1/livekit/token` and `/v1/patients/{id}/*` enforce ownership and that RLS gates every replicated table.
2. **Rotate and remove committed credentials (Finding 2)** — confirm `jane@patel.co` is not a production account; scrub the README and preview default; add `gitleaks` to CI.
3. **Move the recovery callback to a Universal Link (Finding 1)** — closes the custom-scheme interception path to account takeover.
4. **Add certificate pinning (Finding 4)** — defense-in-depth for health/video traffic.
5. **Device-integrity + re-auth on sensitive actions, restore Debug entitlements (Findings 5, 7)** — hardening and hygiene.

*This was a static, source-only review; it cannot observe backend authorization, RLS policies, or runtime behavior. Findings that depend on server-side controls are flagged as such and should be confirmed against the backend.*
