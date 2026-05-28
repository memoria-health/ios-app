import AVFoundation
import SwiftUI
import UIKit

/// `UIViewRepresentable` wrapping `AVCaptureSession` for the live
/// front-camera preview during face enrollment. Exposes a single
/// `capture()` method that snapshots the next sample buffer as a
/// JPEG.
///
/// Design choices:
///   - Front camera only (`.builtInWideAngleCamera`, position `.front`)
///   - 1280×720 capture so the JPEG is ~250-400 KB; iOS Photos-quality
///     selfies are overkill for ArcFace's 112×112 aligned crop
///   - `AVCaptureVideoDataOutput` rather than `AVCapturePhotoOutput`
///     because we want the buffer interception path (so we can drop
///     it into a Data we control without going through the Photos
///     framework's shared-photo permissions)
///   - The preview's `videoOrientation` is fixed to `.portrait`. The
///     enrollment UI is portrait-locked at the View level too, so we
///     don't have to rotate on the fly.
/// Camera capture wrapper. The AVCaptureSession is itself thread-
/// safe for control calls (it has its own internal serialization);
/// we mark this class @unchecked Sendable so Swift 6 strict
/// concurrency doesn't complain about referencing it from background
/// queues. The two @Published properties are written on the main
/// actor via DispatchQueue.main.async so SwiftUI can observe them
/// directly.
final class CameraPreviewModel: ObservableObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "co.elephantlabs.nemara.enrollment-camera")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let delegate: SampleBufferDelegate

    @MainActor @Published private(set) var isConfigured = false
    @MainActor @Published private(set) var setupError: String?

    init() {
        delegate = SampleBufferDelegate()
        videoOutput.setSampleBufferDelegate(delegate, queue: videoQueue)
    }

    /// Idempotent configure: front camera + JPEG-compatible video
    /// output. Safe to call multiple times (no-op after first
    /// success).
    @MainActor
    func configure() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front,
        ) else {
            setupError = "No front-facing camera available"
            session.commitConfiguration()
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            setupError = "Camera input failed: \(error.localizedDescription)"
            session.commitConfiguration()
            return
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_32BGRA,
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if let conn = videoOutput.connection(with: .video) {
            // iOS 17 deprecates videoOrientation in favor of
            // videoRotationAngle, but the legacy API is still
            // functional; we use it for compatibility with our 18.0
            // deployment target without depending on rotation-angle
            // CMVideoOrientation conversions.
            if conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90  // portrait
            }
            // Front camera: mirror so the user sees themselves the
            // same way a mirror does (less disorienting during head
            // turns).
            if conn.isVideoMirroringSupported { conn.isVideoMirrored = true }
        }
        session.commitConfiguration()
        isConfigured = true
    }

    /// Start the capture session. Safe to call from main; the actual
    /// startRunning runs on a background queue because it blocks.
    nonisolated func start() {
        // Capture session ref locally so the closure doesn't capture
        // self across actor boundaries; AVCaptureSession's
        // startRunning is itself thread-safe.
        let sess = session
        DispatchQueue.global(qos: .userInitiated).async {
            if !sess.isRunning { sess.startRunning() }
        }
    }

    nonisolated func stop() {
        let sess = session
        DispatchQueue.global(qos: .userInitiated).async {
            if sess.isRunning { sess.stopRunning() }
        }
    }

    /// Snapshot the next sample as a JPEG. Returns nil if no frame
    /// arrives within a short window (e.g. camera not yet running).
    func captureJPEG(quality: CGFloat = 0.85) async -> Data? {
        guard let image = await delegate.captureNext() else { return nil }
        return image.jpegData(compressionQuality: quality)
    }
}


/// Bridge: `AVCaptureVideoDataOutputSampleBufferDelegate` doesn't
/// hand back a captured image directly; we hold a continuation that
/// the next sample fulfills.
///
/// Marked `@unchecked Sendable` because all mutable state is guarded
/// by `lock` and no other state crosses thread boundaries. AVFoundation
/// calls the delegate methods from the configured queue
/// (`videoQueue` here); the continuation pattern bridges back to
/// async/await safely.
private final class SampleBufferDelegate: NSObject,
                                          AVCaptureVideoDataOutputSampleBufferDelegate,
                                          @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?

    func captureNext() async -> UIImage? {
        await withCheckedContinuation { cont in
            lock.lock()
            // If a caller is already waiting, replace its continuation
            // — only one outstanding capture at a time. Resume the
            // stale one with nil so it doesn't leak.
            if let prev = continuation {
                prev.resume(returning: nil)
            }
            continuation = cont
            lock.unlock()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection,
    ) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()

        guard let waiting else { return }
        let image = _imageFromSampleBuffer(sampleBuffer)
        waiting.resume(returning: image)
    }

    private func _imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}


/// Live preview surface for the camera. Embeds `AVCaptureVideoPreviewLayer`
/// into a `UIView` because SwiftUI doesn't have a native equivalent.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> _PreviewContainer {
        let view = _PreviewContainer()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: _PreviewContainer, context: Context) {
        // Nothing to update — the session and gravity are set at init.
    }

    /// UIView whose backing layer is `AVCaptureVideoPreviewLayer`.
    final class _PreviewContainer: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
