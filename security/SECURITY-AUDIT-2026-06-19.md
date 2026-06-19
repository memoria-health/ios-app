# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-06-19
**Scope:** Static source audit of `nemara-caregiver-app` (native iOS / Swift, SwiftUI).
**Methodology:** [`vibe-security`](https://github.com/raroque/vibe-security-skill) skill — secrets & environment, authentication & authorization, data access & input validation, mobile security (token storage, API-key protection, deep links, client-side trust), and AI/LLM integration. Mobile checks prioritized per the app type.
**Constraint:** Static only. No live services, secrets, or network access were used. Server-side controls (FastAPI backend, Supabase Postgres RLS) are **out of repo** and could not be verified — several findings below are flagged for out-of-band verification.

---

## Executive Summary

This is a **well-architected, security-conscious** codebase. The app is a thin client: every mutation goes through the `nemara-backend` REST API authenticated with a per-request Supabase JWT bearer token, Realtime subscriptions rely on server-side Row-Level Security, auth sessions are stored in the iOS Keychain by the Supabase SDK, AI/LLM inference is proxied through the backend (no model API keys in the app), App Transport Security is left enabled (only local-networking is excepted), and no real secrets or private keys are committed to the repo or its git history.

**No Critical or High severity issues were found.** The findings are defense-in-depth / hardening items appropriate to the unusually sensitive data this app handles (live audio-video of vulnerable adults in their homes, home addresses, dates of birth, and health-event data).

The single most important action is **not a code change in this repo**: because the app ships the public Supabase anon key and trusts the server for all authorization, the entire data-access security model rests on Postgres RLS policies that live in the backend. Those policies must be confirmed correct and enabled on every table (see M3).

### Findings at a glance

| # | Severity | Title |
|---|----------|-------|
| M1 | Medium | Password-recovery code delivered over a hijackable custom URL scheme |
| M2 | Medium | No TLS certificate / public-key pinning on a PHI-bearing app |
| M3 | Medium | Data-access security depends entirely on unverifiable server-side RLS |
| L1 | Low | No jailbreak / runtime-integrity signal for an in-home camera controller |
| L2 | Low | Analytics buffer persisted to disk without an explicit Data Protection class |
| L3 | Low | Full HTTP response/error bodies (potential PHI) logged in DEBUG builds |

### Notable good practices (no action needed)
- Auth tokens are stored in the **Keychain** (via the Supabase SDK), not `UserDefaults` (`SupabaseAuthService.swift:254`). The only `UserDefaults` usage holds non-sensitive UI flags (camera "ever online", tutorial completion).
- **ATS is enabled**; `Info.plist` only sets `NSAllowsLocalNetworking` (for the dev LAN/Supabase stack). No `NSAllowsArbitraryLoads`. Production hosts are HTTPS and TLS-enforced.
- The committed Supabase keys are **publishable / anon keys** (`sb_publishable_*`) — designed to ship in clients — not `service_role` keys. No `service_role`, `sk_live`, AWS, or private-key material appears anywhere in the tree or git history.
- **AI inference is server-side**: `inferDetector` POSTs to `/v1/detectors/infer` (`NemaraAPIClient.swift:733`); no LLM provider keys are embedded in the app.
- **Strong client-side password policy** (≥8 chars, mixed case, digit, symbol) at `SignUpView.swift:17`.
- The dev-only clip-capture / `recordClip` path is double-gated behind `AppConfig.enableClipCapture` (off by default) **and** a backend `NEMARA_ENABLE_INTERNALS` flag (`NemaraAPIClient.swift:936`).
- Password reset uses the **PKCE** flow (`exchangeCodeForSession`), which materially mitigates M1.

---

## Medium

### M1 — Password-recovery code delivered over a hijackable custom URL scheme

**Files:**
- `NemaraCaregiver/Resources/Info.plist:21-31` (and `project.yml:101-104`) — registers the `nemara` custom URL scheme.
- `NemaraCaregiver/App/NemaraCaregiverApp.swift:124-139` — `handleIncomingURL` parses `nemara://reset-password?code=…`.
- `NemaraCaregiver/Services/SupabaseAuthService.swift:158-185` — requests the reset email with `redirectTo: nemara://reset-password` and exchanges the `code`.

**What it is.** The password-reset recovery `code` is delivered to the app via a **custom URL scheme** (`nemara://`). Unlike a Universal Link (which is cryptographically bound to the app via an Associated Domain / `apple-app-site-association` file), any app on the device can declare the same `nemara` scheme. When two apps register the same custom scheme, iOS's choice of recipient is **undefined**, so a malicious app installed on the same device can receive the recovery `code` intended for Nemara.

**Why the impact is bounded (but real).** Supabase's reset uses the **PKCE** flow: `exchangeCodeForSession(authCode:)` requires a `code_verifier` that the SDK stored in *this device's* Keychain when the reset was requested. A different app — or the same code opened on a different device — cannot complete the exchange without that verifier. This downgrades the issue from account takeover to:
1. **Reset-flow denial / hijack-to-phish** — a squatting app can swallow the deep link so the legitimate reset silently fails, and can present a convincing fake "set new password" screen.
2. **Residual takeover risk** if the project's flow type is ever changed away from PKCE, or if recovery links are ever generated as implicit-grant tokens.

This maps directly to the skill's mobile guidance: *"Never include sensitive data in deep link URLs (tokens, passwords, user IDs that grant access)."*

**Fix.** Move the reset redirect to a **Universal Link** over HTTPS and add an Associated Domains entitlement, so only Nemara can receive it:

```swift
// AppConfig.swift — before
static let supabasePasswordResetRedirect = URL(string: "nemara://reset-password")!

// after — an https Universal Link backed by apple-app-site-association
static let supabasePasswordResetRedirect = URL(string: "https://links.nemara.co/reset-password")!
```
Add `applinks:links.nemara.co` to the entitlements, host `/.well-known/apple-app-site-association`, add this URL to Supabase's Redirect-URL allow-list, and keep the PKCE flow. Retain the `nemara://` handler only as a non-sensitive fallback.

---

### M2 — No TLS certificate / public-key pinning on a PHI-bearing app

**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift:107` (uses `URLSession.shared`, no `URLSessionDelegate` / `urlSession(_:didReceive:)` challenge handler); `NemaraCaregiver/Services/LiveKitClient.swift` (LiveKit connection uses SDK defaults).

**What it is.** The app performs no certificate or public-key pinning. All API, Supabase, and LiveKit traffic is validated only against the system trust store. An attacker who can place a trusted CA certificate on the device — a malicious or coerced configuration/MDM profile, a corporate TLS-inspection proxy, or a mis-issued/compromised public CA certificate — can transparently man-in-the-middle every request, reading the Supabase JWT and all patient PII/PHI (home address, DOB, health events) and live video/audio tokens.

**Why it matters here.** Pinning is defense-in-depth and is genuinely optional for many apps, hence Medium not High. But this app streams live in-home audio/video of vulnerable adults and transports health data, which raises the value of MITM resistance well above a typical consumer app.

**Fix.** Pin the leaf or intermediate public key for the backend and Supabase hosts. With `URLSession`, implement `urlSession(_:didReceive:completionHandler:)` and compare the server's SPKI hash against a bundled allow-list (keep a backup pin to survive rotation); LiveKit Cloud certificates are managed by LiveKit, so pin only hosts you control. Apple's `NSPinnedDomains` Info.plist key is a lower-effort alternative for the API/Supabase domains.

---

### M3 — Data-access security depends entirely on unverifiable server-side RLS

**Files:** `NemaraCaregiver/Networking/AppConfig.swift:38` (prod Supabase URL), `:58-60` (committed anon keys); `NemaraCaregiver/Services/NemaraAPIClient.swift:1110-1115` (Realtime subscribes to `patients`, `cameras`, `detectors`, `events` and relies on RLS to filter per-caregiver); `NemaraCaregiver/Services/Analytics.swift:249-251` (client inserts directly into `ui_events`).

**What it is.** The production Supabase project URL and anon (publishable) key are committed to the repo:

```swift
// AppConfig.swift
return URL(string: "https://zgifmvjnggmgzvtnosnu.supabase.co")          // :38
return "sb_publishable_OsfCMOdEIb5gvhRWDyNivg_7GriAmyP"                  // :60
```

Per the skill, an anon/publishable key is **designed** to ship in clients and is **not, by itself, a vulnerability** — *provided* Row-Level Security is enabled and correct on every table. This app leans on that completely: it subscribes to Realtime channels for `patients`, `cameras`, `detectors`, and `events`, and the client writes analytics rows straight into `ui_events`. With the published anon key, anyone can open an authenticated session and issue arbitrary PostgREST / Realtime queries; the *only* thing stopping them from reading or writing other caregivers' patients, cameras, events, and face-embedding data is server-side RLS.

**Why it's flagged despite being "by design."** This is the security crux of the architecture and it cannot be verified from this repo. If **any** replicated or client-writable table (`patients`, `cameras`, `detectors`, `events`, `ui_events`, `face_embeddings`, device tokens) is missing an RLS policy or has an over-permissive one, the committed anon key becomes a full-database read/write primitive against the PHI of every patient in the system — a Critical. The comment at `NemaraAPIClient.swift:1107-1109` asserts RLS filters per-caregiver; that assertion is the entire control and must be proven, not assumed.

**Fix / required verification (backend, out of scope of this repo):**
1. Confirm `ALTER TABLE … ENABLE ROW LEVEL SECURITY` on every table the anon key can reach, including `ui_events` and `face_embeddings`.
2. Confirm each table's policies scope `SELECT`/`INSERT`/`UPDATE`/`DELETE` to `auth.uid()`-owned rows (e.g. caregiver owns the patient, patient owns the camera/detector/event).
3. Confirm the `service_role` key is never exposed to any client and is used only in trusted backend code.
4. Confirm the Realtime publication does not leak rows that RLS would otherwise deny.

---

## Low

### L1 — No jailbreak / runtime-integrity signal for an in-home camera controller

**Files:** none — capability is absent across the codebase (no `jailbreak`/`SecItem`-based integrity checks).

The app can pan/start cameras, open microphones, and stream live audio/video into a vulnerable person's home, yet performs no jailbreak/root or tamper detection. On a compromised device, the Keychain-stored session and LiveKit tokens are exposed and the auth flow can be hooked. Client-side trust is *always* ultimately bypassable, so this is genuinely Low value — but for this threat model it's worth a lightweight signal that can flag a compromised device server-side (e.g. attach a best-effort integrity attestation, or use Apple's **DeviceCheck / App Attest** to bind sensitive actions like Talk/microphone to a verified app instance). Do not rely on a client boolean; verify any attestation server-side.

### L2 — Analytics buffer persisted to disk without an explicit Data Protection class

**Files:** `NemaraCaregiver/Services/Analytics.swift:204-211` (`persist`), `:267-274` (`fileURL` → `ui_events_buffer.json` in Application Support).

The analytics buffer is written with `Data.write(to:options: .atomic)` and contains the caregiver UUID, session id, device model, and full screen-navigation history. It does not set a file protection class, so it inherits the default (`…CompleteUntilFirstUserAuthentication`) rather than `NSFileProtectionComplete`. No credentials or patient PII are stored, so impact is Low, but the file is readable from an unlocked-once device or an unencrypted backup. Add `options: [.atomic, .completeFileProtection]` to the write.

### L3 — Full HTTP response/error bodies (potential PHI) logged in DEBUG builds

**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift:1020-1027` (decode-failure body dump), `:1058-1062` (non-2xx body dump).

On decode failure or any error status, the client prints the entire response body to the console. These bodies can contain patient PII/PHI (names, addresses, event narratives). The logging is wrapped in `#if DEBUG` and is stripped from Release/App Store builds, so production risk is low. However, **TestFlight and ad-hoc builds can be compiled in DEBUG**, and anyone with the device console (or a sysdiagnose) would then see PHI. Recommend redacting bodies even in DEBUG, or gating behind an explicit, off-by-default verbose flag.

---

## Areas reviewed with no findings

- **Secrets / git history** — no `service_role`, `sk_live`/`sk_test`, AWS, GitHub, or private-key material in the tree or history; no `.env`/`.p12`/`.pem`/`.mobileprovision` ever tracked. `.gitignore` covers local config (`Local.xcconfig`).
- **AuthN/AuthZ** — JWT minted and verified server-side; bearer token attached per request (`makeRequest`, `NemaraAPIClient.swift:966-968`); LiveKit identity/role is client-supplied but explicitly re-validated and re-minted server-side (`NemaraAPIClient.swift:864-884`). Realtime auth is refreshed on every token change (`SupabaseAuthService.swift:93-98`).
- **Injection** — no SQL string building, no `WKWebView`/`evaluateJavaScript`, no dynamic code execution. PostgREST/Realtime are parameterized by the SDK.
- **Input validation** — server is treated as the source of truth; client write-through uses typed `Encodable` request bodies, not raw dictionaries; FastAPI validation errors are surfaced (`mapStatus`, `:1049-1082`).
- **Deep links** — beyond M1, the only other handler buffers `event_id`/`patient_id` UUIDs from APNs taps and performs no destructive action without a server fetch (`AppDelegate.swift:84-103`, `DeepLinkRouter.swift`).
- **Dependencies** — only Supabase (`from: 2.44.1`) and LiveKit (`from: 2.0.0`) via SPM, both reputable and floor-pinned. No CocoaPods. (Exact resolved versions live in the gitignored `Package.resolved`; confirm `swift package update` keeps them current and watch for advisories.)

---

## Prioritized recommendations

1. **Verify backend RLS (M3)** — the whole model depends on it; prove every client-reachable table is locked to `auth.uid()`. *(Backend, out of this repo.)*
2. **Migrate the password-reset redirect to a Universal Link (M1)** and keep PKCE.
3. **Add certificate/public-key pinning for the backend + Supabase hosts (M2).**
4. **Harden at-rest/diagnostic data (L2, L3)** — file protection on the analytics buffer; stop dumping PHI-bearing bodies in DEBUG.
5. **Consider App Attest / DeviceCheck (L1)** to bind sensitive camera/mic actions to a verified app instance.

*Audit performed statically against the repository at commit `398b343`. No app code was modified; this report is the only added file.*
