import SwiftUI

/// A circular avatar that derives its hue from the patient's first letter
/// (so different patients are visually distinct without us having to ship
/// a photo). The letter sits centered in Fraunces, like a serif monogram.
///
/// When real photos arrive, swap the body for an `AsyncImage` with this
/// view as the placeholder — keep the size + ring API identical.
struct NemaraAvatar: View {
    let letter: String
    let size: CGFloat
    let ring: Color?

    init(letter: String, size: CGFloat = 40, ring: Color? = nil) {
        self.letter = String(letter.prefix(1)).uppercased()
        self.size = size
        self.ring = ring
    }

    var body: some View {
        ZStack {
            Circle().fill(backgroundColor)
            Text(letter)
                .font(NemaraFont.serif(size: size * 0.42, weight: .semibold))
                .foregroundStyle(NemaraColor.ink)
                .kerning(-0.5)
        }
        .frame(width: size, height: size)
        .overlay(
            ring.map { Circle().strokeBorder($0, lineWidth: 2) }
        )
    }

    /// HSL-style derived warm background so each letter gets a distinct
    /// pastel tone that still reads as "warm" against the paper canvas.
    private var backgroundColor: Color {
        let scalar = letter.unicodeScalars.first?.value ?? 0
        let hue = Double((Int(scalar) * 47) % 360) / 360.0
        return Color(hue: hue, saturation: 0.18, brightness: 0.86)
    }
}

#Preview {
    HStack(spacing: 14) {
        NemaraAvatar(letter: "M")
        NemaraAvatar(letter: "E", size: 56)
        NemaraAvatar(letter: "H", size: 68)
        NemaraAvatar(letter: "S", size: 32)
        NemaraAvatar(letter: "J", size: 28, ring: NemaraColor.terra)
    }
    .padding()
    .background(NemaraColor.paper)
}
