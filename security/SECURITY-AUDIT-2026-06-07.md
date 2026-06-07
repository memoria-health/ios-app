# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-06-07
**Scope:** Static source review of `nemara-caregiver-app` (native iOS / SwiftUI, Swift 6).
**Methodology:** [vibe-security](https://github.com/raroque/vibe-security-skill) skill, mobile-prioritized (secrets, ATS, token storage, certificate pinning, client-side trust), plus authn/authz, injection, dependencies, deep links, and AI/LLM usage.
**Constraints:** Static analysis only. No access to the `nemara-backend` source, live services, or secrets. Findings about server-side enforcement are flagged as *requires backend verification* rather than asserted.

---

## Executive Summary

This is a **well-architected codebase with strong security fundamentals**. The most common classes of "vibe-coded" vulnerability are **absent**:

- **No hardcoded secrets.** The only embedded credentials are Supabase **publishable/anon keys** (`sb_publishable_*`) and **public project/backend URLs** — all designed to ship in clients. No `service_role` key, LiveKit API secret, AI/LLM key, DB connection string, or signing secret appears in source or git history (history scanned, clean).
- **Tokens are stored in the iOS Keychain**, not `UserDefaults` (session managed by the Supabase Swift SDK's Keychain-backed storage). `UserDefaults` holds only non-sensitive UI state.
- **All third-party calls are backend-proxied.** LiveKit access tokens and media-server URLs are minted server-side per request (`POST /v1/livekit/token`); AI/LLM inference (Gemini) runs entirely on the backend. No AI keys or media secrets exist client-side.
- **App Transport Security is intact for production.** The only ATS relaxation is `NSAllowsLocalNetworking`, which permits plaintext only to non-routable/local addresses; routable HTTPS endpoints retain full TLS enforcement.
- Every authenticated request attaches the Supabase JWT as a `Bearer` token; the app defers authorization to backend RLS + JWT validation.

No **Critical** or **High** severity issues were found in the client. The findings below are **defense-in-depth** improvements appropriate for an app that handles **live video and PII of vulnerable (elderly) people in their homes**, plus items that depend on server-side enforcement that should be confirmed.

| # | Severity | Title | Location |
|---|----------|-------|----------|
| 1 | Medium | No TLS certificate / public-key pinning | `NemaraAPIClient.swift`, SDK defaults |
| 2 | Low | Password-reset deep link uses a hijackable custom URL scheme | `NemaraCaregiverApp.swift:113`, `Info.plist` |
| 3 | Low | Client-controlled LiveKit `room`/`role` — access hinges on backend authz | `NemaraAPIClient.swift:862` |
| 4 | Low | DEBUG logging prints full HTTP response bodies (PII) | `NemaraAPIClient.swift:1019` |
| 5 | Low | No jailbreak / runtime-integrity detection | (app-wide) |
| 6 | Info | ATS local-networking exception (correctly scoped) | `Info.plist`, `project.yml` |

---

## Findings

### Medium

#### 1. No TLS certificate or public-key pinning
**Files:** `NemaraCaregiver/Services/NemaraAPIClient.swift:107` (`URLSession.shared`), Supabase & LiveKit SDK clients (`SupabaseAuthService.swift:84`, `LiveKitClient.swift`).

The app uses the default `URLSession` and SDK trust evaluation with no certificate or public-key pinning. Every request carries a Supabase access JWT (`NemaraAPIClient.swift:965`), and the app streams **live in-home video/audio of patients** and transfers PII (names, addresses, DOB, health-relevant detection narratives).

**Why it matters:** An attacker who can get a CA trusted on the device — a malicious/MDM configuration profile, a corporate TLS-inspection proxy, or a user tricked into installing a root cert — can transparently MitM all traffic: read/replay the bearer JWT (full account access until expiry), harvest PII, and view patient video. The default trust store makes this a realistic threat for a sensitive health-adjacent monitoring app, even though baseline ATS already requires TLS.

**Fix:** Pin the backend (Railway) and Supabase certificates/public keys. With iOS 14+ this can be done declaratively without code via Info.plist `NSPinnedDomains`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSPinnedDomains</key>
  <dict>
    <key>nemara-backend-production.up.railway.app</key>
    <dict>
      <key>NSPinnedCAIdentities</key>
      <array>
        <dict><key>SPKI-SHA256-BASE64</key><string><!-- pinned key hash --></string></dict>
      </array>
    </dict>
    <!-- repeat for *.supabase.co and the LiveKit media host -->
  </dict>
</dict>
```

Pin to an intermediate CA's SPKI (not a leaf) to survive cert rotation, and ship at least one backup pin. Alternatively implement a `URLSessionDelegate` `urlSession(_:didReceive:completionHandler:)` evaluator. (Note: LiveKit's media-server host is dynamic/returned at runtime, so pinning there may require an SDK transport hook or an allowlist of LiveKit Cloud SPKIs.)

---

### Low

#### 2. Password-reset deep link uses a hijackable custom URL scheme
**Files:** `NemaraCaregiver/App/NemaraCaregiverApp.swift:113` (`handleIncomingURL`), `Info.plist` `CFBundleURLSchemes = ["nemara"]`, `AppConfig.swift:67`.

The recovery flow routes `nemara://reset-password?code=…` from the password-reset email into `exchangeRecoveryCode` (`SupabaseAuthService.swift:174`). Custom URL schemes are **not exclusive** on iOS — any installed app may register `nemara://`, and the OS does not guarantee which app receives the link. A malicious app could attempt to intercept the recovery `code`.

**Why it matters (and why it's only Low):** If the code alone were sufficient to mint a session, interception would mean account takeover. In practice the Supabase Swift SDK uses the **PKCE** flow for `resetPasswordForEmail` + `exchangeCodeForSession`: the `code_verifier` is generated and stored in *this* app's Keychain, so an intercepting app that captures the `code` cannot complete the exchange without the verifier. That mitigation is what keeps this Low rather than High — but custom-scheme interception is still a fragile foundation for an auth callback.

**Fix:** Migrate the auth callback (and any future sensitive deep links) from a custom scheme to **Universal Links** (`applinks:` + an `apple-app-site-association` file on the domain). Universal Links are cryptographically bound to the verified domain and cannot be claimed by another app:

```xml
<!-- entitlements -->
<key>com.apple.developer.associated-domains</key>
<array><string>applinks:nemara.app</string></array>
```

Confirm PKCE is in effect on the SDK client and keep the custom scheme only as a non-sensitive fallback.

#### 3. Client-controlled LiveKit `room` and `role` — camera access depends entirely on backend authorization
**File:** `NemaraCaregiver/Services/NemaraAPIClient.swift:862` (`mintToken`), `Models/LiveKit.swift:12`.

The client constructs the token request with an attacker-controllable `room: "patient_<pid>"` (the patient UUID comes from the view) and `role: "viewer" | "broadcaster"`, then POSTs it to `/v1/livekit/token`. A code comment notes the server "validates the prefix and re-mints," but the client cannot enforce that the authenticated caregiver actually **owns** the target patient or is entitled to the requested role.

**Why it matters:** Per the core "never trust the client" principle, if the backend mints a token for any `patient_<pid>` room presented by any authenticated caregiver without verifying ownership, this is an IDOR allowing one caregiver to view/Talk into **another family's in-home cameras** by substituting a patient UUID. This is the single highest-impact scenario in the app — but it is **not exploitable from the client alone and cannot be confirmed without the backend**.

**Fix (backend — flagged for verification):** In the `/v1/livekit/token` handler, resolve the caregiver from the JWT, verify the requested patient belongs to that caregiver (DB/RLS check), and derive the `room` and the allowed `role`/grants **server-side** from that authorization — never echo the client's requested room/role into the minted token. The same ownership check applies to `talk/start`, `talk/end`, `record-clip`, and the per-patient REST routes.

#### 4. DEBUG builds log full HTTP response bodies (potential PII in device logs)
**File:** `NemaraCaregiver/Services/NemaraAPIClient.swift:1019-1023` and `1057-1059`.

On decode failure and on non-2xx responses, the client prints the raw response body to the console. Response bodies contain patient PII and detection narratives. This is correctly gated behind `#if DEBUG`, so it does not reach App Store builds — hence Info/Low. Bearer tokens and LiveKit tokens are *not* logged (verified: `LiveKitClient.swift:187` logs the URL only, never the token).

**Fix:** Keep these strictly `#if DEBUG`; consider redacting or truncating bodies even in debug, and route through a logging layer that can be centrally disabled, to avoid PII landing in device/Console logs during field testing on real patient data.

#### 5. No jailbreak / runtime-integrity detection
**Scope:** app-wide. The app stores session tokens in the Keychain and renders sensitive video. On a jailbroken device, Keychain protections weaken and tooling (e.g., Frida) can hook the process.

**Why it's Low:** The app does **not** rely on a client-side boolean for any trust decision (good — no spoofable biometric gate), so the impact is limited to a compromised device, which is inherently outside the app's full control. This is purely defense-in-depth.

**Fix (optional, for the threat model of a health-monitoring app):** Add lightweight jailbreak heuristics (suspicious paths, `fork()` viability, sandbox-escape checks) and degrade gracefully (warn / require re-auth) rather than hard-blocking. Treat as advisory, not a hard control.

---

### Informational / Verified-Good

#### 6. ATS local-networking exception is correctly scoped
**Files:** `Info.plist` and `project.yml` set only `NSAppTransportSecurity → NSAllowsLocalNetworking = true`.

This permits cleartext HTTP **only** to local/non-routable destinations (loopback, `*.local`, RFC1918) used by the dev stack (`http://sunnys-macbook-air.local:8002`, local Supabase on `:54341`). It does **not** introduce `NSAllowsArbitraryLoads` and does **not** weaken TLS for production hosts (Railway/Supabase over HTTPS). This is the minimal, recommended approach — **no change required**. Noted only to document that ATS was reviewed.

#### Positive observations (no action needed)
- **Secrets:** No hardcoded secret keys anywhere; git history scanned clean. Embedded `sb_publishable_*` anon keys and public URLs are safe to ship by design (`AppConfig.swift` comments correctly identify them).
- **Token storage:** Sessions in Keychain via the Supabase SDK; `UserDefaults` used only for `camerasEverOnline` and an onboarding flag — non-sensitive.
- **AI/LLM:** All inference is server-side (`/v1/detectors/infer`, Gemini on the backend). No client-side AI keys; no prompt construction or unsafe LLM-output rendering on device.
- **Injection:** No SQL/shell construction on the client. UUIDs are parsed via `UUID(uuidString:)` (`AppDelegate.swift:90`, `NemaraAPIClient.swift:1398`) before use; path components are server-validated IDs. Hand-rolled multipart bodies (`NemaraAPIClient.swift:496-538`) use fresh per-request boundaries and fixed field names — no user-controlled header injection.
- **Dependencies:** Only Supabase (`from: 2.44.1`) and LiveKit (`from: 2.0.0`) via SwiftPM, both reputable and reasonably current; no `Package.resolved` is committed, so resolve against pinned, audited versions in CI.
- **Auth flows:** Password-reset email enumeration is intentionally avoided (`SupabaseAuthService.swift:156` comment); sign-up enforces strong password rules client-side (still validated server-side by Supabase).

---

## Prioritized Remediation Summary

1. **Add certificate/public-key pinning (Medium).** Highest-value client hardening for an app carrying bearer tokens and live patient video; declarative `NSPinnedDomains` is low-effort.
2. **Verify backend authorization for `/v1/livekit/token` and all per-patient routes (Low client / potentially High server).** Confirm the JWT's caregiver owns the requested patient and that `room`/`role` are derived server-side, not trusted from the request body. This is the most impactful issue *if* the backend does not already enforce it — verify against `nemara-backend`.
3. **Move the password-reset callback to Universal Links (Low).** Removes custom-scheme hijack exposure; confirm PKCE remains enabled.
4. **Keep response-body logging DEBUG-only and consider PII redaction (Low).**
5. **Optionally add jailbreak/runtime-integrity heuristics (Low, advisory).**

*No secrets require rotation based on this review.*
</content>
</invoke>
