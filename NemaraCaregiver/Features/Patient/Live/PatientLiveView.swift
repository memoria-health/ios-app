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

    /// Dev-only data-collection state (gated by `AppConfig.enableClipCapture`).
    /// `capturingCameraId` is the camera whose record-clip request is
    /// in flight (disables its button); `captureNote` is a short toast
    /// shown on that camera's tile after the trigger fires.
    @State private var capturingCameraId: UUID? = nil
    @State private var captureNote: (cameraId: UUID, text: String)? = nil

    /// Set true once a sensor has been stuck "Preparing to start" past the
    /// timeout (see the `.task(id: showPreparingCard)` below) so the
    /// spinner can't hang forever when nothing is actually going to come
    /// online — we fall through to `offlineCard`'s actionable message.
    @State private var preparingTimedOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // The Live grid follows the cameras' ACTUAL live state, never
                // the patient-level pause flag. "Disconnect all" / "Reconnect
                // all" are just bulk desired_state toggles — they must not own
                // or gate what's shown. A camera that comes back online (from
                // the sensor, the web, or here) always appears, regardless of
                // the bulk-button state. (Disconnect-all simply leaves no live
                // cameras → the empty card.)
                if onlineCameras.isEmpty {
                    // Show "Preparing to start" only while the connect is
                    // still plausibly in progress. If sensors never come
                    // online (app closed, unpaired, powered off), the
                    // timeout flips us to `offlineCard` so the spinner can't
                    // hang forever — see the `.task(id: showPreparingCard)`.
                    if showPreparingCard && !preparingTimedOut { preparingCard }
                    else if allCameras.isEmpty { emptyCard }   // no sensors paired at all
                    else { offlineCard }                       // paired, but none streaming (or timed out)
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
        // Timeout for the "Preparing to start" tile. Whenever we enter (or
        // re-enter) the preparing state, restart a 4s timer; if we're still
        // preparing when it fires, flip to the offline message instead of
        // spinning forever. 4s because a real first-connect lands well under
        // that — if it hasn't, the sensors are almost certainly closed/offline,
        // so show the actionable message fast. Re-keys on `showPreparingCard`,
        // so a sensor that actually comes online (preparing → false) cancels
        // the timer, and the flag resets the moment preparing clears.
        .task(id: showPreparingCard) {
            preparingTimedOut = false
            guard showPreparingCard else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { preparingTimedOut = true }
        }
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
            //   • Force one clean LiveKit rejoin (pass 0) so we
            //     re-subscribe to every republished track from scratch —
            //     the Swift SDK can drop `track_subscribed` across a
            //     publisher leave/rejoin.
            // Bail the moment a camera is actually live, max ~15s.
            guard oldValue == true, newValue == false else { return }
            Task {
                for attempt in 0..<6 {
                    await bootstrap(force: attempt == 0)
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
        .onDisappear { Task { await tabAwayCleanup() } }
        .onReceive(timer) { now in clockTick = now }
        .onChange(of: selectedCameraId) { _, newValue in
            // Swipe transfers the call atomically — the backend
            // `/talk/start` broadcasts `is_active=true` to the new
            // target and `false` to every sibling (including the old
            // target), so we don't need an `/end` between transfers.
            guard callState == .active, let newValue else { return }
            Task { await transferCall(to: newValue) }
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
                        if let track {
                            LiveKitVideoView(track: track)
                        } else {
                            NemaraCamFeedPlaceholder(hue: 30)
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
            let tok = try await env.api.mintViewerToken(forPatient: patientId)
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
            // Broadcaster grants over the same room; LiveKitClient
            // disconnects + reconnects to upgrade publish capabilities.
            let tok = try await env.api.mintBroadcasterToken(forPatient: patientId)
            await env.liveKit.connect(
                url: tok.url,
                token: tok.token,
                room: "patient_\(patientId.uuidString.lowercased())",
            )
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

        // Guaranteed mic-off: reconnect with the VIEWER token. The
        // broadcaster grant we connected with is what gives this
        // session canPublish=true; once we re-mint as viewer the SDK
        // physically can't publish audio even if some prior call
        // somehow left a track active. ~1-2s video gap during
        // reconnect — acceptable for a call-end transition.
        do {
            let tok = try await env.api.mintViewerToken(forPatient: patientId)
            await env.liveKit.connect(
                url: tok.url,
                token: tok.token,
                room: "patient_\(patientId.uuidString.lowercased())",
            )
        } catch {
            NSLog("[endCall] re-connect as viewer failed: %@", "\(error)")
        }
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
                    if let id = identity {
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

                if isThisCallTarget, let err = lkError {
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
            if let track = videoTrack {
                LiveKitVideoView(track: track)
                    .background(NemaraColor.ink)
            } else {
                ZStack {
                    NemaraCamFeedPlaceholder(hue: 30)
                    // Buffering: the sensor is online (or just reconnected)
                    // but its video track hasn't arrived yet — show progress
                    // so the gap reads as "coming up", not "broken".
                    if cam.online || env.api.isConnecting(cam) {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(NemaraColor.terraInk)
                            Text("Connecting…")
                                .font(NemaraFont.mono(size: 10, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(NemaraColor.terraInk.opacity(0.85))
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .strokeBorder(NemaraColor.line, lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if isThisCallTarget {
                CallButton(state: callState, onTap: handleCallButtonTap)
                    .offset(y: -10)
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
        .background(
            LinearGradient(
                colors: [NemaraColor.ink.opacity(0.75), .clear],
                startPoint: .bottom, endPoint: .top
            )
        )
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
        case .joining:
            mutedPill("WAITING")
        case .roomDown:
            mutedPill("CONNECTING")
        case .offline, .unpaired:
            // App closed (confirmed dead) wins over the optimistic
            // "Connecting…" reconnect buffer: a shut sensor reads "App
            // closed", not a 30s spinner. Otherwise show "connecting" when
            // online OR within the reconnect window (env.api.isConnecting);
            // else a blank pill.
            if cam.isAppClosed {
                mutedPill("APP CLOSED")
            } else if cam.online || env.api.isConnecting(cam) {
                mutedPill("CONNECTING")
            } else {
                EmptyView()
            }
        }
    }

    /// Tiny circular status indicator next to each camera row in the
    /// cameras card. Reads `LiveKitClient.connectivity(of:)` so the
    /// dot's truth tracks the same source as the tile's state pill.
    @ViewBuilder
    private func cameraStatusDot(for cam: Camera, paused: Bool) -> some View {
        let color: Color = {
            // App closed on the phone — amber "needs you to reopen it",
            // distinct from the red "offline but reconnectable" below. Checked
            // BEFORE `paused` so it still surfaces while monitoring is paused
            // (Reconnect-all won't bring a closed app back).
            if cam.isAppClosed { return NemaraColor.warning }
            if paused { return NemaraColor.ink3 }
            // Backend `online` flag is the source of truth (consistent with
            // web + the Sensors list).
            if cam.online { return NemaraColor.success }
            // First-connect: a sensor still booting reads as "starting up"
            // (amber), not "offline" (red).
            if env.api.isPreparing(cam) { return NemaraColor.warning }
            switch env.liveKit.connectivity(of: cam) {
            case .live, .joining:        return NemaraColor.success
            case .offline:               return NemaraColor.danger
            case .roomDown, .unpaired:   return NemaraColor.ink3
            }
        }()
        Circle().fill(color).frame(width: 7, height: 7)
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
            detail = "All available Memoria Sensors are offline or not open. Check that the **Memoria Sensor** app is open on the camera phone, the phone is charged, or the Pi sensor is connected."
        } else {
            icon = "antenna.radiowaves.left.and.right.slash"
            title = "All sensors are offline"
            detail = "All available Memoria Sensors are offline or not open. Check that each sensor is paired, its **Memoria Sensor** app is open, the phone is charged, or the Pi is connected."
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

    /// Show the "preparing to start" tile instead of the empty card when
    /// at least one sensor is on its first connect (booting up) and the
    /// patient isn't paused. Reassures the caregiver that the blank feed
    /// is expected and temporary, not a failure.
    private var showPreparingCard: Bool {
        allCameras.contains { env.api.isPreparing($0) }
    }

    /// First-connect transitional tile, in the same 16:9 slot as
    /// `emptyCard`. Replaced by the live carousel the moment the sensor's
    /// video track arrives.
    private var preparingCard: some View {
        // Generic copy — do NOT name a specific sensor here. This card can
        // represent one or several sensors connecting, and naming one (e.g.
        // its room) read as if the whole live feed was tied to that single
        // camera, which confused users.
        let preparingCount = allCameras.filter { env.api.isPreparing($0) }.count
        let detail = preparingCount <= 1
            ? "Your sensor is connecting. The live feed will appear here in a moment."
            : "Your sensors are connecting. The live feed will appear here in a moment."
        return ZStack {
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .fill(NemaraColor.cardAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                        .strokeBorder(NemaraColor.line, lineWidth: 1)
                )
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(NemaraColor.action)
                VStack(spacing: 6) {
                    Text("Preparing to start")
                        .font(NemaraFont.title3)
                        .foregroundStyle(NemaraColor.ink)
                        .kerning(-0.3)
                    Text(detail)
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

    private var camerasCard: some View {
        let paused = patient?.camerasPaused ?? false
        return NemaraCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: paused ? "video.slash" : "wifi")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(paused ? NemaraColor.ink3 : NemaraColor.action)
                    NemaraEyebrow(paused
                                  ? "SENSORS · PAUSED"
                                  : "SENSORS · \(onlineCameras.count) ONLINE")
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
                                cameraStatusDot(for: cam, paused: paused)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(NemaraColor.ink3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .opacity(paused ? 0.55 : 1)
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
            else { toggleMonitoring(pause: true) }
        }
        .disabled(isTogglingMonitoring)
        .opacity(isTogglingMonitoring ? 0.6 : 1)
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
    private var allCameras: [Camera] {
        env.api.camerasByPatient[patientId] ?? []
    }
    /// Sensors shown in the carousel right now.
    ///
    /// A tile is in the carousel iff it's eligible (`isLiveStreaming` —
    /// paired, not user-hidden, intent=connected) AND either:
    ///   1. the backend marks it `online` (the single source of truth,
    ///      consistent with web's grid + the Sensors list — flips fast via
    ///      Realtime so the tile appears as soon as the sensor connects), OR
    ///   2. the LiveKit SDK already has a subscribed video track for it
    ///      (so we never hide a feed that's actually streaming if `online`
    ///      is momentarily behind).
    ///
    /// The tile shows the live video once the track arrives, and a
    /// "connecting" placeholder in the gap between `online` and the track.
    /// (Previously this gated purely on the SDK track — the 2026-05-29
    /// incident fix for a then-unreliable `online` column. The reconciler
    /// refactor since made `online` trustworthy, and we now prefer it for
    /// cross-platform consistency.)
    private var onlineCameras: [Camera] {
        // The carousel follows each camera's OWN desired_state + live state,
        // never the patient-level `cameras_paused` bulk flag. A sensor that's
        // publishing always appears — it set its own desired_state=connected
        // (from the sensor app, web, or here) — so the bulk pause never hides
        // a live camera. But "disconnect all" sets EVERY camera to
        // disconnected, so the carousel clears immediately, even while a
        // stale track is still tearing down (no lingering "connecting" tile).
        let tracks = env.liveKit.videoTracksByIdentity
        return allCameras.filter { cam in
            guard let identity = cam.livekitIdentity,
                  !cam.disabled,
                  cam.desiredState == .connected else { return false }
            // Intended-connected: show on a live track (ground truth) OR as
            // soon as the backend confirms a publisher (`online`), so the
            // tile appears without waiting for the first frame. Also keep a
            // just-reconnected sensor in the carousel while it comes back up
            // (`isConnecting` — a bounded window) so its tile can show a
            // "Connecting…" buffer instead of vanishing. This only fires for
            // desired_state==.connected, so a DISCONNECTED camera still drops
            // out immediately (no lingering tile).
            // ...but NOT if the app is confirmed closed — a dead sensor drops
            // out of the carousel immediately instead of being parked in the
            // "Connecting…" buffer for the 30s window.
            return tracks[identity] != nil || cam.online
                || (env.api.isConnecting(cam) && !cam.isAppClosed)
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
