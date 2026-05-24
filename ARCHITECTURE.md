# nemara-caregiver-app · architecture

How the caregiver app is laid out, what conventions are enforced, and how the major flows wire together.

## File layout

```
nemara-caregiver-app/
├── project.yml                            # xcodegen — Apple Team, capabilities, deps, APNs config
├── NemaraCaregiver/
│   ├── App/
│   │   ├── NemaraCaregiverApp.swift       # @main + APNs registration + environment injection
│   │   ├── RootView.swift                 # signed-out vs signed-in gate, deep-link router
│   │   ├── MainTabView.swift              # Home / AppSettings (iOS 26 Liquid Glass)
│   │   └── AppEnvironment.swift           # live() factory wires auth + api + liveKit
│   ├── Networking/
│   │   ├── APIError.swift                 # 401/403/404/409/422 typed errors
│   │   ├── AppConfig.swift                # env-driven URLs + DEBUG defaults
│   │   └── JSONCoders.swift               # multi-format date strategy + dateOnly helpers
│   ├── Services/
│   │   ├── SupabaseAuthService.swift      # signUp / signIn / restoreSession
│   │   ├── LiveKitClient.swift            # Observable wrapper around LiveKit Room (single source of truth for connectivity — see below)
│   │   └── NemaraAPIClient.swift          # CRUD + Realtime + pairing + LiveKit token + Talk + APNs token registration + clip + photo
│   ├── Models/                            # Caregiver, Patient, Camera, Detector, DetectionEvent
│   ├── DesignSystem/
│   │   ├── Tokens/                        # NemaraColor / NemaraFont / NemaraRadius / NemaraSpacing
│   │   ├── Components/                    # NemaraMark, NemaraButton, NemaraCard, NemaraWaveform, NemaraChip, NemaraAvatar, …
│   │   └── Fonts/                         # Fraunces / Inter / JetBrains Mono .ttf
│   └── Features/
│       ├── Auth/                          # Welcome, SignUp, Login
│       ├── Onboarding/                    # NewPatient (with photo upload)
│       ├── Home/                          # Roster, EmptyRoster, PatientRow, pull-to-refresh
│       ├── AppSettings/                   # caregiver settings, daily-summary preview, notification toggles
│       ├── Patient/
│       │   ├── PatientShell.swift         # pinned PHeader + native iOS 26 TabView
│       │   ├── Live/
│       │   │   ├── PatientLiveView.swift  # carousel + phone-call + waveform + full-screen
│       │   │   ├── LiveKitVideoView.swift # SwiftUI bridge to LiveKit VideoView
│       │   │   └── CallButton.swift       # 3-state phone button (idle/connecting/active)
│       │   ├── Events/
│       │   │   ├── EventCard.swift
│       │   │   ├── EventDetailView.swift  # narrative + clip player (VideoPlayer)
│       │   │   └── EventReviewView.swift  # 3-option review + free-text notes
│       │   └── Settings/
│       │       ├── PatientSettingsView.swift   # detector list, monitoring toggle, photo upload, "Pair a new wall phone"
│       │       ├── DetectorRow.swift
│       │       ├── AddDetectorView.swift
│       │       └── PairingCodeSheet.swift # 6-digit code + countdown
│       └── Feedback/
└── NemaraCaregiverTests/
    └── Models/                            # Codable round-trip tests
```

## Connectivity model (single source of truth)

`LiveKitClient` exposes one predicate that every UI consumer should read instead of poking at raw signals:

```swift
enum CameraConnectivity {
    case unpaired   // camera has no livekit_identity yet
    case roomDown   // our LiveKit room isn't connected at all
    case offline    // backend says the camera isn't in the room
    case joining    // backend says joined, no video track yet (transient)
    case live       // video flowing — fully live
}

func connectivity(of cam: Camera) -> CameraConnectivity { ... }
func isLive(_ cam: Camera) -> Bool { connectivity(of: cam) == .live }
```

The fusion is across **four** signals that can disagree during reconnects:

- Room state (we might not be connected at all).
- Backend `cam.online` (lags 1–2s via webhook + Realtime, but persists across app restarts).
- Subscribed video track presence (real-time SDK).
- Paired-but-no-identity rows (placeholders before first claim).

Consumers (`statePill`, `cameraStatusDot`, call-button gates, full-screen entry) all switch on the enum. Adding a new "what counts as live" rule means touching exactly one function.

> Intentional exceptions: `onlineCameras` filter and `PatientSettingsView`'s ONLINE/OFFLINE pill stay on raw `cam.online` because they run when the Live tab isn't even open — `connectivity` would always say `.roomDown` and be meaningless.

## Realtime + API client

`NemaraAPIClient` (a single `@Observable` class) owns:

- All HTTP CRUD against the backend.
- Supabase Realtime channel subscriptions for `patients`, `cameras`, `detectors`, `events` — wires upserts/deletes into in-memory dictionaries keyed by patient id.
- Pairing-code minting, LiveKit token minting (viewer + broadcaster roles).
- Talk session start/end/transfer.
- APNs device-token registration.
- Patient photo upload (multipart) + signed-URL fetch.
- Event clip signed-URL fetch.
- `bootstrap()` (first load) and `refresh()` (pull-to-refresh) — the latter reloads without re-opening Realtime channels.

## Audio routing (Live tab)

Caregiver hears wall-phone audio **only during a call**, mirroring what the wall phone does for caregiver audio. The gate runs through `LiveKitClient.setRemoteAudioPlayback(enabledFor:)`:

- Each subscribed `RemoteAudioTrack` defaults to `volume = 0.0` (silent speaker, track still decodes).
- On `startCall`: volume flips to `1.0` for the target camera, `0.0` for everyone else.
- On `endCall`: all volumes back to `0.0`.

The waveform is driven by `AudioManager.shared.add(remoteAudioRenderer:)` — the combined-remote PCM tap — and only pushes peaks into `audioLevels[activeCallIdentity]`. No active call → empty levels → flat waveform.

Why volume-gating instead of `publication.set(enabled:)`: toggling subscription churns the SDK's audio engine in a way the per-buffer renderer didn't recover from. Continuous decode costs ~20kbps per camera — acceptable for the reliability gain.

## Push notifications (APNs)

`NemaraCaregiverApp.swift`:

1. Requests notification authorization on first launch.
2. Registers with APNs on every cold start.
3. POSTs the device token to `/v1/me/devices` (idempotent on token).

On tap of a notification: `RootView` reads the payload's `event_id` + `patient_id` and routes to that patient's Events tab with the event detail opened.

## Conventions

- **iOS 18+** target.
- **Swift 6** strict concurrency.
- **Light mode only** — `.preferredColorScheme(.light)` at the root.
- **No raw colors or fonts** — go through `NemaraColor` / `NemaraFont`. No hex literals, no `Color.red`.
- **One semantic responsibility per file** — refactor mega-files when touching them.
- **No em dashes anywhere** — chat output, copy, code comments. Use commas, periods, colons, or sentence breaks.
- **Snake_case wire** — Codable models use explicit `CodingKeys` (no `convertFromSnakeCase` — silently collides with explicit keys, learned the hard way in range).
- **Module-level imports.** No lazy imports inside function bodies.
- **No trivial tests.** Codable round-trips, integration paths, behaviors the type system doesn't already prove.

## Sister repos

- [`nemara-backend`](../nemara-backend)
- [`nemara-camera-app`](../nemara-camera-app)
