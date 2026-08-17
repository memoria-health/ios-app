import SwiftUI

/// Patient-wide audio capture toggle — the facilities audio kill.
/// Mirrors `PeopleBlurCard`'s layout, but PATCHes the server
/// (`audio_capture_enabled`) instead of a local preference: when off,
/// the camera publishers never publish an audio track (severed at the
/// source — no live sound, no audio in clips, no speech alerts;
/// listening detectors fall back to visual-only). The flip reaches
/// gateway cameras within seconds via the roster long-poll. Care
/// facilities where audio recording is not permitted keep this OFF.
struct AudioCaptureCard: View {
    @Environment(AppEnvironment.self) private var env
    let patientId: UUID

    @State private var busy = false
    @State private var errorText: String?

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }

    private var enabled: Bool { patient?.audioCaptureEnabled ?? true }

    var body: some View {
        NemaraCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(enabled ? NemaraColor.actionSoft : NemaraColor.paperDim)
                    Image(systemName: enabled ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(enabled ? NemaraColor.action : NemaraColor.ink3)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {

                        Text("Audio capture")

                            .font(NemaraFont.bodySemibold)

                            .foregroundStyle(NemaraColor.ink)

                        InfoDot("Cameras capture sound for live audio, clips, and speech alerts. Turn off to stop all sound capture.")

                    }
                    if let errorText {
                        Text(errorText)
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.terra)
                    }
                }
                Spacer()
                NemaraToggle(isOn: Binding(
                    get: { enabled },
                    set: { flip(to: $0) }
                ), track: "audio_capture.toggle")
                .disabled(busy)
            }
        }
        .padding(.horizontal, 16)
    }

    private func flip(to newValue: Bool) {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            defer { busy = false }
            do {
                var body = UpdatePatientRequest()
                body.audioCaptureEnabled = newValue
                _ = try await env.api.updatePatient(patientId, body)
            } catch {
                errorText = "Couldn't update audio setting. Try again."
            }
        }
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return AudioCaptureCard(patientId: env.api.patients[0].id)
        .environment(env)
        .padding(.vertical)
        .background(NemaraColor.paper)
}
#endif
