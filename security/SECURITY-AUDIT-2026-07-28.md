# Security Audit — nemara-caregiver-app

**Date:** 2026-07-28
**Scope:** Static source audit of the `nemara-caregiver-app` iOS (SwiftUI) client.
**Methodology:** [`vibe-security`](https://github.com/raroque/vibe-security-skill) skill, mobile-prioritized (secrets, ATS, token storage, certificate pinning, deep links, client-side trust), plus committed-secret, authn/authz, injection, dependency, and AI/LLM checks.
**Constraint:** Static analysis only — no live services, secrets, or network access were touched.

---

## Executive Summary

The app is a thin client over a Supabase + FastAPI (Railway) backend. Its security posture is **good**: all authorization is enforced server-side (Supabase RLS + JWT-scoped API), auth tokens are stored in the iOS Keychain (via the Supabase SDK), all AI/LLM calls are proxied through the backend (no model keys on device), and App Transport Security is left intact for production hosts. **No Critical or High severity issues were found.**

The findings below are one **Medium** (a password-reset flow built on a hijackable custom URL scheme) and three **Low** hardening gaps. A set of items that commonly flag as vulnerabilities but are *correct here* is documented at the end so they are not re-litigated.

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | Medium | Password-reset recovery code delivered via hijackable `nemara://` custom URL scheme | `NemaraCaregiverApp.swift:141`, `SupabaseAuthService.swift:182` |
| 2 | Low | Working demo-account credentials committed to the repo | `README.md:62-63` |
| 3 | Low | No TLS certificate / public-key pinning on backend + Supabase + LiveKit | `NemaraAPIClient.swift:103`, `AppConfig.swift` |
| 4 | Low | No jailbreak / app-integrity (client-side trust) check | app-wide |

---

## Medium

### 1. Password-reset recovery code arrives over a hijackable custom URL scheme

**`NemaraCaregiver/App/NemaraCaregiverApp.swift:141-156`** (handler) and **`NemaraCaregiver/Services/SupabaseAuthService.swift:182-191`** (exchange); scheme declared in **`Info.plist:21-31`** / **`project.yml:101-104`**.

The recovery link Supabase emails is `nemara://reset-password?code=…`. The app receives it purely through the **custom URL scheme** `nemara` — there is no Universal Link / associated-domains entitlement (confirmed: `NemaraCaregiver-Release.entitlements` declares only `aps-environment` and `HotspotConfiguration`, no `com.apple.developer.associated-domains`).

Custom URL schemes are not exclusive. Any other app installed on the device may also register the `nemara` scheme, and iOS does **not** guarantee which app receives the URL when more than one claims it. A malicious/piggybacking app that registers `nemara://` can therefore intercept the `?code=` recovery token. That code is exchanged directly for a full recovery session:

```swift
// SupabaseAuthService.swift:182
let session = try await client.auth.exchangeCodeForSession(authCode: code)
// …then updatePassword(newPassword) → a fully signed-in session
```

**Why exploitable:** interception of the code yields `exchangeCodeForSession` → `updateUser(password:)` → **account takeover** of a caregiver account, which grants access to an elderly patient's live audio/video, home address, and health-event history. The bar is a malicious app on the same device declaring the same scheme (or a user tricked into installing one).

**Fix:** Move the recovery redirect to a **Universal Link** (HTTPS, domain-verified) instead of a custom scheme.

```
// 1. Add associated-domains to the Release entitlements
<key>com.apple.developer.associated-domains</key>
<array><string>applinks:links.nemara.co</string></array>

// 2. Host apple-app-site-association at https://links.nemara.co/.well-known/
// 3. Point the Supabase redirect at the HTTPS URL:
static let supabasePasswordResetRedirect = URL(string: "https://links.nemara.co/reset-password")!

// 4. Handle it in .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) rather than .onOpenURL
```

Universal Links are cryptographically bound to a domain you control, so no other app can claim them. If a custom scheme must be retained as a fallback, treat any code arriving via `nemara://` as lower-trust and require the user to re-authenticate before the password change takes effect.

---

## Low

### 2. Working demo-account credentials committed to the repository

**`README.md:62-63`**

```
- Email: `jane@patel.co`
- Password: `Mar9aret!2024`
```

This is a real, usable password string checked into source control. It is documented as a local `make fresh-seed` account, so the immediate blast radius is limited to developer machines running the seed — but committed credentials are a hygiene problem: the same password tends to get reused across seed/staging environments, and it now lives permanently in git history.

**Why it matters:** if this seed (or a human reusing the password) exists in any shared or internet-reachable environment, the credential is a ready-made login. It cannot be "un-committed" — deleting the line leaves it in history.

**Fix:** Remove the literal password from the README and reference an environment variable or a locally-generated secret instead (e.g. "the seed prints a one-time password on `make fresh-seed`"). Rotate the value anywhere the seed has run against a non-throwaway backend.

```markdown
## Demo login
After `make fresh-seed`, use the credentials the seed script prints to your terminal.
```

### 3. No TLS certificate / public-key pinning

**`NemaraCaregiver/Services/NemaraAPIClient.swift:103`** (`session: URLSession = .shared`), production hosts in **`AppConfig.swift:41,94`**.

The app talks to `https://…supabase.co`, `https://nemara-backend-production.up.railway.app`, and LiveKit over stock `URLSession`/SDK TLS with no pinning. It carries sensitive eldercare data: patient names, home addresses (`homeAddress`), uploaded photos, **face embeddings** (`submitFaceEmbeddings`), live audio/video tokens, and health events.

App Transport Security already enforces valid TLS for these routable hosts (see the "verified-safe" note on ATS below), so this is **defense-in-depth**, not an open hole. But without pinning, an attacker who can present a certificate trusted by the device — a compromised/rogue public CA, or (more realistically for a consumer device) a root certificate installed via MDM or social engineering — can transparently MITM this traffic.

**Fix:** Pin the backend and Supabase leaf/intermediate public keys, e.g. with a `URLSessionDelegate` implementing `urlSession(_:didReceive:completionHandler:)` that compares the server public-key hash against a bundled allow-list, or adopt a maintained pinning library. Pin to the intermediate CA public key and ship at least one backup pin to survive certificate rotation.

### 4. No jailbreak / app-integrity (client-side trust) check

**App-wide** — no runtime integrity, jailbreak, or debugger check exists.

For an app that streams a vulnerable person's live camera and audio, there is no detection of a compromised runtime. On a jailbroken device, tools like Frida can hook the app, read the Keychain-resident session token, or tamper with in-memory state. This is inherently **Low** (it protects only against an attacker who already controls the device) and should be weighed against the false-positive cost of jailbreak heuristics, but it is a recognized gap for a health/monitoring app.

**Fix (optional hardening):** Add lightweight integrity signals (jailbreak indicators, `getppid`/debugger checks) and, for any biometric gating you add later, use **cryptographic** attestation (server nonce → Secure Enclave signature → server verify) rather than a boolean success flag — a plain boolean is trivially hooked.

---

## Verified Safe (checked — intentionally not findings)

These patterns frequently read as vulnerabilities but are correct in this codebase; documented so they are not repeatedly re-flagged.

- **Supabase publishable/anon key hardcoded** (`AppConfig.swift:61,64`) — the `sb_publishable_*` anon key is *designed* to ship in clients and is gated by RLS. This is the correct client key, **not** the `service_role` key. No secret key, JWT signing secret, or DB connection string appears anywhere in the client. **Safe.**
- **ATS configuration** (`Info.plist:36-40`) — only `NSAllowsLocalNetworking` is set (to reach LAN dev backends). ATS is **not** globally disabled: there is no `NSAllowsArbitraryLoads` and no `NSExceptionDomains`, so TLS is still fully enforced for all routable/production hosts. **Safe.**
- **Auth token storage** — sessions are held by the Supabase SDK in the **iOS Keychain**, not `UserDefaults`. `UserDefaults` is used only for non-secret UI state (tutorial-done flags, `camerasEverOnline`). No token/credential is written to `UserDefaults` or plaintext disk. **Safe.**
- **AI / LLM integration** — `inferDetector` and `detectDoors` (`NemaraAPIClient.swift:757,787`) post user text / a base64 frame to the app's *own* backend (`/v1/detectors/infer`, `/v1/detect-doors`); no OpenAI/Anthropic/Google key is present client-side. This is the recommended backend-proxy pattern. **Safe.**
- **Authorization / injection** — the client performs no local authz decisions and builds no SQL. All mutations go through JWT-authenticated REST endpoints; server-side RLS scopes every row per caregiver (`NemaraAPIClient.swift` Realtime comment lines 1166-1170). Path parameters are typed `UUID`s, not free strings. LiveKit tokens are minted server-side and room-scoped per patient; the client-supplied identity is explicitly re-validated server-side (`mintToken`, lines 925-945). **Safe.**
- **Dev-only clip capture** (`AppConfig.swift:112-132`) — hard-compiled `false` in Release via `#if !DEBUG`; cannot be re-enabled by the skip-worktree `LocalAppConfig` or an env var in a distribution build. **Safe.**
- **Dependencies** — only two third-party SPM packages, both mainstream and version-floored: `supabase-swift` (from 2.44.1) and `livekit/client-sdk-swift` (from 2.0.0) (`project.yml:3-21`). No obviously abandoned or vulnerable dependency. (Recommend periodic `swift package update` review; version-pinning floors are appropriate.)
- **Git history** — no `.env`, `.p8`, private key, or `service_role`/`sk_*`/cloud-credential blob was ever committed (history scanned). The only credential-shaped string in history is finding #2.

---

## Prioritized Remediation

1. **(Medium) Move password reset off the custom URL scheme to a Universal Link** — closes the recovery-code interception → account-takeover path. Highest-value fix.
2. **(Low) Purge the demo password from the README** and rotate it wherever the seed has run against anything non-throwaway.
3. **(Low) Add certificate/public-key pinning** for the backend and Supabase — meaningful defense-in-depth given the PHI-adjacent and live-media data.
4. **(Low) Consider jailbreak / integrity signals** as future hardening; weigh against false-positive cost.

*No Critical or High findings. The application follows sound client-security fundamentals; the items above are targeted hardening, not open breaches.*
