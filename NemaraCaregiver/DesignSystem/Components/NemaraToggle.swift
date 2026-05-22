import SwiftUI

/// Warm-black on/off pill. Slightly tighter than iOS's stock `Toggle`
/// (40 × 24) and uses the Nemara action color rather than the system
/// green. Pure presentation — wire a binding through `isOn`.
struct NemaraToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(isOn ? NemaraColor.action : NemaraColor.line)
                    .frame(width: 40, height: 24)
                Circle()
                    .fill(NemaraColor.card)
                    .frame(width: 20, height: 20)
                    .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
                    .offset(x: isOn ? 8 : -8)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct Demo: View {
        @State private var a = true
        @State private var b = false
        var body: some View {
            VStack(spacing: 16) {
                NemaraToggle(isOn: $a)
                NemaraToggle(isOn: $b)
            }
            .padding()
            .background(NemaraColor.paper)
        }
    }
    return Demo()
}
