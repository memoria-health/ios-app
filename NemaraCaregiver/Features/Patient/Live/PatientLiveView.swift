import LiveKit
import SwiftUI

/// "Live" sub-tab. Phone-call metaphor — the caregiver swipes through
/// a carousel of camera tiles and taps a call button overlaid on the
/// currently-displayed tile to open full-duplex audio with **that**
/// camera. Swiping during an active call transfers the call to the
/// newly-displayed camera.
///
/// Connection lifecycle: connect on patient OPEN (`bootstrap`),
/// disconnect on patient CLOSE (`PatientShell.onDisappear`). Sub-tab
/// switches inside the patient (Live → Events → Live) keep the room
/// alive so the video resumes instantly; `bootstrap` short-circuits
/// when the room is already up. The single `env.liveKit` instance
/// also handles room switching when the caregiver navigates from one
/// patient to another (`connect` calls `disconnect` first).
struct PatientLiveView: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env

    /// Which camera tile the carousel is currently showing. Drives
    /// both video display and call-routing target.
    @State private var selectedCameraId: UUID?

    /// Master switch for the two-way "talk" (push-to-talk) feature. Kept as a
    /// kill-switch after the Phase-3 hardening — speakerphone audio routing
    /// (force `.speaker` on mic publish) + removal of the per-call room
    /// reconnect (we now hold broadcaster grants for the whole session and just
    /// toggle the mic). Set to `false` to hide the on-tile Call button without
    /// removing any call code. (Gates `CallButton` below.)
    private static let talkEnabled = true

    /// Lifecycle state of the call. `.idle` means no call in flight;
    /// `.connecting` covers token-mint + mic-publish + first
    /// `/talk/start`; `.active` is the live state where swipes
    /// trigger transfers.
    @State private var callState: CallButton.State = .idle

    /// Error surfaced from any of the LiveKit / network operations.
    /// Mirrored into the tile's bottom-overlay so it's visible
    /// without dismissing the carousel.
    @State private var lkError: String? = nil

    /// Per-second clock for the ON AIR timer label.
    @State private var clockTick: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var callStartedAt: Date? = nil

    /// Tracks the in-flight transfer so we can drop stale responses
    /// (rapid swipes can spawn multiple requests).
    @State private var transferSeq: Int = 0

    /// Which camera is currently in full-screen mode. nil = no full-
    /// screen view active. Driven by the expand-icon tap.
    @State private var fullScreenCameraId: UUID?

    /// True while the disconnect-all / reconnect-all PATCH is in flight.
    /// Disables the button so a rapid double-tap can't fire overlapping
    /// toggles (which made the label flash between Disconnect/Reconnect).
    @State private var isTogglingMonitoring = false

    /// Desync reconciler state. `desyncSince` records when each camera entered
    /// the "backend online + intended-connected, but no track on THIS device"
    /// state; `lastResubscribe` is a per-identity cooldown so we re-issue the
    /// surgical subscribe at most every few seconds; `isReconnectingAll`
    /// suppresses the reconciler while the reconnect-all loop owns recovery.
    @State private var desyncSince: [UUID: Date] = [:]
    @State private var lastResubscribe: [String: Date] = [:]
    @State private var isReconnectingAll = false

    /// Dev-only data-collection state (gated by `AppConfig.enableClipCapture`).
    /// `capturingCameraId` is the camera whose record-clip request is
    /// in flight (disables its button); `captureNote` is a short toast
    /// shown on that camera's tile after the trigger fires.
    @State private var capturingCameraId: UUID? = nil
    @State private var captureNote: (cameraId: UUID, text: String)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if privacyOn { privacyBanner }
                // The Live grid follows the cameras' ACTUAL live state, never
                // the patient-level pause flag. "Disconnect all" / "Reconnect
                // all" are just bulk desired_state toggles — they must not own
                // or gate what's shown. A camera that comes back online (from
                // the sensor, the web, or here) always appears, regardless of
                // the bulk-button state. (Disconnect-all simply leaves no live
                // cameras → the empty card.)
                if onlineCameras.isEmpty {
                    // A camera counts as "online" if THIS device has its track OR
                    // the backend says it's live + intended-connected (see
                    // `onlineCameras`). The latter keeps a camera in the carousel
                    // through a brief track gap, and `reconcileDesync` force-
                    // rejoins if that gap persists >2s — so we never sit here
                    // (offline card) while video could actually be streamed.
                    // Reaching this branch means every camera is honestly offline.
                    if allCameras.isEmpty { emptyCard }        // no sensors paired at all
                    else { offlineCard }                       // paired, but none streaming
                } else {
                    cameraCarousel
                }
                camerasCard
                if !allCameras.isEmpty {
                    disconnectAllButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .background(NemaraColor.paper)
        .navigationDestination(for: UUID.self) { cameraId in
            CameraDetailView(cameraId: cameraId, patientId: patientId)
        }
        .task(id: patientId) { await bootstrap() }
        .onChange(of: patient?.camerasPaused) { oldValue, newValue in
            // Reconnect-all. `.task` keys on patientId, so it never
            // re-fires when the kill switch flips back on, and a camera
            // only re-enters `onlineCameras` once it has BOTH
            // `desired_state == .connected` (the `isLiveStreaming` gate)
            // AND a live LiveKit track. Both have to recover, and the
            // publishers (Memoria Sensor) take a few seconds to rejoin
            // (backend cascades desired_state→connected, then each sensor
            // polls + republishes). So reconcile until live instead of
            // trusting a single event:
            //   • REST-refetch the camera rows each pass so desired_state
            //     is fresh — do NOT depend on a Realtime echo arriving
            //     (the most likely reason the old one-shot reconnect still
            //     showed an empty grid: track was back but isLiveStreaming
            //     stayed false).
            //   • Force a clean LiveKit rejoin on the EVEN passes (0, 2, 4, 6,
            //     8 → ~0s, 5s, 10s, 15s, 20s) so we re-subscribe to every
            //     republished track from scratch. The Swift SDK can drop
            //     `track_subscribed`
            //     across a publisher leave/rejoin and won't re-fire it on its
            //     own — so the ONLY reliable recovery is a fresh room.connect()
            //     that re-runs autoSubscribe against the present participant
            //     list (this is exactly what a manual background→foreground or
            //     a second reconnect does). Our FIRST rejoin (pass 0) usually
            //     fires before the sensor has finished republishing, so it
            //     finds nothing; the LATER rejoins catch it once it's actually
            //     back. The leave/rejoin is iOS-SDK-local — web + the sensor
            //     keep streaming throughout, only this device was stuck.
            // Bail the moment a camera is actually live, so when the first
            // rejoin already worked the extra passes never run. Max ~25s — a
            // slow sensor republish was occasionally landing just after the old
            // ~15s cap, leaving the tile stuck on the loading spinner.
            guard oldValue == true, newValue == false else { return }
            Task {
                isReconnectingAll = true
                defer { isReconnectingAll = false }
                for attempt in 0..<10 {
                    await bootstrap(force: attempt % 2 == 0)
                    try? await env.api.loadCameras(forPatient: patientId)
                    #if DEBUG
                    let snapshot = allCameras.map { cam -> String in
                        let hasTrack = cam.livekitIdentity
                            .flatMap { env.liveKit.videoTracksByIdentity[$0] } != nil
                        return "\(cam.displayId):\(cam.desiredState):\(hasTrack ? "trk" : "-")"
                    }
                    print("[reconnect-all] attempt=\(attempt) online=\(onlineCameras.count) lkState=\(env.liveKit.state) \(snapshot)")
                    #endif
                    if !onlineCameras.isEmpty { break }
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                }
            }
        }
        .onChange(of: privacyOn) { oldValue, newValue in
            // Privacy ACTIVATED → if a call is live, tear it down. The
            // backend severs the caregiver's publish grant at the SFU, but
            // the local call state and the backend `/talk` is_active flag
            // would otherwise dangle — the wall phone keeps showing "on
            // air". endCall() sends `/talk/end` and resets local UI state.
            if oldValue == false, newValue == true {
                if callState == .active { Task { await endCall() } }
                return
            }
            // Privacy CLEARED → the caregiver is still holding a token
            // minted with can_subscribe=false (that's what kept the feed
            // severed across reconnects). The SDK reuses that token, so we
            // must force a fresh room.connect() with a re-minted,
            // now-unblocked token before video/audio can return. Same
            // force-rejoin loop as the unpause path.
            guard oldValue == true, newValue == false else { return }
            Task {
                for attempt in 0..<6 {
                    await bootstrap(force: attempt % 2 == 0)
                    if !onlineCameras.isEmpty { break }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        .onDisappear { Task { await tabAwayCleanup() } }
        .onReceive(timer) { now in
            clockTick = now
            reconcileDesync(now: now)
        }
        .onChange(of: selectedCameraId) { _, newValue in
            // Swipe transfers the call atomically — the backend
            // `/talk/start` broadcasts `is_active=true` to the new
            // target and `false` to every sibling (including the old
            // target), so we don't need an `/end` between transfers.
            guard callState == .active, let newValue else { return }
            Task { await transferCall(to: newValue) }
        }
        .onChange(of: onlineCameras.map(\.id)) { _, ids in
            // Make the Call (dial-in) button appear the instant a sensor goes
            // live. When the FIRST camera comes online while we're already
            // sitting on the Live tab, `bootstrap` had already run against an
            // empty roster (→ selectedCameraId == nil) and nothing re-resolves
            // it: SwiftUI's paged TabView won't write back a selection on its
            // own. With no selection, no tile is the call target
            // (`isThisCallTarget`), so the button stayed hidden until you tabbed
            // away and back (which re-ran bootstrap → resolveSelectedCamera).
            // Resolve here the moment the live set changes. Keep a still-valid
            // selection (don't yank the user mid-swipe / mid-call); otherwise
            // fall to the first online camera.
            if let current = selectedCameraId, ids.contains(current) { return }
            selectedCameraId = ids.first
        }
        .fullScreenCover(item: Binding(
            get: { fullScreenCameraId.map(IdentifiableUUID.init) },
            set: { fullScreenCameraId = $0?.id },
        )) { wrap in
            fullScreenView(forCameraId: wrap.id)
        }
    }

    // MARK: - Full-screen presentation

    @ViewBuilder
    private func fullScreenView(forCameraId cameraId: UUID) -> some View {
        if let cam = allCameras.first(where: { $0.id == cameraId }),
           let identity = cam.livekitIdentity {
            let track = env.liveKit.videoTracksByIdentity[identity]
            // The app is portrait-locked (UISupportedInterfaceOrientations)
            // but the wall phone publishes a landscape 1280x720 track.
            // Rotate the LiveKit view 90° and swap width/height so the
            // landscape video fills the portrait device sideways —
            // the caregiver physically rotates their phone to view it
            // right-side-up. Same gesture every iOS video player uses.
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    // Video + chrome rotate together. The caregiver holds
                    // their phone in landscape to view it; once rotated,
                    // close-X and room label are both right-side-up over
                    // the video, matching every iOS video player.
                    ZStack {
                        if privacyOn {
                            privacyPlacard
                        } else if let track {
                            LiveKitVideoView(track: track, identity: identity)
                        } else {
                            NemaraCamFeedPlaceholder(hue: 30, loading: true)
                        }
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    fullScreenCameraId = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(12)
                                        .background(Color.black.opacity(0.55))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 16)
                                .padding(.top, 16)
                            }
                            Spacer()
                            Text(cam.room)
                                .font(NemaraFont.bodyLarge.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule(style: .continuous))
                                .padding(.bottom, 28)
                        }
                    }
                    .frame(width: geo.size.height, height: geo.size.width)
                    .rotationEffect(.degrees(90))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .ignoresSafeArea()
            }
            .statusBarHidden()
        } else {
            // Camera went away mid-presentation (unpaired etc.) —
            // bounce back to the carousel.
            Color.black.ignoresSafeArea().onAppear { fullScreenCameraId = nil }
        }
    }

    /// Local Identifiable wrapper for UUID so .fullScreenCover(item:)
    /// can drive presentation. Same pattern used in RosterView.
    private struct IdentifiableUUID: Identifiable, Hashable {
        let id: UUID
    }

    // MARK: - Lifecycle

    private func bootstrap(force: Bool = false) async {
        // Connect regardless of the patient-level pause flag. The LiveKit
        // room is just a subscription — if every camera is disconnected we
        // simply receive no tracks and show the empty card. Gating the
        // connection on camerasPaused meant a camera that came back online
        // while "paused" had nowhere to surface (we weren't even in the room).
        let expectedRoom = "patient_\(patientId.uuidString.lowercased())"

        // Sub-tab return path: room is already up for this patient,
        // skip the mint+connect entirely. This is what makes
        // Live → Events → Live feel instant — without it, each
        // .onAppear here triggered a full LiveKit reconnect.
        //
        // `LiveKitClient.connect()` is NOT idempotent (it pre-
        // disconnects on every call), so the gate has to be here
        // rather than inside the client. The state check also
        // doubles as a token-expiry escape hatch: if the SDK has
        // dropped the room, `state` won't be `.connected` and we
        // fall through to a fresh mint.
        //
        // `force` bypasses the short-circuit: the reconnect-all path
        // needs a clean re-join so we re-subscribe to every track the
        // wall phones re-publish, rather than trusting a stale session
        // whose subscriptions the SDK may have silently dropped during
        // the publishers' leave/rejoin.
        if !force
            && env.liveKit.currentRoom == expectedRoom
            && env.liveKit.state == .connected {
            lkError = nil
            // Only re-resolve the carousel selection if it's stale
            // (camera unpaired since last visit). Otherwise the
            // server's "active camera" guess would yank the user
            // off whatever tile they were last looking at — annoying
            // every time you tab away and back.
            if selectedCameraId == nil
                || !onlineCameras.contains(where: { $0.id == selectedCameraId }) {
                await resolveSelectedCamera()
            }
            return
        }

        do {
            // Connect with BROADCASTER grants up front (canPublish=true) even
            // for plain viewing. We never publish the mic until the caregiver
            // taps Call, but holding the publish grant means start/end of a
            // call is just a mic toggle — NO room reconnect, so the video tiles
            // never blink. The wall phone still won't play our audio outside a
            // call: it gates on the backend's set_talk_active packet, not on
            // our grant.
            let tok = try await env.api.mintBroadcasterToken(forPatient: patientId)
            await env.liveKit.connect(
                url: tok.url,
                token: tok.token,
                room: expectedRoom,
            )
            lkError = nil
            await resolveSelectedCamera()
        } catch {
            lkError = error.localizedDescription
        }
    }

    /// Desync reconciler — drives THIS device back toward the backend's "online"
    /// truth. When the backend says a camera is live (`online` +
    /// intended-connected) but iOS has NO video track for it (the SDK missed the
    /// subscribe — web has the feed, we don't), that's a divergence. Once the
    /// mismatch persists ≥2s we SURGICALLY re-subscribe just that one camera via
    /// `ensureSubscribed`, which re-issues the subscribe RPC for that
    /// participant's publications without touching the room or any other tile.
    ///
    /// Deliberately NOT a full room rejoin: `bootstrap(force:)` tears the whole
    /// room down (drops every tile) and, crucially, can't tell a fixable
    /// subscribe-miss from a STALE backend `online` flag (sensor really dropped,
    /// presence sweeper hasn't caught up). For the stale case a rejoin never
    /// produces a track, so it loops every cooldown — nuking the room forever.
    /// `reconnectIfAbsent: false` makes the absent case a no-op instead: the
    /// placeholder honestly stays until the sensor republishes, and the room +
    /// working tiles are never disturbed. Runs on the 1s clock tick; the 2s gate
    /// ignores the normal sub-second "online flips just before the track lands"
    /// transient.
    private func reconcileDesync(now: Date) {
        // Only meaningful while we're actually in the room and not already
        // mid-(re)connect — bootstrap / the reconnect-all loop own recovery then.
        guard env.liveKit.state == .connected,
              !isTogglingMonitoring,
              !isReconnectingAll
        else {
            if !desyncSince.isEmpty { desyncSince = [:] }
            return
        }
        let tracks = env.liveKit.videoTracksByIdentity
        for cam in allCameras {
            guard let identity = cam.livekitIdentity, !cam.disabled else {
                if desyncSince[cam.id] != nil { desyncSince[cam.id] = nil }
                continue
            }
            let desynced = cam.online
                && cam.desiredState == .connected
                && tracks[identity] == nil
            guard desynced else {
                if desyncSince[cam.id] != nil { desyncSince[cam.id] = nil }
                continue
            }
            // First moment we noticed this camera diverge.
            if desyncSince[cam.id] == nil { desyncSince[cam.id] = now }
            guard let since = desyncSince[cam.id],
                  now.timeIntervalSince(since) >= 2 else { continue }
            // Per-camera cooldown — the re-subscribe is cheap + idempotent, but
            // no need to re-issue it every single tick while we wait for the
            // track (or for the sensor to actually come back).
            if let last = lastResubscribe[identity],
               now.timeIntervalSince(last) < 6 { continue }
            lastResubscribe[identity] = now
            NSLog("[desync] %@ online but no track >=2s — surgical re-subscribe", identity)
            Task {
                await env.liveKit.ensureSubscribed(
                    identity: identity,
                    reconnectIfAbsent: false,
                )
            }
        }
    }

    private func resolveSelectedCamera() async {
        // Server's best guess wins; fall back to the first online
        // camera in the patient's roster.
        let suggested = (try? await env.api.getActiveCamera(forPatient: patientId)) ?? nil
        if let s = suggested, onlineCameras.contains(where: { $0.id == s }) {
            selectedCameraId = s
        } else {
            selectedCameraId = onlineCameras.first?.id
        }
    }

    /// Runs whenever the Live sub-tab disappears — which happens both
    /// on intra-shell tab switches (Live → Events) AND on the full
    /// `PatientShell` dismiss. We deliberately do NOT disconnect the
    /// LiveKit room here, so tab-back resumes video instantly. The
    /// room teardown lives on `PatientShell.onDisappear`, which only
    /// fires on the real exit.
    ///
    /// The call-end leg stays: leaving the Live screen during an
    /// active call is still "hang up" in the phone metaphor. We drop
    /// the viewer-token reconnect (the original belt-and-braces mic
    /// kill) because `endTalk` already gates the wall phone's audio
    /// playback server-side, and on the shell-dismiss path the
    /// follow-up `liveKit.disconnect()` from PatientShell kills any
    /// local publishing regardless.
    private func tabAwayCleanup() async {
        if callState == .active {
            try? await env.liveKit.publishMicrophone(enable: false)
            try? await env.api.endTalk(forPatient: patientId)
        }
        callState = .idle
        callStartedAt = nil
        // `selectedCameraId` intentionally preserved — keeps the
        // carousel on the same tile when the user returns to Live.
    }

    // MARK: - Call control

    private func startCall() async {
        guard let cameraId = selectedCameraId else { return }
        guard callState == .idle else { return }
        let cameraIdentity = allCameras
            .first(where: { $0.id == cameraId })?
            .livekitIdentity
        callState = .connecting
        do {
            // The room is already connected with broadcaster grants (see
            // bootstrap), so starting a call is just enabling the mic — NO
            // room reconnect, so the video tiles stay up the whole time.
            try await env.liveKit.publishMicrophone(enable: true)
            // Unmute the target camera's remote audio so the caregiver
            // hears the wall phone, and so the combined audio renderer
            // starts firing for the waveform. Everything else stays
            // muted (default state on subscribe).
            env.liveKit.setRemoteAudioPlayback(enabledFor: cameraIdentity)
            try await env.api.startTalk(forPatient: patientId, cameraId: cameraId)
            callState = .active
            callStartedAt = Date()
            lkError = nil
        } catch {
            // Roll back any partial publish so a failed start doesn't
            // leave the mic hot.
            try? await env.liveKit.publishMicrophone(enable: false)
            env.liveKit.setRemoteAudioPlayback(enabledFor: nil)
            callState = .idle
            callStartedAt = nil
            lkError = "Call failed: \(error.localizedDescription)"
        }
    }

    private func endCall() async {
        guard callState == .active else { return }
        // Stamp UI immediately so the button reverts the moment the
        // caregiver taps end, even if network is slow.
        callState = .idle
        callStartedAt = nil

        // Mute all remote audio first — caregiver stops hearing the
        // wall phone instantly, waveform goes flat instantly. Doing
        // this before mic teardown also stops the combined renderer
        // from firing while the rest of the disconnect resolves.
        env.liveKit.setRemoteAudioPlayback(enabledFor: nil)

        // Belt: ask the SDK to disable the local microphone track.
        do {
            try await env.liveKit.publishMicrophone(enable: false)
        } catch {
            NSLog("[endCall] publishMicrophone(false) failed: %@", "\(error)")
        }

        // Braces: tell the backend to broadcast set_talk_active=false
        // so the wall phone gates its playback even if our mic
        // tear-down didn't fully take effect on this side.
        do {
            try await env.api.endTalk(forPatient: patientId)
        } catch {
            lkError = "End call failed: \(error.localizedDescription)"
        }

        // No reconnect on hang-up — we stay in the room as broadcaster so the
        // video never blinks. The mic is already unpublished above, and the
        // wall phone stops playing our audio the instant endTalk broadcasts
        // set_talk_active=false. That packet is the real playback gate, so even
        // a lingering local mic track (there shouldn't be one) is inaudible in
        // the room regardless of our publish grant.
    }

    private func transferCall(to cameraId: UUID) async {
        transferSeq &+= 1
        let seq = transferSeq
        let cameraIdentity = allCameras
            .first(where: { $0.id == cameraId })?
            .livekitIdentity
        do {
            try await env.api.startTalk(forPatient: patientId, cameraId: cameraId)
            // Shift the audio gate to the newly-targeted camera so the
            // caregiver hears the right room and the waveform follows.
            env.liveKit.setRemoteAudioPlayback(enabledFor: cameraIdentity)
            // Older transfers may finish after newer ones; only the
            // latest gets to clear the error indicator.
            if seq == transferSeq { lkError = nil }
        } catch {
            if seq == transferSeq {
                lkError = "Transfer failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Tiles

    private var cameraCarousel: some View {
        TabView(selection: tabSelectionBinding) {
            ForEach(onlineCameras) { cam in
                cameraTile(for: cam)
                    .tag(Optional(cam.id))
                    .padding(.bottom, 32)   // headroom for the page-dot indicator
            }
        }
        .frame(height: tileHeight)
        .tabViewStyle(.page(indexDisplayMode: onlineCameras.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    /// Coerces the optional to non-optional for `TabView` since
    /// SwiftUI's page style doesn't bind cleanly to `Binding<UUID?>`.
    private var tabSelectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedCameraId },
            set: { selectedCameraId = $0 },
        )
    }

    private func cameraTile(for cam: Camera) -> some View {
        let identity = cam.livekitIdentity
        let videoTrack: VideoTrack? = identity.flatMap { env.liveKit.videoTracksByIdentity[$0] }
        let levels = identity.flatMap { env.liveKit.audioLevels[$0] } ?? []
        let isThisCallTarget = cam.id == selectedCameraId
        let connectivity = env.liveKit.connectivity(of: cam)

        // The video render lives in `.background` rather than as a
        // peer in the ZStack. UIKit views inside a SwiftUI ZStack can
        // render above sibling SwiftUI content (an SDK-level layer
        // ordering quirk), which is what made the CallButton vanish
        // the moment the video appeared. As a background layer the
        // UIView is provably below every SwiftUI child in this stack.
        return ZStack {
            VStack {
                HStack {
                    statePill(for: cam, connectivity: connectivity)
                    // Beside the LIVE pill, only for cameras whose own AI is
                    // paused. Driven by `cam.aiPaused` (per-camera), which
                    // updates live via the cameras realtime channel — pause
                    // from any node and it shows here.
                    if cam.aiPaused { aiPausedPill }
                    Spacer()
                    // Per-tile audio mute toggle. Independent of Talk
                    // mode: tapping unmutes a tile so the caregiver can
                    // listen passively without starting a call. The
                    // active Talk camera is always audible regardless of
                    // this toggle; the toggle controls the non-Talk
                    // default mute state for each tile.
                    // Hidden under privacy: there's no audio to listen to.
                    if !privacyOn, let id = identity {
                        Button {
                            _ = env.liveKit.toggleAudio(forIdentity: id)
                        } label: {
                            Image(
                                systemName: env.liveKit.audioEnabledByIdentity.contains(id)
                                    ? "speaker.wave.2.fill"
                                    : "speaker.slash.fill"
                            )
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NemaraColor.terraInk)
                            .padding(8)
                            .background(NemaraColor.ink.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            env.liveKit.audioEnabledByIdentity.contains(id)
                                ? "Mute \(cam.room) audio"
                                : "Unmute \(cam.room) audio"
                        )
                    }
                    // Dev-only data-collection trigger. Tells THIS camera
                    // to record the next 15s and ship it to the laptop
                    // receiver. Hidden entirely unless the flag is on.
                    if AppConfig.enableClipCapture {
                        Button {
                            Task { await captureClip(for: cam.id) }
                        } label: {
                            Image(
                                systemName: capturingCameraId == cam.id
                                    ? "record.circle.fill"
                                    : "record.circle"
                            )
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                capturingCameraId == cam.id
                                    ? Color(.systemRed)
                                    : NemaraColor.terraInk
                            )
                            .padding(8)
                            .background(NemaraColor.ink.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(capturingCameraId != nil)
                        .accessibilityLabel("Capture 15-second clip from \(cam.room)")
                    }
                    Button {
                        fullScreenCameraId = cam.id
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NemaraColor.terraInk)
                            .padding(8)
                            .background(NemaraColor.ink.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if !privacyOn, isThisCallTarget, let err = lkError {
                    Text(err)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.terraInk)
                        .padding(8)
                        .background(NemaraColor.ink.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                if let note = captureNote, note.cameraId == cam.id {
                    Text(note.text)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.terraInk)
                        .padding(8)
                        .background(NemaraColor.ink.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                bottomOverlay(cam: cam, levels: levels)
            }
            .padding(10)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .background {
            ZStack {
                if privacyOn {
                    // Privacy mode: the live feed is severed server-side, so
                    // never render video even if a stale track lingers. Show
                    // the dignity placard instead — insights still flow in
                    // the rest of the app.
                    privacyPlacard
                } else if let track = videoTrack {
                    LiveKitVideoView(track: track, identity: identity)
                        .background(NemaraColor.ink)
                } else {
                    // No live track yet → loading (we're expected-online, just
                    // waiting on the subscribe). Pure-SwiftUI spinner so it
                    // doesn't fight the nil→track UIView swap; see
                    // NemaraCamFeedPlaceholder.
                    NemaraCamFeedPlaceholder(hue: 30, loading: true)
                }
                // Bottom scrim drawn INTO the feed — NOT into the padded content.
                // Because it lives in the background layer it bleeds all the way
                // to the tile's clipped bottom edge, so it reads as a natural
                // video bottom-fade instead of a dark box floating inside the
                // view. The Spacer pins it to the bottom; it sits under the label
                // (which is in the foreground) and seats the white text.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [NemaraColor.ink.opacity(0.6), .clear],
                        startPoint: .bottom, endPoint: .top
                    )
                    .frame(height: 92)
                }
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .strokeBorder(NemaraColor.line, lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            // No Talk under privacy: the caregiver token is minted
            // can_publish=false, so tapping Call only yields a
            // "does not have permission to publish" error. Hide it.
            if Self.talkEnabled && isThisCallTarget && !privacyOn {
                CallButton(state: callState, onTap: handleCallButtonTap)
                    .offset(y: -10)
            }
        }
    }

    /// Top-of-Live-tab indicator that Privacy mode is active for this
    /// patient. Pairs with the per-tile placard so the state is obvious
    /// from anywhere on the screen.
    private var privacyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NemaraColor.action)
            VStack(alignment: .leading, spacing: 1) {
                Text("Privacy mode is on")
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
                Text("Live view and audio are hidden. Insights are still active.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
            Spacer()
        }
        .padding(12)
        .background(NemaraColor.actionSoft)
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous))
    }

    /// Fills a tile when the patient is in Privacy mode. Dignity-first:
    /// no feed, no spinner — just a clear statement that the live view is
    /// intentionally hidden while insights keep arriving elsewhere.
    private var privacyPlacard: some View {
        ZStack {
            NemaraColor.ink
            VStack(spacing: 8) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(NemaraColor.terraInk.opacity(0.85))
                Text("Privacy mode")
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.terraInk)
                Text("Live video and audio are hidden.\nInsights still arrive on your phone.")
                    .font(NemaraFont.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NemaraColor.terraInk.opacity(0.75))
                    .padding(.horizontal, 16)
            }
        }
    }

    private func bottomOverlay(cam: Camera, levels: [Float]) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cam.room)
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.terraInk)
                Text(statusLine(for: cam))
                    .font(NemaraFont.mono(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(NemaraColor.terraInk.opacity(0.78))
            }
            // Light shadow for extra legibility; the real backing is the bottom
            // scrim drawn INTO the feed (flush to the tile's bottom edge) in
            // `cameraTile`, so the text never needs its own box.
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            Spacer()
            // Waveform is only meaningful when audio is flowing —
            // show it for the active call target only.
            if callState == .active && cam.id == selectedCameraId {
                NemaraWaveform(levels: levels)
                    .frame(width: 100, height: 22)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
    }

    /// Per-camera "AI PAUSED" badge, shown beside the LIVE pill when the
    /// camera's own `ai_paused` flag is set. Propagated to every surface via
    /// the `cameras` realtime channel (same path as `desired_state`), so a
    /// pause from any node reflects here within ~1s. The video keeps
    /// streaming — this only signals analysis is off. Styled like the LIVE
    /// pill but in a muted "off" tone rather than the bright terra.
    private var aiPausedPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "pause.fill")
                .font(.system(size: 8, weight: .bold))
            Text("AI PAUSED")
                .font(NemaraFont.mono(size: 9, weight: .bold))
                .tracking(0.8)
        }
        .foregroundStyle(NemaraColor.terraInk)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(NemaraColor.ink.opacity(0.62))
        .clipShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    private func statePill(for cam: Camera, connectivity: LiveKitClient.CameraConnectivity) -> some View {
        switch connectivity {
        case .live:
            HStack(spacing: 6) {
                NemaraPulse(color: NemaraColor.terraInk, size: 5)
                Text(callState == .active ? "ON AIR" : "LIVE")
                    .font(NemaraFont.mono(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(NemaraColor.terraInk)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(callState == .active ? Color(.systemRed) : NemaraColor.terra)
            .clipShape(Capsule(style: .continuous))
        case .joining, .roomDown:
            // "WAITING" / "CONNECTING" pills removed — no loading indication.
            EmptyView()
        case .offline, .unpaired:
            // App-closed still surfaces (actionable: reopen the app on the
            // phone). Otherwise no pill — the "Connecting…" pill was removed too.
            if cam.isAppClosed {
                mutedPill("APP CLOSED")
            } else {
                EmptyView()
            }
        }
    }

    /// Tiny circular status indicator next to each sensor row.
    ///
    /// Color is a PURE function of the shared, Realtime-synced camera fields —
    /// `online`, `app_present` (via `isAppClosed`), and `desired_state`. It does
    /// NOT read this device's LiveKit connection (`connectivity`/`isConnecting`)
    /// or the bulk `cameras_paused` lever, because those are LOCAL or non-shared:
    /// the web dashboard, this phone, and another phone must all show the SAME
    /// dot for the same sensor, so it can only depend on central state. (Using
    /// this phone's room state is exactly what made the dot lie after a
    /// background — room down here, but centrally still online.)
    ///
    /// AI-pause and monitoring-pause never change the color: the feed keeps
    /// streaming when AI is paused, so an online sensor is green either way —
    /// which is why resuming AI never has to "turn it back green," it never left.
    private func cameraStatusDot(for cam: Camera) -> some View {
        let color: Color = {
            // 1) Streaming (backend observes frames) → green. Wins over
            //    everything; ai_paused / cameras_paused don't stop the feed.
            if cam.online { return NemaraColor.success }
            // 2) iPhone sensor app closed → dark. The one "not reconnectable"
            //    state: a remote Reconnect can't help, the app must be reopened.
            if cam.isAppClosed { return NemaraColor.ink3 }
            // 3) Intent is connected but not online yet → amber "connecting".
            if cam.desiredState == .connected { return NemaraColor.warning }
            // 4) Deliberately disconnected (reconnectable) → rust.
            return NemaraColor.danger
        }()
        return Circle().fill(color).frame(width: 7, height: 7)
    }

    private func mutedPill(_ text: String) -> some View {
        Text(text)
            .font(NemaraFont.mono(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(NemaraColor.terraInk)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(NemaraColor.ink.opacity(0.55))
            .clipShape(Capsule(style: .continuous))
    }

    private func statusLine(for cam: Camera) -> String {
        if callState == .active && cam.id == selectedCameraId {
            guard let startedAt = callStartedAt else { return "ON AIR" }
            let elapsed = Int(clockTick.timeIntervalSince(startedAt))
            return String(format: "ON AIR · %02d:%02d", elapsed / 60, elapsed % 60)
        }
        return "SENSOR \(String(format: "%02d", cam.displayId))"
    }

    private func handleCallButtonTap() {
        switch callState {
        case .idle: Task { await startCall() }
        case .active: Task { await endCall() }
        case .connecting: break
        }
    }

    // MARK: - Data collection (dev-only)

    /// Triggers the wall camera to record the next 15s locally and ship
    /// the clip to the laptop receiver (see AppConfig.enableClipCapture).
    /// The button is disabled only for the brief trigger request; the
    /// note then lingers ~5s. No call has to be active — the backend
    /// sends the record packet server-side regardless of Talk state.
    private func captureClip(for cameraId: UUID) async {
        guard capturingCameraId == nil else { return }
        capturingCameraId = cameraId
        captureNote = (cameraId, "Sending…")
        do {
            try await env.api.recordClip(forPatient: patientId, cameraId: cameraId)
            captureNote = (cameraId, "Recording 15s — check the receiver")
        } catch {
            captureNote = (cameraId, "Capture failed: \(error.localizedDescription)")
        }
        capturingCameraId = nil
        // Auto-clear the toast unless a newer capture replaced it.
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if captureNote?.cameraId == cameraId { captureNote = nil }
    }

    // MARK: - Empty / paused / cameras-list

    private var pausedCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .fill(NemaraColor.cardAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                        .strokeBorder(NemaraColor.line, lineWidth: 1)
                )
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(NemaraColor.paperDim)
                        .frame(width: 64, height: 64)
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink3)
                }
                VStack(spacing: 6) {
                    Text("Monitoring paused")
                        .font(NemaraFont.title3)
                        .foregroundStyle(NemaraColor.ink)
                        .kerning(-0.3)
                    Text("Sensors are off. Turn monitoring back on in Settings.")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.vertical, 36)
        }
        .aspectRatio(16/9, contentMode: .fit)
    }

    private var emptyCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .fill(NemaraColor.cardAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                        .strokeBorder(NemaraColor.line, lineWidth: 1)
                )
            VStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink3)
                Text("No sensors paired")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
                Text("Pair a Memoria Sensor from the **Sensors tab** to begin the live feed.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }
            .padding(.vertical, 36)
        }
        .aspectRatio(16/9, contentMode: .fit)
    }

    /// Shown when sensors ARE paired but none is streaming right now —
    /// distinct from `emptyCard` (no sensors paired at all). Copy adapts:
    /// if the patient is paused, point at Reconnect all; otherwise point
    /// at starting a sensor. Never gates the live feed — purely a hint.
    private var offlineCard: some View {
        let paused = patient?.camerasPaused ?? false
        // How many eligible sensors have the app actually CLOSED (iPhone, not
        // online, heartbeat stopped)? Those need the app reopened, not a
        // Reconnect — so we pick the right copy AND, when paused, warn that
        // Reconnect-all won't bring the closed ones back.
        let nClosed = allCameras.filter { $0.isAppClosed && !$0.disabled }.count
        let icon: String
        let title: String
        // LocalizedStringKey (NOT String) so `Text` renders the **bold**
        // markdown — a plain String variable shows the asterisks literally.
        let detail: LocalizedStringKey
        if paused {
            icon = "pause.circle"
            title = "Monitoring paused"
            if nClosed > 0 {
                let closedNote = nClosed == 1
                    ? "1 sensor has its app closed, so Reconnect won't bring it back — reopen Memoria Sensor on that phone."
                    : "\(nClosed) sensors have their app closed, so Reconnect won't bring those back — reopen Memoria Sensor on those phones."
                detail = "Tap **Reconnect all sensors** below to bring your sensors back online. \(closedNote)"
            } else {
                detail = "Tap **Reconnect all sensors** below to bring your sensors back online."
            }
        } else if nClosed > 0 {
            icon = "iphone.slash"
            title = "Memoria Sensor is closed"
            detail = "All available Memoria Sensors are offline, not open, or disconnected."
        } else {
            icon = "antenna.radiowaves.left.and.right.slash"
            title = "All sensors are offline"
            detail = "All available Memoria Sensors are offline, not open, or disconnected."
        }
        return ZStack {
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .fill(NemaraColor.cardAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                        .strokeBorder(NemaraColor.line, lineWidth: 1)
                )
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink3)
                Text(title)
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
                Text(detail)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }
            .padding(.vertical, 36)
        }
        .aspectRatio(16/9, contentMode: .fit)
    }


    private var camerasCard: some View {
        NemaraCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "wifi")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NemaraColor.action)
                    // Always reflect the real online count — never "PAUSED".
                    // `cameras_paused` is only the bulk Disconnect/Reconnect-all
                    // lever (it cascades per-camera desired_state); it doesn't
                    // gate the feed, so a sensor can be live while it's true —
                    // labeling the whole list "PAUSED" contradicts reality.
                    NemaraEyebrow("SENSORS · \(onlineCameras.count) ONLINE")
                    Spacer()
                }
                VStack(spacing: 8) {
                    ForEach(allCameras) { cam in
                        NavigationLink(value: cam.id) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(NemaraColor.paperDim)
                                    Image(systemName: cam.iconName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(NemaraColor.ink2)
                                }
                                .frame(width: 26, height: 26)
                                Text(cam.room).font(NemaraFont.bodySmall).foregroundStyle(NemaraColor.ink)
                                Spacer()
                                // Spell out the app-closed state right in the
                                // list (not just a dot) so the caregiver knows
                                // this one needs the app reopened, not a
                                // reconnect. Shows even while paused — a closed
                                // app won't come back on Reconnect-all, so the
                                // caregiver needs to see it in that state too.
                                if cam.isAppClosed {
                                    Text("APP CLOSED")
                                        .font(NemaraFont.monoSmall)
                                        .foregroundStyle(NemaraColor.warning)
                                } else {
                                    Text(String(format: "Sensor %02d", cam.displayId))
                                        .font(NemaraFont.monoSmall)
                                        .foregroundStyle(NemaraColor.ink3)
                                }
                                cameraStatusDot(for: cam)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(NemaraColor.ink3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// "Disconnect all cameras" button below the camera list. Drives the
    /// patient-level `cameras_paused` flag — the backend cascades
    /// desired_state='disconnected' to every camera (wall phones poll,
    /// then leave the LiveKit room) AND the per-tick loop short-circuits
    /// before the Gemini call, so no AI calls fire. Same lever as the
    /// Settings "Monitoring" toggle; both read the same observable
    /// `camerasPaused` so they stay in sync automatically.
    private var disconnectAllButton: some View {
        // Offer "Reconnect all" whenever nothing is live — whether that's
        // because monitoring is paused OR every sensor went offline / had
        // its app closed. "Disconnect all" only makes sense when there's an
        // actually-live sensor to turn off, so it never sits nonsensically
        // under an all-offline / "Memoria Sensor is closed" card.
        let showReconnect = onlineCameras.isEmpty
        return NemaraButton(
            showReconnect ? "Reconnect all sensors" : "Disconnect all sensors",
            variant: showReconnect ? .primary : .secondary,
            size: .md,
            block: true,
            systemImage: showReconnect ? "video.fill" : "video.slash"
        ) {
            if showReconnect { reconnectAll() }
            else { disconnectAll() }
        }
        // Welcome-tour marker, reported only in the "Reconnect" state: the
        // tour's Live step rings this first when nothing is streaming, and
        // moves on to the live-view explanation once video comes up.
        .tutorialTarget(showReconnect ? .reconnectAll : nil)
        .disabled(isTogglingMonitoring)
        .opacity(isTogglingMonitoring ? 0.6 : 1)
    }

    /// Symmetric to `reconnectAll`: turn every live sensor OFF. We set each
    /// camera's `desired_state=disconnected` DIRECTLY rather than relying on
    /// the `cameras_paused` cascade — because the backend only cascades when
    /// the flag actually CHANGES, and `cameras_paused` can drift to already-
    /// true while a sensor is live (e.g. the sensor restarted itself without
    /// the patient un-pausing). In that state `toggleMonitoring(pause: true)`
    /// was a no-op and nothing disconnected. We also set `cameras_paused=true`
    /// so the Settings "Monitoring" toggle stays in sync.
    private func disconnectAll() {
        guard !isTogglingMonitoring, let id = patient?.id else { return }
        // Capture WHICH cameras to disconnect BEFORE we optimistically flip their
        // local intent below. The PATCH loop is gated on
        // `desired_state == .connected`; if we let the optimistic flip run first,
        // the loop would find ZERO connected cameras and never actually tell the
        // backend to disconnect — so nothing would disconnect and `loadCameras`
        // would bring them all back. (This was the "disconnect-all does nothing"
        // bug.)
        let toDisconnect = allCameras.filter {
            $0.desiredState == .connected && !$0.disabled
        }
        if let idx = env.api.patients.firstIndex(where: { $0.id == id }) {
            env.api.patients[idx].camerasPaused = true  // optimistic
        }
        // Optimistic: flip each connected camera's INTENT locally so the carousel
        // drops it immediately (onlineCameras requires desired_state == .connected
        // for a no-track tile) and falls back to the offline card — without
        // waiting for the PATCH round-trip or the lagging `online` flag.
        if var cams = env.api.camerasByPatient[patientId] {
            for i in cams.indices
            where cams[i].desiredState == .connected && !cams[i].disabled {
                cams[i].desiredState = .disconnected
            }
            env.api.camerasByPatient[patientId] = cams
        }
        isTogglingMonitoring = true
        Task {
            defer { isTogglingMonitoring = false }
            _ = try? await env.api.updatePatient(
                id, UpdatePatientRequest(camerasPaused: true),
            )
            for cam in toDisconnect {
                _ = try? await env.api.updateCamera(
                    cam.id, UpdateCameraRequest(desiredState: .disconnected),
                )
            }
            try? await env.api.loadCameras(forPatient: patientId)
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    /// Best-effort "bring everything back" for the Reconnect-all button.
    /// Works whether or not monitoring was paused:
    ///   1. Unpause at the patient level (cascades desired_state=connected).
    ///   2. Re-assert connect on any still-disconnected sensor, so a sensor
    ///      that dropped on its own (not via the bulk pause) also recovers.
    ///   3. Force a clean LiveKit rejoin + refresh rows.
    /// Sensors whose app is CLOSED can't be revived from here — they stay
    /// offline until the app is reopened (the offline card says exactly
    /// that) — but everything reconnectable comes back.
    private func reconnectAll() {
        guard !isTogglingMonitoring, let id = patient?.id else { return }
        let wasPaused = patient?.camerasPaused ?? false
        if wasPaused, let idx = env.api.patients.firstIndex(where: { $0.id == id }) {
            env.api.patients[idx].camerasPaused = false  // optimistic
        }
        isTogglingMonitoring = true
        Task {
            defer { isTogglingMonitoring = false }
            if wasPaused {
                _ = try? await env.api.updatePatient(
                    id, UpdatePatientRequest(camerasPaused: false),
                )
            }
            for cam in allCameras where cam.desiredState == .disconnected && !cam.disabled {
                _ = try? await env.api.updateCamera(
                    cam.id, UpdateCameraRequest(desiredState: .connected),
                )
            }
            await bootstrap(force: true)
            try? await env.api.loadCameras(forPatient: patientId)
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    /// Optimistic flip with rollback — mirrors PatientSettingsView's
    /// monitoring toggle. Writes the new value into the observable
    /// `patients` array immediately so the UI (here + the carousel's
    /// paused overlay + the Settings toggle) updates instantly, then
    /// PATCHes `/v1/patients/{id}`; reverts on failure.
    private func toggleMonitoring(pause: Bool) {
        guard !isTogglingMonitoring,
              let id = patient?.id,
              let idx = env.api.patients.firstIndex(where: { $0.id == id })
        else { return }
        let previous = env.api.patients[idx].camerasPaused
        env.api.patients[idx].camerasPaused = pause
        isTogglingMonitoring = true
        Task {
            // Reset busy in `defer` (not the catch) so a thrown error can't
            // leave the button permanently disabled.
            defer { isTogglingMonitoring = false }
            do {
                _ = try await env.api.updatePatient(
                    id, UpdatePatientRequest(camerasPaused: pause),
                )
            } catch {
                if let i = env.api.patients.firstIndex(where: { $0.id == id }) {
                    env.api.patients[i].camerasPaused = previous
                }
            }
            // Cooldown. On localhost the PATCH returns in ~20ms — faster than
            // a human's spam-tap interval (~100ms) — so disabling only for the
            // request window doesn't block spam. Hold the disable ~600ms past
            // the round-trip for a real cooldown that stops the rapid re-toggle
            // (and the out-of-order Realtime echoes it caused).
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    // MARK: - Helpers

    private var tileHeight: CGFloat {
        // 16:9 of the assumed phone width minus horizontal padding,
        // plus headroom for the page-dot indicator. The aspect ratio
        // modifier on the tile clamps the actual video frame.
        let w = UIScreen.main.bounds.width - 32
        return w * 9 / 16 + 36
    }

    // MARK: - Data

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }
    /// Privacy mode for this patient. While on, the backend severs the
    /// caregiver's LiveKit media at the SFU (no track ever arrives), so
    /// every tile renders the privacy placard instead of a feed.
    private var privacyOn: Bool { patient?.privacyModeEnabled ?? false }
    private var allCameras: [Camera] {
        env.api.camerasByPatient[patientId] ?? []
    }
    /// Sensors shown in the carousel right now. A camera appears iff it has a
    /// LiveKit identity and isn't user-hidden (`disabled`), AND any of:
    ///   • we hold a live video track for it — the actual feed on THIS device
    ///     (ground truth). This ALWAYS shows; never hidden by intent/online lag.
    ///   • central state says it's streaming (`online` — the exact signal the
    ///     web grid uses), so the tile appears the instant the backend sees a
    ///     publisher, in parity with web.
    ///   • central INTENT says it should be on (`desired_state == connected`)
    ///     but the stream hasn't landed yet — the "Connecting…" bridge.
    ///
    /// `desired_state` is used ONLY additively here — NEVER as a gate that could
    /// hide a present track (that was the bug we removed). It just ADDS a
    /// "Connecting…" tile while the stream is en route. The bridge is the SHARED,
    /// central `desired_state` (set by whoever reconnected — Care, web, or the
    /// sensor), so it's source-agnostic and never expires — unlike the old
    /// phone-local, this-device-only `isConnecting` timer it replaces. No
    /// `cameras_paused` (bulk) gate. A confirmed-closed iPhone app is excluded so
    /// it can't spin "Connecting…" forever (it can't recover without reopening).
    private var onlineCameras: [Camera] {
        let tracks = env.liveKit.videoTracksByIdentity
        return allCameras.filter { cam in
            guard let identity = cam.livekitIdentity, !cam.disabled else {
                return false
            }
            // A camera is in the live carousel if EITHER:
            //   • it has an actual video track — the feed is genuinely here on
            //     this device, so ALWAYS show it regardless of intent (this is
            //     what keeps a streaming camera visible even if its
            //     `desired_state` hasn't caught up), OR
            //   • central state says it's streaming (`online`) AND the intent is
            //     still connected (`desired_state == .connected`).
            //
            // The intent check on the `online` branch is what makes a
            // just-disconnected camera drop out IMMEDIATELY: after disconnect-all
            // the track tears down but `online` lags stale-true for seconds, so
            // without it the tile would linger as a placeholder instead of
            // falling back to the offline card.
            return tracks[identity] != nil
                || (cam.online && cam.desiredState == .connected)
        }
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return PatientLiveView(patientId: env.api.patients[0].id)
        .environment(env)
}
#endif
