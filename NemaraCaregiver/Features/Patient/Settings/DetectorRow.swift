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
    @State private var showSensitivityInfo = false
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
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NemaraColor.paperDim)
                    Image(systemName: detector.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink2)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(detector.name)
                            .font(NemaraFont.bodySmallStrong)
                            .foregroundStyle(NemaraColor.ink)
                            .contentShape(Rectangle())
                            .onTapGesture { showingDetail = true }
                        if detector.source == .custom {
                            Text("CUSTOM")
                                .font(NemaraFont.mono(size: 8.5, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(NemaraColor.terra)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(NemaraColor.terraSoft)
                                .clipShape(Capsule(style: .continuous))
                        }
                    }
                    Text(detector.description)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink2)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    fourAxisCaption
                        .padding(.top, 4)
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

            if detector.isOn {
                sensitivityPicker
                    .padding(.horizontal, 14)
                    .padding(.bottom, isWandering ? 8 : 12)

                if isWandering {
                    wanderingActivationHint
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }
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
                 : "Not active yet — open a sensor in the Sensors tab and set its exit doors to turn wandering on")
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

    private var fourAxisCaption: some View {
        // Caregiver-facing words, never the raw enum (item E2).
        HStack(spacing: 6) {
            Text(detector.alertTrigger.caregiverShort)
            Text("·").foregroundStyle(NemaraColor.line)
            Text(detector.roomsLabel)
            Text("·").foregroundStyle(NemaraColor.line)
            Text(whenLabel)
        }
        .font(NemaraFont.mono(size: 9.5, weight: .semibold))
        .tracking(0.5)
        .foregroundStyle(NemaraColor.ink3)
    }

    private var whenLabel: String {
        detector.whenScope.trimmingCharacters(in: .whitespaces).uppercased() == "ALWAYS"
            ? "Always" : detector.whenScope
    }

    private var sensitivityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink3)
                Text("SENSITIVITY")
                    .font(NemaraFont.mono(size: 10, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(NemaraColor.ink3)
                Button { showSensitivityInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What does sensitivity mean?")
                Spacer()
                Text(sensitivityHint)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 6) {
                ForEach(tunableLevels, id: \.self) { level in
                    let on = detector.sensitivity == level
                    Button {
                        Task {
                            _ = try? await env.api.updateDetector(
                                detector.id, UpdateDetectorRequest(sensitivity: level),
                            )
                        }
                    } label: {
                        Text(level.displayName)
                            .font(NemaraFont.bodySmallStrong.weight(on ? .semibold : .medium))
                            .foregroundStyle(on ? NemaraColor.ink : NemaraColor.ink3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(on ? NemaraColor.card : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
                            .shadow(color: on ? NemaraColor.ink.opacity(0.06) : .clear, radius: 1, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(NemaraColor.paperDim)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        }
        .padding(.leading, 44)
        .sheet(isPresented: $showSensitivityInfo) {
            SensitivityInfoSheet()
                .presentationDetents([.medium])
        }
    }

    private var tunableLevels: [Detector.Sensitivity] {
        [.low, .standard, .high]
    }

    private var sensitivityHint: String {
        switch detector.sensitivity {
        case .low:      "Fewer alerts · only the clearest signals"
        case .standard: "Recommended baseline"
        case .high:     "More alerts"
        case .off:      "Detector off"
        }
    }
}

/// Explains what Low / Standard / High sensitivity actually do — the
/// confidence-vs-noise trade-off — so caregivers can tune intentionally.
private struct SensitivityInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sensitivity")
                        .font(NemaraFont.title2)
                        .foregroundStyle(NemaraColor.ink)
                    Text("How sure Memoria needs to be before it alerts you. Higher catches more, but with more false alarms.")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink2)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                level("Low", "Fewer alerts", "Only fires on the clearest, most obvious signals. Best when you want to avoid false alarms and only hear about the strongest events — at the cost of missing subtler ones.")
                level("Standard", "Recommended", "A balanced baseline that works well for most rooms and detectors. Start here.")
                level("High", "More alerts", "Fires on weaker or more ambiguous signals, so it catches subtle events others miss — but expect more false alarms to review.")

                Text("You can change this anytime per detector; it only affects this sensor.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .padding(.top, 2)
            }
            .padding(20)
        }
        .background(NemaraColor.paper)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(NemaraColor.ink3)
            }
            .buttonStyle(.plain)
            .padding(14)
        }
    }

    private func level(_ name: String, _ tag: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(name)
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
                Text(tag.uppercased())
                    .font(NemaraFont.mono(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(NemaraColor.terra)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(NemaraColor.terraSoft)
                    .clipShape(Capsule(style: .continuous))
            }
            Text(body)
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
