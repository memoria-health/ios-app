import SwiftUI

/// The code an installer types to attach a new sensor to this account.
///
/// Deliberately the same shape as `PairingCodeSheet` — same eyebrow,
/// same big monospaced digits, same countdown, same numbered steps —
/// because to a caregiver these are one idea: "read this number to the
/// person setting the thing up." The two differ only in what redeems the
/// code, which is not something they should have to know.
///
/// Why a code at all: binding a service used to take the caregiver's
/// EMAIL, which is on their invoice and in their signature. Anyone who
/// knew one could attach a sensor to that home. A five-minute code the
/// caregiver generates on demand is proof of the one thing an email
/// never was — that the person granting access is in the room.
struct SensorSetupCodeSheet: View {
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
            NemaraSheetHandle()

            VStack(spacing: 8) {
                Text("ADD A SENSOR").nemaraEyebrow()
                Text("Read this to your installer")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
            }

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
                    // Read aloud down a phone line as often as typed, so
                    // the digits are the one thing VoiceOver should say.
                    .accessibilityLabel(
                        code.map(String.init).joined(separator: " "))
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
                NemaraButton("Try again", variant: .secondary, size: .md) {
                    state = .loading
                    Task { await load() }
                }
            }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("1.", "Give this code to whoever is setting the sensor up.")
            label("2.", "They enter it once the camera is picked.")
            label("3.", "The sensor appears in this list, ready to assign.")
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
            let response = try await env.api.createSensorSetupCode()
            state = .ready(code: response.pairingCode,
                           expiresAt: response.expiresAt)
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }
}
