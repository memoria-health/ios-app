import SwiftUI

/// Per-camera detail screen. Three control surfaces:
///
///   1. **Pause AI / Resume AI** — flips `cameras.ai_paused`. Instant;
///      video keeps streaming, only the LLM tick is skipped.
///   2. **Disconnect / Reconnect** — flips `cameras.desired_state`.
///      Wall phone polls every 1s and reconciles by leaving / rejoining
///      LiveKit. ~1-2s latency on reconnect. Confirmed via alert before
///      Disconnect (destructive direction) but not Reconnect.
///   3. **Per-camera detector toggles** — `cameras_detectors` join
///      table. Each toggle calls
///      `PUT /v1/cameras/{id}/detectors` with the full new set.
///
/// (The old "Hide / Show" control — `cameras.disabled` — was removed from
/// the UI to keep the caregiver's options simple: Disconnect or Pause AI.
/// The `disabled` field still exists and is honored where read, it's just
/// no longer user-settable.)
///
/// Detector toggles use optimistic UI with rollback on error. The
/// Disconnect flip also drops its `busy` flag in `defer` (not just in
/// `catch`) so a successful round-trip doesn't permanently disable the
/// button (we got bit by exactly this pattern in the web grid).
struct CameraDetailView: View {
    let cameraId: UUID
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env

    @State private var assignedDetectorIds: Set<UUID> = []
    @State private var assignmentsError: String?

    /// Detector currently in-flight on the toggle path. Drives a
    /// per-row disabled state; UUID matches the detector being saved.
    @State private var togglingDetectorId: UUID?

    @State private var togglingAiPause = false
    @State private var togglingDisconnect = false
    @State private var deleting = false
    @State private var actionError: String?

    @State private var showingDisconnectConfirm = false
    @State private var showingDeleteConfirm = false
    @State private var showingUnpairConfirm = false
    @State private var unpairing = false
    @State private var showingPairingCode = false

    /// This sensor's wandering exit-door config + picker.
    @State private var doorConfig: Detector.DoorConfig?
    @State private var showDoorPicker = false

    /// Collapsed state of the "Advanced" section (holds Pause AI).
    /// Collapsed by default — pausing AI is a niche lever and sat too
    /// prominently next to Disconnect.
    @State private var showAdvanced = false

    @Environment(\.dismiss) private var dismiss

    private var camera: Camera? {
        env.api.camerasByPatient[patientId]?.first(where: { $0.id == cameraId })
    }
    private var detectors: [Detector] {
        env.api.detectorsByPatient[patientId] ?? []
    }
    /// Detectors shown as simple on/off toggles here. Wandering is excluded —
    /// it's controlled by the exit-doors section (it's only active once its
    /// doors are set), so a plain toggle would be a dead switch.
    private var togglableDetectors: [Detector] {
        detectors.filter { $0.identifier != "wandering" }
    }
    /// Case-insensitive room match against whereRooms. The backend stores
    /// room names in capitals ("HALLWAY"), so comparing them as-typed
    /// showed the doors section on the wrong cameras — both sides are
    /// upper-cased here. Empty/ALL ROOMS = all cameras.
    private func wanderingWatches(room: String, detector wd: Detector) -> Bool {
        let rooms = (wd.whereRooms ?? []).map { $0.uppercased() }
        if rooms.isEmpty || rooms.contains("ALL ROOMS") || rooms.contains("ALL") { return true }
        return rooms.contains(room.uppercased())
    }

    /// The patient's wandering detector (if any) — gates the exit-door section.
    private var wanderingDetector: Detector? {
        detectors.first { $0.identifier == "wandering" }
    }
    private var isWanderingActiveHere: Bool {
        guard let dc = doorConfig else { return false }
        return !dc.noExitDoor && !dc.doors.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let cam = camera {
                    headerCard(cam)
                    // Room-derived privacy. Locked server-side (no user
                    // toggle) — this section only explains the state.
                    if cam.privacyEnabled {
                        privateRoomSection(cam)
                    }
                    // Pairing-code section only applies to wall-phone
                    // cameras. Sensor (Pi) cameras get their ingest
                    // token at provision time, so a 6-digit code would
                    // be misleading on this surface.
                    if cam.sourceType == .phone && !cam.paired {
                        pairingCodeSection(cam)
                    }
                    stateControls(cam)
                    advancedSection(cam)
                    detectorsSection
                    // Exit doors are configured PER SENSOR — this is that sensor.
                    // Exit doors are per-CAMERA config: only show on cameras
                    // the wandering detector actually watches (whereRooms).
                    // A living-room sensor shouldn't carry a doors section
                    // when wandering only watches the hallway.
                    if let wd = wanderingDetector, wd.isOn, cam.livekitIdentity != nil,
                       wanderingWatches(room: cam.room, detector: wd) {
                        exitDoorsSection(cam)
                    }
                    // Unpair returns a paired phone camera to the UNPAIRED
                    // state (re-pairable) without deleting it. Shown only
                    // while paired; once unpaired, the pairing-code section
                    // above takes over.
                    if cam.sourceType == .phone && cam.paired {
                        unpairButton(cam)
                    }
                    deleteCameraButton(cam)
                } else {
                    Text("Sensor not found")
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink3)
                        .padding(.top, 80)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(NemaraColor.paper)
        .navigationTitle(camera?.room ?? "Sensor")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: cameraId) {
            await loadAssignments()
            await loadDoorConfig()
            await prewarmDoorFrame()
        }
        .sheet(isPresented: $showDoorPicker) {
            if let cam = camera, let identity = cam.livekitIdentity {
                WanderingDoorPickerView(
                    patientId: patientId,
                    cameraId: cam.id,
                    cameraIdentity: identity,
                    existingConfig: doorConfig,
                    onSaved: { Task { await loadDoorConfig() } },
                )
            }
        }
        .alert(
            "Unpair this sensor?",
            isPresented: $showingUnpairConfirm,
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Unpair", role: .destructive) {
                Task { await unpairCamera() }
            }
        } message: {
            Text(
                "The paired phone returns to its pairing screen. This "
                + "camera's room, detectors, and history are kept — pair a "
                + "phone back to it any time with a fresh code."
            )
        }
        .alert(
            "Delete this sensor?",
            isPresented: $showingDeleteConfirm,
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteCamera() }
            }
        } message: {
            Text(
                "The wall phone will unpair on its next poll. "
                + "Its event history is preserved. You can pair "
                + "a new phone to this patient any time."
            )
        }
        .alert(
            "Disconnect this sensor?",
            isPresented: $showingDisconnectConfirm,
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task { await disconnectCamera() }
            }
        } message: {
            Text(
                "The wall phone will leave LiveKit entirely. No video, "
                + "no AI calls, no LiveKit costs. Reconnecting takes "
                + "about 1-2 seconds.",
            )
        }
        .sheet(isPresented: $showingPairingCode) {
            if let cam = camera {
                PairingCodeSheet(
                    source: .regenerate(cameraId: cam.id),
                    room: cam.room,
                )
                .presentationDetents([.medium, .large])
                .trackScreen("pairing_code")
            }
        }
    }

    /// "Awaiting pairing" card shown only when the camera row exists
    /// but no wall phone has completed /v1/cameras/pair yet. Tap-tap
    /// opens the regenerate-code sheet — fresh 6-digit code each time
    /// the sheet appears.
    private func pairingCodeSection(_ cam: Camera) -> some View {
        NemaraCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                NemaraEyebrow("AWAITING PAIRING")
                Text("No wall phone has claimed this sensor yet.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                Text(
                    "Tap below for a 6-digit code, then enter it on the "
                    + "MemoriaSensor wall-phone app to complete pairing."
                )
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
                NemaraButton(
                    "Show pairing code",
                    variant: .primary,
                    block: true,
                    systemImage: "qrcode",
                ) {
                    showingPairingCode = true
                }
            }
        }
        .padding(.horizontal, 16)
    }


    // MARK: - Sections

    private func headerCard(_ cam: Camera) -> some View {
        NemaraCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(NemaraColor.paperDim)
                    Image(systemName: cam.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink2)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cam.room)
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink)
                    Text(detailLine(cam))
                        .font(NemaraFont.monoSmall)
                        .foregroundStyle(NemaraColor.ink3)
                }
                Spacer()
                // AI paused indicator. Only shown when the camera is
                // otherwise visible (not hidden, not disconnected) —
                // otherwise the stronger badge would be misleading.
                if cam.aiPaused && !cam.disabled && cam.desiredState == .connected {
                    NemaraChip("AI PAUSED", tone: .neutral)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func detailLine(_ cam: Camera) -> String {
        let id = "SENSOR \(String(format: "%02d", cam.displayId))"
        let identity = cam.livekitIdentity ?? "no identity"
        return "\(id) · \(identity)"
    }

    /// Two state-toggle buttons stacked vertically. State-aware labels
    /// + colors. Both buttons stay clickable through the round-trip
    /// (busy flag clears in `defer`) — important because the row stays
    /// mounted across the state change.
    private func stateControls(_ cam: Camera) -> some View {
        VStack(spacing: 8) {
            NemaraEyebrow("CONTROLS")
                .padding(.horizontal, 16)

            NemaraCard(padding: 0) {
                VStack(spacing: 0) {
                    // Disconnect / Reconnect — destructive when going
                    // FROM connected; harmless when going back.
                    Button {
                        if cam.desiredState == .connected {
                            showingDisconnectConfirm = true
                        } else {
                            Task { await reconnectCamera() }
                        }
                    } label: {
                        controlRow(
                            icon: cam.desiredState == .disconnected
                                ? "antenna.radiowaves.left.and.right"
                                : "wifi.slash",
                            title: togglingDisconnect
                                ? (cam.desiredState == .disconnected
                                    ? "Reconnecting…"
                                    : "Disconnecting…")
                                : (cam.desiredState == .disconnected
                                    ? "Reconnect"
                                    : "Disconnect (privacy)"),
                            subtitle: cam.desiredState == .disconnected
                                ? "Phone rejoins LiveKit (~1-2s)."
                                : "Phone leaves LiveKit entirely.",
                            destructive: cam.desiredState == .connected,
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(togglingAiPause || togglingDisconnect)
                }
            }
            .padding(.horizontal, 16)

            if let err = actionError {
                Text(err)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.terra)
                    .padding(.horizontal, 16)
            }
        }
    }

    /// "Private room" explainer, shown when per-camera privacy is on.
    /// Read-only by design: privacy is derived from AI room
    /// classification (bathroom/bedroom) and locked server-side, so
    /// there is deliberately no toggle here.
    private func privateRoomSection(_ cam: Camera) -> some View {
        NemaraCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(NemaraColor.actionSoft)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NemaraColor.action)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Private room")
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink)
                    Text(
                        "Live view off, clips protected. Set automatically "
                        + "because this looks like a \(roomClassLabel(cam))."
                    )
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    /// Human label for the classified room, for the private-room copy.
    /// Falls back to the generic pair when the class is missing or
    /// non-sensitive (privacy can only be on for bathroom/bedroom, but
    /// stay defensive against contract drift).
    private func roomClassLabel(_ cam: Camera) -> String {
        switch cam.roomClass {
        case .bathroom: return "bathroom"
        case .bedroom: return "bedroom"
        case .other, .none: return "bathroom or bedroom"
        }
    }

    /// Collapsed "Advanced" section holding the Pause AI control. It
    /// lived beside Disconnect in CONTROLS, but pausing the AI tick is
    /// a niche cost lever — collapsed by default so the primary
    /// controls stay simple.
    private func advancedSection(_ cam: Camera) -> some View {
        VStack(spacing: 8) {
            NemaraCard(padding: 0) {
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showAdvanced.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(NemaraColor.paperDim)
                                Image(systemName: "gearshape")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(NemaraColor.ink2)
                            }
                            .frame(width: 32, height: 32)
                            Text("Advanced")
                                .font(NemaraFont.bodySmallStrong)
                                .foregroundStyle(NemaraColor.ink)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(NemaraColor.ink3)
                                .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showAdvanced {
                        NemaraColor.line.frame(height: 1)

                        // Pause AI / Resume AI — instant, no confirm.
                        // Lighter than Disconnect: video keeps
                        // streaming, only the LLM tick is skipped.
                        Button {
                            Task { await toggleAiPause() }
                        } label: {
                            controlRow(
                                icon: cam.aiPaused ? "waveform" : "waveform.slash",
                                title: togglingAiPause
                                    ? (cam.aiPaused ? "Resuming AI…" : "Pausing AI…")
                                    : (cam.aiPaused ? "Resume AI" : "Pause AI"),
                                subtitle: cam.aiPaused
                                    ? "Resume AI tick. Video keeps streaming either way."
                                    : "Pause AI tick. Video keeps streaming.",
                                destructive: false,
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(togglingAiPause || togglingDisconnect)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func controlRow(
        icon: String, title: String, subtitle: String, destructive: Bool,
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(destructive ? NemaraColor.terraSoft : NemaraColor.paperDim)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(destructive ? NemaraColor.terra : NemaraColor.ink2)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(NemaraFont.bodySmallStrong)
                    .foregroundStyle(destructive ? NemaraColor.terra : NemaraColor.ink)
                Text(subtitle)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NemaraColor.ink3)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    /// Per-camera detector toggles. The list comes from the patient's
    /// full detector set; checkmark = currently assigned in
    /// `cameras_detectors`. Tapping a row flips that detector's
    /// membership in the camera's set.
    private var detectorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("DETECTORS ON THIS SENSOR")
                .padding(.horizontal, 16)

            if let err = assignmentsError {
                Text(err)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.terra)
                    .padding(.horizontal, 16)
            }

            NemaraCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(togglableDetectors.indices, id: \.self) { i in
                        let det = togglableDetectors[i]
                        DetectorAssignmentRow(
                            detector: det,
                            isAssigned: assignedDetectorIds.contains(det.id),
                            isBusy: togglingDetectorId == det.id,
                            onToggle: { Task { await toggleDetector(det) } },
                        )
                        if i < togglableDetectors.count - 1 {
                            NemaraColor.line.frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            HStack {
                Spacer()
                InfoDot("Applies to this camera only, other cameras are independent. The master switch lives on the detector.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    // MARK: - Exit doors (per sensor)

    private func exitDoorsSection(_ cam: Camera) -> some View {
        let active = isWanderingActiveHere
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                NemaraEyebrow("WANDERING · EXIT DOORS")
                Spacer()
                Text(active ? "ACTIVE" : "NOT ACTIVE")
                    .font(NemaraFont.mono(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(active ? NemaraColor.success : NemaraColor.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((active ? NemaraColor.success : NemaraColor.ink3).opacity(0.14))
                    .clipShape(Capsule(style: .continuous))
            }
            .padding(.horizontal, 16)

            NemaraCard(padding: 0) {
                Button { showDoorPicker = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "door.left.hand.open")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NemaraColor.terra)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exit doors on this sensor")
                                .font(NemaraFont.bodySemibold)
                                .foregroundStyle(NemaraColor.ink)
                            Text(doorStatusText)
                                .font(NemaraFont.caption)
                                .foregroundStyle(NemaraColor.ink3)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer()
                        Text(doorConfig != nil ? "Change" : "Set")
                            .font(NemaraFont.mono(size: 10, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(NemaraColor.terra)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            Text(active
                 ? "Only someone leaving through these doors counts as wandering on this sensor."
                 : "Wandering is OFF on this sensor until you set its exit doors — pick the door(s) someone would use to leave home in this view.")
            .font(NemaraFont.caption)
            .foregroundStyle(NemaraColor.ink3)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private var doorStatusText: String {
        guard let dc = doorConfig else {
            return "Not set · any doorway counts as leaving"
        }
        if dc.noExitDoor { return "No door leads outside · wandering off here" }
        switch dc.doors.count {
        case 0:
            return "Not set · any doorway counts as leaving"
        case 1:
            if let label = dc.doors.first?.label, !label.isEmpty {
                return "1 exit door · \(label)"
            }
            return "1 exit door set"
        default:
            return "\(dc.doors.count) exit doors set"
        }
    }

    private func loadDoorConfig() async {
        guard let list = try? await env.api.wanderingDoors(forPatient: patientId) else { return }
        doorConfig = list.first(where: { $0.cameraId == cameraId })?.doorConfig
    }

    /// Warm this sensor's frame + door detection in the background so opening
    /// the picker is instant (cached; Rescan refreshes).
    private func prewarmDoorFrame() async {
        // The identity itself is no longer needed (the backend resolves the
        // camera from its id), but a nil one still means "not paired yet",
        // so the guard stays.
        guard let wd = wanderingDetector, wd.isOn,
              let cam = camera, cam.online, !cam.disabled,
              cam.livekitIdentity != nil else { return }
        let out = await WanderingDoorCache.shared.ensureFrame(
            cameraId: cam.id, api: env.api,
        )
        if out == .ok {
            _ = await WanderingDoorCache.shared.ensureDoors(cameraId: cam.id, api: env.api)
        }
    }

    // MARK: - Actions

    /// Load the per-camera detector assignment set. Called on appear
    /// and whenever `cameraId` changes (defensive — the view is
    /// usually constructed per-camera).
    private func loadAssignments() async {
        assignmentsError = nil
        do {
            let ids = try await env.api.getCameraDetectors(cameraId)
            assignedDetectorIds = Set(ids)
        } catch {
            assignmentsError = "Couldn't load detector assignments: "
                + error.localizedDescription
        }
    }

    /// Optimistically flip a detector's assignment and PUT the new
    /// full set. Roll back on failure. Backend echoes the final set,
    /// which we adopt as ground truth.
    private func toggleDetector(_ det: Detector) async {
        guard togglingDetectorId == nil else { return }
        let prev = assignedDetectorIds
        var next = prev
        if next.contains(det.id) {
            next.remove(det.id)
        } else {
            next.insert(det.id)
        }
        assignedDetectorIds = next
        togglingDetectorId = det.id
        defer { togglingDetectorId = nil }
        do {
            let final = try await env.api.setCameraDetectors(
                cameraId, detectorIds: Array(next),
            )
            assignedDetectorIds = Set(final)
        } catch {
            assignedDetectorIds = prev
            assignmentsError = "Couldn't update: " + error.localizedDescription
        }
    }

    private func toggleAiPause() async {
        guard let cam = camera else { return }
        togglingAiPause = true
        actionError = nil
        defer { togglingAiPause = false }
        do {
            _ = try await env.api.updateCamera(
                cameraId, UpdateCameraRequest(aiPaused: !cam.aiPaused),
            )
        } catch {
            actionError = "Couldn't update: " + error.localizedDescription
        }
    }

    private func disconnectCamera() async {
        togglingDisconnect = true
        actionError = nil
        defer { togglingDisconnect = false }
        do {
            _ = try await env.api.updateCamera(
                cameraId, UpdateCameraRequest(desiredState: .disconnected),
            )
        } catch {
            actionError = "Couldn't disconnect: " + error.localizedDescription
        }
    }

    /// Delete the camera row from the backend. The wall phone polls
    /// /v1/cameras/me/desired-state every 1s; after 5 consecutive
    /// 401/403/404 it self-unpairs (see DesiredStateMonitor in
    /// MemoriaSensor). Local cache update from the realtime DELETE event
    /// will remove the camera from `camerasByPatient` so the parent
    /// list updates without a refresh.
    private func unpairButton(_ cam: Camera) -> some View {
        VStack(spacing: 8) {
            NemaraEyebrow("PAIRING")
                .padding(.horizontal, 16)
            Button {
                showingUnpairConfirm = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 14, weight: .semibold))
                    Text(unpairing ? "Unpairing…" : "Unpair sensor")
                        .font(NemaraFont.bodySmallStrong)
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .foregroundStyle(NemaraColor.ink)
                .background(NemaraColor.paperDim)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(unpairing)
            .padding(.horizontal, 16)
            Text("Frees this sensor so a phone can be re-paired to it. Keeps the room, detectors, and history.")
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        }
    }

    private func unpairCamera() async {
        unpairing = true
        actionError = nil
        defer { unpairing = false }
        do {
            try await env.api.unpairCamera(cameraId)
            // Stay on the detail screen — the camera flips to unpaired and
            // the "Show pairing code" section appears so a phone can be
            // re-paired. (Delete dismisses; unpair does not.)
        } catch {
            actionError = "Couldn't unpair: " + error.localizedDescription
        }
    }

    private func deleteCameraButton(_ cam: Camera) -> some View {
        VStack(spacing: 8) {
            NemaraEyebrow("DANGER ZONE")
                .padding(.horizontal, 16)
            Button {
                showingDeleteConfirm = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                    Text(deleting ? "Deleting…" : "Delete sensor")
                        .font(NemaraFont.bodySmallStrong)
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .foregroundStyle(NemaraColor.terra)
                .background(NemaraColor.terraSoft)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(deleting)
            .padding(.horizontal, 16)
        }
    }

    private func deleteCamera() async {
        deleting = true
        actionError = nil
        defer { deleting = false }
        do {
            try await env.api.deleteCamera(cameraId)
            // Pop back to the parent (Cameras list) immediately; the
            // realtime DELETE event will also remove the row from
            // env.api.camerasByPatient so the list updates.
            await MainActor.run { dismiss() }
        } catch {
            actionError = "Couldn't delete: " + error.localizedDescription
        }
    }

    private func reconnectCamera() async {
        togglingDisconnect = true
        actionError = nil
        defer { togglingDisconnect = false }
        do {
            _ = try await env.api.updateCamera(
                cameraId, UpdateCameraRequest(desiredState: .connected),
            )
        } catch {
            actionError = "Couldn't reconnect: " + error.localizedDescription
        }
    }
}

/// One row in the camera-detail's detector-assignment list.
/// Tappable; busy state disables interaction.
private struct DetectorAssignmentRow: View {
    let detector: Detector
    let isAssigned: Bool
    let isBusy: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NemaraColor.paperDim)
                    Image(systemName: detector.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink2)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(detector.name)
                            .font(NemaraFont.bodySmallStrong)
                            .foregroundStyle(NemaraColor.ink)
                        if !detector.isOn {
                            NemaraChip("OFF GLOBALLY", tone: .neutral)
                        }
                        if detector.identifier == nil {
                            NemaraChip("COMPILING…", tone: .warning)
                        }
                    }
                    Text(detector.description)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .lineLimit(2)
                }
                Spacer()
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(
                        systemName: isAssigned
                            ? "checkmark.circle.fill"
                            : "circle",
                    )
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(
                        isAssigned ? NemaraColor.action : NemaraColor.ink3,
                    )
                }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || !detector.isOn)
        .opacity(detector.isOn ? 1.0 : 0.55)
    }
}
