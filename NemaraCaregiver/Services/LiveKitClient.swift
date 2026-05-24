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

    /// Active audio taps, keyed by publisher identity. Held so we
    /// can remove them when the track unsubscribes.
    private var audioTaps: [String: _AudioLevelTap] = [:]

    init() {
        self.room = Room()
        // Delegate set in init so we capture every event from
        // construction onward — no race against the first `connect`.
        room.add(delegate: self)
    }

    // MARK: - Connection

    func connect(url: String, token: String, room roomName: String) async {
        if state != .disconnected {
            await room.disconnect()
        }
        state = .connecting
        currentRoom = roomName
        do {
            try await room.connect(url: url, token: token)
            // Terminal state arrives via the delegate; don't pre-flip.
        } catch {
            state = .failed("\(error)")
            currentRoom = nil
        }
    }

    func disconnect() async {
        await room.disconnect()
        // Explicitly null the tracks now so the UI shows empty tiles
        // immediately, not after the next delegate round-trip.
        videoTracksByIdentity = [:]
        audioTracksByIdentity = [:]
        audioLevels = [:]
        audioTaps = [:]
        currentRoom = nil
        state = .disconnected
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

    fileprivate func handleSubscribedAudio(_ track: AudioTrack, identity: String) {
        audioTracksByIdentity[identity] = track
        // Attach an AudioRenderer to start populating audioLevels.
        // The tap retains a weak ref to self via the closure.
        let tap = _AudioLevelTap(identity: identity) { [weak self] identity, peak in
            Task { @MainActor [weak self] in
                self?.pushAudioLevel(identity: identity, peak: peak)
            }
        }
        track.add(audioRenderer: tap)
        audioTaps[identity] = tap
        #if DEBUG
        print("[LiveKit] subscribed audio: identity=\(identity), tap attached")
        #endif
    }

    fileprivate func handleUnsubscribedVideo(identity: String) {
        videoTracksByIdentity.removeValue(forKey: identity)
    }

    fileprivate func handleUnsubscribedAudio(identity: String) {
        if let tap = audioTaps.removeValue(forKey: identity),
           let track = audioTracksByIdentity[identity] {
            track.remove(audioRenderer: tap)
        }
        audioTracksByIdentity.removeValue(forKey: identity)
        audioLevels.removeValue(forKey: identity)
    }

    private func pushAudioLevel(identity: String, peak: Float) {
        var samples = audioLevels[identity] ?? []
        samples.append(peak)
        if samples.count > audioLevelCapacity {
            samples.removeFirst(samples.count - audioLevelCapacity)
        }
        audioLevels[identity] = samples
    }
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

    nonisolated func room(_: Room, didUpdateConnectionState newState: ConnectionState, from _: ConnectionState) {
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
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let vt = track as? VideoTrack {
                self.handleSubscribedVideo(vt, identity: identity)
            } else if let at = track as? AudioTrack {
                self.handleSubscribedAudio(at, identity: identity)
            }
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
            if count == 1 || count % 256 == 0 {
                print("[LiveKit] audio render: identity=\(snapshotIdentity), peak=\(clamped), buf#=\(count)")
            }
        }
        #endif
    }
}
