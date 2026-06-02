import AVFoundation
import Foundation
import LiveKit
import Observation
import os.lock

/// Wraps a single `LiveKit.Room` for the lifetime of the caregiver app.
///
/// One instance lives in `AppEnvironment` and is reused across
/// patients — the caregiver only ever views one room at a time (the
/// patient whose Live tab is open). Opening a different patient's
/// Live tab disconnects the previous room first.
///
/// Tracks are exposed keyed by participant identity (= the camera's
/// `livekit_identity` minted at pairing time) so the carousel can
/// render each camera's feed in its own tile and route audio per
/// camera.
@MainActor
@Observable
final class LiveKitClient {

    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed(String)
    }

    /// Fused per-camera connectivity status. Single source of truth for
    /// "is this wall phone actually streaming to us right now" — folds
    /// the four signals that can disagree during reconnects:
    ///   - room state (we may not even be connected)
    ///   - backend `cam.online` (1-2s lag via webhook + Realtime)
    ///   - subscribed video track presence (real-time SDK)
    ///   - paired-but-no-identity rows (placeholders before first claim)
    /// Consumers should switch on this rather than reading the raw
    /// signals — keeps "what counts as live" in one place.
    enum CameraConnectivity: Equatable {
        /// Camera row has no `livekitIdentity` yet (pairing code
        /// issued, wall phone hasn't claimed it).
        case unpaired
        /// Our LiveKit room isn't connected at all — can't speak to
        /// any camera's state.
        case roomDown
        /// Backend says the camera isn't in the room.
        case offline
        /// Backend says the camera joined; we haven't subscribed its
        /// video track yet. Brief transient on (re)connect.
        case joining
        /// Video track is flowing — the camera is fully live.
        case live
    }

    /// Connection state mirrored from `Room.connectionState`
    /// transitions arriving on the room delegate.
    private(set) var state: State = .disconnected

    /// Subscribed remote video tracks, keyed by publisher identity.
    /// `PatientLiveView`'s carousel reads this map to fill each tile.
    private(set) var videoTracksByIdentity: [String: VideoTrack] = [:]

    /// Subscribed remote audio tracks, keyed by publisher identity.
    /// `LiveKitClient` taps these via `AudioRenderer` to drive the
    /// per-camera waveform; consumers shouldn't need to touch them
    /// directly.
    private(set) var audioTracksByIdentity: [String: AudioTrack] = [:]

    /// Rolling per-camera audio peak levels (0.0–1.0). Each push
    /// trims to `audioLevelCapacity` so the array is safe to dump
    /// directly into a SwiftUI chart. Updated ~20-50× per second
    /// from the audio renderer hopping onto MainActor.
    private(set) var audioLevels: [String: [Float]] = [:]
    private let audioLevelCapacity: Int = 80

    /// True iff the caregiver mic is currently being published.
    private(set) var isMicrophonePublished: Bool = false

    /// The room name (`patient_<patient_id>`) we're connected to.
    /// nil when disconnected.
    private(set) var currentRoom: String?

    /// The underlying LiveKit Room. One instance, reused across
    /// connect / disconnect cycles.
    private let room: Room

    /// Concrete `RemoteAudioTrack` refs (the SDK's protocol-typed
    /// `AudioTrack` in `audioTracksByIdentity` doesn't expose
    /// `volume`). We gate speaker playback by setting each track's
    /// volume to 0 (silent) or 1 (normal); the tracks stay
    /// subscribed so audio keeps decoding and the combined renderer
    /// keeps firing — only the speaker output is muted when no
    /// call is active.
    ///
    /// Why volume-gating instead of `publication.set(enabled:)`:
    /// toggling subscription churns the SDK's audio engine in a
    /// way that the per-buffer renderer doesn't recover from
    /// (waveform stays flat after re-enabling). Continuous decode
    /// costs ~20kbps of bandwidth per camera — acceptable
    /// trade-off for a reliable visualization.
    private var remoteAudioTracksByIdentity: [String: RemoteAudioTrack] = [:]

    /// Identity of the camera currently in a Talk call, or nil. The
    /// combined-remote renderer pushes its peaks into this identity's
    /// `audioLevels` entry; all other identities stay flat.
    private var activeCallIdentity: String?

    /// Per-camera user-set audio listen state. When an identity is in
    /// this set, its remote audio is played to the caregiver's speaker
    /// even outside a Talk call. The caregiver toggles this via the
    /// per-tile mute button on the Live tab.
    ///
    /// Audio plays iff `identity in audioEnabledByIdentity || identity
    /// == activeCallIdentity`. Talk wins (the active call always plays
    /// regardless of user-set state), and the previous mute state is
    /// preserved across Talk start/end so silencing a tile sticks.
    private(set) var audioEnabledByIdentity: Set<String> = []

    /// Tap on the combined remote-audio buffer (all remote tracks
    /// mixed just before playback). The per-track
    /// `RemoteAudioTrack.add(audioRenderer:)` path was dead in
    /// real-device e2e (subscribed-track fired 4× across camera
    /// reconnects, render never fired once — likely the multicast
    /// adapter's `NSHashTable.weakObjects()` going stale across the
    /// resubscribe thrash). Combined hits a different SDK seam
    /// (`renderPreProcessingDelegate`) and only fires when audio
    /// actually plays out the speaker — which, with the
    /// subscribe-muted default below, only happens during a call.
    private let combinedRemoteTap: _AudioLevelTap

    init() {
        self.room = Room()
        // The combined-tap closure needs a path back to `self` to push
        // peaks onto MainActor state. We can't write `[weak self]`
        // directly here — `self` isn't yet fully initialized until
        // every stored property is set. A small weak-box class solves
        // that without creating a retain cycle (closure -> box ->
        // weak LiveKitClient).
        let box = _LiveKitClientWeakBox()
        self.combinedRemoteTap = _AudioLevelTap(identity: "_combined_") { _, peak in
            Task { @MainActor in
                box.ref?.pushAudioLevelToActiveCall(peak: peak)
            }
        }
        box.ref = self
        AudioManager.shared.add(remoteAudioRenderer: combinedRemoteTap)
        #if DEBUG
        print("[LiveKit] combinedRemoteTap registered with AudioManager.shared.add(remoteAudioRenderer:)")
        #endif
        // Delegate set in init so we capture every event from
        // construction onward — no race against the first `connect`.
        room.add(delegate: self)
    }

    // MARK: - Connectivity predicate

    /// Authoritative "is this camera live to us right now" check.
    /// Use this from any UI that needs to decide between "ready to
    /// view / call" and "show offline / waiting". Don't read `state`,
    /// `cam.online`, or `videoTracksByIdentity` directly — the
    /// answer can disagree across them during transient reconnects.
    ///
    /// `cam.online` is intentionally NOT consulted: the SDK's
    /// `videoTracksByIdentity` map IS the most direct signal for
    /// "video is flowing from this publisher right now," and the
    /// backend's `online` column can lag the SDK by up to ~10s (the
    /// REST reconcile interval). Using SDK presence keeps the chip
    /// honest at the same instant the tile starts/stops rendering
    /// video.
    func connectivity(of cam: Camera) -> CameraConnectivity {
        guard let identity = cam.livekitIdentity else { return .unpaired }
        guard state == .connected else { return .roomDown }
        if videoTracksByIdentity[identity] != nil { return .live }
        return .offline
    }

    /// Convenience for the common "is fully live" gate (call buttons,
    /// full-screen entry, waveform display, etc.).
    func isLive(_ cam: Camera) -> Bool {
        connectivity(of: cam) == .live
    }

    // MARK: - Connection

    func connect(url: String, token: String, room roomName: String) async {
        #if DEBUG
        print("[LiveKit] connect → room=\(roomName) url=\(url) (prevState=\(state))")
        #endif
        if state != .disconnected {
            await room.disconnect()
        }
        state = .connecting
        currentRoom = roomName
        do {
            try await room.connect(url: url, token: token)
            // Terminal state arrives via the delegate; don't pre-flip.
            #if DEBUG
            print("[LiveKit] connect → room.connect() returned ok; remoteParticipants=\(room.remoteParticipants.keys.map { $0.stringValue })")
            #endif
        } catch {
            state = .failed("\(error)")
            currentRoom = nil
            #if DEBUG
            print("[LiveKit] connect FAILED room=\(roomName): \(error)")
            #endif
        }
    }

    // MARK: - Best-effort re-subscribe (Realtime-driven reconciler)

    /// Best-effort re-subscribe path for the case where the SDK has
    /// missed a `track_subscribed` event for an identity that we know
    /// (via Supabase Realtime `cameras.online=true`) is currently
    /// publishing. This is the iOS analog of the backend's REST-poll
    /// reconciler: the SDK's in-memory event-sourced view of a room
    /// can drift after the WebRTC engine restarts internally (we saw
    /// this on the backend with the `recreateEngine` bug class).
    ///
    /// Steps, in order of escalation:
    ///   1. Already have a video track for this identity → no-op.
    ///   2. Room not connected yet → bail; the connect-time backfill
    ///      will pick it up.
    ///   3. Participant present in `remoteParticipants` but tracks
    ///      missing → walk publications and call `set(subscribed:
    ///      true)` so the SDK re-issues the subscribe RPC.
    ///   4. Participant absent from SDK entirely (true desync) →
    ///      force a room disconnect. The caller's supervisor /
    ///      connect-time backfill brings it back with a fresh
    ///      participant list.
    ///
    /// Idempotent and cheap; safe to call from every Realtime
    /// `cameras` UPDATE.
    func ensureSubscribed(identity: String, reconnectIfAbsent: Bool = true) async {
        guard state == .connected else {
            #if DEBUG
            print("[LiveKit] ensureSubscribed: identity=\(identity) skipped — room not connected (state=\(state))")
            #endif
            return
        }
        if videoTracksByIdentity[identity] != nil { return }

        let participant = room.remoteParticipants.values.first(where: {
            $0.identity?.stringValue == identity
        })
        guard let participant else {
            #if DEBUG
            print("[LiveKit] ensureSubscribed: identity=\(identity) absent from SDK (reconnectIfAbsent=\(reconnectIfAbsent))")
            #endif
            // Force a fresh reconnect ONLY when the caller knows the
            // publisher really is in the room (worker-confirmed
            // `online=true`) — that's a true SDK desync. The realtime
            // `desired_state==connected` path over-calls this while the
            // publisher may simply not have rejoined yet; tearing the
            // room down there would strand us (nothing re-mints on iOS
            // outside the view's bootstrap).
            if reconnectIfAbsent {
                await room.disconnect()
            }
            return
        }

        #if DEBUG
        print("[LiveKit] ensureSubscribed: identity=\(identity) found; re-subscribing \(participant.trackPublications.count) publication(s)")
        #endif
        for pub in participant.trackPublications.values {
            guard let remotePub = pub as? RemoteTrackPublication else { continue }
            do {
                try await remotePub.set(subscribed: true)
            } catch {
                #if DEBUG
                print("[LiveKit] ensureSubscribed: set(subscribed:) failed for sid=\(pub.sid.stringValue): \(error)")
                #endif
            }
        }
    }

    func disconnect() async {
        await room.disconnect()
        // Explicitly null the tracks now so the UI shows empty tiles
        // immediately, not after the next delegate round-trip.
        videoTracksByIdentity = [:]
        audioTracksByIdentity = [:]
        remoteAudioTracksByIdentity = [:]
        audioLevels = [:]
        activeCallIdentity = nil
        // Per-tile mute state is connection-scoped: a fresh patient
        // session should start with every tile muted again.
        audioEnabledByIdentity = []
        currentRoom = nil
        state = .disconnected
    }

    // MARK: - Remote audio gate (Talk mode)

    /// Enable speaker playback (and waveform rendering) for exactly
    /// one camera identity, or none. Mirrors the camera-side gate the
    /// wall phone applies to caregiver-published audio: nothing plays
    /// unless both ends agree a call is active.
    ///
    /// - Parameter identity: the camera whose audio should be heard,
    ///   or nil to mute all remote audio (call ended / not started).
    ///
    /// The per-tile mute state (`audioEnabledByIdentity`) is preserved
    /// — the active call identity only overlays an additional unmute,
    /// it does not clear the user's listen choices.
    func setRemoteAudioPlayback(enabledFor identity: String?) {
        activeCallIdentity = identity
        if identity == nil {
            // Drop visualised levels immediately so the waveform goes
            // flat the instant the caregiver taps end — no waiting on
            // the next render that won't come.
            audioLevels = [:]
        }
        applyAudioGate()
        #if DEBUG
        print("[LiveKit] setRemoteAudioPlayback active=\(identity ?? "nil"), tracks=\(remoteAudioTracksByIdentity.count)")
        #endif
    }

    /// Per-tile user-driven mute toggle. Independent of Talk mode —
    /// the caregiver can unmute a passive tile to listen in without
    /// starting a Talk call. State persists across Talk start/end.
    ///
    /// Returns the new audio-enabled state (true = audible, false =
    /// muted). UI uses the returned value to update the button icon
    /// without a separate read.
    @discardableResult
    func toggleAudio(forIdentity identity: String) -> Bool {
        let nowEnabled: Bool
        if audioEnabledByIdentity.contains(identity) {
            audioEnabledByIdentity.remove(identity)
            nowEnabled = false
        } else {
            audioEnabledByIdentity.insert(identity)
            nowEnabled = true
        }
        applyAudioGate()
        return nowEnabled
    }

    /// True iff the caregiver will hear audio from this camera right
    /// now — either because they unmuted it via the per-tile toggle,
    /// or because Talk is active on this camera.
    func isAudioAudible(forIdentity identity: String) -> Bool {
        audioEnabledByIdentity.contains(identity)
            || identity == activeCallIdentity
    }

    /// Apply the combined Talk + per-tile mute state to every
    /// subscribed remote audio track's `volume`. Volume gating is
    /// preferred over (un)subscribing because the combined-remote
    /// renderer doesn't recover cleanly from churned subscriptions —
    /// see the comment on `remoteAudioTracksByIdentity` above.
    private func applyAudioGate() {
        for (id, track) in remoteAudioTracksByIdentity {
            let audible =
                audioEnabledByIdentity.contains(id) || id == activeCallIdentity
            track.volume = audible ? 1.0 : 0.0
        }
    }

    // MARK: - Microphone publish (Talk mode)

    /// Toggle the caregiver's mic track on the existing connection.
    /// The broadcaster-role token granted by `/v1/livekit/token`
    /// already permits `canPublish=true`.
    func publishMicrophone(enable: Bool) async throws {
        guard state == .connected || state == .reconnecting else {
            throw LiveKitClientError.notConnected
        }
        try await room.localParticipant.setMicrophone(enabled: enable)
        isMicrophonePublished = enable
    }

    // MARK: - Internal: track lifecycle (called from delegate hop)

    fileprivate func handleSubscribedVideo(_ track: VideoTrack, identity: String) {
        videoTracksByIdentity[identity] = track
    }

    fileprivate func handleSubscribedAudio(
        _ track: AudioTrack,
        identity: String,
    ) {
        audioTracksByIdentity[identity] = track
        if let remote = track as? RemoteAudioTrack {
            remoteAudioTracksByIdentity[identity] = remote
            // Silent speaker by default — track stays subscribed and
            // decodes, but no audible output until either (a) the
            // caregiver taps Call (which flips the active camera's
            // volume to 1.0 via setRemoteAudioPlayback) or (b) the
            // caregiver unmutes the tile via toggleAudio. Continuous
            // decode is what keeps the combined-remote renderer firing
            // reliably; the earlier `publication.set(enabled:)`
            // approach churned the SDK's audio engine and the renderer
            // never recovered.
            let audible =
                audioEnabledByIdentity.contains(identity)
                    || identity == activeCallIdentity
            remote.volume = audible ? 1.0 : 0.0
        }
        #if DEBUG
        print("[LiveKit] subscribed audio: identity=\(identity), volume=\((track as? RemoteAudioTrack)?.volume ?? -1)")
        #endif
    }

    fileprivate func handleUnsubscribedVideo(identity: String) {
        videoTracksByIdentity.removeValue(forKey: identity)
    }

    fileprivate func handleUnsubscribedAudio(identity: String) {
        audioTracksByIdentity.removeValue(forKey: identity)
        remoteAudioTracksByIdentity.removeValue(forKey: identity)
        audioLevels.removeValue(forKey: identity)
    }

    private func pushAudioLevelToActiveCall(peak: Float) {
        guard let identity = activeCallIdentity else {
            #if DEBUG
            // No active call — render fired but waveform shouldn't move
            // anyway. Throttled: only every 256th would-be push.
            droppedPushCount &+= 1
            if droppedPushCount % 256 == 1 {
                print("[LiveKit] pushAudioLevel DROPPED (no activeCallIdentity), peak=\(peak), dropped#=\(droppedPushCount)")
            }
            #endif
            return
        }
        var samples = audioLevels[identity] ?? []
        samples.append(peak)
        if samples.count > audioLevelCapacity {
            samples.removeFirst(samples.count - audioLevelCapacity)
        }
        audioLevels[identity] = samples
        #if DEBUG
        acceptedPushCount &+= 1
        if acceptedPushCount <= 5 || acceptedPushCount % 256 == 0 {
            print("[LiveKit] pushAudioLevel id=\(identity), peak=\(peak), levels.count=\(samples.count), accepted#=\(acceptedPushCount)")
        }
        #endif
    }

    #if DEBUG
    private var acceptedPushCount: Int = 0
    private var droppedPushCount: Int = 0
    #endif
}

enum LiveKitClientError: Error, LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to a LiveKit room."
        }
    }
}

// MARK: - RoomDelegate

extension LiveKitClient: RoomDelegate {

    nonisolated func room(_: Room, didUpdateConnectionState newState: ConnectionState, from oldState: ConnectionState) {
        #if DEBUG
        print("[LiveKit] connState \(oldState) → \(newState)")
        #endif
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            switch newState {
            case .disconnected:
                // Don't clobber a terminal failure — keeps the reason
                // visible in the UI.
                if case .failed = self.state { return }
                self.state = .disconnected
            case .connecting: self.state = .connecting
            case .connected: self.state = .connected
            case .reconnecting: self.state = .reconnecting
            case .disconnecting: self.state = .disconnected
            @unknown default: self.state = .disconnected
            }
        }
    }

    nonisolated func room(
        _: Room,
        participant: RemoteParticipant,
        didSubscribeTrack publication: RemoteTrackPublication,
    ) {
        let track = publication.track
        let identity = participant.identity?.stringValue ?? ""
        guard !identity.isEmpty else { return }
        #if DEBUG
        print("[LiveKit] didSubscribeTrack identity=\(identity) kind=\(publication.kind)")
        #endif
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let vt = track as? VideoTrack {
                self.handleSubscribedVideo(vt, identity: identity)
            } else if let at = track as? AudioTrack {
                self.handleSubscribedAudio(at, identity: identity)
            }
        }
    }

    /// A remote participant published a track — fires whenever ANY camera
    /// turns on (sensor Start, web, or iOS), no matter who triggered it or
    /// how `desired_state`/`online`/Realtime are timed. With autoSubscribe
    /// the SDK *usually* follows with `didSubscribeTrack`, but it can miss
    /// that for a publisher who joins AFTER we connected — the intermittent
    /// "fresh camera-on doesn't show on iOS" case. Force the subscribe here;
    /// `ensureSubscribed` no-ops if we already have the track.
    nonisolated func room(
        _: Room,
        participant: RemoteParticipant,
        didPublishTrack publication: RemoteTrackPublication,
    ) {
        let identity = participant.identity?.stringValue ?? ""
        guard !identity.isEmpty else { return }
        #if DEBUG
        print("[LiveKit] didPublishTrack identity=\(identity) kind=\(publication.kind) — ensuring subscribed")
        #endif
        Task { @MainActor [weak self] in
            await self?.ensureSubscribed(identity: identity, reconnectIfAbsent: false)
        }
    }

    /// A remote participant joined. It may already have published tracks
    /// (publish/connect ordering races), so reconcile its subscriptions now
    /// too — belt-and-suspenders for the same source-agnostic goal.
    nonisolated func room(_: Room, participantDidConnect participant: RemoteParticipant) {
        let identity = participant.identity?.stringValue ?? ""
        guard !identity.isEmpty else { return }
        #if DEBUG
        print("[LiveKit] participantDidConnect identity=\(identity) — ensuring subscribed")
        #endif
        Task { @MainActor [weak self] in
            await self?.ensureSubscribed(identity: identity, reconnectIfAbsent: false)
        }
    }

    nonisolated func room(
        _: Room,
        participant: RemoteParticipant,
        didUnsubscribeTrack publication: RemoteTrackPublication,
    ) {
        let kind = publication.kind
        let identity = participant.identity?.stringValue ?? ""
        guard !identity.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            switch kind {
            case .video: self.handleUnsubscribedVideo(identity: identity)
            case .audio: self.handleUnsubscribedAudio(identity: identity)
            default: break
            }
        }
    }
}

/// Weak ref to `LiveKitClient`, used by the combined-remote audio tap
/// closure so it can hop onto `LiveKitClient` without retaining it.
private final class _LiveKitClientWeakBox: @unchecked Sendable {
    weak var ref: LiveKitClient?
}

// MARK: - Audio level tap

/// `AudioRenderer` implementation that computes the peak amplitude of
/// each PCM buffer and forwards it to a callback. Used by
/// `LiveKitClient` to drive the per-camera waveform.
///
/// Cheap on purpose — peak amplitude is a single `vDSP_maxmgv` over
/// the float channel data, no FFT, no allocation per call. The
/// renderer runs on the LiveKit SDK's internal audio queue; the
/// closure must be safe to call off the main actor (it hops via
/// `Task { @MainActor in ... }`).
private final class _AudioLevelTap: NSObject, AudioRenderer, @unchecked Sendable {
    let identity: String
    let callback: @Sendable (String, Float) -> Void

    /// Atomic counter for throttled DEBUG logging (one line per ~256
    /// pcm buffers ≈ once per several seconds). Helps confirm the
    /// renderer is actually firing without spamming the console.
    private let renderCount = OSAllocatedUnfairLock(initialState: 0)

    init(identity: String, callback: @escaping @Sendable (String, Float) -> Void) {
        self.identity = identity
        self.callback = callback
    }

    func render(pcmBuffer: AVAudioPCMBuffer) {
        guard let channelData = pcmBuffer.floatChannelData else { return }
        let frameLength = Int(pcmBuffer.frameLength)
        guard frameLength > 0 else { return }
        // Mix all channels into a single peak so a stereo track
        // doesn't visually double itself. In practice the wall phone
        // publishes mono, so this is a one-channel loop.
        var peak: Float = 0
        let channelCount = Int(pcmBuffer.format.channelCount)
        for ch in 0..<channelCount {
            let ptr = channelData[ch]
            for i in 0..<frameLength {
                let v = abs(ptr[i])
                if v > peak { peak = v }
            }
        }
        let clamped = min(peak, 1.0)
        callback(identity, clamped)
        #if DEBUG
        let snapshotIdentity = identity
        renderCount.withLock { count in
            count += 1
            // First 3 buffers (catches "did it ever fire") + every
            // 256th thereafter (confirms it keeps firing without
            // flooding the console).
            if count <= 3 || count % 256 == 0 {
                print("[LiveKit] audio render: identity=\(snapshotIdentity), peak=\(clamped), buf#=\(count)")
            }
        }
        #endif
    }
}
