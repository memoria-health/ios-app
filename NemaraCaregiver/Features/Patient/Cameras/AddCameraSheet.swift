import SwiftUI

/// Bottom sheet for adding a new camera under a patient. A segmented
/// picker at the top toggles between the two device classes:
///
///   Phone Camera (existing flow):
///     Caregiver types a room name + icon, taps "Generate code",
///     the sheet shows a 6-digit pairing code with a live countdown.
///     The wall phone enters the code in the NemaraCam app and the
///     placeholder cameras row flips to online via Realtime.
///
///   Sensor Camera (new flow):
///     Polls GET /v1/cameras/discovered every 3 s, lists unclaimed
///     sensor cameras. Caregiver taps one, picks a room + icon,
///     taps "Pair". Backend marks the discovery claimed and creates
///     the cameras row in one shot (no two-step exchange because
///     the sensor camera has no UI to enter a code).
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
            case .sensor: "Sensor"
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(NemaraColor.line)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Text("ADD A CAMERA").nemaraEyebrow()

            Picker("Camera type", selection: $tab) {
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
                    SensorCameraTab(patientId: patientId, onDone: { dismiss() })
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
            Text("Open the Nemara camera app on your wall phone and enter the code that appears.")
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
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink3)
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

// ─────────────────────────────────────────────────────────────
// Sensor Camera tab.
//
// Two states: discovered list → assign-to-room form. Polling at 3 s
// matches the web app's cadence; the backend keeps discovery rows
// for up to 5 minutes after the last announcement, so a transient
// network blip on the sensor side does not make it vanish from the
// picker.
// ─────────────────────────────────────────────────────────────

private struct SensorCameraTab: View {
    let patientId: UUID
    let onDone: () -> Void

    @Environment(AppEnvironment.self) private var env

    @State private var discovered: [DiscoveredCamera] = []
    @State private var loadError: String?
    @State private var firstLoadComplete: Bool = false
    @State private var selected: DiscoveredCamera?
    @State private var showingSetupAssistant: Bool = false

    private let pollInterval: TimeInterval = 3.0

    var body: some View {
        Group {
            if let chosen = selected {
                AssignSensorForm(
                    patientId: patientId,
                    discovery: chosen,
                    onCancel: { selected = nil },
                    onPaired: { onDone() },
                )
            } else {
                discoveredList
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .task { await pollLoop() }
        .sheet(isPresented: $showingSetupAssistant) {
            SensorSetupAssistant()
        }
    }

    private var discoveredList: some View {
        VStack(alignment: .leading, spacing: 12) {
            setupHelp
            HStack {
                Text("AVAILABLE CAMERAS").nemaraEyebrow()
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(NemaraColor.action)
                        .frame(width: 6, height: 6)
                    Text("scanning")
                        .font(NemaraFont.monoSmall)
                        .foregroundStyle(NemaraColor.ink3)
                }
            }
            if let loadError {
                Text(loadError)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.terra)
            }
            if !firstLoadComplete {
                ProgressView().scaleEffect(1.0)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if discovered.isEmpty {
                Text("No cameras found yet. Follow the setup steps above.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink3)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                NemaraCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(discovered) { d in
                            Button {
                                selected = d
                            } label: {
                                discoveredRow(d)
                            }
                            .buttonStyle(.plain)
                            if d.id != discovered.last?.id {
                                NemaraColor.line.frame(height: 1)
                            }
                        }
                    }
                }
            }
            // Always-visible escape hatch: even when discoveries
            // exist, a new camera the caregiver just plugged in
            // would not be on home WiFi yet. Tapping here launches
            // the AP-mode assistant.
            NemaraButton(
                "Set up a new sensor camera",
                variant: .secondary,
                size: .md,
                block: true,
                systemImage: "wifi.router",
            ) {
                showingSetupAssistant = true
            }
            .padding(.top, 6)
        }
    }

    private var setupHelp: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                helpLine("1.", "Plug the camera in and wait about 30 seconds for it to power on.")
                helpLine("2.", "Tap \"Set up a new sensor camera\" below.")
                helpLine("3.", "Enter the 6-character code printed on the camera, then tap \"Connect to camera\". iOS will ask permission to join the camera's setup WiFi.")
                helpLine("4.", "The setup page opens automatically. Pick your home WiFi and enter the password.")
                helpLine("5.", "The camera joins your home WiFi and appears under Available cameras within about a minute.")
            }
            .padding(.top, 8)
        } label: {
            Text("Setting up a new sensor camera?")
                .font(NemaraFont.bodySmallStrong)
                .foregroundStyle(NemaraColor.ink)
        }
        .tint(NemaraColor.ink2)
        .padding(12)
        .background(NemaraColor.cardAlt)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func helpLine(_ index: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(index)
                .font(NemaraFont.bodySmallStrong)
                .foregroundStyle(NemaraColor.ink3)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func discoveredRow(_ d: DiscoveredCamera) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(NemaraColor.paperDim)
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink2)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.deviceLabel)
                    .font(NemaraFont.bodySmallStrong)
                    .foregroundStyle(NemaraColor.ink)
                Text("\(hostOf(d.currentUrl)) · \(relativeAge(d.lastSeenAt))")
                    .font(NemaraFont.monoSmall)
                    .foregroundStyle(NemaraColor.ink3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NemaraColor.ink3)
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    @MainActor
    private func pollLoop() async {
        // First poll fires immediately; subsequent polls fire every
        // `pollInterval`. The .task lifecycle cancels this when the
        // sheet is dismissed or the tab is switched.
        while !Task.isCancelled {
            await poll()
            firstLoadComplete = true
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    @MainActor
    private func poll() async {
        do {
            let list = try await env.api.listDiscoveredCameras()
            discovered = list
            loadError = nil
        } catch {
            loadError = errorMessage(error)
        }
    }
}

private struct AssignSensorForm: View {
    let patientId: UUID
    let discovery: DiscoveredCamera
    let onCancel: () -> Void
    let onPaired: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var room: String = ""
    @State private var icon: String = "tv"
    @State private var busy: Bool = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NemaraCard(padding: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PAIRING").nemaraEyebrow()
                    Text(discovery.deviceLabel)
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink)
                    Text(discovery.currentUrl)
                        .font(NemaraFont.monoSmall)
                        .foregroundStyle(NemaraColor.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            NemaraField(
                "Room",
                text: $room,
                placeholder: "e.g. Living room",
                autocapitalization: .words,
            )
            IconPicker(selection: $icon)
            if let error {
                Text(error)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.terra)
            }
            HStack(spacing: 10) {
                NemaraButton("Back", variant: .secondary, size: .md) {
                    onCancel()
                }
                NemaraButton(
                    busy ? "Pairing..." : "Pair camera",
                    variant: .primary,
                    size: .md,
                    block: true,
                ) {
                    Task { await pair() }
                }
                .disabled(busy || room.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 8)
    }

    @MainActor
    private func pair() async {
        let trimmed = room.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        busy = true
        error = nil
        do {
            _ = try await env.api.provisionSensorCamera(
                forPatient: patientId,
                room: trimmed,
                iconName: icon,
                discoveryId: discovery.discoveryId,
            )
            onPaired()
        } catch {
            self.error = errorMessage(error)
            busy = false
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

private func hostOf(_ url: String) -> String {
    URL(string: url)?.host ?? url
}

private func relativeAge(_ date: Date) -> String {
    let s = max(0, Int(-date.timeIntervalSinceNow))
    if s < 60 { return "seen \(s)s ago" }
    let m = s / 60
    if m < 60 { return "seen \(m)m ago" }
    return "seen \(m / 60)h ago"
}
