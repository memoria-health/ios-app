import SwiftUI

/// Exit-door picker for the Wandering detector. Shows a captured camera frame
/// (cached, so it doesn't re-analyze on every open — use Rescan to refresh),
/// highlights the doorways the VLM found as tappable dots, and lets the
/// caregiver:
///   • tap highlighted doors to select/deselect MULTIPLE exits (source = "vlm"),
///   • tap empty space to place their own door (source = "manual"), tap it again
///     to remove it,
///   • or declare "No door leads outside" (turns the detector off).
///
/// Saved via `POST /v1/patients/{id}/wandering-door`, which regenerates the
/// wandering prompt so only leaving THROUGH one of the chosen doors counts.
struct WanderingDoorPickerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let patientId: UUID
    let cameraId: UUID
    let cameraIdentity: String
    let existingConfig: Detector.DoorConfig?
    /// Called after a successful save so the parent can refresh its status.
    var onSaved: () -> Void = {}

    private enum Phase: Equatable {
        case loading(String)
        case ready
        case blocked(String)
        case failed(String)
        case saving
    }

    private struct ManualDoor: Identifiable, Hashable {
        let id = UUID()
        var box: [Double]   // [x,y,w,h]
    }

    @State private var phase: Phase = .loading("Loading the camera view…")
    @State private var loaded: WanderingDoorCache.Frame?
    @State private var detectedDoors: [DetectedDoor] = []
    @State private var detectingDoors = false
    @State private var selectedDoorIDs: Set<DetectedDoor.ID> = []
    @State private var manualDoors: [ManualDoor] = []
    @State private var didApplyExisting = false

    private var cache: WanderingDoorCache { .shared }

    // A tap within this many points of a dot hits it (select/remove).
    private let hitRadius: CGFloat = 30
    // Default size of a tap-placed door box (fractions of the frame).
    private let manualW = 0.12
    private let manualH = 0.20

    var body: some View {
        NavigationStack {
            ZStack {
                NemaraColor.paper.ignoresSafeArea()
                content
            }
            // Just "Exit doors" — the camera name used to be prefixed here and
            // an inline title has no room for it ("Aryaman Bedroom · exit
            // doors" truncated mid-word). It was redundant anyway: you reach
            // this screen from one specific camera.
            .navigationTitle("Exit doors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(NemaraColor.ink2)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load(reload: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .foregroundStyle(NemaraColor.terra)
                    .disabled(isBusy)
                }
            }
        }
        .task { await load(reload: false) }
    }

    private var isBusy: Bool {
        if case .loading = phase { return true }
        if case .saving = phase { return true }
        return false
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

    private var doors: [DetectedDoor] { detectedDoors }
    private var selectionCount: Int { selectedDoorIDs.count + manualDoors.count }

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
            NemaraEyebrow(
                detectingDoors ? "TAP EACH EXIT DOOR · FINDING DOORS…"
                : doors.isEmpty ? "TAP EACH EXIT DOOR"
                : "TAP EACH EXIT DOOR")
            Text("Tap every door that leads outside. Tap anywhere else to place one yourself; tap a marker again to remove it.")
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
            let fit = fittedRect(imageSize: loaded?.image.size ?? geo.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                if let image = loaded?.image {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .offset(x: fit.minX, y: fit.minY)
                        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
                }
                // VLM-detected doors (selectable dots)
                ForEach(doors) { door in
                    let c = center(door.box, in: fit)
                    doorDot(selected: selectedDoorIDs.contains(door.id), manual: false)
                        .position(x: c.x, y: c.y)
                        .allowsHitTesting(false)
                }
                // Manual (tap-placed) doors
                ForEach(manualDoors) { m in
                    let c = center(m.box, in: fit)
                    doorDot(selected: true, manual: true)
                        .position(x: c.x, y: c.y)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in handleTap(location, fit: fit) }
        }
        .aspectRatio(frameAspect, contentMode: .fit)
    }

    @ViewBuilder
    private func doorDot(selected: Bool, manual: Bool) -> some View {
        ZStack {
            Circle()
                .fill(selected ? NemaraColor.terra : NemaraColor.terra.opacity(0.35))
                .frame(width: selected ? 30 : 24, height: selected ? 30 : 24)
                .overlay(Circle().stroke(.white, lineWidth: selected ? 2.5 : 2))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            if selected {
                Image(systemName: manual ? "figure.walk" : "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            NemaraButton(
                setButtonTitle,
                variant: .terra,
                block: true,
                systemImage: "checkmark",
            ) { Task { await saveSelection() } }
            .disabled(selectionCount == 0)
            .opacity(selectionCount == 0 ? 0.5 : 1)

            NemaraButton(
                "No door leads outside",
                variant: .ghost,
                block: true,
            ) { Task { await saveNoExitDoor() } }
        }
        .padding(16)
    }

    private var setButtonTitle: String {
        switch selectionCount {
        case 0: return "Set exit doors"
        case 1: return "Set 1 exit door"
        default: return "Set \(selectionCount) exit doors"
        }
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
                    Task { await load(reload: true) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tap handling (select / deselect / place / remove)

    private func handleTap(_ location: CGPoint, fit: CGRect) {
        // 1) hit an existing VLM dot -> toggle selection
        if let door = nearest(doors.map { ($0.id, center($0.box, in: fit)) },
                              to: location, within: hitRadius) {
            if selectedDoorIDs.contains(door) { selectedDoorIDs.remove(door) }
            else { selectedDoorIDs.insert(door) }
            return
        }
        // 2) hit an existing manual dot -> remove it
        if let mid = nearest(manualDoors.map { ($0.id, center($0.box, in: fit)) },
                             to: location, within: hitRadius) {
            manualDoors.removeAll { $0.id == mid }
            return
        }
        // 3) empty space -> place a new manual door
        guard let n = normalizedPoint(location, in: fit) else { return }
        let x = min(max(n.x - manualW / 2, 0), 1 - manualW)
        let y = min(max(n.y - manualH / 2, 0), 1 - manualH)
        manualDoors.append(ManualDoor(box: [x, y, manualW, manualH]))
    }

    private func nearest<ID: Hashable>(
        _ items: [(ID, CGPoint)], to loc: CGPoint, within radius: CGFloat,
    ) -> ID? {
        var best: (ID, CGFloat)?
        for (id, c) in items {
            let d = hypot(c.x - loc.x, c.y - loc.y)
            if d <= radius, best == nil || d < best!.1 { best = (id, d) }
        }
        return best?.0
    }

    // MARK: - Save

    private func saveSelection() async {
        var payload: [WanderingDoorInput] = []
        for door in doors where selectedDoorIDs.contains(door.id) {
            payload.append(WanderingDoorInput(box: door.box, label: door.label, source: "vlm"))
        }
        for m in manualDoors {
            payload.append(WanderingDoorInput(box: m.box, label: nil, source: "manual"))
        }
        guard !payload.isEmpty else { return }
        phase = .saving
        do {
            try await env.api.setCameraWanderingDoors(
                cameraId: cameraId, doors: payload, noExitDoor: false,
            )
            onSaved()
            dismiss()
        } catch {
            phase = .failed("Couldn't save the exit doors. Please try again.")
        }
    }

    private func saveNoExitDoor() async {
        phase = .saving
        do {
            try await env.api.setCameraWanderingDoors(
                cameraId: cameraId, doors: [], noExitDoor: true,
            )
            onSaved()
            dismiss()
        } catch {
            phase = .failed("Couldn't save. Please try again.")
        }
    }

    // MARK: - Load (cache-backed)

    private func load(reload: Bool) async {
        phase = .loading(reload ? "Getting a fresh view…" : "Loading the camera view…")
        // FRAME first — fast, no LLM. The picker becomes usable immediately.
        let outcome = reload
            ? await cache.reloadFrame(cameraId: cameraId, patientId: patientId,
                                      identity: cameraIdentity, api: env.api, liveKit: env.liveKit)
            : await cache.ensureFrame(cameraId: cameraId, patientId: patientId,
                                      identity: cameraIdentity, api: env.api, liveKit: env.liveKit)
        switch outcome {
        case .ok:
            loaded = cache.cachedFrame(cameraId)
            detectedDoors = cache.cachedDoors(cameraId) ?? []
            applyExistingSelectionIfNeeded()
            phase = .ready
            await detectDoorsInBackground()
        case .blocked(let m):
            phase = .blocked(m)
        case .failed(let m):
            phase = .failed(m)
        }
    }

    /// Run the single door-detection call WITHOUT blocking the view. Dots appear
    /// when it returns; the caregiver can tap-place in the meantime.
    private func detectDoorsInBackground() async {
        guard detectedDoors.isEmpty else { return }
        detectingDoors = true
        let found = await cache.ensureDoors(cameraId: cameraId, api: env.api)
        // Drop any detected door that's basically on top of a door the caregiver
        // already placed/selected, so we don't stack two dots.
        detectedDoors = found.filter { d in
            !manualDoors.contains { iou($0.box, d.box) > 0.4 }
        }
        detectingDoors = false
    }

    /// Pre-select the doors already saved for THIS camera, once, so the picker
    /// opens reflecting the current configuration.
    private func applyExistingSelectionIfNeeded() {
        guard !didApplyExisting else { return }
        didApplyExisting = true
        guard let dc = existingConfig, !dc.noExitDoor else { return }
        for stored in dc.doors {
            guard let box = stored.box, box.count == 4 else { continue }
            if let match = doors.first(where: { iou($0.box, box) > 0.5 }) {
                selectedDoorIDs.insert(match.id)
            } else {
                manualDoors.append(ManualDoor(box: box))
            }
        }
    }

    // MARK: - Geometry

    private var frameAspect: CGFloat {
        guard let s = loaded?.image.size, s.height > 0 else { return 16.0 / 9.0 }
        return s.width / s.height
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    /// Center of a normalized [x,y,w,h] box in view coordinates.
    private func center(_ box: [Double], in fit: CGRect) -> CGPoint {
        guard box.count == 4 else { return CGPoint(x: fit.midX, y: fit.midY) }
        return CGPoint(
            x: fit.minX + CGFloat(box[0] + box[2] / 2) * fit.width,
            y: fit.minY + CGFloat(box[1] + box[3] / 2) * fit.height,
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
