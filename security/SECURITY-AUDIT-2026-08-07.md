# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-08-07
**Scope:** Static source audit of `nemara-caregiver-app` (native iOS / SwiftUI, Swift 6).
**Methodology:** [`vibe-security`](https://github.com/raroque/vibe-security-skill) skill, prioritizing the Mobile Security, Secrets & Environment, Authentication, Data Access, and AI-Integration reference checks.
**Constraints:** Static analysis only. No live services, secrets, or backend (`nemara-backend`) were accessed. Server-side controls (Supabase RLS policies, endpoint authorization, rate limiting) could not be verified from this repository and are explicitly out of scope.

---

## Executive Summary

**No Critical or High severity issues were found.** The app is well-architected from a client-security standpoint and avoids the failure modes that most commonly appear in rapidly-built mobile apps:

- **No exploitable secrets are embedded.** The only hardcoded keys are Supabase **publishable/anon** keys (`sb_publishable_…`), which are explicitly designed to ship in client apps. No `service_role` key, no third-party API secret, no AI-provider key, and no signing secret appears anywhere in the source or config.
- **All privileged and AI work is proxied through the backend.** Every LLM feature (door detection, detector inference, home briefing/report) and every third-party call goes to `nemara-backend` carrying the user's Supabase JWT — there is no client-side AI key to drain.
- **Auth tokens live in the Keychain**, via the Supabase SDK's default secure storage. `UserDefaults` holds only non-sensitive UI state (dismissal flags, camera-online tracking). No tokens or credentials are written to plaintext storage.
- **App Transport Security is correctly configured.** Only `NSAllowsLocalNetworking` is enabled (cleartext to LAN/dev hosts); there is **no** `NSAllowsArbitraryLoads`. Production hosts are reached over HTTPS with ATS enforced.
- **Secrets are excluded from git** (`.env`, `.env.*` ignored) and none were found committed.
- **The client does not trust itself for authorization.** All patient/camera/detector/event mutations are ID-scoped requests to the backend under the JWT; the client updates optimistically but defers ownership enforcement server-side (code comments consistently note caregiver-scoped 404s and per-caregiver RLS).

The findings below are **defense-in-depth hardening** items, all Low severity. The most impactful is the absence of TLS certificate pinning for an app that streams live audio/video of vulnerable adults.

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | Low | No TLS certificate / public-key pinning | `NemaraAPIClient.swift:102`, `SupabaseAuthService.swift:92` |
| 2 | Low | Password-reset deep link uses a hijackable custom URL scheme instead of Universal Links | `NemaraCaregiverApp.swift:120–156`, `AppConfig.swift:71` |
| 3 | Low | UI-analytics buffer persisted unencrypted and backed up | `Analytics.swift:204–211, 267–274` |

An **Informational / verified-safe** section follows the findings.

---

## Findings

### Low

#### 1. No TLS certificate or public-key pinning

**Location:** `NemaraCaregiver/Services/NemaraAPIClient.swift:102` (`session: URLSession = .shared`); `NemaraCaregiver/Services/SupabaseAuthService.swift:92` (`SupabaseClient(...)` with default transport). LiveKit signaling (`LiveKitClient.swift`) likewise relies on system trust.

**What it is:** All HTTPS traffic — REST API to Railway, Supabase Auth/Realtime, and LiveKit — is validated only against the system's default certificate-authority trust store. There is no `URLSessionDelegate` performing `SecTrust` evaluation against a pinned certificate or public key.

**Why it matters:** This is a caregiver app that carries auth JWTs and brokers **live audio/video of vulnerable adults** plus health-adjacent detection events. Without pinning, an adversary who can get a rogue-but-CA-valid certificate trusted on the device — a malicious/compromised MDM profile, a user socially engineered into installing a root CA, or a corporate TLS-intercepting proxy — can transparently man-in-the-middle every request, reading tokens and stream-access material. Pinning collapses that attack surface to the specific server keys you control.

**Concrete fix:** Add a `URLSessionDelegate` that pins the leaf or intermediate public key (SPKI hash) for the production API and Supabase hosts, and inject that session into `NemaraAPIClient`. Pin at least two keys (current + backup) to survive rotation.

```swift
// After — pin the server public key
final class PinningDelegate: NSObject, URLSessionDelegate {
    // SHA-256 of the server certificate's SubjectPublicKeyInfo (base64).
    private let pinnedSPKIHashes: Set<String>

    init(pins: Set<String>) { self.pinnedSPKIHashes = pins }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let key = SecTrustCopyKey(trust),
              let spki = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              pinnedSPKIHashes.contains(Data(SHA256.hash(data: spki)).base64EncodedString())
        else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
// let session = URLSession(configuration: .default, delegate: PinningDelegate(pins: [...]), delegateQueue: nil)
```

Note: this is a client-hardening measure. It does not replace server-side authorization, and it must be paired with a key-rotation plan so an expired pin can't brick the app.

---

#### 2. Password-reset deep link uses a hijackable custom URL scheme instead of Universal Links

**Location:** `NemaraCaregiver/App/NemaraCaregiverApp.swift:120–156` (`handleIncomingURL`, parsing `nemara://reset-password?code=…`); `NemaraCaregiver/Networking/AppConfig.swift:71` (`supabasePasswordResetRedirect = nemara://reset-password`); scheme registered in `Info.plist:21–31`.

**What it is:** The account-recovery flow delivers the Supabase recovery `code` to the app via the custom URL scheme `nemara://`. Any app installed on the device can also register the `nemara` scheme; when two apps claim the same scheme, iOS resolves the open non-deterministically, so a malicious app can register `nemara://` and receive the recovery `code` intended for this app.

**Why it matters:** A recovery `code` is a step toward setting a new password. If it could be redeemed on its own, interception would mean account takeover of a caregiver account — which grants access to patient video, events, and PII.

**Mitigating factor (why this is Low, not Medium):** The Supabase Swift SDK defaults to the **PKCE** flow. `exchangeCodeForSession(authCode:)` (`SupabaseAuthService.swift:182`) requires the `code_verifier` that this app generated and stored in **its own** Keychain. An app that only intercepts the `code` cannot complete the exchange without that verifier, so interception does not by itself yield a session. The residual risk is the weaker binding of custom schemes generally (no cryptographic association with a domain, phishing-friendly), not a direct takeover.

**Concrete fix:** Migrate the recovery redirect to a **Universal Link** (HTTPS URL backed by an `apple-app-site-association` file and an `associated-domains` entitlement). Universal Links are cryptographically bound to the domain and cannot be claimed by another app.

```
// Before — custom scheme, claimable by any app
static let supabasePasswordResetRedirect = URL(string: "nemara://reset-password")!

// After — Universal Link bound to your verified domain
static let supabasePasswordResetRedirect = URL(string: "https://links.nemara.co/reset-password")!
// + add `applinks:links.nemara.co` to associated-domains entitlement
// + host /.well-known/apple-app-site-association listing this app's appID
// + add the HTTPS redirect to Supabase Auth → URL Configuration allow-list
```

Keep PKCE enabled regardless.

---

#### 3. UI-analytics buffer persisted unencrypted and included in backups

**Location:** `NemaraCaregiver/Services/Analytics.swift:204–211` (`persist()` → `data.write(to:)`), `:267–274` (`fileURL` → Application Support / `ui_events_buffer.json`).

**What it is:** Buffered analytics events are written as plaintext JSON to Application Support. Each record contains `caregiver_id` (UUID), a session id, screen names, event names, device model, OS version, and app build. The file is not tagged with an explicit file-protection class and is not excluded from iCloud/iTunes device backups.

**Why it matters:** Sensitivity is low — the file holds **no credentials and no patient names/health content** — so the real-world impact is limited. However, on a jailbroken or backup-extracted device it exposes a caregiver's usage/behavior trail and their `caregiver_id`. For a health-adjacent app, minimizing incidental data at rest is worthwhile.

**Concrete fix:** Write with an explicit data-protection class and exclude the buffer from backup.

```swift
// After — encrypt at rest until first unlock, and keep it out of backups
try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
var res = URLResourceValues(); res.isExcludedFromBackup = true
var mutableURL = url; try? mutableURL.setResourceValues(res)
```

---

## Informational / Verified-Safe

These were checked and found **not** to be vulnerabilities. Documented so future contributors don't mistake them for regressions.

- **Hardcoded Supabase keys are publishable/anon keys, not secrets.** `AppConfig.swift:61,64` embed `sb_publishable_…` values for local and production. Anon/publishable keys are designed to ship in clients; security rests on server-side RLS, not on key secrecy. No `service_role` key is present. ✅
- **No AI-provider or third-party secret keys in the client.** All LLM features route through the backend: `detectDoors` (`NemaraAPIClient.swift:841`), `inferDetector` (`:784`), `homeBriefing` (`:1074`), `homeReport` (`:1095`). The client sends user/image input under the JWT; the server holds the model keys. This matches the skill's required "backend proxy" pattern. ✅
- **Auth tokens are stored in the Keychain**, via the Supabase SDK's default secure local storage. Grep confirms no token/credential is written to `UserDefaults`; `UserDefaults` usage is limited to UI state (`PeopleBlurStore`, tutorial flags, `camerasEverOnline`, sensitive-room acks). ✅
- **App Transport Security is correctly scoped.** `Info.plist:36–40` / `project.yml:90–91` enable only `NSAllowsLocalNetworking` (cleartext to `.local`/RFC1918 dev hosts). There is no `NSAllowsArbitraryLoads` and no `NSExceptionDomains` weakening production. DEBUG dev traffic uses `http://…local`; release traffic is HTTPS only (`AppConfig.swift:41,94`). ✅
- **Secrets are gitignored and none are committed.** `.gitignore:19–23` ignores `.env`/`.env.*`; a full-repo scan for `sk_live`, `service_role`, JWT (`eyJ…`), AWS/GitHub/Slack token patterns, and private-key headers returned nothing (the one `eyJhbG…` hit is a truncated placeholder in `ClipURLCodableTests.swift`, not a live token). ✅
- **The `"Mar9aret!"` string is not a real credential.** `NemaraField.swift:149` is inside a `#if DEBUG` `#Preview` block (SwiftUI canvas placeholder), compiled out of release. ✅
- **Client does not trust client-side authorization.** All resource operations are ID-scoped calls to the backend under the JWT; the client updates local state optimistically but relies on server enforcement (e.g. caregiver-scoped 404 on foreign event ids, `NemaraAPIClient.swift:929`). Actual IDOR resistance depends on backend RLS, which is out of scope here. ⚠️ (Verify server-side.)
- **Dev-only clip-capture feature is hard-compiled off in release.** `AppConfig.swift:112–132` forces `enableClipCapture = false` under `#if !DEBUG`, so the data-collection recording path cannot be enabled in a distribution build. ✅
- **Deep-link handler performs no destructive action without user interaction.** The reset flow requires the user to enter and confirm a new password (`ResetPasswordView.swift`); notification taps only navigate. ✅
- **Debug-only response logging** (`NemaraAPIClient.swift:1195–1200, 1233–1237`) can print response bodies but is wrapped in `#if DEBUG` and stripped from release builds. Low concern; left as-is.

---

## Recommendations (prioritized)

1. **Add TLS public-key pinning** (Finding 1) for the API, Supabase, and LiveKit hosts — the highest-value client hardening for an app streaming live A/V of vulnerable adults.
2. **Move the password-reset redirect to a Universal Link** (Finding 2) and keep PKCE enabled, removing reliance on the claimable `nemara://` scheme.
3. **Encrypt and exclude-from-backup the analytics buffer** (Finding 3) as low-cost data-minimization.
4. **Out of band (backend repo):** confirm Supabase **RLS policies** enforce per-caregiver ownership on every table, and that AI/expensive endpoints have server-side rate limits and spend caps — the client correctly defers authorization to the server, so those controls are load-bearing and must be verified where they live.

---

*Generated by an automated security-audit routine using the vibe-security methodology. Static analysis only; no secrets or live systems were accessed.*
