# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-06-04
**Scope:** Static source review of `nemara-caregiver-app` (native iOS / SwiftUI, Swift 6).
**Method:** `vibe-security` skill methodology, prioritizing mobile checks (hardcoded secrets, ATS, token storage, certificate pinning, deep-link / client-side trust), plus authn/authz, injection, dependencies, and AI/LLM usage.
**Constraint:** Static analysis only. No live services, no secrets, no network access. Server-side controls (Supabase RLS, FastAPI authorization, LiveKit token minting) could not be verified and are called out where the client's safety depends on them.

---

## Executive Summary

The app is, by the standard of "vibe-coded" mobile apps, **soundly architected from a security standpoint**. The audit found **no Critical or High severity issues**. Specifically, the things that most often go wrong were done right:

- **No exploitable secrets in the client.** The only embedded keys are Supabase **publishable/anon** keys, which are designed to be shipped in clients. No service-role key, no third-party secret API keys, no AI/LLM API keys.
- **Authorization is server-side.** Every data operation goes through the FastAPI backend with a Supabase JWT `Authorization: Bearer` header; Realtime relies on RLS; the LiveKit token `identity` is treated as informational and re-validated server-side (`NemaraAPIClient.swift:826-846`). The code consistently follows "never trust the client."
- **Tokens are stored in the Keychain**, not `UserDefaults`. Session persistence is delegated to the Supabase Swift SDK, whose default storage is the iOS Keychain (`SupabaseAuthService.swift:251-262`). `UserDefaults` is used only for non-sensitive UI flags.
- **ATS is intact.** The only exception is `NSAllowsLocalNetworking` (for dev against a LAN backend); TLS is still enforced for all routable/production hosts (`project.yml:82-83`, `Info.plist:36-40`).
- **No injection surface in the client.** Path segments are UUIDs (`.uuidString.lowercased()`), query strings use `URLQueryItem`, and there are no web views, no `evaluateJavaScript`, no string-built SQL.
- **AI is server-side.** Detector inference calls `POST /v1/detectors/infer` (`NemaraAPIClient.swift:718`); no LLM keys or prompts live in the app.

The findings below are **defense-in-depth** improvements, ranked Medium → Low. The single most valuable hardening step is adding **certificate pinning** (M1), given the app handles live audio/video and health-event data about vulnerable patients.

| # | Severity | Title |
|---|----------|-------|
| M1 | Medium | No TLS certificate / public-key pinning on backend, Supabase, or LiveKit connections |
| L1 | Low | Password-reset relies on a hijackable custom URL scheme rather than Universal Links |
| L2 | Low | No jailbreak / runtime-tamper detection |
| L3 | Low (informational) | Publishable keys hardcoded in source & a legacy anon JWT in git history — security rests entirely on server-side RLS |

---

## Medium

### M1 — No TLS certificate / public-key pinning

**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift:97` (`session: URLSession = .shared`), `NemaraCaregiver/Networking/AppConfig.swift:72-88` (backend URL), `NemaraCaregiver/Services/LiveKitClient.swift:185-207` (LiveKit connect).

**What it is.** All HTTPS traffic — REST calls to the Railway backend, Supabase Auth/Realtime, and the LiveKit media connection — uses the default `URLSession.shared` / SDK transport with no `URLSessionDelegate` performing certificate or public-key pinning. The app trusts any certificate that chains to a system-trusted root.

**Why it matters here.** Standard ATS/TLS already defeats *passive* eavesdropping. The residual risk is an *active* man-in-the-middle who can present a certificate from a CA the device trusts — e.g., a malicious or coerced MDM/configuration profile, a corporate TLS-intercepting proxy, or a user tricked into installing a root CA. In that scenario an attacker on-path can read and modify the caregiver's **Supabase JWT** (full account access), **live patient audio/video**, and **health-event data**. For an app whose subjects are vulnerable patients, this is sensitive enough to warrant pinning as defense-in-depth.

**Fix.** Pin the leaf or intermediate public keys for the production hosts (`*.up.railway.app` backend, the Supabase project host, and the LiveKit Cloud host) using a `URLSessionDelegate` that validates `SecTrust` against a bundled key set, and configure the LiveKit SDK's transport similarly. Pin to the SPKI (public key), not the full cert, so rotation doesn't brick clients; ship at least one backup pin.

```swift
// Sketch — reject any server whose SPKI isn't in the pinned set.
final class PinningDelegate: NSObject, URLSessionDelegate {
    let pinnedSPKIHashes: Set<Data>   // sha256 of DER SubjectPublicKeyInfo
    func urlSession(_ s: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let trust = challenge.protectionSpace.serverTrust,
              SecTrustEvaluateWithError(trust, nil),
              let key = pinnedKey(from: trust), pinnedSPKIHashes.contains(sha256(spki(of: key))) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
// Inject instead of .shared:
let session = URLSession(configuration: .default, delegate: PinningDelegate(...), delegateQueue: nil)
```

---

## Low

### L1 — Password-reset deep link uses a hijackable custom URL scheme

**Files:** `NemaraCaregiver/Resources/Info.plist:21-31` & `project.yml:93-96` (registers `nemara://`), `NemaraCaregiver/App/NemaraCaregiverApp.swift:99-117` (`handleIncomingURL`), `NemaraCaregiver/Services/SupabaseAuthService.swift:156-183` (`requestPasswordReset` / `exchangeRecoveryCode`).

**What it is.** Account recovery flows through `nemara://reset-password?code=…`. Custom URL schemes are first-come/ambiguous on iOS: any other installed app may also register `nemara://`, and the OS does not guarantee which app receives the link. A malicious app could attempt to intercept the recovery `code`.

**Why the impact is limited (Low, not High).** The Supabase Swift SDK defaults to the **PKCE** flow: `resetPasswordForEmail` stores a `code_verifier` in this app's Keychain, and `exchangeCodeForSession(authCode:)` requires both the `code` *and* that locally-held verifier. An app that intercepts only the `code` cannot complete the exchange or take over the account; the worst outcome is consuming (denial-of) a single-use, short-lived code. The deep-link parser also safely no-ops on missing/garbage input.

**Fix.** Migrate the recovery (and any future sensitive) deep links to **Universal Links** (an `https://` link backed by an `apple-app-site-association` file and the `com.apple.developer.associated-domains` entitlement). Universal Links are bound to a domain you control and cannot be claimed by another app. Keep the existing PKCE flow.

### L2 — No jailbreak / runtime-tamper detection

**Files:** app-wide; no detection present (no checks in `AppEnvironment.swift`, `NemaraCaregiverApp.swift`, or elsewhere).

**What it is.** The app performs no jailbreak/root or debugger/tamper detection. On a jailbroken device an attacker with physical access can read the Keychain, hook the process with Frida, and inspect/modify in-memory state (e.g., the JWT).

**Why it's Low.** This is purely defense-in-depth: the app already keeps tokens in the Keychain and enforces all authorization server-side, so a compromised client only ever has the access of its own signed-in user — it cannot escalate or reach other caregivers' data. Detection raises the bar for targeted attacks against a single device but does not change the trust model.

**Fix (optional).** If the threat model warrants it, add lightweight jailbreak heuristics (presence of `/Applications/Cydia.app`, ability to write outside the sandbox, suspicious dylibs) and degrade gracefully (warn / limit) rather than only crashing. Treat as a signal, never as a security boundary.

### L3 — Publishable keys in source & legacy anon JWT in git history (informational)

**Files:** `NemaraCaregiver/Networking/AppConfig.swift:46-62` (hardcoded `sb_publishable_*` keys for Debug & Release); git history contains an older Supabase **anon** JWT (`eyJ…role":"anon"…`, `iss: supabase-demo`) from before the migration to `sb_publishable_*`.

**Assessment — acceptable, not a leak.** Supabase **publishable/anon** keys are explicitly designed to be embedded in client apps; they are not secrets. The code comments correctly state this (`AppConfig.swift:43-45`). No service-role key, database connection string, or third-party secret is present in source or history. This item is recorded so a future reader doesn't mistake the embedded keys for a vulnerability — and to flag the one real dependency it creates.

**The actual control to verify (out of static scope).** Because the anon key is public, **all** confidentiality and integrity protection for caregiver data depends on **server-side Supabase Row-Level Security** being correctly enabled on every replicated table (`patients`, `cameras`, `detectors`, `events`, plus storage buckets and the `face_embeddings` / device-token tables). The Realtime subscription code (`NemaraAPIClient.swift:1065-1077`) explicitly assumes "RLS policies filter per-caregiver server-side." If any of those policies are missing or misconfigured, the embedded anon key would let anyone read or modify other patients' data. **Action:** confirm RLS is `ENABLE`d and policy-scoped to `auth.uid()` on every table in the `supabase_realtime` publication and on all REST-backed tables/buckets.

**Hygiene.** The legacy anon JWT in history is a non-sensitive demo key, so no rotation is required. Going forward, keep even publishable keys out of long-lived history where practical and prefer build-time config; treat any *secret* that ever lands in history as compromised and rotate it.

---

## Areas Reviewed With No Findings

- **Secrets scan** — no `sk_live`/`sk_test`, AWS keys, GitHub/GitLab/Slack tokens, private keys, or DB connection strings in source or git history. No `.env` files tracked; `.gitignore` covers local config and `Package.resolved`.
- **Token storage** — Supabase session in Keychain (SDK default); `UserDefaults` holds only the `camerasEverOnline` set and a per-patient onboarding bool (`NemaraAPIClient.swift:200-215`, `NewPatientView.swift:464-467`) — no credentials.
- **Authn/Authz** — JWT obtained via SDK and verified server-side; no client-side `jwt.decode`-style trust. LiveKit identity re-validated by the backend. No client-side role/entitlement gating that grants access.
- **Injection** — REST path segments are UUIDs; query params use `URLQueryItem`; no raw SQL, no web views, no `evaluateJavaScript`, no dynamic code execution.
- **Mass assignment** — request bodies are typed `Encodable` DTOs (`CreatePatientRequest`, `UpdateCameraRequest`, …), not arbitrary dictionaries.
- **AI/LLM** — inference is a backend call; no API keys, prompts, or LLM output rendered as HTML/executed on-device.
- **Debug logging** — response-body / status logging is wrapped in `#if DEBUG` and is absent from Release; access tokens are never logged.
- **Dependencies** — only Supabase (`from: 2.44.1`) and LiveKit (`from: 2.0.0`) via SwiftPM, from official upstreams. `from:` floors allow forward minor/patch resolution; no pinned-vulnerable versions. (Recommend committing `Package.resolved` for reproducible, auditable builds.)
- **ATS** — no `NSAllowsArbitraryLoads`; only `NSAllowsLocalNetworking` for dev. Production TLS enforced.

---

## Prioritized Recommendations

1. **(M1) Add certificate/public-key pinning** for the backend, Supabase, and LiveKit hosts — the highest-value hardening for an app carrying patient video and health events.
2. **(L3) Verify server-side RLS** on every table/bucket (out of static scope but the linchpin of the whole security model, since the client key is public).
3. **(L1) Move password-reset to Universal Links** to remove the custom-scheme hijack surface (PKCE already limits impact).
4. **(L2) Consider jailbreak/tamper heuristics** if the threat model justifies it — as a signal, not a boundary.
5. **Commit `Package.resolved`** for reproducible dependency auditing.

*No application code was modified by this audit. This report is the only file added.*
