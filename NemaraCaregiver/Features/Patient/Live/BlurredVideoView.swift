import CoreImage
import ImageIO
import LiveKit
import SwiftUI
import UIKit
import Vision

/// Live camera tile with people blurred on-device ("Blur people").
///
/// Drop-in replacement for `LiveKitVideoView`, used ONLY when the per-patient
/// blur preference is on (`PeopleBlurStore`). When off, callers render the
/// normal `LiveKitVideoView` — this path is fully additive, so turning blur off
/// restores the untouched original behavior (reversible).
///
/// Pipeline (all on-device): attach a `VideoRenderer` to the track → per frame
/// run Apple **Vision** human *detection* (`VNDetectHumanRectanglesRequest`) to
/// get person bounding BOXES → **Core Image** blurs each box over the sharp
/// frame → render to a `CALayer`. This mirrors the web dashboard's COCO-SSD
/// box approach: a detector works at any distance (near AND far), unlike
/// person *segmentation*, which is tuned for close-up subjects and drops a
/// person who walks away.
///
/// DISPLAY-privacy only: frames are still decoded on this device.
struct BlurredVideoView: UIViewRepresentable {
    var track: VideoTrack?
    var identity: String?

    func makeUIView(context: Context) -> BlurRenderView {
        let v = BlurRenderView()
        v.update(track: track)
        return v
    }

    func updateUIView(_ uiView: BlurRenderView, context: Context) {
        uiView.update(track: track)
    }

    static func dismantleUIView(_ uiView: BlurRenderView, coordinator: ()) {
        uiView.detach()
    }
}

/// UIView that hosts the blurred output layer and owns the renderer lifecycle.
final class BlurRenderView: UIView {
    private let renderer = BlurVideoRenderer()
    private weak var attachedTrack: VideoTrack?
    private let displayLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.contentsGravity = .resizeAspectFill // match LiveKitVideoView's .fill
        displayLayer.masksToBounds = true
        layer.addSublayer(displayLayer)
        // Renderer produces a CGImage on the SDK video thread, then hops to main.
        renderer.onImage = { [weak self] cgImage in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true) // no implicit fade between frames
            self.displayLayer.contents = cgImage
            CATransaction.commit()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer.frame = bounds
    }

    func update(track: VideoTrack?) {
        guard track !== attachedTrack else { return }
        detach()
        attachedTrack = track
        track?.add(videoRenderer: renderer)
    }

    func detach() {
        attachedTrack?.remove(videoRenderer: renderer)
        attachedTrack = nil
    }

    deinit {
        // deinit is nonisolated; detach touches only the (thread-safe) track API.
        attachedTrack?.remove(videoRenderer: renderer)
    }
}

/// Attaches to a LiveKit `VideoTrack` and, for each decoded frame, blurs a box
/// over each detected person. `render(frame:)` fires on the SDK's serial video
/// thread, so the mutable state here needs no locking; only the final `CGImage`
/// crosses to the main thread. Mirrors `LiveKitFrameGrabber`.
final class BlurVideoRenderer: NSObject, VideoRenderer, @unchecked Sendable {

    /// Called on the MAIN thread with each composited frame.
    var onImage: ((CGImage) -> Void)?

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Run detection at ~15/s and hold the boxes on the frames in between; the
    // blur composite runs every frame. A reused VNSequenceRequestHandler gives
    // temporal stability. Only ever touched on the SDK's serial video thread.
    private let detectionRequest: VNDetectHumanRectanglesRequest = {
        let r = VNDetectHumanRectanglesRequest()
        r.upperBodyOnly = false // full-body boxes
        return r
    }()
    private let sequenceHandler = VNSequenceRequestHandler()
    private let detectInterval: CFTimeInterval = 0.066 // ~15/s
    private var lastDetectTime: CFTimeInterval = 0

    // Lower = catches farther / more partial people (more false positives).
    private let minConfidence: Float = 0.25
    // Uniform padding around each person box so the blur sits proud of the body.
    // Mirrors the web dashboard's PAD = 0.18.
    private let boxPad: CGFloat = 0.18
    // Gaussian blur strength. Mirrors the web dashboard's BLUR_PX = 36 (CSS
    // blur radius ≈ Gaussian sigma). Tune here if it reads differently on device.
    private let blurSigma: Double = 36
    // Keep a box this long after its last sighting so a detection gap never
    // suddenly un-blurs someone (privacy hold). Mirrors web HOLD_MS = 1500.
    private let holdSeconds: CFTimeInterval = 1.5
    private var heldBoxes: [(rect: CGRect, exp: CFTimeInterval)] = []

    // MARK: VideoRenderer

    // We render every frame ourselves, so opt out of adaptive-stream downscaling.
    var isAdaptiveStreamEnabled: Bool { false }
    var adaptiveStreamSize: CGSize { .zero }

    func render(frame: VideoFrame) {
        guard let pixelBuffer = frame.toCVPixelBuffer() else { return }
        let source = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(Self.orientation(for: frame.rotation))

        let now = CACurrentMediaTime()
        if now - lastDetectTime >= detectInterval {
            lastDetectTime = now
            let boxes = personBoxes(in: source)
            if !boxes.isEmpty {
                heldBoxes = boxes.map { (rect: $0, exp: now + holdSeconds) }
            } else {
                heldBoxes = heldBoxes.filter { $0.exp > now } // let old ones expire
            }
        }
        let live = heldBoxes.filter { $0.exp > now }.map { $0.rect }

        var output = source
        if !live.isEmpty {
            let blurred = source
                .clampedToExtent()
                .applyingGaussianBlur(sigma: blurSigma)
                .cropped(to: source.extent)
            // Composite the blurred content back only inside each person box.
            for box in live {
                output = blurred.cropped(to: box.intersection(source.extent)).composited(over: output)
            }
        }

        guard let cgImage = Self.ciContext.createCGImage(output, from: source.extent)
        else { return }
        let handler = onImage
        DispatchQueue.main.async { handler?(cgImage) }
    }

    // MARK: Helpers

    /// Padded person bounding boxes in `image`'s pixel coordinates.
    private func personBoxes(in image: CIImage) -> [CGRect] {
        do {
            try sequenceHandler.perform([detectionRequest], on: image, orientation: .up)
        } catch { return [] }
        guard let results = detectionRequest.results else { return [] }

        let W = image.extent.width, H = image.extent.height
        return results.compactMap { obs -> CGRect? in
            guard obs.confidence >= minConfidence else { return nil }
            // Vision boundingBox: normalized, bottom-left origin — matches CIImage.
            let b = obs.boundingBox
            var r = CGRect(x: image.extent.origin.x + b.origin.x * W,
                           y: image.extent.origin.y + b.origin.y * H,
                           width: b.width * W, height: b.height * H)
            r = r.insetBy(dx: -r.width * boxPad, dy: -r.height * boxPad)
            return r
        }
    }

    /// LiveKit `rotation` is clockwise degrees to upright; map to the EXIF-style
    /// orientation `CIImage.oriented(_:)` expects. If the picture comes out
    /// sideways/upside-down, swap `.right`/`.left` (or use `.up`) here.
    private static func orientation(for rotation: VideoRotation) -> CGImagePropertyOrientation {
        switch rotation {
        case ._0: return .up
        case ._90: return .right
        case ._180: return .down
        case ._270: return .left
        @unknown default: return .up
        }
    }
}

extension BlurVideoRenderer {
    // Guard flag; only flipped once from the launch task. `unsafe` is fine — a
    // duplicate warm-up (if it ever raced) is harmless.
    nonisolated(unsafe) private static var warmed = false

    /// Preload the human-detection model + Neural Engine ahead of first use, so
    /// the first blurred frame isn't slow (mirrors the web PreloadVision). Cheap
    /// one-shot on a tiny dummy image; Vision caches the model process-wide, so
    /// every later detection — including the real sequence-handler path — is
    /// fast. Safe to call repeatedly (guarded); runs off the main thread.
    static func warmUp() {
        guard !warmed else { return }
        warmed = true
        DispatchQueue.global(qos: .utility).async {
            let req = VNDetectHumanRectanglesRequest()
            req.upperBodyOnly = false
            let dummy = CIImage(color: .black)
                .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 128))
            try? VNImageRequestHandler(ciImage: dummy, options: [:]).perform([req])
        }
    }
}
