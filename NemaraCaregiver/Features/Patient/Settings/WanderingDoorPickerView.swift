import LiveKit
import SwiftUI

/// Exit-door picker for the Wandering detector. Grabs a live frame from the
/// patient's camera, asks the backend VLM to find doorways, highlights them,
/// and lets the caregiver:
///   • tap a highlighted door (source = "vlm"), OR
///   • tap anywhere else to place the door themselves (source = "manual"), OR
///   • declare "no door leads outside" (turns the detector off).
///
/// The choice is saved via `POST /v1/patients/{id}/wandering-door`, which
/// regenerates the wandering prompt so only leaving THROUGH that door counts.
struct WanderingDoorPickerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let patientId: UUID
    let detector: Detector

    private enum Phase: Equatable {
        case loading(String)
        case ready
        case blocked(String)   // recoverable: no camera / not streaming
        case failed(String)
        case saving
    }

    @State private var phase: Phase = .loading("Connecting to the camera…")
    @State private var frame: UIImage?
    @State private var doors: [DetectedDoor] = []
    @State private var selectedDoorID: DetectedDoor.ID?
    @State private var manualBox: [Double]?     // [x,y,w,h] from a tap-override
    @State private var weConnected = false       // did WE open the room?

    // Default size of a tap-placed door box (fractions of the frame).
    private let manualW = 0.14
    private let manualH = 0.22

    var body: some View {
        NavigationStack {
            ZStack {
                NemaraColor.paper.ignoresSafeArea()
                content
            }
            .navigationTitle("Exit door")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(NemaraColor.ink2)
                }
            }
        }
        .task { await load() }
        .onDisappear {
            if weConnected {
                let lk = env.liveKit
                Task { await lk.disconnect() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading(let msg):
            statusView(msg, spinner: true)
        case .saving:
            statusView("Saving…", spinner: true)
        case .blocked(let msg):
            statusView(msg, spinner: false, retry: true)
        case .failed(let msg):
            statusView(msg, spinner: false, retry: true)
        case .ready:
            readyView
        }
    }

    // MARK: - Ready (the picker)

    private var readyView: some View {
        VStack(spacing: 0) {
            instructions
            frameCanvas
                .padding(.horizontal, 16)
            controls
        }
    }

    private var instructions: some View {
        VStack(spacing: 6) {
            NemaraEyebrow(doors.isEmpty ? "NO DOORS DETECTED · TAP TO PLACE" : "TAP THE EXIT DOOR")
            Text(doors.isEmpty
                 ? "Tap the spot on the camera view where the door your loved one would leave through is."
                 : "Tap the highlighted door your loved one would use to leave home. Tap anywhere else to place it yourself.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var frameCanvas: some View {
        GeometryReader { geo in
            let fit = fittedRect(imageSize: frame?.size ?? geo.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                if let frame {
                    Image(uiImage: frame)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .offset(x: fit.minX, y: fit.minY)
                        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
                }
                // VLM-detected doors
                ForEach(doors) { door in
                    let r = boxRect(door.box, in: fit)
                    let on = selectedDoorID == door.id
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(on ? NemaraColor.terra : Color.white.opacity(0.9),
                                lineWidth: on ? 3 : 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(NemaraColor.terra.opacity(on ? 0.28 : 0.10))
                        )
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                        .allowsHitTesting(false)
                }
                // Manual tap-override marker
                if let manualBox {
                    let r = boxRect(manualBox, in: fit)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(NemaraColor.terra, lineWidth: 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(NemaraColor.terra.opacity(0.28))
                        )
                        .overlay(
                            Image(systemName: "figure.walk.motion")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in handleTap(location, fit: fit) }
        }
        .aspectRatio(frameAspect, contentMode: .fit)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            NemaraButton(
                "Set exit door",
                variant: .terra,
                block: true,
                systemImage: "checkmark",
            ) { Task { await saveSelection() } }
            .disabled(!hasSelection)
            .opacity(hasSelection ? 1 : 0.5)

            NemaraButton(
                "No door leads outside",
                variant: .ghost,
                block: true,
            ) { Task { await saveNoExitDoor() } }
        }
        .padding(16)
    }

    private func statusView(_ msg: String, spinner: Bool, retry: Bool = false) -> some View {
        VStack(spacing: 16) {
            if spinner {
                ProgressView().controlSize(.large).tint(NemaraColor.terra)
            } else {
                Image(systemName: "video.slash")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(NemaraColor.ink3)
            }
            Text(msg)
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            if retry {
                NemaraButton("Try again", variant: .secondary) {
                    Task { await load() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selection

    private var hasSelection: Bool { selectedDoorID != nil || manualBox != nil }

    private func handleTap(_ location: CGPoint, fit: CGRect) {
        // A tap inside a detected door selects it; anywhere else places a
        // manual door box centered on the tap.
        if let hit = doors.first(where: { boxRect($0.box, in: fit).contains(location) }) {
            selectedDoorID = hit.id
            manualBox = nil
            return
        }
        guard let n = normalizedPoint(location, in: fit) else { return }
        let x = min(max(n.x - manualW / 2, 0), 1 - manualW)
        let y = min(max(n.y - manualH / 2, 0), 1 - manualH)
        manualBox = [x, y, manualW, manualH]
        selectedDoorID = nil
    }

    private func saveSelection() async {
        let box: [Double]
        let label: String?
        let source: String
        if let id = selectedDoorID, let door = doors.first(where: { $0.id == id }) {
            box = door.box
            label = door.label
            source = "vlm"
        } else if let manualBox {
            box = manualBox
            label = nil
            source = "manual"
        } else {
            return
        }
        phase = .saving
        do {
            _ = try await env.api.setWanderingDoor(
                forPatient: patientId, box: box, label: label,
                source: source, noExitDoor: false,
            )
            dismiss()
        } catch {
            phase = .failed("Couldn't save the exit door. Please try again.")
        }
    }

    private func saveNoExitDoor() async {
        phase = .saving
        do {
            _ = try await env.api.setWanderingDoor(
                forPatient: patientId, box: nil, label: nil,
                source: "manual", noExitDoor: true,
            )
            dismiss()
        } catch {
            phase = .failed("Couldn't save. Please try again.")
        }
    }

    // MARK: - Load pipeline

    private func load() async {
        phase = .loading("Connecting to the camera…")
        frame = nil
        doors = []
        selectedDoorID = nil
        manualBox = nil

        let cams = env.api.camerasByPatient[patientId] ?? []
        let target = cams.first(where: { $0.livekitIdentity != nil && $0.online && !$0.disabled })
            ?? cams.first(where: { $0.livekitIdentity != nil })
        guard let identity = target?.livekitIdentity else {
            phase = .blocked("This patient doesn't have a paired camera yet. Pair one first, then set the exit door.")
            return
        }

        let room = "patient_\(patientId.uuidString.lowercased())"
        if env.liveKit.currentRoom == room, env.liveKit.state == .connected {
            weConnected = false
        } else {
            do {
                let tok = try await env.api.mintViewerToken(forPatient: patientId)
                await env.liveKit.connect(url: tok.url, token: tok.token, room: room)
                weConnected = true
            } catch {
                phase = .failed("Couldn't connect to the camera. Check your connection and try again.")
                return
            }
        }

        // Wait for the camera's video track (up to ~6s).
        var track: VideoTrack?
        for _ in 0..<30 {
            if let t = env.liveKit.videoTracksByIdentity[identity] {
                track = t
                break
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let track else {
            phase = .blocked("The camera isn't streaming right now. Open the Live tab to wake it, then try again.")
            return
        }

        phase = .loading("Capturing the room…")
        guard let jpeg = await LiveKitFrameCapture.jpeg(from: track),
              let img = UIImage(data: jpeg) else {
            phase = .failed("Couldn't capture a frame from the camera. Please try again.")
            return
        }
        frame = img

        phase = .loading("Looking for doors…")
        do {
            doors = try await env.api.detectDoors(imageBase64: jpeg.base64EncodedString())
        } catch {
            doors = []   // fall back to tap-to-place; not fatal
        }

        // Pre-highlight a prior selection.
        if let dc = detector.doorConfig, !dc.noExitDoor, let box = dc.box, box.count == 4 {
            if let match = doors.first(where: { iou($0.box, box) > 0.5 }) {
                selectedDoorID = match.id
            } else {
                manualBox = box
            }
        }
        phase = .ready
    }

    // MARK: - Geometry

    private var frameAspect: CGFloat {
        guard let s = frame?.size, s.height > 0 else { return 16.0 / 9.0 }
        return s.width / s.height
    }

    /// Aspect-fit `imageSize` inside `container`, centered.
    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func boxRect(_ box: [Double], in fit: CGRect) -> CGRect {
        guard box.count == 4 else { return .zero }
        return CGRect(
            x: fit.minX + CGFloat(box[0]) * fit.width,
            y: fit.minY + CGFloat(box[1]) * fit.height,
            width: CGFloat(box[2]) * fit.width,
            height: CGFloat(box[3]) * fit.height,
        )
    }

    private func normalizedPoint(_ loc: CGPoint, in fit: CGRect) -> CGPoint? {
        guard fit.contains(loc), fit.width > 0, fit.height > 0 else { return nil }
        return CGPoint(x: (loc.x - fit.minX) / fit.width, y: (loc.y - fit.minY) / fit.height)
    }

    private func iou(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == 4, b.count == 4 else { return 0 }
        let ax2 = a[0] + a[2], ay2 = a[1] + a[3]
        let bx2 = b[0] + b[2], by2 = b[1] + b[3]
        let ix1 = max(a[0], b[0]), iy1 = max(a[1], b[1])
        let ix2 = min(ax2, bx2), iy2 = min(ay2, by2)
        let iw = max(0, ix2 - ix1), ih = max(0, iy2 - iy1)
        let inter = iw * ih
        let union = a[2] * a[3] + b[2] * b[3] - inter
        return union > 0 ? inter / union : 0
    }
}
