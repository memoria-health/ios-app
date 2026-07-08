import LiveKit
import SwiftUI

/// Result of trying to load a door-picker frame.
enum DoorLoadOutcome: Sendable, Equatable {
    case ok                    // a frame is now in the cache
    case blocked(String)       // recoverable: no camera / not streaming
    case failed(String)        // connect / capture error
}

/// Process-wide cache of the captured camera frame + detected doors, keyed by
/// patient. This is what makes the exit-door picker NOT re-analyze every time
/// it opens: the first open (or an explicit Reload) grabs a frame and runs door
/// detection once; subsequent opens read the cached result instantly. Also used
/// to pre-warm the frame when the wandering detector row appears.
@MainActor
@Observable
final class WanderingDoorCache {
    static let shared = WanderingDoorCache()
    private init() {}

    struct Frame {
        let jpeg: Data
        let image: UIImage
        let doors: [DetectedDoor]
        let capturedAt: Date
    }

    private var frames: [UUID: Frame] = [:]
    private var inFlight: [UUID: Task<DoorLoadOutcome, Never>] = [:]

    func cached(_ pid: UUID) -> Frame? { frames[pid] }

    /// Return immediately if a frame is cached; otherwise load one (deduped so
    /// concurrent callers share a single capture + detection).
    func ensureLoaded(
        _ pid: UUID, api: NemaraAPIClient, liveKit: LiveKitClient,
    ) async -> DoorLoadOutcome {
        if frames[pid] != nil { return .ok }
        if let task = inFlight[pid] { return await task.value }
        let task = Task { await self.run(pid, api: api, liveKit: liveKit) }
        inFlight[pid] = task
        let outcome = await task.value
        inFlight[pid] = nil
        return outcome
    }

    /// Force a fresh capture + detection (the Reload button).
    func reload(
        _ pid: UUID, api: NemaraAPIClient, liveKit: LiveKitClient,
    ) async -> DoorLoadOutcome {
        inFlight[pid]?.cancel()
        inFlight[pid] = nil
        frames[pid] = nil
        return await ensureLoaded(pid, api: api, liveKit: liveKit)
    }

    // MARK: - Load pipeline

    private func run(
        _ pid: UUID, api: NemaraAPIClient, liveKit: LiveKitClient,
    ) async -> DoorLoadOutcome {
        let cams = api.camerasByPatient[pid] ?? []
        let target = cams.first { $0.livekitIdentity != nil && $0.online && !$0.disabled }
            ?? cams.first { $0.livekitIdentity != nil }
        guard let identity = target?.livekitIdentity else {
            return .blocked("This patient doesn't have a paired camera yet. Pair one first, then set the exit door.")
        }

        // Reuse an already-connected room (e.g. the Live tab); otherwise open one
        // ourselves and tear it back down after grabbing the frame so we never
        // leave a dangling connection or disturb an active Live view.
        let room = "patient_\(pid.uuidString.lowercased())"
        var weConnected = false
        if liveKit.currentRoom != room || liveKit.state != .connected {
            do {
                let tok = try await api.mintViewerToken(forPatient: pid)
                await liveKit.connect(url: tok.url, token: tok.token, room: room)
                weConnected = true
            } catch {
                return .failed("Couldn't connect to the camera. Check your connection and try again.")
            }
        }

        var track: VideoTrack?
        for _ in 0..<30 {
            if let t = liveKit.videoTracksByIdentity[identity] { track = t; break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let track else {
            if weConnected { await liveKit.disconnect() }
            return .blocked("The camera isn't streaming right now. Open the Live tab to wake it, then try again.")
        }

        let jpeg = await LiveKitFrameCapture.jpeg(from: track)
        if weConnected { await liveKit.disconnect() }   // done with LiveKit
        guard let jpeg, let image = UIImage(data: jpeg) else {
            return .failed("Couldn't capture a frame from the camera. Please try again.")
        }

        var doors: [DetectedDoor] = []
        do {
            doors = try await api.detectDoors(imageBase64: jpeg.base64EncodedString())
        } catch {
            doors = []   // fall back to tap-to-place; not fatal
        }
        frames[pid] = Frame(jpeg: jpeg, image: image, doors: doors, capturedAt: Date())
        return .ok
    }
}
