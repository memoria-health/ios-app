import SwiftUI

/// Nemara button. Five variants × three sizes. Always rendered with the
/// system `Button` so SwiftUI's tap targets and accessibility work as
/// expected.
///
/// - `primary` — warm near-black (the default action color)
/// - `terra`   — brand-charged CTA (Talk-to-room, founders email)
/// - `secondary` — paper card on hairline border
/// - `ghost`   — bare text, no background
/// - `danger`  — terra solid; reserved for destructive confirmations
struct NemaraButton: View {
    enum Variant { case primary, terra, secondary, ghost, danger }
    enum Size { case sm, md, lg }

    let title: String
    let variant: Variant
    let size: Size
    let block: Bool
    let systemImage: String?
    let action: () -> Void

    init(
        _ title: String,
        variant: Variant = .primary,
        size: Size = .md,
        block: Bool = false,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.size = size
        self.block = block
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .semibold))
                }
                Text(title)
                    .font(NemaraFont.sans(size: fontSize, weight: .semibold))
                    .tracking(-0.1)
            }
            .frame(maxWidth: block ? .infinity : nil)
            .padding(.vertical, paddingV)
            .padding(.horizontal, paddingH)
            .foregroundStyle(foreground)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var fontSize: CGFloat {
        switch size { case .sm: 13; case .md: 14; case .lg: 16 }
    }
    private var iconSize: CGFloat { fontSize + 2 }
    private var paddingV: CGFloat {
        switch size { case .sm: 8; case .md: 12; case .lg: 16 }
    }
    private var paddingH: CGFloat {
        switch size { case .sm: 12; case .md: 16; case .lg: 20 }
    }
    private var background: Color {
        switch variant {
        case .primary:   return NemaraColor.action
        case .terra:     return NemaraColor.terra
        case .secondary: return NemaraColor.card
        case .ghost:     return .clear
        case .danger:    return NemaraColor.terra
        }
    }
    private var foreground: Color {
        switch variant {
        case .primary:   return NemaraColor.actionInk
        case .terra:     return NemaraColor.terraInk
        case .secondary: return NemaraColor.ink
        case .ghost:     return NemaraColor.ink
        case .danger:    return NemaraColor.terraInk
        }
    }
    private var borderColor: Color {
        switch variant {
        case .primary:   return NemaraColor.action
        case .terra:     return NemaraColor.terra
        case .secondary: return NemaraColor.line
        case .ghost:     return .clear
        case .danger:    return NemaraColor.terra
        }
    }
}

#Preview {
    VStack(spacing: 14) {
        NemaraButton("Primary action", action: {})
        NemaraButton("Brand CTA", variant: .terra, action: {})
        NemaraButton("Secondary", variant: .secondary, action: {})
        NemaraButton("Ghost", variant: .ghost, action: {})
        NemaraButton("Remove patient", variant: .danger, action: {})
        NemaraButton("Create an account", variant: .primary, size: .lg, block: true, action: {})
        HStack {
            NemaraButton("Edit", variant: .ghost, size: .sm, systemImage: "pencil", action: {})
            NemaraButton("Add a detector", variant: .secondary, size: .md, block: true, systemImage: "plus", action: {})
        }
    }
    .padding()
    .background(NemaraColor.paper)
}
