import NetworkExtension
import SwiftUI

/// Linear 3-step wizard for bringing a new "Native" Memoria Sensor
/// (our purpose-built Raspberry-Pi hardware) onto the home network and
/// pairing it to a patient.
///
///   1. setUp     — plug-in instructions + 6-char setup code, then
///                  "Join sensor Wi-Fi" runs the NEHotspot join to
///                  "Memoria-Setup-<CODE>". On success → step 2.
///   2. joining   — iOS presents its OWN captive portal for home-Wi-Fi
///                  entry (we do NOT open an in-app Safari — that stacked
///                  a duplicate pop-up). Meanwhile a 3 s discovery poll
///                  runs: first freshly seen sensor → step 3; if more than
///                  one appears the caregiver picks. ~120 s budget, with a
///                  "Go back" to restart. Single source of the join+poll.
///   3. configured — AssignSensorForm (room/icon → pi-provision), then a
///                  "Done" confirmation that dismisses.
///
/// Presented as a sheet, so there's no Cancel button — swipe down to
/// dismiss.
///
/// Requires the Hotspot Configuration entitlement
/// (`com.apple.developer.networking.HotspotConfiguration`) and the
/// NSLocalNetworkUsageDescription Info.plist key (both already present
/// in NemaraCaregiver). If the entitlement is missing, `apply` returns a
/// localized error and the wizard falls back to manual Settings > Wi-Fi
/// instructions on step 1.
struct SensorSetupWizard: View {
    let patientId: UUID
    /// Called after a successful provision + "Done" tap so the parent
    /// add-camera sheet can dismiss back to PatientCamerasView.
    let onFinished: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    enum Step: Int { case setUp, joining, configured }
    @State private var step: Step = .setUp

    // ── Step 1: join state ───────────────────────────────────────
    @State private var code: String = ""
    @State private var joinState: JoinState = .idle
    enum JoinState: Equatable {
        case idle
        case joining
        case error(String)
    }

    // ── Step 2: discovery poll ───────────────────────────────────
    @State private var discovered: [DiscoveredCamera] = []
    @State private var discoveryError: String?
    @State private var elapsedSeconds: Int = 0
    @State private var selected: DiscoveredCamera?

    private static let _ssidPrefix = "Memoria-Setup"
    private let pollInterval: TimeInterval = 3.0
    private let discoveryBudgetSeconds: Int = 120

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stepHeader
                    switch step {
                    case .setUp:      setUpCameraStep
                    case .joining:    joiningStep
                    case .configured: configuredStep
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NemaraColor.paper)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            // No Cancel button — this is a sheet, so a swipe-down dismisses
            // it. The configured step finishes via AssignSensorForm's own
            // action.
            //
            // We deliberately do NOT open an in-app Safari for the captive
            // portal: joining the sensor's open Wi-Fi makes iOS present its
            // OWN captive-portal page automatically, so opening a second
            // in-app one just stacked a duplicate ("two pop-ups"). We rely
            // on the system page for Wi-Fi entry and poll for the sensor
            // once it joins the home network.
        }
    }

    private var navTitle: String {
        switch step {
        case .setUp:      return "Set up Memoria Sensor"
        case .joining:    return "Joining network"
        case .configured: return "Almost done"
        }
    }

    // ── Header (step indicator) ──────────────────────────────────

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STEP \(step.rawValue + 1) OF 3").nemaraEyebrow()
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i <= step.rawValue ? NemaraColor.terra : NemaraColor.line)
                        .frame(height: 4)
                }
            }
        }
        .padding(.top, 4)
    }

    // ─────────────────────────────────────────────────────────────
    // Step 1 — Set up your Memoria Sensor
    // ─────────────────────────────────────────────────────────────

    private var setUpCameraStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up your Memoria Sensor")
                .font(NemaraFont.title3)
                .foregroundStyle(NemaraColor.ink)

            VStack(alignment: .leading, spacing: 8) {
                helpLine("1.", "Plug the Memoria Sensor in and wait about 30 seconds for it to power on and broadcast its setup Wi-Fi.")
                helpLine("2.", "Enter the 6-character setup code printed on the device, then tap \"Join sensor Wi-Fi.\"")
                helpLine("3.", "iOS will ask permission to join the sensor's setup Wi-Fi. Tap Allow.")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Setup code")
                    .font(NemaraFont.bodySmallStrong)
                    .foregroundStyle(NemaraColor.ink2)
                Text("The 6-character code printed on the Memoria Sensor, e.g. A4B7C2.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
            .padding(.top, 4)

            TextField("A4B7C2", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .font(NemaraFont.mono(size: 22, weight: .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(NemaraColor.paperDim)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .submitLabel(.done)
                .onSubmit { Self.resignFirstResponder() }

            if case .joining = joinState {
                HStack(spacing: 10) {
                    ProgressView().tint(NemaraColor.ink2)
                    Text("Joining the sensor's setup network…")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink3)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                NemaraButton(
                    "Join sensor Wi-Fi",
                    variant: .primary,
                    size: .lg,
                    block: true,
                    systemImage: "wifi",
                ) {
                    Task { await join() }
                }
                .disabled(_normalizedCode().count != 6)
            }

            if case .error(let message) = joinState {
                joinErrorView(message: message)
            }
        }
    }

    private func joinErrorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(NemaraColor.terra)
                Text("Couldn't join the setup Wi-Fi")
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
            }
            Text(message)
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect manually")
                    .font(NemaraFont.bodySmallStrong)
                    .foregroundStyle(NemaraColor.ink)
                Text("If the auto-join is not working, you can connect manually:")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink2)
                helpLine("1.", "Open Settings, tap Wi-Fi.")
                helpLine("2.", "Connect to \"\(_predictedSsid())\".")
                helpLine("3.", "A setup page opens automatically — pick your home Wi-Fi, then come back and tap Continue.")
            }
            .padding(.top, 4)
            HStack(spacing: 10) {
                NemaraButton("Try again", variant: .secondary, size: .md) {
                    joinState = .idle
                }
                NemaraButton("Continue", variant: .primary, size: .md, block: true) {
                    step = .joining
                }
            }
        }
        .padding(.top, 4)
    }

    // ─────────────────────────────────────────────────────────────
    // Step 2 — Sensor is joining your network (discovery poll)
    // ─────────────────────────────────────────────────────────────

    private var joiningStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sensor is joining your network")
                .font(NemaraFont.title3)
                .foregroundStyle(NemaraColor.ink)
            Text("Pick your home Wi-Fi in the setup page that opened and enter the password. We'll detect the sensor as soon as it connects.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if discovered.count > 1 {
                // Ambiguous: more than one freshly seen camera. Let the
                // caregiver pick rather than guessing.
                Text("More than one sensor is announcing. Pick the one you just set up.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                NemaraCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(discovered) { d in
                            Button {
                                selected = d
                                step = .configured
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
            } else {
                VStack(spacing: 14) {
                    ProgressView().scaleEffect(1.4).tint(NemaraColor.ink2)
                    Text("This can take up to a minute while the sensor joins your Wi-Fi.")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }

            if let discoveryError {
                Text(discoveryError)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.terra)
            }

            if elapsedSeconds >= discoveryBudgetSeconds {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Still waiting for the sensor")
                        .font(NemaraFont.bodySmallStrong)
                        .foregroundStyle(NemaraColor.ink)
                    Text("It can take a little longer on a busy network. Make sure you picked your home Wi-Fi and entered the password correctly.")
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }

            // Always-available way back to the start (re-enter the code +
            // rejoin the sensor's Wi-Fi) if setup didn't take.
            NemaraButton("Go back", variant: .secondary, size: .md) {
                resetToStart()
            }
            .padding(.top, 4)
        }
        .task(id: step == .joining) {
            // Only the active joining step drives the poll loop; the
            // .task is cancelled when the step changes or the wizard
            // dismisses.
            guard step == .joining else { return }
            await pollLoop()
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
                Text(hostOf(d.currentUrl))
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

    // ─────────────────────────────────────────────────────────────
    // Step 4 — Memoria Sensor configured
    // ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private var configuredStep: some View {
        if let chosen = selected {
            AssignSensorForm(
                patientId: patientId,
                discovery: chosen,
                onFinished: { onFinished() },
            )
        } else {
            // Shouldn't happen (we only enter step 4 with a selection),
            // but guard so the wizard never wedges on an empty screen.
            VStack(alignment: .leading, spacing: 12) {
                Text("Sensor not found")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
                Text("We lost track of the sensor. Let's try again.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                NemaraButton("Start over", variant: .secondary, size: .md) {
                    resetToStart()
                }
            }
        }
    }

    // ── Shared subviews ──────────────────────────────────────────

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

    // ── Step 1 join logic (moved from SensorSetupAssistant) ──────

    private func _normalizedCode() -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private func _predictedSsid() -> String {
        let n = _normalizedCode()
        return n.isEmpty ? "\(Self._ssidPrefix)-XXXXXX" : "\(Self._ssidPrefix)-\(n)"
    }

    @MainActor
    private func join() async {
        let ssid = _predictedSsid()
        joinState = .joining
        let config = NEHotspotConfiguration(ssid: ssid)
        // joinOnce=true means iOS will not auto-rejoin this open
        // network on future scans; the AP is short-lived anyway and
        // we do not want it competing with the home Wi-Fi.
        config.joinOnce = true
        do {
            try await NEHotspotConfigurationManager.shared.apply(config)
            // .apply succeeds when the user accepts the system prompt AND
            // the phone actually joins. iOS then presents its own captive
            // portal for Wi-Fi entry; we advance to the joining/discovery
            // step and poll for the sensor.
            joinState = .idle
            step = .joining
        } catch let error as NEHotspotConfigurationError {
            // .alreadyAssociated is success: phone is already on the AP
            // from a prior attempt.
            if error == .alreadyAssociated {
                joinState = .idle
                step = .joining
                return
            }
            // .userDenied means the caregiver tapped Cancel on the
            // system prompt; return to idle silently.
            if error == .userDenied {
                joinState = .idle
                return
            }
            joinState = .error(Self.describe(error))
        } catch {
            joinState = .error(error.localizedDescription)
        }
    }

    private static func describe(_ error: NEHotspotConfigurationError) -> String {
        switch error {
        case .invalid:                  return "The setup network configuration was invalid."
        case .invalidSSID:              return "The setup network name is not valid."
        case .invalidWPAPassphrase:     return "The setup network password is not valid."
        case .invalidWEPPassphrase:     return "The setup network password is not valid."
        case .invalidEAPSettings:       return "The setup network's authentication settings are not valid."
        case .invalidHS20Settings:      return "The setup network's Hotspot 2.0 settings are not valid."
        case .invalidHS20DomainName:    return "The setup network's domain name is not valid."
        case .userDenied:               return "The setup network join was canceled."
        case .internal:                 return "iOS could not start the network join."
        case .pending:                  return "Another network join is already in progress."
        case .systemConfiguration:      return "iOS rejected the network configuration."
        case .unknown:                  return "An unknown error occurred while joining the setup network."
        case .joinOnceNotSupported:     return "One-time joins are not supported on this device."
        case .alreadyAssociated:        return "Already connected to the setup network."
        case .applicationIsNotInForeground: return "The app must be in the foreground to join a network."
        @unknown default:               return "Could not join the setup network."
        }
    }

    // ── Step 3 discovery poll (moved from SensorCameraTab) ───────

    @MainActor
    private func pollLoop() async {
        // First poll fires immediately; subsequent polls fire every
        // `pollInterval`. The .task lifecycle cancels this when the step
        // changes or the wizard dismisses.
        elapsedSeconds = 0
        while !Task.isCancelled && step == .joining {
            await poll()
            // A single freshly seen camera auto-advances; ambiguity
            // (>1) waits for the caregiver to pick on this screen.
            if discovered.count == 1, let only = discovered.first {
                selected = only
                step = .configured
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            elapsedSeconds += Int(pollInterval)
        }
    }

    @MainActor
    private func poll() async {
        do {
            discovered = try await env.api.listDiscoveredCameras()
            discoveryError = nil
        } catch {
            discoveryError = errorMessage(error)
        }
    }

    private func resetToStart() {
        selected = nil
        discovered = []
        discoveryError = nil
        elapsedSeconds = 0
        joinState = .idle
        code = ""
        step = .setUp
    }
}

// ─────────────────────────────────────────────────────────────
// Final step: assign the discovered camera to a room + icon and
// provision it. Moved here from AddCameraSheet so the wizard owns the
// whole Native flow end-to-end. The action button reads as completion
// ("Finish"); on success we show a confirmation with a "Done" button
// that dismisses the wizard.
// ─────────────────────────────────────────────────────────────

private struct AssignSensorForm: View {
    let patientId: UUID
    let discovery: DiscoveredCamera
    let onFinished: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var room: String = ""
    @State private var icon: String = "tv"
    @State private var busy: Bool = false
    @State private var error: String?
    @State private var provisioned: Bool = false

    var body: some View {
        if provisioned {
            confirmation
        } else {
            form
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Memoria Sensor configured")
                .font(NemaraFont.title3)
                .foregroundStyle(NemaraColor.ink)
            Text("Give it a room name so you can find it in the sensors list.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
            NemaraCard(padding: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SENSOR").nemaraEyebrow()
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
            NemaraButton(
                busy ? "Finishing…" : "Finish",
                variant: .primary,
                size: .lg,
                block: true,
            ) {
                Task { await provision() }
            }
            .disabled(busy || room.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(NemaraColor.success)
                Text("Memoria Sensor added")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
            }
            Text("\(room.trimmingCharacters(in: .whitespaces)) is now paired. It will come online shortly.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            NemaraButton("Done", variant: .primary, size: .lg, block: true) {
                onFinished()
            }
            .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    @MainActor
    private func provision() async {
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
            // provisionSensorCamera already refreshes the patient's
            // camera list; the new row shows as online=false until the
            // Pi opens its outbound stream (hence "online shortly").
            busy = false
            provisioned = true
        } catch {
            self.error = errorMessage(error)
            busy = false
        }
    }
}

// ─────────────────────────────────────────────────────────────
// Room/icon picker, shared with the phone-camera compose form.
// (Mirrors AddCameraSheet's private IconPicker; kept here so the
// wizard is self-contained.)
// ─────────────────────────────────────────────────────────────

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
