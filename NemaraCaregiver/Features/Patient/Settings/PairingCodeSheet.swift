import SwiftUI

/// Bottom sheet shown when the caregiver wants a 6-digit pairing
/// code. Two modes, selected by `Source`:
///
///   - `.create` — first-time pairing flow, called from the "Pair a
///     new phone" button. Inserts a new `cameras` row with the code.
///   - `.regenerate` — re-mint flow on an EXISTING unpaired camera,
///     called from CameraDetailView's "Show pairing code" button when
///     the user dismissed the original sheet without entering the
///     code on a wall phone.
///
/// Both modes return the same `CreatePairingCodeResponse` shape and
/// render the same UI; only the loader differs.
struct PairingCodeSheet: View {
    /// Which API path to hit when the sheet appears.
    enum Source {
        case create(patientId: UUID, iconName: String)
        case regenerate(cameraId: UUID)
    }

    let source: Source
    let room: String

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var state: SheetState = .loading
    @State private var clockTick: Int = 0   // forces countdown text to refresh

    enum SheetState {
        case loading
        case ready(code: String, expiresAt: Date)
        case error(String)
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(NemaraColor.line)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("PAIR A NEW PHONE").nemaraEyebrow()
                Text("for \(room)")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
            }
            .padding(.top, 8)

            Spacer(minLength: 12)

            content
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

            Spacer(minLength: 12)

            instructions

            NemaraButton("Close", variant: .secondary, size: .lg, block: true) {
                dismiss()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(NemaraColor.paper)
        .task { await load() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            clockTick &+= 1
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .scaleEffect(1.4)
                .tint(NemaraColor.ink2)

        case .ready(let code, let expiresAt):
            VStack(spacing: 10) {
                Text(code)
                    .font(NemaraFont.mono(size: 56, weight: .bold))
                    .tracking(8)
                    .foregroundStyle(NemaraColor.ink)
                    .padding(.horizontal, 16)
                Text(countdownText(expiresAt: expiresAt))
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }

        case .error(let message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(NemaraColor.terra)
                Text(message)
                    .font(NemaraFont.body)
                    .foregroundStyle(NemaraColor.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("1.", "Open MemoriaSensor on the wall phone.")
            label("2.", "Enter the code above when prompted.")
            label("3.", "The camera will appear here once it's paired.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private func label(_ index: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(index)
                .font(NemaraFont.bodySmallStrong)
                .foregroundStyle(NemaraColor.ink3)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
        }
    }

    private func countdownText(expiresAt: Date) -> String {
        let _ = clockTick   // dependency for re-render
        let remaining = max(0, Int(expiresAt.timeIntervalSinceNow))
        if remaining <= 0 {
            return "Code expired — close and try again."
        }
        let m = remaining / 60
        let s = remaining % 60
        return "Expires in \(m):\(String(format: "%02d", s))"
    }

    @MainActor
    private func load() async {
        do {
            let response: CreatePairingCodeResponse
            switch source {
            case .create(let patientId, let iconName):
                response = try await env.api.createPairingCode(
                    forPatient: patientId, room: room, iconName: iconName,
                )
            case .regenerate(let cameraId):
                response = try await env.api.regeneratePairingCode(forCamera: cameraId)
            }
            state = .ready(code: response.pairingCode, expiresAt: response.expiresAt)
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }
}
