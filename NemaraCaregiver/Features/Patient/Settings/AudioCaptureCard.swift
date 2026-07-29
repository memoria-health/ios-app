import SwiftUI

/// Patient-wide audio capture toggle — the facilities audio kill.
/// PATCHes `audio_capture_enabled`; when off, the camera publishers
/// never publish an audio track (severed at the source: no live sound,
/// no audio in clips, no speech alerts — listening detectors fall back
/// to visual-only). The flip reaches gateway cameras within seconds via
/// the roster long-poll. Care facilities where audio recording is not
/// permitted must keep this OFF for every resident.
struct AudioCaptureCard: View {
    @Environment(AppEnvironment.self) private var env
    let patientId: UUID

    @State private var busy = false
    @State private var errorText: String?

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { patient?.audioCaptureEnabled ?? true },
                set: { flip(to: $0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio capture")
                        .font(NemaraFont.body)
                        .foregroundStyle(NemaraColor.ink)
                    Text(
                        (patient?.audioCaptureEnabled ?? true)
                            ? "Cameras capture sound for clips and speech alerts."
                            : "No sound is captured, recorded, or analyzed."
                    )
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                }
            }
            .disabled(busy)
            if let errorText {
                Text(errorText)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.terra)
            }
        }
        .padding(16)
        .background(NemaraColor.card, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func flip(to enabled: Bool) {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            defer { busy = false }
            do {
                var body = UpdatePatientRequest()
                body.audioCaptureEnabled = enabled
                _ = try await env.api.updatePatient(patientId, body)
            } catch {
                errorText = "Couldn't update audio setting. Try again."
            }
        }
    }
}
