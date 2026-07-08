import AVFoundation
import CoreImage
import Foundation
import LiveKit

/// One-shot grab of a single still frame from a LiveKit ``VideoTrack``,
/// encoded as JPEG. Used by the Wandering exit-door picker to send the current
/// camera view to the door-detection VLM.
///
/// LiveKit delivers frames by attaching a ``VideoRenderer`` to the track; each
/// decoded frame arrives on the SDK's internal video thread (nonisolated). We
/// take the FIRST frame, encode it to JPEG **on that thread** (so only the
/// `Sendable` `Data` crosses back — `CVPixelBuffer` is non-Sendable), resume
/// the awaiting continuation, and detach. Mirrors the `_AudioLevelTap`
/// conformance in `LiveKitClient` — an `NSObject` subclass so Swift bridges the
/// `@objc` `VideoRenderer` requirements.
final class LiveKitFrameGrabber: NSObject, VideoRenderer, @unchecked Sendable {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private let lock = NSLock()
    private var captured = false
    private var continuation: CheckedContinuation<Data?, Never>?
    private let maxWidth: CGFloat
    private let quality: CGFloat

    init(maxWidth: CGFloat, quality: CGFloat) {
        self.maxWidth = maxWidth
        self.quality = quality
    }

    // MARK: VideoRenderer

    // AdaptiveStream hints — we render off-screen for a single frame, so these
    // are constant. (The protocol marks them @MainActor; a constant witness is
    // safe to read from any thread.)
    var isAdaptiveStreamEnabled: Bool { false }
    var adaptiveStreamSize: CGSize { .zero }

    /// Fires on the SDK video thread for every decoded frame. We encode the
    /// first one and ignore the rest.
    func render(frame: VideoFrame) {
        lock.lock()
        if captured {
            lock.unlock()
            return
        }
        captured = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: Self.encode(frame, maxWidth: maxWidth, quality: quality))
    }

    // MARK: Await API

    /// Suspend until the next frame arrives and is encoded (or return nil if one
    /// was already captured). The caller times out and detaches.
    func nextJPEG() async -> Data? {
        await withCheckedContinuation { cont in
            lock.lock()
            if captured {
                lock.unlock()
                cont.resume(returning: nil)
                return
            }
            continuation = cont
            lock.unlock()
        }
    }

    /// If still suspended (e.g. the caller timed out), resume with nil so the
    /// awaiting task doesn't leak.
    func cancel() {
        lock.lock()
        captured = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: nil)
    }

    private static func encode(
        _ frame: VideoFrame, maxWidth: CGFloat, quality: CGFloat,
    ) -> Data? {
        guard let pixelBuffer = frame.toCVPixelBuffer() else { return nil }
        var ci = CIImage(cvPixelBuffer: pixelBuffer)
        let width = ci.extent.width
        if width > maxWidth, width > 0 {
            let s = maxWidth / width
            ci = ci.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        return ciContext.jpegRepresentation(
            of: ci,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality],
        )
    }
}

enum LiveKitFrameCapture {
    /// Attach a one-shot grabber to `track`, wait up to `timeout` seconds for a
    /// frame, and return it as JPEG bytes (downscaled to `maxWidth`). Returns
    /// nil if no frame arrived in time.
    @MainActor
    static func jpeg(
        from track: VideoTrack,
        timeout: TimeInterval = 4,
        maxWidth: CGFloat = 1280,
        quality: CGFloat = 0.85,
    ) async -> Data? {
        let grabber = LiveKitFrameGrabber(maxWidth: maxWidth, quality: quality)
        track.add(videoRenderer: grabber)
        defer { track.remove(videoRenderer: grabber) }

        return await withTaskGroup(of: Data?.self) { group in
            group.addTask { await grabber.nextJPEG() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                grabber.cancel()   // unblocks nextJPEG() with nil
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
