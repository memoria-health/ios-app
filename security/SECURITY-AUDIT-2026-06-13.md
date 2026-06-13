# Security Audit — Nemara Caregiver iOS App

**Date:** 2026-06-13
**Auditor:** Automated static review (vibe-security methodology)
**Scope:** `nemara-caregiver-app` — native iOS / SwiftUI caregiver app (Swift 6).
**Commit audited:** `9b4d7c4` (`chore(caregiver): version 1.1 (23)`)
**Method:** Static source review only. No live services, secrets, or network
access were used. Backend (`nemara-backend`) and Supabase RLS policies are
**out of scope** (separate repo) and could not be verified — several findings
below depend on server-side controls that must be confirmed there.

---

## Executive Summary

This is a **well-architected, security-conscious codebase**. The fundamentals
that are most often broken in rapidly-built apps are handled correctly here:

- **No third-party secret keys in the client.** All AI/LLM calls, LiveKit token
  minting, and privileged Supabase operations go through the app's own backend.
  The app never holds an OpenAI/Anthropic key, a LiveKit API secret, or a
  Supabase `service_role` key.
- **Auth tokens are stored in the Keychain** (via the Supabase Swift SDK), not
  in `UserDefaults`. `UserDefaults` is used only for non-sensitive UI flags
  (camera "ever online" UUIDs, an onboarding bool).
- **App Transport Security is not globally disabled.** The only ATS key is
  `NSAllowsLocalNetworking` (for LAN device setup during development); TLS is
  still enforced for all routable/production hosts.
- **LiveKit access is server-scoped.** The app requests a per-room, role-scoped
  (`viewer`/`broadcaster`) JWT from the backend; URL and token are minted
  server-side per call.
- **Authorization is enforced server-side.** The client carries a Supabase
  Bearer JWT; every CRUD path is a backend endpoint, and Realtime relies on
  per-caregiver RLS. No client-side trust of price/role/ownership was found.

**No Critical or High severity issues were identified.** The findings below are
hardening opportunities. The single most important one is the **absence of TLS
certificate pinning** (Medium) for an app that transmits auth tokens and live
audio/video of vulnerable adults. The remaining items are Low / Informational.

| # | Severity | Title |
|---|----------|-------|
| 1 | Medium | No TLS certificate pinning on backend / Supabase / LiveKit traffic |
| 2 | Low | Production Supabase URL + anon key hardcoded — security rests entirely on (unverified) RLS |
| 3 | Low | Weak client-side password policy (length-only, ≥ 8) |
| 4 | Low | Demo/seed account credentials committed in `README.md` |
| 5 | Info | Auth callback uses a hijackable custom URL scheme instead of a Universal Link |
| 6 | Info | DEBUG-only logging prints full HTTP response bodies (may contain PII) |

---

## Findings

### Medium

#### 1. No TLS certificate pinning on backend / Supabase / LiveKit traffic

**Files:**
- `NemaraCaregiver/Services/NemaraAPIClient.swift:102` (`session: URLSession = .shared`) and `:1030` (`session.data(for:)`)
- `NemaraCaregiver/Services/SupabaseAuthService.swift:86` (`SupabaseClient(...)` default URLSession)
- `NemaraCaregiver/Services/LiveKitClient.swift:195` (`room.connect(url:token:)`)

**Why it's exploitable.** Every network call uses the platform default server
trust evaluation (any CA in the system/user trust store is accepted). The app
carries a Supabase access JWT in the `Authorization: Bearer …` header
(`NemaraAPIClient.swift:964-966`) and streams live audio/video of the patient.
On a hostile network — a user who installs a malicious enterprise/MDM root, a
compromised Wi-Fi with a rogue CA, or a corporate TLS-intercepting proxy — an
attacker positioned in the middle can present a valid-looking certificate,
decrypt the TLS session, and capture the bearer token (full account takeover for
its lifetime) plus PII (patient names, addresses, health events) and the live
camera feed. For an eldercare/health context with vulnerable subjects, the
impact is high even though exploitation requires a MITM position.

**Fix.** Pin the leaf or intermediate public key (SPKI) for the backend and
Supabase hosts. Use a custom `URLSessionDelegate` performing
`SecTrustEvaluateWithError` + SPKI comparison, and inject that session into
`NemaraAPIClient` and the Supabase client. Keep a backup pin and a rotation plan
to avoid bricking the app on cert rotation.

```swift
// Before — default trust, any installed CA is accepted
init(... session: URLSession = .shared) { self.session = session }

// After — pinned session injected at composition (AppEnvironment.live())
final class SPKIPinningDelegate: NSObject, URLSessionDelegate {
    let pinnedSPKIHashes: Set<Data>   // backup pin included
    func urlSession(_ s: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let trust = challenge.protectionSpace.serverTrust,
              SecTrustEvaluateWithError(trust, nil),
              let spki = currentServerSPKIHash(trust),         // extract + SHA256(SPKI)
              pinnedSPKIHashes.contains(spki)
        else { return completionHandler(.cancelAuthenticationChallenge, nil) }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
let session = URLSession(configuration: .default,
                         delegate: SPKIPinningDelegate(pinnedSPKIHashes: pins),
                         delegateQueue: nil)
```

> Note: LiveKit media is DTLS/SRTP-encrypted end-to-end and the signaling URL is
> server-minted, so pinning the REST/Supabase paths is the priority.

---

### Low

#### 2. Production Supabase URL + anon key hardcoded — all protection rests on (unverified) RLS

**File:** `NemaraCaregiver/Networking/AppConfig.swift:38` (prod URL `https://zgifmvjnggmgzvtnosnu.supabase.co`), `:58` and `:60` (publishable/anon keys).

**Assessment.** This is **by design and acceptable**: Supabase anon /
"publishable" keys are intended to ship in clients (the skill's
`secrets-and-env.md` explicitly lists the Supabase anon key as client-safe).
There is **no** `service_role` key, database connection string, or signing
secret in the bundle — those would be Critical, and none are present.

**Why it still warrants a note.** Because the anon key is embedded and the app
talks to Supabase directly (Auth + Realtime + PostgREST), the **only** thing
standing between any user (or anyone who extracts the key from the App Store
binary) and other caregivers' rows is **Row-Level Security**. RLS policies live
in the backend repo and could not be verified here. If RLS is missing or
permissive on any table exposed to Realtime/PostgREST
(`patients`, `cameras`, `detectors`, `events`, `face_embeddings`), this silently
becomes a Critical broken-access-control hole.

**Fix / action.** Confirm, in `nemara-backend` / Supabase, that:
- RLS is **enabled** on every table and the default is deny.
- Every policy scopes rows to `auth.uid()` (the signed-in caregiver), for
  `SELECT`/`INSERT`/`UPDATE`/`DELETE` **and** the Realtime publication.
- The anon role cannot read service tables (device tokens, face embeddings,
  pairing codes) beyond the owning caregiver.

---

#### 3. Weak client-side password policy (length-only)

**File:** `NemaraCaregiver/Features/Auth/SignUpView.swift:17-18`

```swift
private var passwordValid: Bool {
    password.count >= 8
}
```

**Why it matters.** The only client gate is length ≥ 8, so `"12345678"` passes.
Weak passwords on a health/eldercare account increase credential-stuffing and
guessing risk. (Server-side Supabase password policy may add constraints, but it
isn't enforced or visible here.)

**Fix.** Require a stronger rule client-side and rely on the Supabase project's
password policy as the authority. The app already renders a
`NemaraPasswordChecklist` — wire the validity check to the same rules
(length + character-class / breached-password check).

---

#### 4. Demo/seed account credentials committed in `README.md`

**File:** `README.md:62-63`

```
- Email: jane@patel.co
- Password: Mar9aret!2024
```

**Why it matters.** These are local-seed credentials (created by
`make fresh-seed`), so risk is low today. It becomes a real problem if the same
seed is ever applied to a shared/staging/production Supabase project — the
password is then a publicly-known credential for a live account.

**Fix.** Keep seed credentials strictly local; never run the demo seed against a
shared environment, and consider generating a random password at seed time
rather than committing a fixed one.

---

### Informational

#### 5. Auth callback uses a hijackable custom URL scheme

**Files:** `project.yml` (`CFBundleURLSchemes: [nemara]`), `Resources/Info.plist:21-31`,
`App/NemaraCaregiverApp.swift:113-128` (handles `nemara://reset-password?code=…`).

Custom URL schemes are first-come/any-app — a malicious app on the device can
register `nemara://` and intercept the open. Impact here is limited: the handler
only presents `ResetPasswordView`, and the recovery `code` is exchanged
**server-side and single-use** (`SupabaseAuthService.exchangeRecoveryCode`), and
is delivered to the user's own email. No token or destructive action is exposed
by the scheme alone. **Recommendation:** migrate the password-reset callback to
a **Universal Link** (Associated Domains) so iOS guarantees only this app
handles the link.

#### 6. DEBUG-only logging prints full HTTP response bodies

**File:** `NemaraCaregiver/Services/NemaraAPIClient.swift:1018-1024` and `:1056-1060`

On decode/HTTP errors the client prints the raw response body (which can include
patient PII) to the console. This is gated behind `#if DEBUG`, so it is **not**
present in App Store / TestFlight release builds — informational only. Just
ensure DEBUG builds are never distributed and avoid logging the `Authorization`
header (it is currently never logged — good).

---

## What was checked and found clean

- **Secrets scan** (`sk_live`/`sk_test`/`service_role`/JWT/`AKIA`/private keys)
  across tracked files and full git history — no privileged secrets committed.
  (The one "password" string match, `NemaraField.swift:149`, is inside a
  `#if DEBUG #Preview` block and is stripped from release builds.)
- **Token storage** — Keychain via Supabase SDK; `UserDefaults` holds only
  non-sensitive flags.
- **ATS** — not globally weakened; production hosts use HTTPS.
- **AI/LLM** — `inferDetector` (`POST /v1/detectors/infer`) and all LLM use is
  proxied through the backend; no model keys in the client. Free-text detector
  prompts are passed to the server (prompt-handling is a backend concern).
- **Injection / mass assignment** — the client only emits typed `Codable`
  request bodies; there is no client-side SQL/ORM and no raw query construction.
- **Deep links** — parameters are not used for destructive actions; the reset
  code is server-validated and single-use.
- **Network surface** — only `NemaraAPIClient` performs HTTP; there are no
  direct plaintext calls to local camera devices from the app (device discovery
  and provisioning are brokered by the backend).

---

## Prioritized Recommendations

1. **(Medium) Add TLS certificate/SPKI pinning** to the backend and Supabase
   sessions, with a backup pin and rotation plan. Highest-value hardening for a
   health app carrying bearer tokens and PII.
2. **(Low, verify externally) Confirm Supabase RLS** is enabled and
   `auth.uid()`-scoped on every table exposed via PostgREST/Realtime — the
   embedded anon key makes RLS the sole access-control boundary.
3. **(Low) Strengthen the signup password rule** beyond length-only and lean on
   the Supabase password policy.
4. **(Low) Stop shipping fixed seed credentials**; keep them local-only.
5. **(Info) Move the password-reset callback to a Universal Link.**
