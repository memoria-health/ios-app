import SwiftUI

/// Per-camera detail screen. Three control surfaces:
///
///   1. **Hide / Show** — flips `cameras.disabled`. Instant; LiveKit
///      stays connected. Web dashboard's tile menu calls this
///      "Hide camera".
///   2. **Disconnect / Reconnect** — flips `cameras.desired_state`.
///      Wall phone polls every 1s and reconciles by leaving / rejoining
///      LiveKit. ~1-2s latency on reconnect. Confirmed via alert before
///      Disconnect (destructive direction) but not Reconnect.
///   3. **Per-camera detector toggles** — `cameras_detectors` join
///      table. Each toggle calls
///      `PUT /v1/cameras/{id}/detectors` with the full new set.
///
/// Detector toggles use optimistic UI with rollback on error. Hide /
/// Disconnect flips also drop their `busy` flags in `defer` (not just
/// in `catch`) so a successful round-trip doesn't permanently disable
/// the buttons (we got bit by exactly this pattern in the web grid).
struct CameraDetailView: View {
    let cameraId: UUID
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env

    @State private var assignedDetectorIds: Set<UUID> = []
    @State private var loadingAssignments = true
    @State private var assignmentsError: String?

    /// Detector currently in-flight on the toggle path. Drives a
    /// per-row disabled state; UUID matches the detector being saved.
    @State private var togglingDetectorId: UUID?

    @State private var togglingHide = false
    @State private var togglingAiPause = false
    @State private var togglingDisconnect = false
    @State private var actionError: String?

    @State private var showingDisconnectConfirm = false

    private var camera: Camera? {
        env.api.camerasByPatient[patientId]?.first(where: { $0.id == cameraId })
    }
    private var detectors: [Detector] {
        env.api.detectorsByPatient[patientId] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let cam = camera {
                    headerCard(cam)
                    stateControls(cam)
                    detectorsSection
                } else {
                    Text("Camera not found")
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink3)
                        .padding(.top, 80)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(NemaraColor.paper)
        .navigationTitle(camera?.room ?? "Camera")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: cameraId) { await loadAssignments() }
        .alert(
            "Disconnect this camera?",
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
        let id = "CAM \(String(format: "%02d", cam.displayId))"
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
                    // Pause AI / Resume AI — instant, no confirm.
                    // Lighter than Hide: video keeps streaming, only
                    // the LLM call is skipped.
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
                    .disabled(togglingHide || togglingAiPause || togglingDisconnect)

                    NemaraColor.line.frame(height: 1)

                    // Hide / Show — instant, no confirm.
                    Button {
                        Task { await toggleHide() }
                    } label: {
                        controlRow(
                            icon: cam.disabled ? "eye" : "eye.slash",
                            title: togglingHide
                                ? (cam.disabled ? "Showing…" : "Hiding…")
                                : (cam.disabled ? "Show camera" : "Hide camera"),
                            subtitle: cam.disabled
                                ? "Show tile + resume AI calls."
                                : "Hide tile + pause AI calls. LiveKit stays connected.",
                            destructive: false,
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(togglingHide || togglingAiPause || togglingDisconnect)

                    NemaraColor.line.frame(height: 1)

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
                    .disabled(togglingHide || togglingAiPause || togglingDisconnect)
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
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                NemaraEyebrow("DETECTORS ON THIS CAMERA")
                Spacer()
                if loadingAssignments {
                    ProgressView().controlSize(.small)
                } else {
                    NemaraChip(
                        "\(assignedDetectorIds.count) / \(detectors.count) on",
                        tone: assignedDetectorIds.isEmpty ? .neutral : .action,
                    )
                }
            }
            .padding(.horizontal, 16)

            if let err = assignmentsError {
                Text(err)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.terra)
                    .padding(.horizontal, 16)
            }

            NemaraCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(detectors.indices, id: \.self) { i in
                        let det = detectors[i]
                        DetectorAssignmentRow(
                            detector: det,
                            isAssigned: assignedDetectorIds.contains(det.id),
                            isBusy: togglingDetectorId == det.id,
                            onToggle: { Task { await toggleDetector(det) } },
                        )
                        if i < detectors.count - 1 {
                            NemaraColor.line.frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            Text(
                "Toggling here only affects this camera. Other cameras "
                + "under the same patient are independent. The global "
                + "master switch lives on the detector itself.",
            )
            .font(NemaraFont.caption)
            .foregroundStyle(NemaraColor.ink3)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    // MARK: - Actions

    /// Load the per-camera detector assignment set. Called on appear
    /// and whenever `cameraId` changes (defensive — the view is
    /// usually constructed per-camera).
    private func loadAssignments() async {
        loadingAssignments = true
        assignmentsError = nil
        defer { loadingAssignments = false }
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

    private func toggleHide() async {
        guard let cam = camera else { return }
        togglingHide = true
        actionError = nil
        defer { togglingHide = false }
        do {
            _ = try await env.api.updateCamera(
                cameraId, UpdateCameraRequest(disabled: !cam.disabled),
            )
        } catch {
            actionError = "Couldn't update: " + error.localizedDescription
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
