import LiveKit
import SwiftUI

/// Result of trying to load a door-picker frame.
enum DoorLoadOutcome: Sendable, Equatable {
    case ok                    // a frame is now in the cache
    case blocked(String)       // recoverable: not streaming
    case failed(String)        // connect / capture error
}

/// Process-wide cache for the exit-door picker, keyed by CAMERA. Two separate
/// concerns so the UI never blocks on the LLM:
///   • FRAME  — connect + grab one still; shown immediately, tap-place enabled.
///   • DOORS  — a single background VLM call; dots overlay when/if it returns.
/// The first open (or Reload) captures once; later opens read the cache.
@MainActor
@Observable
final class WanderingDoorCache {
    static let shared = WanderingDoorCache()
    private init() {}

    struct Frame {
        let jpeg: Data
        let image: UIImage
        let capturedAt: Date
    }

    private var frames: [UUID: Frame] = [:]
    private var doors: [UUID: [DetectedDoor]] = [:]
    private var frameTasks: [UUID: Task<DoorLoadOutcome, Never>] = [:]
    private var doorTasks: [UUID: Task<[DetectedDoor], Never>] = [:]

    func cachedFrame(_ cameraId: UUID) -> Frame? { frames[cameraId] }
    func cachedDoors(_ cameraId: UUID) -> [DetectedDoor]? { doors[cameraId] }

    // MARK: - Frame (fast; no LLM)

    /// Grab (or return the cached) still frame for this camera. No detection —
    /// this is what the picker awaits so the view appears fast.
    func ensureFrame(
        cameraId: UUID, patientId: UUID, identity: String,
        api: NemaraAPIClient, liveKit: LiveKitClient,
    ) async -> DoorLoadOutcome {
        if frames[cameraId] != nil { return .ok }
        if let task = frameTasks[cameraId] { return await task.value }
        let task = Task {
            await self.grab(cameraId: cameraId, patientId: patientId,
                            identity: identity, api: api, liveKit: liveKit)
        }
        frameTasks[cameraId] = task
        let outcome = await task.value
        frameTasks[cameraId] = nil
        return outcome
    }

    /// Force a fresh capture (+ drop stale doors) — the Reload button.
    func reloadFrame(
        cameraId: UUID, patientId: UUID, identity: String,
        api: NemaraAPIClient, liveKit: LiveKitClient,
    ) async -> DoorLoadOutcome {
        frameTasks[cameraId]?.cancel(); frameTasks[cameraId] = nil
        doorTasks[cameraId]?.cancel(); doorTasks[cameraId] = nil
        frames[cameraId] = nil
        doors[cameraId] = nil
        return await ensureFrame(cameraId: cameraId, patientId: patientId,
                                 identity: identity, api: api, liveKit: liveKit)
    }

    // MARK: - Doors (single background VLM call)

    /// Detect doors on the already-captured frame (cached). Returns [] if there's
    /// no frame yet or detection fails — the caregiver just tap-places instead.
    func ensureDoors(cameraId: UUID, api: NemaraAPIClient) async -> [DetectedDoor] {
        if let cached = doors[cameraId] { return cached }
        guard let frame = frames[cameraId] else { return [] }
        if let task = doorTasks[cameraId] { return await task.value }
        let task = Task { () -> [DetectedDoor] in
            let found = (try? await api.detectDoors(
                imageBase64: frame.jpeg.base64EncodedString())) ?? []
            self.doors[cameraId] = found
            return found
        }
        doorTasks[cameraId] = task
        let result = await task.value
        doorTasks[cameraId] = nil
        return result
    }

    // MARK: - Capture pipeline

    private func grab(
        cameraId: UUID, patientId: UUID, identity: String,
        api: NemaraAPIClient, liveKit: LiveKitClient,
    ) async -> DoorLoadOutcome {
        // Reuse an already-connected room (e.g. the Live tab); otherwise open one
        // ourselves and tear it down after grabbing so we never leave a dangling
        // connection or disturb an active Live view.
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
        if weConnected { await liveKit.disconnect() }
        guard let jpeg, let image = UIImage(data: jpeg) else {
            return .failed("Couldn't capture a frame from the camera. Please try again.")
        }
        frames[cameraId] = Frame(jpeg: jpeg, image: image, capturedAt: Date())
        return .ok
    }
}
