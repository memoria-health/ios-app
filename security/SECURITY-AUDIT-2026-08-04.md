# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-08-04
**Scope:** Static source review of `nemara-caregiver-app` (native iOS / Swift, SwiftUI).
**Methodology:** `vibe-security` skill (Chris Raroque) — mobile, secrets & env, authentication, data-access, and AI-integration reference checks, adapted from its React-Native framing to native Swift.
**Constraint:** Static only. No live services, no secrets, no network calls. Findings are limited to what is provable from the checked-out source; the backend (`nemara-backend` on Railway) and Supabase RLS policies are **not** in this repo and were **not** assessed — the app's security ultimately depends on them.

---

## Executive Summary

This is a **well-architected, security-conscious client**. The app is a thin front-end over a backend it does not trust: every authenticated request carries a Supabase JWT, all third-party/AI work is proxied through the backend rather than called with embedded secret keys, sessions live in the Supabase SDK's Keychain-backed store, and authorization is delegated to server-side RLS + JWT. The scan for the classic "vibe-coded" failure modes — hardcoded secret keys, `service_role`/`sk_live` exposure, client-trusted prices/roles, arbitrary-loads ATS, TLS bypass, tokens in `UserDefaults`, secrets in git history — came back **clean**.

No Critical or High issues were found. The findings below are **defense-in-depth hardening** for an app that handles eldercare PHI and live audio/video of vulnerable adults, where a higher bar than "correct by default" is warranted.

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | Low | Password-recovery uses a custom URL scheme, not Universal Links | `Info.plist`, `AppConfig.swift:71`, `NemaraCaregiverApp.swift:141` |
| 2 | Low | No TLS certificate pinning for PHI / live A-V traffic | `NemaraAPIClient.swift:102`, `LiveKitClient.swift:206` |
| 3 | Low | Dependencies unpinned in-repo (`Package.resolved` gitignored + broad `from:` ranges) | `.gitignore:16`, `project.yml:13,21` |
| 4 | Info | DEBUG-only logging of HTTP bodies / connect URLs | `NemaraAPIClient.swift:1235`, `LiveKitClient.swift:208` |
| 5 | Info | Preview placeholder password in source | `NemaraField.swift:149` |

A section of **positive findings** (things done right) follows the findings, because they are the reason the report is short.

---

## Findings

### Low

#### 1. Password-recovery redirect uses a custom URL scheme rather than Universal Links

**Where:**
- `NemaraCaregiver/Resources/Info.plist:21-31` — registers the `nemara` custom URL scheme.
- `NemaraCaregiver/Networking/AppConfig.swift:71` — `supabasePasswordResetRedirect = URL(string: "nemara://reset-password")!`.
- `NemaraCaregiver/App/NemaraCaregiverApp.swift:141-156` — `handleIncomingURL` extracts `?code=` and drives `ResetPasswordView`.
- `NemaraCaregiver/Services/SupabaseAuthService.swift:164-191` — `resetPasswordForEmail(redirectTo:)` then `exchangeCodeForSession(authCode:)`.

**Why it's a (bounded) risk:** iOS does not grant exclusive ownership of a custom URL scheme. A malicious app co-installed on the device can also register `nemara://`; when the OS resolves the recovery link, delivery to a specific app is undefined, so a hostile app can receive the recovery `code`.

**Why it is only Low, not High:** The SDK uses the **PKCE** flow (`exchangeCodeForSession(authCode:)` with no `flowType` override → Supabase Swift's default). The `code_verifier` generated when `resetPasswordForEmail` is called is stored in the *legitimate* app's sandboxed storage and is unreachable by another app. An intercepted `code` cannot be exchanged for a session without that verifier, so this does not yield account takeover under the current same-device PKCE flow. The residual risk is interception/DoS of the recovery step and reliance on PKCE staying enabled.

**Fix (hardening):** Move the recovery (and any future auth) callback to a **Universal Link** — add an Associated Domains entitlement (`applinks:<your-domain>`) and host an `apple-app-site-association` file — so the callback can only be delivered to this app. Keep the PKCE flow. Keep the custom scheme only as a non-auth fallback, if at all.

```swift
// AppConfig.swift — Before
static let supabasePasswordResetRedirect = URL(string: "nemara://reset-password")!

// After — Universal Link the OS binds exclusively to this app via AASA
static let supabasePasswordResetRedirect = URL(string: "https://links.nemara.co/reset-password")!
```

#### 2. No TLS certificate pinning for PHI and live audio/video traffic

**Where:**
- `NemaraCaregiver/Services/NemaraAPIClient.swift:98-110` — `session: URLSession = .shared`, no `URLSessionDelegate` performing pinning.
- `NemaraCaregiver/Services/LiveKitClient.swift:206` — `room.connect(url:token:)` with the SDK default trust chain.

**Why it matters:** All patient data, avatars, face-embedding uploads (Re-ID biometrics), event clips, and live A/V of vulnerable adults transit standard system-trust TLS. Without pinning, an attacker able to install a trusted root on a managed/compromised device (MDM, malicious profile) can transparently MITM this sensitive traffic. Standard TLS defends against passive eavesdropping; pinning is the additional wall for an app in a healthcare-adjacent trust class.

**Fix:** Pin the backend leaf/intermediate public key. Either configure `NSPinnedDomains` in `Info.plist` (iOS 14+, no code) or implement `urlSession(_:didReceive:completionHandler:)` on a custom `URLSession` delegate that validates the server public key against a bundled set. Pin the LiveKit signaling/media endpoints similarly, or rely on short-lived tokens as the compensating control and document that decision.

```xml
<!-- Info.plist — NSPinnedDomains under NSAppTransportSecurity -->
<key>NSPinnedDomains</key>
<dict>
  <key>nemara-backend-production.up.railway.app</key>
  <dict>
    <key>NSPinnedLeafIdentities</key>
    <array><dict><key>SPKI-SHA256-BASE64</key><string>…pin…</string></dict></array>
  </dict>
</dict>
```

#### 3. Dependencies are not pinned in-repo

**Where:**
- `.gitignore:16` — `Package.resolved` is gitignored.
- `project.yml:13` — Supabase `from: "2.44.1"`; `project.yml:21` — LiveKit `from: "2.0.0"`.

**Why it matters:** `Package.resolved` is the lockfile that records the exact resolved commit of every dependency. Gitignoring it for an **application** (as opposed to a library) means CI and release builds can silently resolve to different dependency versions than any developer tested — reproducibility and supply-chain-integrity gap. The `from:` ranges compound this: `LiveKit from: "2.0.0"` admits everything up to `<3.0.0`, a very wide band of code (auth SDK and a media SDK) that could ship a regression or a compromised release into a build with no committed record of what was used.

**Fix:** Commit `Package.resolved` (remove it from `.gitignore`) so the exact dependency graph is versioned and reviewable, and tighten the ranges toward the tested minor (e.g. `"2.44.x"` / `"2.x"` via `.upToNextMinor`) so an unaudited minor bump is a deliberate, reviewed change rather than an implicit one.

### Informational

#### 4. DEBUG-only logging of HTTP response bodies and connect URLs

`NemaraCaregiver/Services/NemaraAPIClient.swift:1197,1235` print decode failures and raw HTTP error bodies; `LiveKitClient.swift:208,219` print room/connect URLs. All are wrapped in `#if DEBUG`, so they never reach a release/TestFlight/App Store build. No action required beyond keeping the `#if DEBUG` guards intact; noted only so they are not later promoted out of the guard. Tokens are **not** logged anywhere (verified).

#### 5. Preview placeholder password in source

`NemaraCaregiver/DesignSystem/Components/NemaraField.swift:149` defines `password = "Mar9aret!"` inside a `#if DEBUG` `#Preview`. It is a SwiftUI canvas placeholder, not a credential, and is compiled out of release builds. No action required; listed for completeness so a secret-scanner hit is pre-triaged.

---

## Positive Findings (verified good practices)

These are the reason there are no Critical/High findings — recording them so the posture is auditable:

- **Only publishable/anon keys are embedded**, and correctly so. `AppConfig.swift:45-66` ships Supabase `sb_publishable_*` keys, which are designed for client distribution. No `service_role`, `sk_live/sk_test`, DB connection string, JWT signing secret, or third-party secret key appears anywhere in the source, `Info.plist`, `xcconfig`, or assets.
- **Backend-proxy for all secret-bearing work.** Every AI/LLM feature (detector inference `/v1/detectors/infer`, door detection `/v1/detect-doors`, home briefing/report) and every third-party call goes through `nemara-backend`; no OpenAI/Anthropic/LiveKit **secret** key is present in the app. Matches the skill's "use a backend proxy" rule exactly.
- **Server-side trust model.** `NemaraAPIClient.makeRequest` (`:1125-1145`) attaches a Supabase JWT to every request; authorization is delegated to backend RLS + JWT (comments at `:1288`, `:239`). LiveKit tokens are minted server-side with the server re-validating role/identity (`mintToken` `:979-999`) — the client-supplied identity is explicitly "informational."
- **Sessions in the Keychain, not `UserDefaults`.** Auth tokens are managed by the Supabase SDK's Keychain-backed store (`SupabaseAuthService`); the only `UserDefaults` writes are non-sensitive UI state (camera-online memory, per-device blur/warning toggles).
- **Minimal ATS exception.** `Info.plist:36-40` sets only `NSAllowsLocalNetworking` (needed for LAN camera discovery on Wi-Fi). There is **no** `NSAllowsArbitraryLoads`; release endpoints are all HTTPS. The only `http://` URLs are `#if DEBUG` LAN/Bonjour dev hosts, hard-compiled off in release (`AppConfig.swift:37-42,89-95`).
- **No TLS bypass.** No `URLAuthenticationChallenge` handler, no `serverTrust` override, no arbitrary-loads — searched and confirmed absent.
- **Clean git history.** No `.env`, `.p8`, `.p12`, `.pem`, or credential file has ever been committed; `.gitignore:19-23` explicitly keeps env files out following a prior leak in a sibling repo.
- **Dev-only research features hard-gated off in release.** The clip-capture data-collection path is compiled off via `#if !DEBUG` at a single choke point (`AppConfig.swift:112-132`) with a clear rationale.
- **Analytics carry no PHI.** `Analytics.swift` sends only UI-interaction telemetry (button/screen names, OS/device/build, `caregiver_id`) to Supabase under RLS — no patient names, health data, or media.

---

## Prioritized Recommendations

1. **(Low) Adopt Universal Links** for the password-recovery callback and any future auth deep links; keep the PKCE flow. Removes reliance on custom-scheme delivery for auth.
2. **(Low) Add certificate pinning** (`NSPinnedDomains` for the Railway backend; pin or document the LiveKit path) given the PHI/live-A-V data class.
3. **(Low) Commit `Package.resolved`** and tighten SPM `from:` ranges so the dependency graph is versioned and reviewed.
4. **(Info)** Keep DEBUG-only logging and preview placeholders behind their `#if DEBUG` guards.
5. **Out of scope but essential:** the client's safety rests on backend Supabase **RLS policies** and JWT verification, which are not in this repo. Ensure a matching audit covers RLS on `patients`, `cameras`, `detectors`, `events`, `ui_events`, storage buckets (avatars, face-embeddings, clips), and the LiveKit token-minting endpoint's authorization.

---

*Static audit generated by an automated security-review agent using the `vibe-security` skill. No application code was modified; this report is the only added file.*
