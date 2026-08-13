# Security Audit — Nemara Caregiver App (iOS)

**Date:** 2026-08-13
**Scope:** Static source audit of `nemara-caregiver-app` (native iOS / Swift 6, SwiftUI). No live services, secrets, or backend were accessed.
**Methodology:** `vibe-security` skill (Chris Raroque), prioritizing the mobile category — secret storage, backend-URL/API-key exposure, App Transport Security, token storage, certificate pinning, deep-link handling, client-side trust — plus committed-secret scanning, auth/authz, injection, dependencies, and AI/LLM usage.

---

## Executive Summary

The Nemara caregiver app is **well-architected from a security standpoint**. The common failure modes that this methodology targets in "vibe-coded" mobile apps are largely *absent* here:

- **No hardcoded secrets.** The only embedded keys are Supabase **publishable/anon** keys, which are designed to ship in clients. No service-role key, no third-party secret, no signing key, no connection string.
- **Correct token storage.** Auth sessions live in the iOS **Keychain** (Supabase SDK default), not `UserDefaults`. `UserDefaults` is used only for non-sensitive UI flags (camera IDs, tutorial/dismissal state).
- **No client-side AI keys.** Every LLM/VLM feature (detector inference, home briefing/report, door detection) is a thin proxy call to the backend over an authenticated endpoint. No provider key is in the bundle.
- **Server-side authorization.** All API calls carry a Supabase JWT (`Bearer`), Realtime is RLS-filtered per caregiver, and LiveKit tokens are minted and re-validated server-side.
- **ATS not weakened for production.** The only ATS relaxation is `NSAllowsLocalNetworking` (dev LAN stack); `NSAllowsArbitraryLoads` is **not** set, and production hosts are HTTPS/WSS.
- **Deep links are safe.** The single `nemara://reset-password?code=…` route only forwards an opaque Supabase recovery code to a server-side exchange; no destructive or trust-granting action is driven from link parameters.
- **Secrets kept out of git.** `.gitignore` covers `.env*` and `Local.xcconfig`; no tracked env/secret files contain live keys.

There are **no Critical or High findings.** The findings below are **Medium/Low hardening items** appropriate to the app's sensitivity — it streams live in-home video of cognitively-impaired elderly patients and carries protected health information (PHI). They are defense-in-depth improvements, not active exploits.

| # | Severity | Finding |
|---|----------|---------|
| 1 | Medium | No TLS certificate / public-key pinning on API, Realtime, or LiveKit traffic |
| 2 | Low | Verbose `#if DEBUG` logging prints full HTTP response bodies (signed URLs, LiveKit JWTs, PII) |
| 3 | Low | Analytics buffer persisted to disk without an explicit file-protection class |
| 4 | Low | No device-integrity (jailbreak) signal despite a long-lived refresh token + live PHI |
| 5 | Low/Info | `Package.resolved` not committed — dependency versions float to latest 2.x per build |

---

## Findings

### Medium

#### 1. No TLS certificate / public-key pinning
**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift:99-110` (`session: URLSession = .shared`, no `URLSessionDelegate`); `NemaraCaregiver/Services/LiveKitClient.swift:206-216` (`room.connect(url:token:)`); Supabase Realtime channels via the shared SDK client.

**What it is.** Every network path — the REST client (`URLSession.shared`, no `serverTrust` handling), Supabase Auth/Realtime, and the LiveKit media connection — relies solely on the system CA trust store. There is no certificate or public-key pinning anywhere in the codebase (`grep` for `serverTrust`/`SecTrust`/`evaluateServerTrust`/`URLSessionDelegate` returns nothing).

**Why it matters for *this* app.** The traffic includes a `Bearer` Supabase access token, signed URLs that grant access to archived patient video clips and avatars, LiveKit JWTs that grant access to a live in-bedroom camera room, and PHI (patient names, addresses, health-relevant event narratives). An attacker who can get a rogue root CA onto the device — a coerced or mis-trusted MDM/configuration profile, a malicious "install our Wi-Fi certificate" captive portal, or a compromised corporate proxy — can transparently MITM all of it: capture the bearer token, replay it, and watch live camera feeds of a vulnerable person. System CA trust alone does not defend against an attacker-controlled trust anchor.

**Exploitability.** Requires the attacker to plant a trusted CA on the victim device, so it is not remotely exploitable against a clean device; it is a realistic elevation for a targeted attacker (abusive family member, someone with brief physical access, hostile network). This is why it is Medium, not High.

**Fix.** Pin the leaf or intermediate public key for the API host (and, where the SDKs allow, Supabase/LiveKit) via a `URLSessionDelegate`:

```swift
// Give NemaraAPIClient a pinned session instead of URLSession.shared.
final class PinnedTrust: NSObject, URLSessionDelegate {
    // SPKI SHA-256 pins for nemara-backend-production.up.railway.app (+ a backup pin).
    private let pinnedSPKIHashes: Set<Data> = [ /* base64-decoded SHA-256 of the SPKI */ ]

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              SecTrustEvaluateWithError(trust, nil),
              let key = SecTrustCopyKey(trust),
              let spki = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              pinnedSPKIHashes.contains(sha256(spki))   // your SHA-256 helper
        else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
// Always ship at least one BACKUP pin and a rotation plan so a cert roll doesn't brick the app.
```

If full pinning is judged too operationally heavy, a lighter mitigation is to at least document the accepted residual risk and monitor for anomalous token use server-side.

---

### Low

#### 2. Verbose DEBUG logging of full HTTP response bodies
**File:** `NemaraCaregiver/Services/NemaraAPIClient.swift:1195-1200` (decode-failure path) and `:1233-1237` (non-2xx path).

```swift
#if DEBUG
if let body = String(data: data, encoding: .utf8) {
    print("[NemaraAPIClient] decode failure for \(Response.self): \(error)")
    print("[NemaraAPIClient] response body: \(body)")   // <- full body
}
#endif
```

**Why it matters.** Response bodies here include capability-bearing data: short-lived **signed clip/photo URLs**, **LiveKit JWTs** (`MintTokenResponse.token`), and caregiver/patient PII. The logging is correctly gated behind `#if DEBUG`, so it is **stripped from App Store / TestFlight release builds** and is not a production exposure. The residual risk is internal: any developer, QA, or pilot **debug** build writes this to the Xcode/device console, where it can be shoulder-surfed or captured in a screen recording / sysdiagnose during testing. `print` (used elsewhere too, e.g. `LiveKitClient.swift:219`) also isn't privacy-redacted the way `os.Logger` is.

**Fix.** Redact tokens/URLs before logging, or log only status + a body length/prefix. Prefer `Logger` with `privacy: .private` for anything that could carry a token:

```swift
#if DEBUG
Logger(subsystem: "co.sunny.nemara", category: "api")
    .debug("decode failure for \(String(describing: Response.self)); \(data.count) bytes")
#endif
```

#### 3. Analytics buffer persisted without an explicit file-protection class
**File:** `NemaraCaregiver/Services/Analytics.swift:204-211` (`persist()`, `data.write(to: url, options: .atomic)`) and `:267-274` (`fileURL` in Application Support).

**What it is.** The UI-analytics buffer is JSON-encoded and written to Application Support with only `.atomic` — no `NSFileProtection` option. The file contains `caregiver_id` (UUID), session/screen-flow, and device model. It holds **no PHI, no patient names, and no tokens**, so impact is low. It does inherit iOS's default container protection (`CompleteUntilFirstUserAuthentication`), so it is readable while the device is unlocked-after-first-unlock.

**Why note it.** For a health app it is cheap belt-and-suspenders to request stronger protection explicitly rather than relying on the default, and to keep the choice visible in code.

**Fix.**
```swift
try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
```
(Use `.completeFileProtection` if the buffer never needs to be written while backgrounded/locked.)

#### 4. No device-integrity (jailbreak) signal
**Scope:** whole app — no jailbreak/root check exists (`grep` for `jailbreak`/`cydia` returns nothing).

**What it is.** The app holds a **long-lived Supabase refresh token** in the Keychain and renders live PHI video. On a jailbroken device the Keychain and app sandbox are readable by other processes, and runtime hooking (Frida) can tamper with client logic. There is no detection, no degraded mode, and no server signal.

**Assessment.** Jailbreak detection is easily bypassed and is not a strong control on its own, so this is intentionally rated **Low/Informational** — it is a threat-model gap to acknowledge, not a must-fix. If pursued, treat any client "device is clean" claim as a soft signal only; never gate real authorization on it. (Note: the app has no biometric-auth path, so the `mobile.md` "boolean biometric bypass" concern does not apply here.)

#### 5. `Package.resolved` not committed
**File:** `.gitignore` (`Package.resolved` ignored); `project.yml:3-21` declares SwiftPM deps with open upper bounds (`Supabase from: 2.44.1`, `LiveKit from: 2.0.0`).

**What it is.** With `Package.resolved` gitignored and only lower bounds pinned, each fresh checkout / CI build resolves whatever the newest `2.x` is at build time. No known-vulnerable version is pinned today (the floors are recent), so this is a **reproducibility / supply-chain-hygiene** note, not an active vulnerability: a regressed or compromised upstream minor could enter a build unnoticed and unpinned.

**Fix.** Commit `Package.resolved` so builds are reproducible and dependency bumps are reviewable in diffs, and periodically audit the resolved versions.

---

## Areas Reviewed and Found Sound

These were checked specifically and are called out so the results aren't re-litigated:

- **Committed secrets:** none. Only Supabase publishable/anon keys (`AppConfig.swift:61,64`), which are safe to embed. No `sk_live`/`sk_test`/`AKIA`/private-key material anywhere.
- **Backend URL handling (`AppConfig.swift`):** plaintext `http://` URLs appear **only** in `#if DEBUG` branches (the local dev stack); Release always returns the production HTTPS/Railway/Supabase hosts and never consults `LocalAppConfig`/env. Correct separation.
- **Token storage:** Keychain via the Supabase SDK; `UserDefaults` holds only UI state.
- **AI/LLM:** all inference proxied through the authenticated backend; no client-side provider keys; user text is sent as request fields, not concatenated into client-side prompts.
- **Deep links (`NemaraCaregiverApp.swift:141-156`):** scheme-checked, single safe route, opaque code exchanged server-side, no destructive action.
- **ATS (`Info.plist:36-40`, `project.yml:90-91`):** only `NSAllowsLocalNetworking`; arbitrary loads not enabled.
- **Injection / mass-assignment:** requests use typed `Encodable` bodies; multipart boundaries are fresh UUIDs with fixed filenames; UUID path components are formatted, not concatenated user strings.
- **LiveKit auth:** room URL + token both come from the server-minted `MintTokenResponse`; client identity is informational and re-minted server-side.
- **Debug entitlements (`NemaraCaregiver-Debug.entitlements`):** a local-dev artifact (push/hotspot stripped "revert before PR"); the **Release** entitlements are correct (`aps-environment: production`). Not a release-build issue.

---

## Prioritized Remediation

1. **(Medium) Add certificate/public-key pinning** to the API client (and Supabase/LiveKit where supported), with a backup pin + rotation plan. Highest-leverage hardening given the PHI + live-video threat model.
2. **(Low) Redact secrets from DEBUG logging** — never print full response bodies, LiveKit tokens, or signed URLs; move to `Logger` with `.private`.
3. **(Low) Set an explicit file-protection class** on the analytics buffer write.
4. **(Low/Info) Commit `Package.resolved`**; periodically audit resolved dependency versions.
5. **(Low/Info) Decide and document** the device-integrity threat-model stance.

*This was a static review. It cannot verify server-side controls (RLS policies, LiveKit token validation, per-user AI rate limits, ownership checks on `/v1/...` endpoints). The client correctly defers authorization to the backend; a companion review of the backend's RLS and endpoint authorization is recommended to complete the picture.*
