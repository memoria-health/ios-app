import SwiftUI

/// Mono-uppercase eyebrow label modifier. Wraps the design system's
/// "ts-eye" pattern: JetBrains Mono, 11pt, 0.6em tracking, uppercase.
extension Text {
    /// Apply Nemara eyebrow styling — uppercase, mono, 0.6 letter-spacing.
    /// Default color is `ink3` (muted); pass `.terra` for the section
    /// eyebrows above hero headlines.
    func nemaraEyebrow(_ color: Color = NemaraColor.ink3) -> some View {
        self
            .font(NemaraFont.eyebrow)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// A bare eyebrow view — convenient when you want the styled label
/// inline without converting a Text. Equivalent to
/// `Text(text).nemaraEyebrow(color)`.
struct NemaraEyebrow: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color = NemaraColor.ink3) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).nemaraEyebrow(color)
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 12) {
        NemaraEyebrow("RECENT EVENTS")
        NemaraEyebrow("BEFORE YOU TURN IT ON", color: NemaraColor.terra)
        NemaraEyebrow("CAMERAS · 4 ONLINE")
    }
    .padding()
    .background(NemaraColor.paper)
}
#endif
