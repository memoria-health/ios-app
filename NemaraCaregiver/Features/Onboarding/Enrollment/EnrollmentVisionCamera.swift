import AVFoundation
import CoreImage
import SwiftUI
import UIKit
import Vision

/// Camera + Vision engine for guided face enrollment.
///
/// Streams frames from the chosen camera (front or rear), runs on-device
/// **Vision** face detection to get the face box + head pose (yaw/pitch)
/// + capture quality, and feeds the shared `FaceCoverageModel`. It uses
/// plain Vision — **no ARKit / TrueDepth** — so it works on the rear
/// camera and on older iPhones. The embedded JPEG is the *un-mirrored*
/// frame (we mirror only the preview) so the gallery matches what the
/// wall cam actually sees.
///
/// Threading follows the existing enrollment-camera pattern: AVFoundation
/// delivers frames on `videoQueue`, Vision runs there, and the @Published
/// UI state + the `coverage.ingest` call hop to the main actor. Marked
/// `@unchecked Sendable` because every value that crosses the hop is
/// copied (pose/quality/box are scalars; the JPEG is `Data`).
final class EnrollmentVisionCamera: ObservableObject, @unchecked Sendable {

    enum Facing { case front, rear }

    // ── device-tune constants (verify once on a real device) ──────
    // If the dial fills OPPOSITE to where you turn, flip the matching
    // sign here — nothing else needs to change.
    /// Vision yaw sign so a left/right turn maps to the arc the user
    /// expects. The front preview is mirrored, so its sign is flipped vs
    /// the rear. (Device-verified: front -1 gives nose-left → left arc.)
    private var yawSign: Double { facing == .front ? -1 : 1 }
    /// Vision pitch sign so up/down maps to the top/bottom arcs.
    /// (Device-verified good at -1.)
    private var pitchSign: Double { -1 }
    /// Process at ~this rate (Vision every frame is wasteful at 30 fps).
    private let targetHz: Double = 15

    let session = AVCaptureSession()
    let facing: Facing
    /// The shared coverage model (main-actor). Fed from `ingest` below.
    let coverage: FaceCoverageModel

    @MainActor @Published private(set) var isConfigured = false
    @MainActor @Published private(set) var setupError: String?
    /// Latest face rect in NORMALISED Vision coords (origin bottom-left,
    /// relative to the upright portrait buffer). nil when no face.
    @MainActor @Published private(set) var faceBox: CGRect?
    @MainActor @Published private(set) var faceVisible = false
    @MainActor @Published private(set) var quality: Float = 0

    private let videoQueue = DispatchQueue(label: "co.elephantlabs.nemara.enroll-vision")
    private let output = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private var delegate: VisionDelegate!
    private var lastProcess = Date.distantPast

    @MainActor
    init(facing: Facing, coverage: FaceCoverageModel) {
        self.facing = facing
        self.coverage = coverage
        self.delegate = VisionDelegate(owner: self)
        output.setSampleBufferDelegate(delegate, queue: videoQueue)
    }

    // ── setup ─────────────────────────────────────────────────────

    @MainActor
    func configure() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        let position: AVCaptureDevice.Position = facing == .front ? .front : .back
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: position,
        ) else {
            setupError = "No \(facing == .front ? "front" : "rear") camera available"
            session.commitConfiguration()
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            setupError = "Camera input failed: \(error.localizedDescription)"
            session.commitConfiguration()
            return
        }

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }
        if let conn = output.connection(with: .video) {
            // Deliver upright portrait buffers so Vision + the JPEG use
            // `.up` orientation. We do NOT mirror the data output — the
            // embedded face must be the true (un-mirrored) face; the
            // preview layer mirrors for display only.
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
        }
        session.commitConfiguration()
        isConfigured = true
    }

    nonisolated func start() {
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

    // ── per-frame work (video queue) ──────────────────────────────

    fileprivate func handle(_ sampleBuffer: CMSampleBuffer) {
        // rate-limit
        let now = Date()
        guard now.timeIntervalSince(lastProcess) >= 1.0 / targetHz else { return }
        lastProcess = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let rectReq = VNDetectFaceRectanglesRequest()
        rectReq.revision = VNDetectFaceRectanglesRequestRevision3  // yaw + pitch
        let qualReq = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer, orientation: .up, options: [:],
        )
        try? handler.perform([rectReq, qualReq])

        guard let face = (rectReq.results ?? [])
            .max(by: { $0.boundingBox.area < $1.boundingBox.area }) else {
            publish(box: nil, quality: 0, visible: false)
            return
        }
        let q = (qualReq.results ?? [])
            .compactMap { $0.faceCaptureQuality }.max() ?? 0
        let yaw = (face.yaw?.doubleValue ?? 0) * 180 / .pi * yawSign
        let pitch = (face.pitch?.doubleValue ?? 0) * 180 / .pi * pitchSign
        let box = face.boundingBox

        // Encode only when the frame is worth keeping (cheap quality gate
        // eliminates most frames before we pay the JPEG cost).
        let jpeg: Data? = q >= coverage.minQuality
            ? encodeJPEG(pixelBuffer) : nil

        publish(box: box, quality: q, visible: true)
        DispatchQueue.main.async { [coverage] in
            coverage.ingest(yawDeg: yaw, pitchDeg: pitch, quality: q, jpeg: jpeg)
        }
    }

    private func publish(box: CGRect?, quality: Float, visible: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.faceBox = box
            self.quality = quality
            self.faceVisible = visible
        }
    }

    private func encodeJPEG(_ pixelBuffer: CVPixelBuffer) -> Data? {
        var ci = CIImage(cvPixelBuffer: pixelBuffer)
        // downscale to ~640 wide — ArcFace only needs a 112² aligned crop,
        // so a full-res selfie is wasted bytes.
        let targetW: CGFloat = 640
        if ci.extent.width > targetW {
            let s = targetW / ci.extent.width
            ci = ci.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        return ciContext.jpegRepresentation(
            of: ci,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8],
        )
    }
}

// ── sample-buffer delegate ────────────────────────────────────────

private final class VisionDelegate: NSObject,
                                    AVCaptureVideoDataOutputSampleBufferDelegate,
                                    @unchecked Sendable {
    private weak var owner: EnrollmentVisionCamera?
    init(owner: EnrollmentVisionCamera) { self.owner = owner }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection,
    ) {
        owner?.handle(sampleBuffer)
    }
}

// ── preview surface ───────────────────────────────────────────────

/// Live camera preview. Mirrors horizontally when `mirrored` (front
/// self-enroll) so the person sees themselves as in a mirror; the
/// captured/embedded frame is never mirrored (that happens on the data
/// output, which we leave un-mirrored).
struct EnrollmentCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool = false

    func makeUIView(context: Context) -> PreviewContainer {
        let view = PreviewContainer()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let conn = view.previewLayer.connection {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = mirrored
            }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewContainer, context: Context) {}

    final class PreviewContainer: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// ── coordinate mapping ────────────────────────────────────────────

/// Maps a normalised Vision rect (origin bottom-left, relative to the
/// upright portrait buffer) into a SwiftUI view rect for a preview shown
/// with `.resizeAspectFill`. Deterministic (no UIKit layer needed), so
/// the tracking ring can be positioned purely in SwiftUI.
enum EnrollmentGeometry {
    /// Portrait source aspect (w/h): 720×1280 after the 90° rotation.
    static let sourceAspect: CGFloat = 720.0 / 1280.0

    static func viewRect(
        normVision: CGRect,
        in size: CGSize,
        mirrored: Bool,
    ) -> CGRect {
        // Vision (bottom-left) → top-left normalised.
        var nx = normVision.minX
        let ny = 1 - normVision.maxY
        let nw = normVision.width
        let nh = normVision.height
        if mirrored { nx = 1 - normVision.maxX }

        // aspect-fill the portrait source into `size`
        let scale = max(size.width / sourceAspect, size.height / 1.0)
        let dispW = sourceAspect * scale
        let dispH = 1.0 * scale
        let originX = (size.width - dispW) / 2
        let originY = (size.height - dispH) / 2

        return CGRect(
            x: originX + nx * dispW,
            y: originY + ny * dispH,
            width: nw * dispW,
            height: nh * dispH,
        )
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
