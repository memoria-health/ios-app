import SwiftUI

/// Roster row card — Avatar + name/age + status line (pulse on critical)
/// + last-event + chevron.
///
/// Critical state paints the entire card with a terra-soft tint and a
/// 1.5pt terra border; offline state mutes the status text. Otherwise
/// the row is a default Card with hairline borders.
struct PatientRow: View {
    @Environment(AppEnvironment.self) private var env
    let patient: Patient

    /// The patient-level pause flag (`cameras_paused`) no longer gates
    /// detection or display — those follow each camera's own state — so the
    /// roster no longer paints a misleading "Monitoring paused" treatment
    /// for it. Pinned to `false` so the styling branches below collapse to
    /// the normal state without restructuring the row.
    private var isPaused: Bool { false }

    private var unopenedCount: Int {
        env.api.eventsByPatient[patient.id]?.filter { !$0.opened }.count ?? 0
    }

    var body: some View {
        NemaraCard(
            tone: isPaused ? .alt : (patient.state == .critical ? .terra : .default),
            padding: 14,
            borderColor: isPaused ? NemaraColor.line : (patient.state == .critical ? NemaraColor.terra : NemaraColor.line)
        ) {
            HStack(spacing: 12) {
                PatientAvatar(patient: patient, size: 48)
                    .opacity(isPaused ? 0.55 : 1)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(patient.preferredName)
                            .font(NemaraFont.serif(size: 19, weight: .regular))
                            .kerning(-0.3)
                            .foregroundStyle(NemaraColor.ink)
                        Text(", \(patient.age)")
                            .font(NemaraFont.bodyLarge)
                            .foregroundStyle(NemaraColor.ink3)
                        if isPaused {
                            Text("PAUSED")
                                .font(NemaraFont.mono(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(NemaraColor.ink3)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(NemaraColor.paperDim)
                                .clipShape(Capsule(style: .continuous))
                                .padding(.leading, 2)
                        }
                    }
                    HStack(spacing: 6) {
                        if !isPaused && patient.state == .critical {
                            NemaraPulse(color: NemaraColor.terra, size: 6)
                        }
                        Text(isPaused ? "Monitoring paused" : patient.statusLine)
                            .font(NemaraFont.bodySmall.weight(!isPaused && patient.state == .critical ? .semibold : .medium))
                            .foregroundStyle(statusColor)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Text(lastEventLabel)
                            .font(NemaraFont.monoSmall)
                            .tracking(0.5)
                            .foregroundStyle(NemaraColor.ink3)
                        if !isPaused, unopenedCount > 0 {
                            Text("·").foregroundStyle(NemaraColor.line)
                            Text("\(unopenedCount) NEW")
                                .font(NemaraFont.monoSmall)
                                .tracking(0.5)
                                .foregroundStyle(NemaraColor.terra)
                        }
                    }
                    .opacity(isPaused ? 0.55 : 1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(!isPaused && patient.state == .critical ? NemaraColor.terra : NemaraColor.ink3)
            }
        }
    }

    private var statusColor: Color {
        if isPaused { return NemaraColor.ink3 }
        switch patient.state {
        case .critical: return NemaraColor.terra
        case .offline:  return NemaraColor.ink3
        case .calm:     return NemaraColor.ink
        }
    }
    private var lastEventLabel: String {
        guard let when = patient.lastEventAt else { return "" }
        let now = Date()
        let minutes = Int(now.timeIntervalSince(when) / 60)
        if minutes < 1 { return "JUST NOW" }
        if minutes < 60 { return "\(minutes) MIN AGO" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) H AGO" }
        return "YESTERDAY"
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return VStack(spacing: 10) {
        ForEach(env.api.patients) { p in
            PatientRow(patient: p)
        }
    }
    .padding()
    .background(NemaraColor.paper)
    .environment(env)
}
#endif
