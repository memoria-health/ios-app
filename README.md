# nemara-caregiver-app

SwiftUI iOS app for caregivers of patients in homes with wall-mounted phones acting as cameras + microphones. Talks live to [`nemara-backend`](../nemara-backend) — no in-app mock data.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the file tree, conventions, LiveKit connectivity model, and design-system overview.

> **Bring up [`nemara-backend`](../nemara-backend) first** — it has the prereq checklist and the LiveKit/Apple invites you need from the inviting teammate. This app needs a live backend on your LAN to sign in.

## What the app does

- **Home tab** — patient roster, live state (calm / critical / offline), status line, last-event time. Updates via Supabase Realtime.
- **Patient → Live tab** — snap-paged carousel of camera tiles over the patient's `patient_<id>` LiveKit room. Phone-call metaphor: tap to start a full-duplex audio session with the currently-displayed camera. Swiping during an active call transfers it atomically. Live audio waveform during a call.
- **Patient → Events tab** — review fired events; PATCH `opened` / `reviewed` / `review_choice` to mark caregiver actions. Inline `VideoPlayer` for archived clips.
- **Patient → Settings tab** — tune detector sensitivity, toggle detectors, pause/unpause monitoring, pair a new wall phone (mints a 6-digit code in a sheet with countdown), upload/remove patient photo.
- **App Settings tab** — caregiver profile, notification toggles, sign-out.

## Prereqs

- macOS with **Xcode 15+**.
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
- Backend up and reachable on the LAN — see [`nemara-backend`](../nemara-backend) README.

## Build

```bash
cd nemara-caregiver-app
xcodegen generate                  # produces NemaraCaregiver.xcodeproj
open NemaraCaregiver.xcodeproj
```

If the file tree changes, re-run `xcodegen` to keep the project in sync.

## Apple signing

In Xcode: `NemaraCaregiver` target → **Signing & Capabilities** → pick your Apple Developer Team.

Bundle ID is `co.elephantlabs.nemara`. If you're not on the `Elephant Labs` Apple Team (`V8N59CF74G`), change the bundle ID prefix to one your team owns. **APNs needs an extra step** — see "APNs" below.

## Backend / Supabase URL configuration

The bundled scheme env vars default to localhost (works in the iOS simulator):

```
NEMARA_BACKEND_URL=http://127.0.0.1:8002
SUPABASE_URL=http://127.0.0.1:54341
SUPABASE_ANON_KEY=<the well-known local key>
```

To run on a **physical iPhone**, override these in Xcode → Edit Scheme → Run → Environment Variables with your Mac's LAN address (the same IP the backend's `local-start.sh` printed):

```
NEMARA_BACKEND_URL=http://192.168.1.42:8002      # example
SUPABASE_URL=http://192.168.1.42:54341
```

(Your Mac's LAN IP shows in System Settings → Wi-Fi → Details.)

## Demo login

After backend `make fresh-seed`:

- Email: `jane@patel.co`
- Password: `Mar9aret!2024`

This caregiver has patient Maggie + a few seeded detectors + a few historical events to look at.

## APNs

Push notifications are configured via `project.yml` — `aps-environment` capability + remote-notification background mode are already set up.

If you're on the `Elephant Labs` Apple Team (`V8N59CF74G`), the `.env` in `nemara-backend` ships with the matching APNs key — pushes will work immediately. If you're on a different team:

1. Apple Developer → Keys → create a new key with Push capability.
2. Download the `.p8` file (you only get to download it once).
3. In `nemara-backend/.env`, replace:
   - `NEMARA_APNS_TEAM_ID` with your team's ID.
   - `NEMARA_APNS_KEY_ID` with the new key's ID.
   - `NEMARA_APNS_AUTH_KEY` with the contents of the `.p8` file (BEGIN/END lines preserved, between double quotes — see the existing entry's shape).
4. Restart the backend.

## Sign in flow

1. Sign in (or sign up) via the Welcome screen.
2. App lands on the Home tab. If you signed up fresh, the roster is empty — tap "Add a patient" to onboard.
3. To add a wall phone: tap a patient → Settings tab → "Pair a new wall phone" → generate code. The 6-digit code stays valid 10 minutes.

## Sister repos

- [`nemara-backend`](../nemara-backend) — serves the CRUD surface, mints LiveKit tokens, runs the detector pipeline.
- [`nemara-camera-app`](../nemara-camera-app) — wall-phone iOS app; pairs against the caregiver app's "Pair a new wall phone" flow.
