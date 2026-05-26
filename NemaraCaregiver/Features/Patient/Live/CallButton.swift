import SwiftUI

/// Phone-call button overlaid on the live camera tile in
/// `PatientLiveView`. Three visual states: idle (green, tap to start),
/// connecting (spinner, disabled), active (red, tap to end).
///
/// LiveKit-agnostic — the parent view owns the call lifecycle and
/// passes in the resolved state + tap closure. Keeps this component
/// composable for future surfaces (e.g. event-detail-view call back).
struct CallButton: View {
    enum State: Equatable {
        case idle
        case connecting
        case active
    }

    let state: State
    let onTap: () -> Void

    private let size: CGFloat = 64

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(background)
                    .shadow(color: NemaraColor.ink.opacity(0.25), radius: 8, x: 0, y: 4)

                switch state {
                case .idle:
                    Image(systemName: "phone.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(NemaraColor.terraInk)
                case .connecting:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(NemaraColor.terraInk)
                case .active:
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            // Subtle pulse while live — telegraphs "this is hot" so
            // the caregiver never wonders whether the mic is open.
            .scaleEffect(state == .active ? 1.0 : 1.0)
            .modifier(_ActiveCallPulse(active: state == .active))
        }
        .buttonStyle(.plain)
        .disabled(state == .connecting)
        .accessibilityLabel(accessibilityLabel)
    }

    private var background: Color {
        switch state {
        case .idle: return NemaraColor.action
        case .connecting: return NemaraColor.ink2
        case .active: return Color(.systemRed)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Start call"
        case .connecting: return "Connecting"
        case .active: return "End call"
        }
    }
}

/// 1.06× scale ping every ~1.4s while a call is active. Cheap visual
/// reassurance the mic is hot; ignored entirely when idle.
private struct _ActiveCallPulse: ViewModifier {
    let active: Bool
    @State private var on: Bool = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && on ? 1.06 : 1.0)
            .animation(
                active
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .default,
                value: on,
            )
            .onAppear { if active { on = true } }
            .onChange(of: active) { _, isActive in
                on = isActive
            }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 20) {
        CallButton(state: .idle, onTap: {})
        CallButton(state: .connecting, onTap: {})
        CallButton(state: .active, onTap: {})
    }
    .padding()
    .background(NemaraColor.ink)
}
#endif
