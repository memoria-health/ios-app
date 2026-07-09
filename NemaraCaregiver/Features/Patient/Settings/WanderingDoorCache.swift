import LiveKit
import SwiftUI

/// Result of trying to load a door-picker frame.
enum DoorLoadOutcome: Sendable, Equatable {
    case ok                    // a frame is now in the cache
    case blocked(String)       // recoverable: not streaming
    case failed(String)        // connect / capture error
}

/// Process-wide cache of the captured camera frame + detected doors, keyed by
/// CAMERA. The exit door is per-sensor, so each camera caches its own frame.
/// This is what makes the picker NOT re-analyze every open: the first open (or
/// an explicit Reload) grabs a frame + runs door detection once; later opens
/// read the cached result instantly. Also used to pre-warm.
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

    private var frames: [UUID: Frame] = [:]                 // keyed by cameraId
    private var inFlight: [UUID: Task<DoorLoadOutcome, Never>] = [:]

    func cached(_ cameraId: UUID) -> Frame? { frames[cameraId] }

    /// Return immediately if a frame is cached for this camera; otherwise load
    /// one (deduped so concurrent callers share a single capture + detection).
    func ensureLoaded(
        cameraId: UUID, patientId: UUID, identity: String,
        api: NemaraAPIClient, liveKit: LiveKitClient,
    ) async -> DoorLoadOutcome {
        if frames[cameraId] != nil { return .ok }
        if let task = inFlight[cameraId] { return await task.value }
        let task = Task {
            await self.run(cameraId: cameraId, patientId: patientId,
                           identity: identity, api: api, liveKit: liveKit)
        }
        inFlight[cameraId] = task
        let outcome = await task.value
        inFlight[cameraId] = nil
        return outcome
    }

    /// Force a fresh capture + detection for this camera (the Reload button).
    func reload(
        cameraId: UUID, patientId: UUID, identity: String,
        api: NemaraAPIClient, liveKit: LiveKitClient,
    ) async -> DoorLoadOutcome {
        inFlight[cameraId]?.cancel()
        inFlight[cameraId] = nil
        frames[cameraId] = nil
        return await ensureLoaded(cameraId: cameraId, patientId: patientId,
                                  identity: identity, api: api, liveKit: liveKit)
    }

    // MARK: - Load pipeline

    private func run(
        cameraId: UUID, patientId: UUID, identity: String,
        api: NemaraAPIClient, liveKit: LiveKitClient,
    ) async -> DoorLoadOutcome {
        // Reuse an already-connected room (e.g. the Live tab); otherwise open one
        // ourselves and tear it back down after grabbing the frame so we never
        // leave a dangling connection or disturb an active Live view.
        let room = "patient_\(patientId.uuidString.lowercased())"
        var weConnected = false
        if liveKit.currentRoom != room || liveKit.state != .connected {
            do {
                let tok = try await api.mintViewerToken(forPatient: patientId)
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
            return .blocked("This sensor isn't streaming right now. Open its Live view to wake it, then try again.")
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
        frames[cameraId] = Frame(jpeg: jpeg, image: image, doors: doors, capturedAt: Date())
        return .ok
    }
}
