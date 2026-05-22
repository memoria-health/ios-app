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
                ))
            }
            .padding(14)

            if detector.isOn {
                sensitivityPicker
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            if !isLast {
                NemaraColor.line.frame(height: 1)
            }
        }
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
    }

    private var tunableLevels: [Detector.Sensitivity] {
        [.low, .standard, .high]
    }

    private var sensitivityHint: String {
        switch detector.sensitivity {
        case .low:      "Fewer alerts · only the clearest signals"
        case .standard: "Recommended baseline"
        case .high:     "More alerts · catches subtle signals"
        case .off:      "Detector off"
        }
    }
}
