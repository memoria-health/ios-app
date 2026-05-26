import SwiftUI

/// A circular avatar. Without a `photoURL` it draws a serif initial
/// (so different patients are still visually distinct via a pastel
/// hue derived from the letter). With a `photoURL`, the AsyncImage
/// renders on top; the initials placeholder remains visible during
/// load + as the failure fallback so the layout never shifts.
struct NemaraAvatar: View {
    let letter: String
    let size: CGFloat
    let ring: Color?
    let photoURL: URL?

    init(letter: String, size: CGFloat = 40, ring: Color? = nil, photoURL: URL? = nil) {
        self.letter = String(letter.prefix(1)).uppercased()
        self.size = size
        self.ring = ring
        self.photoURL = photoURL
    }

    var body: some View {
        ZStack {
            initialsBackground

            if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .empty:
                        // Initials placeholder remains visible underneath.
                        Color.clear
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        // URL minted but fetch failed — keep initials.
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .overlay(
            ring.map { Circle().strokeBorder($0, lineWidth: 2) }
        )
    }

    private var initialsBackground: some View {
        ZStack {
            Circle().fill(backgroundColor)
            Text(letter)
                .font(NemaraFont.serif(size: size * 0.42, weight: .semibold))
                .foregroundStyle(NemaraColor.ink)
                .kerning(-0.5)
        }
    }

    /// HSL-style derived warm background so each letter gets a distinct
    /// pastel tone that still reads as "warm" against the paper canvas.
    private var backgroundColor: Color {
        let scalar = letter.unicodeScalars.first?.value ?? 0
        let hue = Double((Int(scalar) * 47) % 360) / 360.0
        return Color(hue: hue, saturation: 0.18, brightness: 0.86)
    }
}

#if DEBUG
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
#endif
