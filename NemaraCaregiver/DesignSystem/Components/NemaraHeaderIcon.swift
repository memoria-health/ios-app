import SwiftUI

/// One icon action in a screen header (the roster's, a patient's). Exists so the header's actions are the
/// same size, weight and hit area by construction rather than by three
/// copies of the same modifiers agreeing with each other — which they
/// had stopped doing.
///
/// The glyph is 20pt but the tappable frame is 32pt: at 20pt alone the
/// targets were under Apple's 44pt guidance and sat closer together than
/// they measured, because a `plus` is narrower than a `sensor.tag`.
struct NemaraHeaderIcon: View {
    static let hit: CGFloat = 32
    static let gap: CGFloat = 20

    private let symbol: String
    private let label: String
    private let action: () -> Void

    init(_ symbol: String, label: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(NemaraColor.ink)
                .frame(width: Self.hit, height: Self.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
