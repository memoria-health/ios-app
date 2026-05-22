import SwiftUI

/// Roster row card — Avatar + name/age + status line (pulse on critical)
/// + last-event + battery + chevron.
///
/// Critical state paints the entire card with a terra-soft tint and a
/// 1.5pt terra border; offline state mutes the status text. Otherwise
/// the row is a default Card with hairline borders.
struct PatientRow: View {
    let patient: Patient

    /// Paused overrides everything else — caregiver-driven state takes
    /// precedence over critical/calm/offline. So a critical patient
    /// whose cameras have been paused renders as PAUSED on the roster,
    /// not as critical, because there's nothing live to alarm about.
    private var isPaused: Bool { patient.camerasPaused }

    var body: some View {
        NemaraCard(
            tone: isPaused ? .alt : (patient.state == .critical ? .terra : .default),
            padding: 14,
            borderColor: isPaused ? NemaraColor.line : (patient.state == .critical ? NemaraColor.terra : NemaraColor.line)
        ) {
            HStack(spacing: 12) {
                NemaraAvatar(letter: patient.avatarLetter, size: 48)
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
                        Text("·").foregroundStyle(NemaraColor.line)
                        HStack(spacing: 4) {
                            BatteryGlyph(percent: patient.batteryPercent, color: batteryColor)
                            Text(batteryLabel)
                                .font(NemaraFont.monoSmall)
                                .foregroundStyle(batteryColor)
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
    private var batteryColor: Color {
        guard let p = patient.batteryPercent else { return NemaraColor.ink3 }
        if p < 20 { return NemaraColor.terra }
        if p < 40 { return NemaraColor.warning }
        return NemaraColor.ink3
    }
    private var batteryLabel: String {
        patient.batteryPercent.map { "\($0)%" } ?? "—"
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

/// Tiny battery glyph matching the design's 16×8 rect-with-tab.
private struct BatteryGlyph: View {
    let percent: Int?
    let color: Color

    var body: some View {
        let w: CGFloat = 16, h: CGFloat = 8
        Canvas { ctx, size in
            let outline = CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1)
            ctx.stroke(Path(roundedRect: outline, cornerRadius: 1.5),
                       with: .color(color), lineWidth: 1)
            // tab
            ctx.fill(Path(roundedRect: CGRect(x: w, y: h * 0.3, width: 1.5, height: h * 0.4), cornerRadius: 0.5),
                     with: .color(color))
            if let percent {
                let fillW = max(1.5, (CGFloat(percent) / 100.0) * (w - 2))
                ctx.fill(Path(CGRect(x: 2, y: 2, width: fillW, height: h - 4)),
                         with: .color(color))
            }
        }
        .frame(width: w + 2, height: h)
    }
}

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
