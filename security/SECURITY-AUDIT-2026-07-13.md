# Security Audit — Nemara Caregiver App (iOS)

**Date:** 2026-07-13
**Scope:** Static source audit of `nemara-caregiver-app` (native iOS / Swift, SwiftUI, xcodegen).
**Methodology:** [vibe-security skill](https://github.com/raroque/vibe-security-skill) — mobile, secrets/env, authentication, data-access, and AI-integration reference checks.
**Constraints:** Static only. No access to the live backend, Supabase project, LiveKit, or any secret. Backend (`nemara-backend`, FastAPI) and DB Row-Level-Security policies are **out of scope** and could not be verified — several findings below depend on server-side controls that this audit *assumes* exist but did **not** inspect.

---

## Executive Summary

The caregiver app is a **thin, backend-proxy client** and is, overall, in good security shape. It follows the single most important mobile rule correctly: **no third-party secret keys, AI/LLM keys, or privileged credentials are embedded in the app.** Every sensitive operation (auth, AI door/detector inference, LiveKit token minting, CRUD) is delegated to the backend over HTTPS with a per-request Supabase JWT. Session tokens are held by the Supabase SDK in the iOS Keychain (no insecure `UserDefaults`/plaintext token storage was found). App Transport Security is left at its secure default for production hosts.

**No Critical or High severity issues were found.** The findings are defense-in-depth and hardening items appropriate to an app that handles sensitive data for a vulnerable population (live video of elderly patients, fall/medical events, home addresses).

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | Medium | No TLS certificate/public-key pinning on the API + Supabase clients | `NemaraAPIClient.swift`, `SupabaseAuthService.swift` |
| 2 | Low | UI-analytics buffer persisted unencrypted to disk | `Services/Analytics.swift:267` |
| 3 | Low | No jailbreak / client-integrity signal for a health-sensitive app | app-wide |
| 4 | Low | Recovery deep-link `code` accepted with no scheme-host hardening beyond `nemara://` | `NemaraCaregiverApp.swift:136` |
| 5 | Info | Debug builds fall back to cleartext HTTP to a hardcoded dev host | `Networking/AppConfig.swift:36,88` |
| 6 | Info | Production Supabase URL + publishable key committed in source (verified *safe*) | `Networking/AppConfig.swift:41,64` |

Items explicitly **verified as correctly implemented** are listed in the final section so future changes don't regress them.

---

## Findings

### Medium

#### 1. No TLS certificate / public-key pinning

**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift:102` (`session: URLSession = .shared`), `NemaraCaregiver/Services/SupabaseAuthService.swift:92` (`SupabaseClient(...)`)

The API client uses `URLSession.shared` and the Supabase client uses its default transport. Neither implements certificate or public-key pinning (no `URLSessionDelegate` performing `urlSession(_:didReceive:completionHandler:)` challenge validation exists anywhere in the codebase).

**Why it matters (concrete impact):** This app carries unusually sensitive data — live video/audio of elderly patients inside their homes, fall and medical-event narratives, patient home addresses (`Patient.homeAddress`), and caregiver auth JWTs. Transport is protected by ATS/TLS, so a passive network attacker sees nothing. However, an attacker who can present a certificate the device trusts — a fraudulently-issued/mis-issued CA cert, a compromised private CA, or a malicious root profile installed on the device (common in enterprise/MDM or social-engineering scenarios) — can transparently MITM every request: read the caregiver JWT (full account takeover for its lifetime), read/alter event data, and intercept the LiveKit join tokens minted at `/v1/livekit/token`, gaining access to the patient's live camera room. Pinning removes this entire class of "trusted-but-hostile CA" attacks.

This is rated **Medium** (not High) because it requires the attacker to already hold a device-trusted certificate and a network position — it is not remotely exploitable on its own.

**Fix (pin the two backend origins — backend API + Supabase):**

```swift
// A URLSessionDelegate that pins the leaf/intermediate SPKI hashes for
// nemara-backend + *.supabase.co, injected into NemaraAPIClient's session
// (replace `URLSession = .shared`) and into the SupabaseClient via a custom
// URLSessionConfiguration. Rotate hashes ahead of cert renewal; ship a
// backup pin so a renewal can't brick the fleet.
final class PinningDelegate: NSObject, URLSessionDelegate {
    private let pinnedSPKISHA256: Set<String>   // base64 SHA-256 of SubjectPublicKeyInfo
    func urlSession(_ s: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              isValid(trust, against: pinnedSPKISHA256) else {
            return completionHandler(.cancelAuthenticationChallenge, nil)
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
```

Alternatively, since deployment targets iOS 17+, declare pins declaratively via the ATS `NSPinnedDomains` key in `Info.plist`, which requires no custom delegate for the `URLSession.shared` path.

---

### Low

#### 2. UI-analytics buffer persisted unencrypted to disk

**File:** `NemaraCaregiver/Services/Analytics.swift:204-211, 267-274`

The analytics buffer is written as plaintext JSON to Application Support:

```swift
private static var fileURL: URL? {
    ...
    return dir.appendingPathComponent("ui_events_buffer.json")   // no protection class
}
private func persist() {
    guard let data = try? JSONEncoder().encode(buffer) else { return }
    Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
}
```

Each `Event` (lines 44-57) contains `caregiver_id` (the account UUID), `session_id`, per-screen navigation history, app build, OS version, and device model. It contains **no** auth tokens, passwords, or patient identifiers, which is why this is **Low**. But on a lost/stolen device that is jailbroken or backed up unencrypted, the file reveals the caregiver's account UUID and a behavioral trail. It is written with the default file-protection class rather than `.completeUntilFirstUserAuthentication` or better.

**Fix:** write with an explicit Data Protection class so the file is encrypted at rest and unreadable while the device is locked:

```swift
try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
```

(For a stricter posture, `.completeFileProtection`; balance against needing to flush while backgrounded.)

#### 3. No jailbreak / client-integrity signal

**Scope:** app-wide (no integrity check exists).

The app performs no jailbreak/root detection and no App Attest / DeviceCheck attestation. The mobile reference notes that on a jailbroken device, client-side checks and in-memory state can be hooked (e.g. Frida). This app is largely resilient to that because it trusts the server for all authorization — there is no client-side gate worth bypassing (no local "isPremium"/role flag drives access). Impact is therefore limited, hence **Low**. The residual risk is that a rooted device can read the Keychain session and the analytics file (see #2), and that the backend has no way to distinguish a genuine app instance from a scripted client replaying a stolen JWT.

**Fix (optional, defense-in-depth):** adopt **App Attest** (`DCAppAttestService`) so the backend can require a hardware-attested assertion from a genuine, unmodified app build on high-value endpoints (`/v1/livekit/token`, `/v1/me` delete). This raises the bar on stolen-token replay from a non-genuine client. Client-side jailbreak *detection* alone is easily defeated and is not recommended as a primary control.

#### 4. Recovery deep-link handling

**File:** `NemaraCaregiver/App/NemaraCaregiverApp.swift:136-151`

```swift
private func handleIncomingURL(_ url: URL) {
    guard url.scheme == "nemara" else { return }
    let host = url.host(percentEncoded: false)
    switch host {
    case "reset-password":
        ...
        if let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value {
            pendingResetCode = code
        }
```

The handler is well-behaved: it validates the scheme, switches on host, extracts only a `code`, and performs no destructive action — the `code` is exchanged with Supabase (`exchangeCodeForSession`) which is the actual trust boundary. Because `nemara://` is a **custom URL scheme**, any other app on the device can invoke it, so a malicious app could open `nemara://reset-password?code=<attacker-code>` to present the reset UI. The blast radius is limited (the user must then type a new password, and the code is bound to Supabase's recovery flow), so this is **Low/informational** rather than a real bypass.

**Fix / hardening:**
- Prefer **Universal Links** (`applinks:` associated domain) over a custom scheme for the recovery link — universal links are bound to a domain you control and can't be spoofed/claimed by another app.
- The `code` is a bearer secret in a URL; ensure it is never logged and that Supabase's recovery codes are single-use and short-lived (server-side — confirm in the Supabase project's Auth settings).

---

### Informational

#### 5. Debug builds use cleartext HTTP to a hardcoded dev host

**File:** `NemaraCaregiver/Networking/AppConfig.swift:36, 88`

`#if DEBUG` fallbacks point at `http://sunnys-macbook-air.local:54341` (Supabase) and `http://sunnys-macbook-air.local:8002` (backend) over plaintext. This is **compiled out of Release builds** — the `#else` branches hardcode the HTTPS production origins and explicitly refuse to consult `LocalAppConfig`/env in Release (`AppConfig.swift:37-42, 89-95`). ATS permits this only because `NSAllowsLocalNetworking` scopes the exception to local/private addresses. No action needed for production; noted only so the DEBUG cleartext path is never widened to routable hosts or leaked into a shipped build.

#### 6. Production Supabase URL + publishable key committed in source

**File:** `NemaraCaregiver/Networking/AppConfig.swift:41` (`https://zgifmvjnggmgzvtnosnu.supabase.co`), `:64` (`sb_publishable_OsfCMOdEIb5gvhRWDyNivg_7GriAmyP`)

These were checked against the "must never be client-side" list. Both are **designed to be public**: the Supabase **anon/publishable** key is meant to ship in clients and is safe *only when Row-Level-Security is enforced on every table*. The key is confirmed to be the publishable/anon variant (`sb_publishable_` prefix), **not** the `service_role` key. **No secret was leaked.** Two caveats:

- This safety is entirely contingent on **RLS being correctly configured server-side** — which this static, client-only audit could **not** verify. The app's own comments (`NemaraAPIClient.swift:1170`, `Analytics.swift:239`) assert that RLS filters every Realtime channel and analytics insert per-caregiver; that assertion must be validated against the actual Supabase policies. If any table lacks RLS, this publishable key grants an anonymous attacker direct read/write to that table. **Recommend a follow-up backend/RLS audit.**
- Treat the hardcoded local publishable key at `:61` the same way — it's the well-known deterministic local-CLI key, harmless.

---

## Verified Correct (do not regress)

These patterns were reviewed and found sound; call-outs so future refactors preserve them:

- **No secret keys in the bundle.** No Stripe secret, AWS, OpenAI/Anthropic, or `service_role` key anywhere in Swift, plist, or xcconfig. All AI (`/v1/detect-doors`, `/v1/detectors/infer`) and LiveKit token minting are **backend-proxied** — the correct pattern per the mobile & AI-integration references. (`NemaraAPIClient.swift:757,787,925`)
- **Session tokens live in the Keychain.** The Supabase SDK's default `KeychainLocalStorage` is used (no `SupabaseClientOptions`/`localStorage` override present), so JWTs are not in `UserDefaults` or plaintext. `UserDefaults` is used only for non-sensitive UI flags (camera "ever online" set, tutorial completion). (`SupabaseAuthService.swift:92`, `NemaraAPIClient.swift:208`)
- **ATS is at its secure default for production.** Only `NSAllowsLocalNetworking` is set; there is **no** `NSAllowsArbitraryLoads`. Routable production hosts are forced through TLS. (`Info.plist:36-40`, `project.yml`)
- **Authorization is server-side.** The client holds no role/entitlement gate; every request carries `Authorization: Bearer <jwt>` and the backend + RLS decide access. Foreign/stale resource IDs return 404 (e.g. `fetchEvent`, `NemaraAPIClient.swift:875`). This honors "never trust the client."
- **LiveKit identity is server-validated.** The client sends a cosmetic `identity`, and the code comments confirm the server re-mints/validates it (`NemaraAPIClient.swift:929-945`) — no client-controlled room authorization.
- **No injection surface on the client.** Path parameters are typed `UUID.uuidString` (not free-text), query values go through `URLQueryItem` (percent-encoded), and multipart boundaries are freshly generated per call. There is no local SQL and no string-built queries. (`NemaraAPIClient.swift:1011-1073`)
- **`.gitignore` covers local secrets.** `Local.xcconfig` (per-dev signing overrides) is ignored; the committed `LocalAppConfig.swift` ships nil defaults and is meant to be `skip-worktree`. No `.env` files are tracked.
- **Hardcoded password `"Mar9aret!"`** at `DesignSystem/Components/NemaraField.swift:149` is inside a `#if DEBUG` SwiftUI `#Preview` and is stripped from release builds — **not** a credential leak.

---

## Prioritized Recommendations

1. **(Medium) Add TLS pinning** for the backend API and Supabase origins via ATS `NSPinnedDomains` or a `URLSessionDelegate`, with a backup pin and a rotation plan. Highest-value hardening given the sensitivity of the data in transit.
2. **(Follow-up, out of this scope) Audit the Supabase RLS policies.** The safety of the shipped anon key and every Realtime channel depends entirely on server-side RLS this client-only audit could not see. Confirm every table (`patients`, `cameras`, `detectors`, `events`, `ui_events`, `caregivers`, device tokens, storage buckets) enforces per-caregiver RLS.
3. **(Low) Set an explicit Data Protection class** on the analytics buffer file.
4. **(Low) Move the password-recovery link to a Universal Link** and confirm recovery codes are single-use/short-lived server-side.
5. **(Low, optional) Adopt App Attest** on high-value endpoints to resist stolen-token replay from non-genuine clients.
