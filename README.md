# Nemara · caregiver iOS app

SwiftUI app for caregivers of patients in homes with wall-mounted
phones acting as cameras + microphones. Talks live to
[`nemara-backend`](../nemara-backend) — no in-app mock data.

## Quick start

```bash
brew install xcodegen
cd nemara-caregiver-app
xcodegen generate                  # produces NemaraCaregiver.xcodeproj
open NemaraCaregiver.xcodeproj
```

The bundled scheme env vars point at the local-dev stack out of the
box:

```
NEMARA_BACKEND_URL=http://127.0.0.1:8002      # simulator
SUPABASE_URL=http://127.0.0.1:54341           # local Supabase
SUPABASE_ANON_KEY=<the well-known local key>
```

To run on a physical iPhone, override `NEMARA_BACKEND_URL` and
`SUPABASE_URL` in Xcode → Edit Scheme → Run → Environment Variables
with your Mac's LAN address (e.g. `http://10.0.0.245:8002`).

Sign-in uses real Supabase auth. Seed `jane@patel.co` /
`Mar9aret!2024` exists after running `make db-reset` in
nemara-backend.

## What the app does

- **Home tab** — patient roster, live state (calm / critical /
  offline), status line, last-event time, battery %. Updates via
  Supabase Realtime when wall phones / detector pipeline push.
- **Patient → Live tab** — *(Phase 1, not wired yet)* will subscribe
  to the patient's LiveKit room and render the active camera feed.
- **Patient → Events tab** — review fired events; PATCH `opened` /
  `reviewed` / `review_choice` to mark caregiver actions.
- **Patient → Settings tab** — tune detector sensitivity, toggle
  detectors, pause/unpause monitoring, **pair a new wall phone**
  (mints a 6-digit code via `POST /v1/patients/<id>/cameras/pairing-code`,
  shows it in a sheet with countdown).
- **App Settings tab** — caregiver profile, notification toggles,
  sign-out, privacy / contact links.

## File layout

```
nemara-caregiver-app/
├── project.yml                            # xcodegen, includes Supabase SDK
├── NemaraCaregiver/
│   ├── App/
│   │   ├── NemaraCaregiverApp.swift       # @main + environment
│   │   ├── RootView.swift                 # signed-out vs signed-in gate
│   │   ├── MainTabView.swift              # Home / Settings tabs (iOS 26 Liquid Glass)
│   │   └── AppEnvironment.swift           # live() factory wires auth + api
│   ├── Networking/
│   │   ├── APIError.swift
│   │   ├── AppConfig.swift                # env-driven URLs + DEBUG defaults
│   │   └── JSONCoders.swift               # multi-format date strategy
│   ├── Services/
│   │   ├── SupabaseAuthService.swift      # signUp / signIn / restoreSession
│   │   └── NemaraAPIClient.swift          # CRUD + Realtime + pairing
│   ├── Models/                            # Caregiver, Patient, Camera, Detector, DetectionEvent
│   ├── DesignSystem/
│   │   ├── Tokens/                        # Color / Font / Radius / Spacing
│   │   ├── Components/                    # NemaraMark, NemaraButton, NemaraCard, …
│   │   └── Fonts/                         # Fraunces / Inter / JetBrains .ttf
│   └── Features/
│       ├── Auth/                          # Welcome, SignUp, Login
│       ├── Onboarding/                    # NewPatient
│       ├── Home/                          # Roster, EmptyRoster, PatientRow
│       ├── AppSettings/                   # caregiver settings, daily-summary preview
│       ├── Patient/
│       │   ├── PatientShell.swift         # pinned PHeader + native iOS 26 TabView
│       │   ├── Live/PatientLiveView.swift # Phase 1: LiveKit subscriber
│       │   ├── Events/                    # EventCard, EventDetailView, EventReviewView
│       │   └── Settings/
│       │       ├── PatientSettingsView.swift  # detector list, monitoring toggle, "Pair a new phone"
│       │       ├── DetectorRow.swift
│       │       ├── AddDetectorView.swift
│       │       └── PairingCodeSheet.swift # 6-digit code + countdown
│       └── Feedback/
└── NemaraCaregiverTests/
    └── Models/                            # 29 Codable round-trip tests
```

## Pairing flow

1. Settings tab → patient → "Pair a new phone".
2. Alert prompts for a room name (default "Camera N"; user types
   "Kitchen" or whatever). Tap *Generate code*.
3. Backend mints a 6-digit code + creates a placeholder `cameras` row
   with `online=false`. The sheet displays the code + a live
   countdown to expiry (10 minutes).
4. User picks up the wall phone (running `nemara-camera-app` in
   unpaired state) and enters the code.
5. Wall phone POSTs `/v1/cameras/pair`, receives a long-lived
   `api_key`, starts publishing to LiveKit + uploading clips.
6. Realtime updates the caregiver app's camera list (`online`
   flips to true on the first heartbeat). The sheet stays open
   until the user dismisses it.

## Conventions

- **iOS 18+** · uses `@Observable`, `NavigationStack`, modern SwiftUI.
- **Swift 6** with strict concurrency.
- **Light mode only** — `.preferredColorScheme(.light)` at the root.
- **No raw colors or fonts** — go through `NemaraColor` / `NemaraFont`.
- **One semantic responsibility per file** — refactor mega-files
  when touching them.
- **Snake_case wire** — Codable models use explicit `CodingKeys`
  (no `convertFromSnakeCase` — silently collides with explicit keys
  per range learnings).

## Sister repos

- [`nemara-backend`](../nemara-backend) — FastAPI; serves the CRUD
  surface, mints LiveKit tokens, runs the detector pipeline.
- [`nemara-camera-app`](../nemara-camera-app) — wall-phone iOS app;
  pairs against this caregiver app's "Pair a new phone" flow.
