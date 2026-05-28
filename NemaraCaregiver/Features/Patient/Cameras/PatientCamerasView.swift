import SwiftUI

/// "Cameras" sub-tab. Lists every paired camera under this patient,
/// shows live status, and provides entry points to the per-camera
/// detail view (which hosts Hide / Disconnect / detector-assignment
/// controls) plus the pair-a-new-phone flow.
///
/// Extracted from `PatientSettingsView.swift`'s prior `camerasSection`
/// so cameras get their own first-class tab, matching the web
/// dashboard's `/cameras` page.
struct PatientCamerasView: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env

    @State private var showingAddCamera = false

    private var cameras: [Camera] {
        env.api.camerasByPatient[patientId] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if cameras.isEmpty {
                    emptyCard
                } else {
                    list
                }
                NemaraButton(
                    "Add a camera",
                    variant: .secondary,
                    block: true,
                    systemImage: "plus",
                ) {
                    showingAddCamera = true
                }
                .padding(.horizontal, 16)
                // Clear the floating tab bar so the last row isn't
                // hidden behind it.
                .padding(.bottom, 120)
            }
            .padding(.top, 12)
        }
        .background(NemaraColor.paper)
        .sheet(isPresented: $showingAddCamera) {
            AddCameraSheet(patientId: patientId)
                .presentationDetents([.large])
        }
    }

    private var emptyCard: some View {
        NemaraCard(padding: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("No cameras yet")
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
                Text("Pair a wall phone to start monitoring. Each pairing generates a 6-digit code valid for ~10 minutes.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("CAMERAS · \(cameras.count) PAIRED")
                .padding(.horizontal, 16)
            NemaraCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(cameras.indices, id: \.self) { i in
                        let cam = cameras[i]
                        NavigationLink(value: cam.id) {
                            CameraRow(camera: cam)
                        }
                        .buttonStyle(.plain)
                        if i < cameras.count - 1 {
                            NemaraColor.line.frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .navigationDestination(for: UUID.self) { cameraId in
            CameraDetailView(cameraId: cameraId, patientId: patientId)
        }
    }

}

/// One row in the cameras list. Live status comes from the canonical
/// `online` flag (which is reliable for paired rows — see Camera.swift
/// for why we don't use it as the visibility filter on the Live tab).
private struct CameraRow: View {
    let camera: Camera

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(NemaraColor.paperDim)
                Image(systemName: camera.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink2)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(camera.room)
                    .font(NemaraFont.bodySmallStrong)
                    .foregroundStyle(NemaraColor.ink)
                Text(statusLine)
                    .font(NemaraFont.monoSmall)
                    .foregroundStyle(NemaraColor.ink3)
            }
            Spacer()
            if camera.sourceType == .sensor {
                // Always-on badge identifying this row as a sensor
                // camera. Placed before the interesting-state pill so
                // a sensor camera that is also disconnected/hidden
                // shows both chips, source first.
                NemaraChip("SENSOR", tone: .sky)
            }
            stateBadge
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NemaraColor.ink3)
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    private var statusLine: String {
        let id = "CAM \(String(format: "%02d", camera.displayId))"
        if !camera.paired {
            return "\(id) · PAIRING"
        }
        if camera.desiredState == .disconnected {
            return "\(id) · DISCONNECTED"
        }
        if camera.disabled {
            return "\(id) · HIDDEN"
        }
        if camera.aiPaused {
            return "\(id) · AI PAUSED"
        }
        return "\(id) · \(camera.online ? "LIVE" : "OFFLINE")"
    }

    /// Compact pill to the right of the row. Only shows when state is
    /// "interesting" (i.e., not the default Connected+visible). Lets
    /// the caregiver eyeball at-a-glance which cameras need attention.
    /// NemaraChip tones come from {neutral, terra, sky, action,
    /// warning, dark} — picked for semantic weight (terra=destructive,
    /// warning=needs-attention, action=informational).
    @ViewBuilder
    private var stateBadge: some View {
        if camera.desiredState == .disconnected {
            NemaraChip("OFF", tone: .terra)
        } else if camera.disabled {
            NemaraChip("HIDDEN", tone: .warning)
        } else if camera.aiPaused {
            NemaraChip("AI PAUSED", tone: .neutral)
        } else if !camera.paired {
            NemaraChip("PAIRING", tone: .action)
        }
    }
}
