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
        cameraId: UUID, api: NemaraAPIClient,
    ) async -> DoorLoadOutcome {
        if frames[cameraId] != nil { return .ok }
        if let task = frameTasks[cameraId] { return await task.value }
        let task = Task { await self.grab(cameraId: cameraId, api: api) }
        frameTasks[cameraId] = task
        let outcome = await task.value
        frameTasks[cameraId] = nil
        return outcome
    }

    /// Force a fresh capture (+ drop stale doors) — the Reload button.
    func reloadFrame(
        cameraId: UUID, api: NemaraAPIClient,
    ) async -> DoorLoadOutcome {
        frameTasks[cameraId]?.cancel(); frameTasks[cameraId] = nil
        doorTasks[cameraId]?.cancel(); doorTasks[cameraId] = nil
        frames[cameraId] = nil
        doors[cameraId] = nil
        return await ensureFrame(cameraId: cameraId, api: api)
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
        cameraId: UUID, api: NemaraAPIClient,
    ) async -> DoorLoadOutcome {
        // Ask the BACKEND for a still rather than subscribing to the track
        // ourselves (2026-08-04).
        //
        // The old path connected to the room, waited up to 6s for
        // `videoTracksByIdentity[identity]`, captured a frame, and tore the
        // connection down. For a PRIVATE camera the track never arrives —
        // privacy mode restricts subscription to the detector workers — so it
        // always timed out and reported "this sensor isn't streaming right
        // now". The sensor was streaming; we simply may not watch it.
        //
        // Letting the picker subscribe would have been the smaller change and
        // the wrong one: it makes this screen a live-view bypass for exactly
        // the rooms privacy mode protects. The server masks people out of the
        // still for private cameras instead, so doors stay visible and the
        // room does not.
        //
        // Side benefit: no room connect, no 6s wait, no teardown, and no risk
        // of disturbing an active Live view.
        do {
            let jpeg = try await api.doorFrame(cameraId: cameraId)
            guard let image = UIImage(data: jpeg) else {
                return .failed("Couldn't read the camera image. Please try again.")
            }
            frames[cameraId] = Frame(jpeg: jpeg, image: image, capturedAt: Date())
            return .ok
        } catch let APIError.serverError(_, message) {
            // The backend distinguishes two 503s, and they need different
            // advice — "check it's online" is wrong when the camera is fine
            // and the privacy mask is what failed.
            switch message {
            case "camera_not_streaming":
                return .blocked("This sensor isn't sending video right now. Check it's online, then try again.")
            case "privacy_mask_unavailable":
                return .failed("Can't show a picture from a private room at the moment. Please try again shortly.")
            default:
                return .failed("The server couldn't provide a picture from this sensor. Please try again.")
            }
        } catch {
            return .failed("Couldn't load a picture from this sensor. Please try again.")
        }
    }
}
