import SwiftUI

/// Bottom sheet for adding a new camera under a patient. A segmented
/// picker at the top toggles between the two device classes (both
/// branded "Memoria Sensor"):
///
///   Phone (existing flow):
///     A phone running the MemoriaSensor app. Caregiver types a room
///     name + icon, taps "Generate code", the sheet shows a 6-digit
///     pairing code with a live countdown. The wall phone enters the
///     code in the MemoriaSensor app and the placeholder cameras row
///     flips to online via Realtime.
///
///   Native (our purpose-built Raspberry-Pi hardware):
///     Mounts `SensorSetupWizard` — a linear 4-step flow that joins the
///     camera's setup Wi-Fi, opens the captive portal for home Wi-Fi
///     credentials, polls discovery until the camera appears, then
///     assigns it to a room and provisions it.
///
/// Replaces the prior alert-then-sheet pattern in PatientCamerasView.
struct AddCameraSheet: View {
    let patientId: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var tab: SourceTab = .phone

    enum SourceTab: String, CaseIterable, Identifiable {
        case phone, sensor
        var id: String { rawValue }
        var label: String {
            switch self {
            case .phone: "Phone"
            case .sensor: "Native"
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(NemaraColor.line)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Text("ADD A SENSOR").nemaraEyebrow()

            Picker("Sensor type", selection: $tab) {
                ForEach(SourceTab.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            Group {
                switch tab {
                case .phone:
                    PhoneCameraTab(patientId: patientId, onDone: { dismiss() })
                case .sensor:
                    SensorSetupWizard(patientId: patientId, onFinished: { dismiss() })
                }
            }

            Spacer(minLength: 0)
        }
        .background(NemaraColor.paper)
    }
}

// ─────────────────────────────────────────────────────────────
// Phone Camera tab.
//
// Two states: enter room → generate code → show code with countdown.
// The "show code" state survives until the caregiver dismisses the
// sheet; the placeholder cameras row appears immediately in the
// patient's cameras list (via the loadCameras call inside
// createPairingCode), and Realtime flips it online when the phone
// completes pairing.
// ─────────────────────────────────────────────────────────────

private struct PhoneCameraTab: View {
    let patientId: UUID
    let onDone: () -> Void

    @Environment(AppEnvironment.self) private var env

    @State private var room: String = ""
    @State private var icon: String = "tv"
    @State private var state: TabState = .composing
    @State private var clockTick: Int = 0

    enum TabState {
        case composing
        case generating
        case showing(code: String, expiresAt: Date)
        case error(String)
    }

    var body: some View {
        VStack(spacing: 16) {
            switch state {
            case .composing:
                composeForm
            case .generating:
                ProgressView().scaleEffect(1.4).tint(NemaraColor.ink2)
                    .frame(maxWidth: .infinity, minHeight: 200)
            case .showing(let code, let expiresAt):
                codeDisplay(code: code, expiresAt: expiresAt)
            case .error(let message):
                errorView(message)
            }
        }
        .padding(.horizontal, 16)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if case .showing = state { clockTick &+= 1 }
        }
    }

    private var composeForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            NemaraField(
                "Room",
                text: $room,
                placeholder: "e.g. Living room",
                autocapitalization: .words,
            )
            IconPicker(selection: $icon)
            NemaraButton(
                "Generate code",
                variant: .primary,
                size: .lg,
                block: true,
                systemImage: "qrcode",
            ) {
                Task { await generate() }
            }
            .disabled(room.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.top, 4)
            Text("Open the MemoriaSensor app on your wall phone and enter the code that appears.")
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink3)
                .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    private func codeDisplay(code: String, expiresAt: Date) -> some View {
        VStack(spacing: 14) {
            Text("for \(room)")
                .font(NemaraFont.title3)
                .foregroundStyle(NemaraColor.ink)
            Text(code)
                .font(NemaraFont.mono(size: 56, weight: .bold))
                .tracking(8)
                .foregroundStyle(NemaraColor.ink)
            Text(countdownText(expiresAt: expiresAt))
                .font(NemaraFont.title3)
                .foregroundStyle(NemaraColor.ink2)
            NemaraButton("Done", variant: .secondary, size: .lg, block: true) {
                onDone()
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 16)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(NemaraColor.terra)
            Text(message)
                .font(NemaraFont.body)
                .foregroundStyle(NemaraColor.ink2)
                .multilineTextAlignment(.center)
            NemaraButton("Try again", variant: .secondary, size: .md) {
                state = .composing
            }
        }
        .padding(.top, 24)
    }

    private func countdownText(expiresAt: Date) -> String {
        let _ = clockTick
        let remaining = max(0, Int(expiresAt.timeIntervalSinceNow))
        if remaining <= 0 { return "Code expired, close and try again." }
        let m = remaining / 60
        let s = remaining % 60
        return "Expires in \(m):\(String(format: "%02d", s))"
    }

    @MainActor
    private func generate() async {
        let trimmed = room.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        state = .generating
        do {
            let response = try await env.api.createPairingCode(
                forPatient: patientId, room: trimmed, iconName: icon,
            )
            state = .showing(code: response.pairingCode, expiresAt: response.expiresAt)
        } catch {
            state = .error(errorMessage(error))
        }
    }
}

// ─── shared subviews ────────────────────────────────────────────

private struct IconPicker: View {
    @Binding var selection: String

    private let options: [String] = [
        "tv",
        "fork.knife",
        "bed.double",
        "shower",
        "door.left.hand.open",
        "car",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Icon")
                .font(NemaraFont.bodySmallStrong)
                .foregroundStyle(NemaraColor.ink2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { name in
                        Button {
                            selection = name
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(
                                    selection == name
                                    ? NemaraColor.ink
                                    : NemaraColor.ink3
                                )
                                .frame(width: 52, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(
                                            selection == name
                                            ? NemaraColor.cardAlt
                                            : NemaraColor.paperDim
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(
                                            selection == name
                                            ? NemaraColor.ink2
                                            : Color.clear,
                                            lineWidth: 1.5,
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private func errorMessage(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}
