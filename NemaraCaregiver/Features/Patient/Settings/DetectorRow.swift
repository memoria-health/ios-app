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
    @State private var showDoorPicker = false

    /// The wandering detector gets an extra "exit door" affordance.
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
                    wanderingDoorRow
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }
            }

            if !isLast {
                NemaraColor.line.frame(height: 1)
            }
        }
        .sheet(isPresented: $showDoorPicker) {
            WanderingDoorPickerView(patientId: patientId, detector: detector)
        }
    }

    /// Exit-door affordance shown under the wandering detector. Tapping it opens
    /// the picker where the caregiver highlights the door that leads outside.
    private var wanderingDoorRow: some View {
        Button { showDoorPicker = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NemaraColor.terra)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exit door")
                        .font(NemaraFont.bodySmallStrong)
                        .foregroundStyle(NemaraColor.ink)
                    Text(doorStatusText)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                Text(detector.doorConfig?.box != nil ? "Change" : "Set")
                    .font(NemaraFont.mono(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(NemaraColor.terra)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink3)
            }
            .padding(12)
            .background(NemaraColor.paperDim)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 44)
    }

    private var doorStatusText: String {
        guard let dc = detector.doorConfig else {
            return "Not set · any doorway counts as leaving"
        }
        if dc.noExitDoor { return "No door leads outside" }
        if let label = dc.label, !label.isEmpty { return "Set · \(label)" }
        if dc.box != nil { return "Exit door set" }
        return "Not set · any doorway counts as leaving"
    }

    private var fourAxisCaption: some View {
        HStack(spacing: 6) {
            Text(detector.shape.displayName)
            Text("·").foregroundStyle(NemaraColor.line)
            Text(detector.whereScope)
            Text("·").foregroundStyle(NemaraColor.line)
            Text(detector.whenScope)
        }
        .font(NemaraFont.mono(size: 9.5, weight: .semibold))
        .tracking(0.5)
        .foregroundStyle(NemaraColor.ink3)
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
