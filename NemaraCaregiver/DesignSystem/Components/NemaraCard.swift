import SwiftUI

/// Raised paper card. Default background is `Card` (`#FBF8F0`); tone
/// variants paint a soft tint over the same border treatment.
///
/// Use the `tone` parameter for hero cards (terra-soft for safety hero,
/// sky-soft for routine hero) — never for event cards in the events list,
/// which compose `Card(pad: 0)` directly with a custom background.
struct NemaraCard<Content: View>: View {
    enum Tone { case `default`, alt, terra, sky, success, action }

    let tone: Tone
    let padding: CGFloat
    let borderColor: Color?
    let content: () -> Content

    init(
        tone: Tone = .default,
        padding: CGFloat = NemaraSpacing.md,
        borderColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tone = tone
        self.padding = padding
        self.borderColor = borderColor
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                    .strokeBorder(borderColor ?? NemaraColor.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous))
    }

    private var background: Color {
        switch tone {
        case .default: return NemaraColor.card
        case .alt:     return NemaraColor.cardAlt
        case .terra:   return NemaraColor.terraSoft
        case .sky:     return NemaraColor.skySoft
        case .success: return NemaraColor.actionSoft
        case .action:  return NemaraColor.actionSoft
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        NemaraCard {
            Text("Default card")
                .font(NemaraFont.bodyMedium)
        }
        NemaraCard(tone: .terra) {
            Text("Terra-tinted hero")
                .font(NemaraFont.bodyMedium)
        }
        NemaraCard(tone: .sky) {
            Text("Sky-tinted hero")
                .font(NemaraFont.bodyMedium)
        }
        NemaraCard(tone: .alt, padding: NemaraSpacing.lg) {
            Text("Alt surface, padded")
                .font(NemaraFont.bodyMedium)
        }
    }
    .padding()
    .background(NemaraColor.paper)
}
