# Nemara · caregiver iOS app

SwiftUI app for caregivers of patients in homes with wall-mounted phones acting as cameras + microphones. Companion to the (future) Nemara detection backend.

This is the **v0 UI scaffold**: every screen renders, navigation works end-to-end, but the data is in-memory mock and auth is a no-op. Phase 2 swaps in real Supabase auth + a backend client.

## Quick start

```bash
brew install xcodegen          # one-time
cd nemara-caregiver-app
xcodegen generate              # produces NemaraCaregiver.xcodeproj
open NemaraCaregiver.xcodeproj # then ⌘R to run in the Simulator
```

The app launches in-memory mock mode. Sign-up / log-in accept anything and drop you into an empty roster (or a roster with Margaret pre-populated, depending on which mock entry point you tap).

## Where things live

```
nemara-caregiver-app/
├── project.yml                  # xcodegen, the single source of truth
├── NemaraCaregiver/
│   ├── App/                     # @main entry, root navigation, env
│   ├── DesignSystem/
│   │   ├── Tokens/              # Color / Font / Radius / Spacing
│   │   ├── Components/          # NemaraMark, NemaraButton, NemaraCard, …
│   │   └── Fonts/               # Fraunces / Inter / JetBrains .ttf
│   ├── Models/                  # Caregiver, Patient, Camera, Detector, Event
│   ├── Services/                # AuthService base class
│   ├── Features/
│   │   ├── Auth/                # Welcome, SignUp, Login
│   │   ├── Onboarding/          # NewPatient
│   │   ├── Home/                # Roster, EmptyRoster
│   │   ├── AppSettings/         # caregiver-level settings, daily summary
│   │   ├── Patient/             # Live / Events / Settings sub-tabs
│   │   └── Feedback/            # founders contact + form + share
│   ├── Mocks/                   # ALL in-memory data — delete to ship real
│   └── Resources/Assets.xcassets/
└── README.md
```

## Design source

The design system lives at `claude.ai/design` (handoff bundle imported into `/tmp/nemara_design/` during initial implementation). Tokens, type specs, geometry, and component patterns in `Resources/Assets.xcassets/Colors/` and `DesignSystem/` match the bundle 1:1 — never invent a hex value at the call site.

## Mock data containment

Every piece of mock data lives under `NemaraCaregiver/Mocks/`. Views read from `AppEnvironment.mockStore`, which is built from `Mocks/MockData.swift`. To swap in a real backend:

1. Add a `Services/WolfAPIClient.swift`-style real client.
2. Add `Services/SupabaseAuthService.swift` (port from `elephantLabs-range`).
3. Delete `NemaraCaregiver/Mocks/`.
4. Wire views to the real services in the `AppEnvironment` constructor.

The compile-time errors after step 3 mark every wire-up point.

## Conventions

- **iOS 17+** · uses `@Observable`, `NavigationStack`, modern SwiftUI.
- **Swift 6** with strict concurrency.
- **Light mode only** — `.preferredColorScheme(.light)` at the root.
- **No raw colors or fonts** — go through `NemaraColor` / `NemaraFont`.
- **Previews everywhere** — every component and screen has `#Preview`.
- **Single-responsibility files** — one component / one screen per file.
