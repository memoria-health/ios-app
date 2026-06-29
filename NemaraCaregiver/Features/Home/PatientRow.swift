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

    private var unopenedEvents: [DetectionEvent] {
        env.api.eventsByPatient[patient.id]?.filter { !$0.opened } ?? []
    }
    private var unopenedCount: Int { unopenedEvents.count }

    /// Only an unopened SAFETY event escalates the card to the red
    /// attention treatment. Routine (blue) events still show the NEW count
    /// but never paint the card red. `patient.state` / `statusLine` /
    /// `lastEventAt` are not server-maintained yet, so we derive everything
    /// the card shows from the events the app already has.
    private var hasUnopenedSafety: Bool {
        !isPaused && unopenedEvents.contains { $0.category == .safety }
    }

    var body: some View {
        NemaraCard(
            tone: isPaused ? .alt : (hasUnopenedSafety ? .terra : .default),
            padding: 14,
            borderColor: hasUnopenedSafety ? NemaraColor.terra : NemaraColor.line
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
                        if hasUnopenedSafety {
                            NemaraPulse(color: NemaraColor.terra, size: 6)
                        }
                        Text(isPaused ? "Monitoring paused" : statusText)
                            .font(NemaraFont.monoSmall)
                            .tracking(0.4)
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hasUnopenedSafety ? NemaraColor.terra : NemaraColor.ink3)
            }
        }
    }

    /// The prominent line where the (unwired) status summary used to be:
    /// the count of unopened events, or "All quiet" when there are none.
    private var statusText: String {
        if unopenedCount == 0 { return "All quiet" }
        return "\(unopenedCount) New event" + (unopenedCount == 1 ? "" : "s")
    }
    private var statusColor: Color {
        if isPaused || unopenedCount == 0 { return NemaraColor.ink3 }
        return hasUnopenedSafety ? NemaraColor.terra : NemaraColor.sky
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
