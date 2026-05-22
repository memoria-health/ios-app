import SwiftUI

/// Pill chips. Used for:
/// - status badges (ALL ONLINE / PARTIAL / OFFLINE) — `tone: .action / .warning / .terra`
/// - event category labels (SAFETY / ROUTINE / CUSTOM) — `solidPill` flavor
/// - generic neutral metadata pills (Last 7d) — `tone: .neutral`
///
/// For the solid-fill mono pills (SAFETY / ROUTINE / CUSTOM, 9pt 700 mono),
/// use `NemaraChip.solid(_:background:foreground:)` instead.
struct NemaraChip: View {
    enum Tone { case neutral, terra, sky, action, warning, dark }

    let text: String
    let tone: Tone
    let icon: String?
    let dotColor: Color?

    init(
        _ text: String,
        tone: Tone = .neutral,
        icon: String? = nil,
        dotColor: Color? = nil
    ) {
        self.text = text
        self.tone = tone
        self.icon = icon
        self.dotColor = dotColor
    }

    var body: some View {
        HStack(spacing: 5) {
            if let dotColor {
                Circle().fill(dotColor).frame(width: 5, height: 5)
            }
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(NemaraFont.mono(size: 9, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(foreground)
        .background(background)
        .clipShape(Capsule(style: .continuous))
    }

    private var background: Color {
        switch tone {
        case .neutral: return NemaraColor.paperDim
        case .terra:   return NemaraColor.terraSoft
        case .sky:     return NemaraColor.skySoft
        case .action:  return NemaraColor.actionSoft
        case .warning: return Color(red: 244/255, green: 227/255, blue: 199/255) // amber soft
        case .dark:    return NemaraColor.ink
        }
    }
    private var foreground: Color {
        switch tone {
        case .neutral: return NemaraColor.ink2
        case .terra:   return NemaraColor.terra
        case .sky:     return NemaraColor.sky
        case .action:  return NemaraColor.action
        case .warning: return Color(red: 140/255, green: 95/255, blue: 31/255) // darkened amber for AA
        case .dark:    return NemaraColor.paper
        }
    }
}

/// Solid-fill category pill — used for SAFETY / ROUTINE / CUSTOM badges
/// on event cards. Always 9pt 700 mono uppercase, paper text on a
/// saturated background.
struct NemaraSolidPill: View {
    let text: String
    let background: Color

    var body: some View {
        Text(text)
            .font(NemaraFont.mono(size: 9, weight: .bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(NemaraColor.terraInk)
            .background(background)
            .clipShape(Capsule(style: .continuous))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            NemaraChip("ALL ONLINE", tone: .action, dotColor: NemaraColor.action)
            NemaraChip("PARTIAL", tone: .warning, dotColor: Color(red: 198/255, green: 138/255, blue: 61/255))
            NemaraChip("OFFLINE", tone: .terra, dotColor: NemaraColor.terra)
        }
        HStack {
            NemaraSolidPill(text: "SAFETY", background: NemaraColor.terra)
            NemaraSolidPill(text: "ROUTINE", background: NemaraColor.sky)
            NemaraSolidPill(text: "CUSTOM", background: NemaraColor.terra)
        }
        HStack {
            NemaraChip("Last 7d")
            NemaraChip("5 active", tone: .action)
        }
    }
    .padding()
    .background(NemaraColor.paper)
}
