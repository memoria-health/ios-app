# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-06-25
**Scope:** Static review of the native iOS (Swift/SwiftUI) caregiver app in `aryamandarda/nemara-caregiver-app` (`HEAD` at `a429b08`, v1.2.4 build 29).
**Methodology:** [vibe-security](https://github.com/raroque/vibe-security-skill) skill, with emphasis on mobile-specific checks (secrets in the bundle, App Transport Security, token storage, certificate pinning, deep links, client-side trust). Backend (`nemara-backend` on Railway, Supabase RLS) is **out of scope** — no live services or secrets were accessed.

---

## Executive Summary

The app is **soundly architected from a security standpoint** and follows the core "never trust the client" principle well:

- **Auth tokens are never stored insecurely.** The app delegates all session storage to the Supabase Swift SDK (hardware-backed Keychain), and reads the access JWT on demand via `currentAccessToken()`. No tokens are written to `UserDefaults` or plaintext files. The only `UserDefaults` use is a set of non-sensitive camera UUIDs.
- **No real secrets are committed.** The only embedded keys are Supabase *publishable/anon* keys (designed to ship in clients). A scan of full git history (65 commits) found no `service_role` key, Stripe secret, private key, or other high-value credential — only the well-known Supabase local-dev demo JWT.
- **All authorization is server-side.** Every request carries a `Bearer` JWT; LiveKit tokens are minted and re-validated server-side; Realtime relies on per-caregiver RLS. There is no client-side price/role/entitlement logic to tamper with.
- **App Transport Security is correctly scoped.** Only `NSAllowsLocalNetworking` is enabled (for LAN sensor setup); there is **no** `NSAllowsArbitraryLoads`, so TLS is still enforced for all routable/production hosts.

No **Critical** or **High** severity issues were found. The findings below are **Medium and lower**, and are primarily defense-in-depth and supply-chain hardening for an app that handles sensitive health/PHI data (patient video, biometric face embeddings, care events).

| # | Severity | Title |
|---|----------|-------|
| 1 | Medium | Password-reset deep link uses a hijackable custom URL scheme (account-takeover vector) |
| 2 | Medium | Dependencies float on `from:` with no committed lockfile (supply-chain risk) |
| 3 | Low | No certificate/public-key pinning for PHI and live-video traffic |
| 4 | Low | Weak client-side password policy (length-only, ≥8 chars) |
| 5 | Low / Informational | Production Supabase project URL + anon key embedded — entire authz model rests on RLS (unverifiable here) |
| 6 | Informational | Verbose `#if DEBUG` logging includes full response bodies (may contain JWTs/signed URLs) |
| 7 | Informational | No jailbreak/root or anti-tamper signal (acceptable given server-side enforcement) |

---

## Medium

### 1. Password-reset deep link uses a hijackable custom URL scheme

**Files:**
- `NemaraCaregiver/Resources/Info.plist:21-31` (registers `CFBundleURLSchemes` = `nemara`)
- `NemaraCaregiver/App/NemaraCaregiverApp.swift:136-151` (`handleIncomingURL` extracts `?code=`)
- `NemaraCaregiver/Networking/AppConfig.swift:67` (`supabasePasswordResetRedirect = nemara://reset-password`)
- `NemaraCaregiver/Services/SupabaseAuthService.swift:164-191` (`requestPasswordReset` / `exchangeRecoveryCode`)

**What it is.** The password-recovery email links to `nemara://reset-password?code=<recovery_code>`. The app receives that via `.onOpenURL`, pulls out `code`, and exchanges it for a full session (`exchangeCodeForSession`), after which `updatePassword` sets a new password and signs the user in.

**Why it's exploitable.** Custom URL schemes are **not exclusive on iOS** — any app may register the same `nemara` scheme, and when two apps claim one scheme iOS resolution is undefined (commonly "last installed wins"). A malicious app installed on the same device that registers `nemara://` can therefore receive the recovery `code` when the victim taps the email link. Because exchanging that code yields a recovery session that can immediately *set a new password*, a successful interception is **full account takeover** of an account guarding live video and PHI of a vulnerable (elderly/at-risk) person. Likelihood is moderate (requires a hostile app on-device), but impact is high.

**Fix.** Migrate the recovery (and any future auth) redirect to a **Universal Link** (HTTPS, backed by an Associated Domains entitlement + `apple-app-site-association`), which is cryptographically bound to your domain and cannot be claimed by another app:

```swift
// Before — custom scheme, claimable by any app
static let supabasePasswordResetRedirect = URL(string: "nemara://reset-password")!

// After — Universal Link bound to your verified domain
static let supabasePasswordResetRedirect = URL(string: "https://nemara.app/auth/reset-password")!
// + add the domain to Associated Domains entitlement (applinks:nemara.app)
// + serve /.well-known/apple-app-site-association
// + add the new HTTPS URL to Supabase Auth → URL Configuration allow-list
```

Defense-in-depth (server-side, out of audit scope but worth confirming): ensure recovery codes are strictly single-use and short-TTL so a replayed/intercepted code fails after first use.

---

### 2. Dependencies float on `from:` with no committed lockfile

**Files:**
- `project.yml:12-21` (`Supabase` `from: "2.44.1"`, `LiveKit` `from: "2.0.0"`)
- `.gitignore` (ignores `Package.resolved`)

**What it is.** Both SwiftPM dependencies use `from:` (which allows *any* later version up to the next major), and `Package.resolved` — the file that pins exact resolved versions — is git-ignored.

**Why it matters.** With no committed lockfile and open-ended ranges, every `swift package update`, fresh clone, and CI run may resolve **different** versions of `supabase-swift` and `client-sdk-swift`. If an upstream release (or a transitive dependency) is compromised, yanked, or ships a regression, it is pulled silently with no review gate and no reproducible record of what shipped. For an app processing PHI and biometric data, the inability to reproduce or audit the exact dependency set used in a given App Store build is a real supply-chain exposure.

**Fix.** Commit the lockfile and pin tightly so the build is reproducible and upgrades are explicit, reviewed changes:

```
# .gitignore — remove this line so the lockfile is tracked
- Package.resolved
```

```yaml
# project.yml — prefer an exact/upToNextMinor pin over open-ended `from:`
Supabase:
  url: https://github.com/supabase/supabase-swift
  exactVersion: "2.44.1"      # or: upToNextMinorVersion: "2.44.1"
LiveKit:
  url: https://github.com/livekit/client-sdk-swift
  upToNextMinorVersion: "2.x.y"   # pin the floor you actually ship
```

Commit `Package.resolved`, and bump dependencies via reviewed PRs rather than ambient resolution.

---

## Low

### 3. No certificate / public-key pinning for PHI and live-video traffic

**Files:**
- `NemaraCaregiver/Services/NemaraAPIClient.swift:102` (`session: URLSession = .shared`, no `URLSessionDelegate`)
- `NemaraCaregiver/Services/SupabaseAuthService.swift:92` (default `SupabaseClient`)
- `NemaraCaregiver/Services/LiveKitClient.swift` (default LiveKit transport)

**What it is.** All HTTPS/WSS traffic (backend API, Supabase Auth/Realtime, LiveKit) uses the system default trust evaluation with no certificate or SPKI pinning.

**Why it matters.** ATS already enforces TLS 1.2+, so a passive network attacker cannot read traffic. However, an attacker who can get a CA certificate trusted on the device (a user-installed/MDM root, or a compromised CA) can transparently MITM the connection — intercepting JWTs, patient video tokens, and PHI. Given the sensitivity of the data (live feeds of vulnerable adults, biometric face embeddings), pinning is justified as defense-in-depth. This is a hardening recommendation, not an active vulnerability; many apps reasonably ship without it.

**Fix.** Pin the leaf or intermediate public key (SPKI hash) for your backend and Supabase hosts via a `URLSessionDelegate` performing `urlSession(_:didReceive:completionHandler:)` validation, or configure pinning through the SDK transport. Pin to the intermediate (not the leaf) and ship a backup pin to avoid bricking the app on certificate rotation.

### 4. Weak client-side password policy

**Files:**
- `NemaraCaregiver/Features/Auth/ResetPasswordView.swift:32-34` (`password.count >= 8`)
- (verify the same in `SignUpView.swift`)

**What it is.** The only client-side password requirement is a minimum length of 8 characters — no check for breached/common passwords or complexity.

**Why it matters.** Length-only validation permits weak passwords (e.g. `password`, `12345678`) on accounts that guard PHI and live video. Client validation is a UX nicety, not a control, so the real fix is server-side.

**Fix.** Enforce a stronger policy in Supabase Auth (minimum length + the "Prevent use of leaked passwords" / HIBP option in Auth settings), and mirror a reasonable minimum client-side for fast feedback. Confirm the server actually rejects weak passwords rather than relying on the client gate.

---

## Informational

### 5. Production Supabase URL + anon key embedded — authz rests entirely on RLS

**File:** `NemaraCaregiver/Networking/AppConfig.swift:38, 60`

The production Supabase project URL (`https://zgifmvjnggmgzvtnosnu.supabase.co`) and the publishable/anon key (`sb_publishable_…`) are compiled into the Release binary. **This is by design and is the documented, supported pattern** — anon/publishable keys are meant to ship in clients, and no `service_role` or secret key is present anywhere in the repo or history.

The note is that, consequently, **the app's entire data-authorization model depends on Supabase Row-Level Security and backend JWT checks**, which are server-side and could not be verified in this static review. RLS is the #1 source of critical vulnerabilities in this class of app. **Strongly recommend a dedicated review of the backend's RLS policies and FastAPI endpoint authorization** (every `/v1/...` route, Realtime publication filters, and Storage bucket policies) to confirm a caregiver can only ever read/write their own patients', cameras', events', and face-embedding rows.

### 6. Verbose DEBUG logging includes full response bodies

**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift:1044-1049, 1082-1086`

In DEBUG builds the client prints full HTTP response bodies on decode failure and on non-2xx, which can include JWTs and short-lived signed media URLs. These logs are wrapped in `#if DEBUG` and are stripped from Release/App Store builds, so this is not a shipping exposure. Keep it that way (no `os_log`/print of tokens outside `#if DEBUG`), and avoid logging `Authorization` headers or `access_token` values even in debug.

### 7. No jailbreak/root detection or anti-tamper

No jailbreak detection, anti-debugging, or runtime integrity checks are present. This is **acceptable and consistent with the app's correct design**: all trust decisions are enforced server-side (RLS + JWT), so a tampered client cannot escalate beyond what its own session is authorized for. Only consider adding integrity signals if a future feature begins to rely on client-side enforcement.

---

## What Was Checked and Found Clean

- **Token storage** — Keychain via Supabase SDK; no `UserDefaults`/plaintext token persistence (`SupabaseAuthService.swift:279-286`, `NemaraAPIClient.swift:207-222`).
- **Committed secrets** — none beyond by-design publishable keys; full-history scan clean.
- **App Transport Security** — `NSAllowsLocalNetworking` only; no arbitrary-loads exception (`Info.plist:36-40`, `project.yml:90-91`).
- **Injection** — no raw SQL, no `WKWebView`/`evaluateJavaScript`, no dynamic code execution; all DB access via PostgREST/RLS.
- **Authorization** — server-minted, server-validated LiveKit tokens; client-supplied identity is re-validated server-side (`NemaraAPIClient.swift:888-908`).
- **Deep-link payload handling** — APNs `event_id`/`patient_id` are parsed as `UUID` (rejecting malformed input) and resolved through caregiver-scoped, 404-on-foreign-id endpoints (`AppDelegate.swift:90-109`, `NemaraAPIClient.swift:838-843`).
- **Wi-Fi sensor setup** — joins an open setup SSID via `NEHotspotConfiguration`; no Wi-Fi credentials are handled in-app (iOS captive portal owns home-network entry) (`SensorSetupWizard.swift:383-418`).
- **Analytics buffer** — app-sandboxed JSON containing only UI telemetry (screen/button names, device model, caregiver UUID); no PHI, tokens, or secrets (`Analytics.swift`).

---

## Prioritized Remediation

1. **(Medium) Move the password-reset redirect to a Universal Link** to eliminate the custom-scheme account-takeover vector. Confirm recovery codes are single-use server-side.
2. **(Medium) Commit `Package.resolved` and pin dependency versions** for reproducible, reviewable builds.
3. **(Low) Add certificate/SPKI pinning** for backend, Supabase, and LiveKit hosts (with a backup pin).
4. **(Low) Strengthen the server-side password policy** (length + leaked-password check); mirror client-side.
5. **(Informational, high-value) Commission a backend RLS + endpoint-authorization review** — the app's security correctly depends on it, and it was out of scope here.
