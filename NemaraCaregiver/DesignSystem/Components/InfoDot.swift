import SwiftUI

/// The house pattern for explanatory text: an ⓘ that reveals a SHORT
/// popover instead of a permanent caption. Screens stay clean; the
/// explanation is one tap away for whoever wants it.
struct InfoDot: View {
    let text: String
    @State private var open = false

    init(_ text: String) { self.text = text }

    var body: some View {
        Button { open = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(NemaraColor.ink4)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .top) {
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(NemaraColor.ink2)
                .padding(14)
                .frame(maxWidth: 280)
                .presentationCompactAdaptation(.popover)
        }
    }
}
