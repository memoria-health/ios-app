import Foundation
import Observation

/// Top-level dependency container. Lives once for the lifetime of the
/// app, injected via `.environment(_:)` from `NemaraCaregiverApp`.
///
/// - `auth`     — Supabase Auth (sessions, sign-in / sign-up / sign-out).
/// - `api`      — nemara-backend HTTP client + observable state +
///                Supabase Realtime subscriptions. Views read from
///                `api.patients`, `api.eventsByPatient[id]`, etc.
/// - `liveKit`  — Single LiveKit Room wrapper reused across patients.
///                Live tab connects on appear, disconnects on disappear;
///                Talk mode (Phase 3) reuses the same connection.
@MainActor
@Observable
final class AppEnvironment {
    let auth: SupabaseAuthService
    let api: NemaraAPIClient
    let liveKit: LiveKitClient
    /// Single source of truth for patient-shell presentation + APNs
    /// event deep-linking. See `DeepLinkRouter`.
    let deepLink: DeepLinkRouter

    init(auth: SupabaseAuthService, api: NemaraAPIClient, liveKit: LiveKitClient) {
        self.auth = auth
        self.api = api
        self.liveKit = liveKit
        self.deepLink = DeepLinkRouter()
    }

    /// Build the live environment used by `@main`. Wires the auth
    /// service's `onAuthenticated` callback so a successful sign-up /
    /// sign-in / session restore produces a `Caregiver` row and an
    /// initial data load, in that order.
    static func live() -> AppEnvironment {
        let auth = SupabaseAuthService()
        let api = NemaraAPIClient(
            supabaseClient: auth.client,
            tokenProvider: { [weak auth] in await auth?.currentAccessToken() },
        )
        let liveKit = LiveKitClient()
        let env = AppEnvironment(auth: auth, api: api, liveKit: liveKit)

        // iOS analog of the backend's REST-poll reconciler. When
        // Supabase Realtime delivers a `cameras` row that's meant to be
        // live (desired_state==connected, or worker-confirmed
        // online=true), ask LiveKitClient to make sure we're subscribed
        // to its tracks — recovers from any SDK-side `track_subscribed`
        // that got lost during a publisher reconnect. The API client
        // doesn't know about LiveKit; the wiring lives here so the
        // two services stay decoupled.
        //
        // `reconnectIfAbsent: false`: this fires on every qualifying
        // `cameras` UPDATE, including before the publisher has actually
        // rejoined the room. In that window the participant is legitimately
        // absent and we must NOT tear the room down (there's no supervisor
        // to re-mint outside the Live view's bootstrap) — we just no-op
        // and let the SDK's own `didSubscribeTrack` / a later UPDATE catch
        // it. The destructive force-reconnect stays available for callers
        // that KNOW the publisher is present.
        api.onCameraOnline = { [weak liveKit] identity in
            guard let liveKit else { return }
            Task { await liveKit.ensureSubscribed(identity: identity, reconnectIfAbsent: false) }
        }

        // Provisioning + bootstrap pipeline. AppEnvironment owns the
        // composition; auth + api stay decoupled.
        auth.onAuthenticated = { [weak api] signUpDisplayName in
            guard let api else {
                throw APIError.other(message: "API client released before bootstrap.")
            }
            let caregiver: Caregiver
            if let dn = signUpDisplayName {
                caregiver = try await api.provisionMe(displayName: dn)
            } else {
                caregiver = try await api.me()
            }
            try await api.bootstrap()
            return caregiver
        }
        auth.onSignedOut = { [weak api] in
            await api?.teardown()
        }
        auth.onDeleteAccount = { [weak api] in
            guard let api else {
                throw APIError.other(message: "API client released before account delete.")
            }
            try await api.deleteAccount()
        }
        return env
    }

    #if DEBUG
    /// Preview-only environment with seeded observable state. Builds a
    /// real `SupabaseAuthService` + `NemaraAPIClient` (so type identity
    /// matches `.live()`) but never makes a network call — we set
    /// `currentCaregiver` and the per-patient collections directly.
    /// Xcode `#Preview` blocks use this to render against deterministic
    /// data without standing up the backend.
    static func preview() -> AppEnvironment {
        let env = AppEnvironment.live()
        let cgID = UUID()
        let pID = UUID()
        let now = Date()
        env.auth.currentCaregiver = Caregiver(
            id: cgID,
            displayName: "Jane Patel",
            email: "jane@patel.co",
            phone: "+14155550123",
            createdAt: now,
            updatedAt: now,
        )
        let patient = Patient(
            id: pID,
            caregiverId: cgID,
            fullName: "Margaret O'Brien",
            preferredName: "Maggie",
            dateOfBirth: Calendar.current.date(from: .init(year: 1944, month: 5, day: 12)),
            gender: "Female",
            relation: .parent,
            homeAddress: "12 Cedar Ln, Berkeley CA",
            state: .critical,
            statusLine: "Possible fall, living room",
            lastEventAt: now.addingTimeInterval(-42 * 60),
            camerasPaused: false,
            emailAlertsEnabled: false,
            emailAlertRecipients: [],
            photoStorageKey: nil,
            createdAt: now.addingTimeInterval(-86_400 * 30),
            updatedAt: now,
        )
        env.api.patients = [patient]
        env.api.camerasByPatient[pID] = [
            Camera(disabled: false, aiPaused: false, desiredState: .connected,
                   id: UUID(), patientId: pID, displayId: 1, room: "Living room",
                   iconName: "tv", online: true,
                   livekitIdentity: "cam_preview1",
                   createdAt: now.addingTimeInterval(-86_400 * 30),
                   paired: true),
            Camera(disabled: false, aiPaused: false, desiredState: .connected,
                   id: UUID(), patientId: pID, displayId: 2, room: "Kitchen",
                   iconName: "fork.knife", online: true,
                   livekitIdentity: "cam_preview2",
                   createdAt: now.addingTimeInterval(-86_400 * 30),
                   paired: true),
            Camera(disabled: false, aiPaused: false, desiredState: .disconnected,
                   id: UUID(), patientId: pID, displayId: 3, room: "Bedroom",
                   iconName: "bed.double", online: false,
                   livekitIdentity: "cam_preview3",
                   createdAt: now.addingTimeInterval(-86_400 * 30),
                   paired: false),
        ]
        env.api.detectorsByPatient[pID] = [
            Detector(id: UUID(), patientId: pID, name: "Falls", iconName: "figure.fall",
                     description: "Detects falls in any room.", category: .safety,
                     source: .preset, shape: .pointInTime, whereScope: "ALL ROOMS",
                     whenScope: "ALWAYS", sensitivity: .high, isOn: true,
                     customPrompt: nil, identifier: "fall",
                     createdAt: now, updatedAt: now),
            Detector(id: UUID(), patientId: pID, name: "Took meds", iconName: "pills",
                     description: "Patient took morning + evening medication.",
                     category: .routine, source: .custom, shape: .state,
                     whereScope: "KITCHEN", whenScope: "8 AM, 8 PM ±1H",
                     sensitivity: .standard, isOn: true,
                     customPrompt: "Confirm pills swallowed near the dispenser.",
                     identifier: "medication",
                     createdAt: now, updatedAt: now),
        ]
        env.api.eventsByPatient[pID] = [
            DetectionEvent(id: UUID(), patientId: pID, detectorId: nil, cameraId: nil,
                           category: .safety, source: .preset, iconName: "figure.fall",
                           title: "Possible fall", location: "Living room",
                           occurredAt: now.addingTimeInterval(-42 * 60), hasClip: true,
                           narrative: "Patient appears to have lost balance near the couch.",
                           opened: false, reviewed: false,
                           reviewChoice: nil, reviewNotes: nil, reviewedAt: nil,
                           createdAt: now.addingTimeInterval(-42 * 60)),
            DetectionEvent(id: UUID(), patientId: pID, detectorId: nil, cameraId: nil,
                           category: .routine, source: .custom, iconName: "pills",
                           title: "Took meds", location: "Kitchen",
                           occurredAt: now.addingTimeInterval(-7 * 3600), hasClip: false,
                           narrative: "Patient retrieved the morning pill dispenser.",
                           opened: true, reviewed: true,
                           reviewChoice: .correct, reviewNotes: nil,
                           reviewedAt: now.addingTimeInterval(-6 * 3600),
                           createdAt: now.addingTimeInterval(-7 * 3600)),
        ]
        return env
    }
    #endif
}
