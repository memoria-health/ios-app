import SwiftUI

/// One row in the Patient Settings detector list. Icon tile + name +
/// description + 4-axis mono caption + on/off toggle. When the
/// detector is on, an inline Low / Standard / High segmented picker
/// appears below the description so the caregiver can tune sensitivity
/// without drilling into another screen. Source==custom adds a CUSTOM pill.
struct DetectorRow: View {
    @Environment(AppEnvironment.self) private var env
    let patientId: UUID
    let detector: Detector
    let isLast: Bool

    @State private var confirmingDelete = false
    @State private var deleting = false
    /// Detail sheet: what this detector looks for + plain-words refine.
    @State private var showingDetail = false
    /// Per-sensor exit-door config, keyed by camera id (from the backend) — used
    /// only to show whether wandering is active on any sensor yet.
    @State private var doorConfigs: [UUID: Detector.DoorConfig] = [:]

    /// The wandering detector gets the per-sensor "exit doors" affordance.
    private var isWandering: Bool { detector.identifier == "wandering" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Icon tint carries the category (safety vs routine), so the
                // separate CUSTOM / category pills are gone.
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(detector.category == .safety ? NemaraColor.terraSoft : NemaraColor.skySoft)
                    Image(systemName: detector.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(detector.category == .safety ? NemaraColor.terraDeep : NemaraColor.sky)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(detector.name)
                        .font(NemaraFont.bodySmallStrong)
                        .foregroundStyle(NemaraColor.ink)
                    Text(detector.description)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink2)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    whereWhenPill
                        .padding(.top, 4)
                    // Compact accuracy caveat for fine-detail detectors, matching
                    // the web list's inline notice.
                    if detector.showsAccuracyCaveat {
                        AccuracyCaveatNotice(compact: true)
                            .padding(.top, 4)
                    }
                }
                Spacer()
                NemaraToggle(isOn: Binding(
                    get: { detector.isOn },
                    set: { newValue in
                        Task {
                            _ = try? await env.api.updateDetector(
                                detector.id, UpdateDetectorRequest(isOn: newValue),
                            )
                        }
                    }
                ), track: "detector.toggle")
                Menu {
                    Button {
                        showingDetail = true
                    } label: {
                        Label("Edit detector", systemImage: "slider.horizontal.3")
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete detector", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink3)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(deleting)
            }
            .padding(14)
            .sheet(isPresented: $showingDetail) {
                DetectorDetailSheet(patientId: patientId, detector: detector)
            }
            .alert(
                "Delete \"\(detector.name)\"?",
                isPresented: $confirmingDelete,
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleting = true
                    Task {
                        defer { deleting = false }
                        try? await env.api.deleteDetector(detector.id)
                    }
                }
            } message: {
                Text("This removes the detector for this patient. Any in-flight clips that already fired stay in the events feed.")
            }

            // Sensitivity now lives in the detail sheet (edit sheet only),
            // matching the web dashboard. The wandering activation hint still
            // shows here while the detector is on.
            if detector.isOn && isWandering {
                wanderingActivationHint
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            if !isLast {
                NemaraColor.line.frame(height: 1)
            }
        }
        .task(id: prefetchKey) {
            if isWandering, detector.isOn { await loadDoorConfigs() }
        }
    }

    private var prefetchKey: String { "\(detector.id)-\(detector.isOn)" }

    private func loadDoorConfigs() async {
        guard let list = try? await env.api.wanderingDoors(forPatient: patientId) else { return }
        var m: [UUID: Detector.DoorConfig] = [:]
        for entry in list {
            if let dc = entry.doorConfig { m[entry.cameraId] = dc }
        }
        doorConfigs = m
    }

    /// A sensor counts as "active" for wandering once it has >=1 exit door set.
    private var activeSensorCount: Int {
        doorConfigs.values.filter { !$0.noExitDoor && !$0.doors.isEmpty }.count
    }

    /// Wandering only runs on a sensor once its exit doors are set. Surface that
    /// here (and point to the Sensors tab), so "on" doesn't imply it's actually
    /// watching anything yet.
    private var wanderingActivationHint: some View {
        let active = activeSensorCount
        // .top so the icon lines up with the first line when the text wraps
        // to two lines (item E7).
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: active > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active > 0 ? NemaraColor.success : NemaraColor.warning)
            Text(active > 0
                 ? "Active on \(active) sensor\(active == 1 ? "" : "s") · set exit doors per sensor in the Sensors tab"
                 : "Not active yet. Open a sensor in the Sensors tab and set its exit doors to turn wandering on")
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((active > 0 ? NemaraColor.success : NemaraColor.warning).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        .padding(.leading, 44)
    }

    // A single where·when pill. The trigger label was dropped to keep the row
    // minimal; it lives in the detail sheet.
    private var whereWhenPill: some View {
        HStack(spacing: 4) {
            Text(detector.roomsLabel)
            Text("·").foregroundStyle(NemaraColor.line)
            Text(whenLabel)
        }
        .font(NemaraFont.mono(size: 9.5, weight: .semibold))
        .tracking(0.5)
        .foregroundStyle(NemaraColor.ink3)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay(Capsule(style: .continuous).stroke(NemaraColor.line, lineWidth: 1))
    }

    private var whenLabel: String {
        detector.whenScope.trimmingCharacters(in: .whitespaces).uppercased() == "ALWAYS"
            ? "Always" : detector.whenScope
    }

}
