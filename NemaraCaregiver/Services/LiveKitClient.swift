import Foundation
import LiveKit
import Observation

/// Wraps a single `LiveKit.Room` for the lifetime of the caregiver app.
///
/// One instance lives in `AppEnvironment` and is reused across patients —
/// the caregiver only ever views one room at a time (the patient whose
/// Live tab is open). Opening a different patient's Live tab disconnects
/// the previous room first.
///
/// Phase 1 (Look-In): just `connect`/`disconnect` + observe the first
/// remote video track so `PatientLiveView` can render it.
///
/// Phase 3 (Talk) extends this with `publishMicrophone(enable:)` so the
/// caregiver can speak into the wall phone(s). Data-message routing
/// (`{type: "set_talk_active"}`) is server-driven, not client-driven —
/// nothing for this class to send.
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

    /// Current connection state, mirrored from `Room.connectionState`
    /// transitions arriving on the room delegate.
    private(set) var state: State = .disconnected

    /// First subscribed remote video track. `PatientLiveView` renders
    /// this. Multi-track UI (split screen across cameras in the patient's
    /// home) is a v2 concern.
    private(set) var videoTrack: VideoTrack?

    /// First subscribed remote audio track. Caregiver doesn't need to
    /// gate it (LiveKit plays it automatically) but we surface it for
    /// the audio-meter UI Phase 3 wants.
    private(set) var audioTrack: AudioTrack?

    /// True iff Talk mode is currently publishing the caregiver mic.
    /// Driven by `publishMicrophone(enable:)` below.
    private(set) var isMicrophonePublished: Bool = false

    /// The current room name (`patient_<patient_id>`) we're connected
    /// to. nil when disconnected. Set on a successful `connect`.
    private(set) var currentRoom: String?

    /// The underlying LiveKit Room. Holds the WebRTC session, the
    /// SFU connection, and the participant graph. We re-use a single
    /// instance across (dis)connect cycles — `room.connect(...)` works
    /// fine on a previously-disconnected room.
    private let room: Room

    init() {
        // Delegate set in init so we capture every event from
        // construction onward — no race against the first `connect`.
        self.room = Room()
        room.add(delegate: self)
    }

    // MARK: - Phase 1 connect/disconnect

    func connect(url: String, token: String, room roomName: String) async {
        // Disconnect any previous session first. `room.disconnect()` is
        // idempotent on a never-connected Room; safe to call.
        if state != .disconnected {
            await room.disconnect()
        }
        state = .connecting
        currentRoom = roomName
        do {
            try await room.connect(url: url, token: token)
            // State transitions to `.connected` arrive via the delegate
            // (`room(_:didUpdate connectionState:from:)`). Do not flip
            // manually here — that would race against an immediate
            // delegate callback that might already be `.reconnecting`.
        } catch {
            state = .failed("\(error)")
            currentRoom = nil
        }
    }

    func disconnect() async {
        await room.disconnect()
        // Track refs cleared on the delegate's didUnsubscribe path;
        // explicitly null here too so PatientLiveView's onDisappear
        // shows an empty tile immediately, not after the next
        // round-trip.
        videoTrack = nil
        audioTrack = nil
        currentRoom = nil
        state = .disconnected
    }

    // MARK: - Phase 3 Talk

    /// Enable / disable the caregiver's mic track. Publishing happens
    /// over the same `Room`; the broadcaster-role token granted by
    /// `/v1/livekit/token` already permits `canPublish=true`.
    func publishMicrophone(enable: Bool) async throws {
        guard state == .connected || state == .reconnecting else {
            throw LiveKitClientError.notConnected
        }
        try await room.localParticipant.setMicrophone(enabled: enable)
        isMicrophonePublished = enable
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
                // Only flip if we weren't already in a terminal failure
                // — keeps the failure reason visible to the UI.
                if case .failed = self.state { return }
                self.state = .disconnected
            case .connecting:
                self.state = .connecting
            case .connected:
                self.state = .connected
            case .reconnecting:
                self.state = .reconnecting
            case .disconnecting:
                // Treat in-flight teardown as already-disconnected so
                // the UI doesn't briefly hold a stale `.connected`
                // pill. Track refs cleared via the unsubscribe path.
                self.state = .disconnected
            @unknown default:
                self.state = .disconnected
            }
        }
    }

    nonisolated func room(
        _: Room,
        participant _: RemoteParticipant,
        didSubscribeTrack publication: RemoteTrackPublication,
    ) {
        let track = publication.track
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let vt = track as? VideoTrack {
                self.videoTrack = vt
            } else if let at = track as? AudioTrack {
                self.audioTrack = at
            }
        }
    }

    nonisolated func room(
        _: Room,
        participant _: RemoteParticipant,
        didUnsubscribeTrack publication: RemoteTrackPublication,
    ) {
        let track = publication.track
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let vt = track as? VideoTrack, vt === self.videoTrack {
                self.videoTrack = nil
            } else if let at = track as? AudioTrack, at === self.audioTrack {
                self.audioTrack = nil
            }
        }
    }
}
