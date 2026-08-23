import SwiftUI

/// Bottom sheet for adding a sensor, reached from the patient's Live view.
/// Two device classes, and the split is about WHO does the setup:
///
///   Spare phone:
///     A phone running the MemoriaSensor app. Caregiver types a room
///     name + icon, taps "Generate code", the sheet shows a 6-digit
///     pairing code with a live countdown. The wall phone enters it and
///     the placeholder cameras row flips online via Realtime. Bound to
///     the ACCOUNT like everything else since 2026-08-23; naming a
///     resident is coverage, and optional.
///
///   Memoria Sensor:
///     Our own hardware, and anything an installer puts in (gateway
///     camera, hosted bridge). Also a 6-digit code, but it binds to the
///     ACCOUNT, so the sensor arrives unassigned and streaming and is
///     given its residents afterwards in Sensors. One flow for every
///     installed sensor, whatever the vendor.
///
/// The Raspberry-Pi wizard that used to live in the second tab is gone
/// (2026-08-23). Its backend (pi_discovery and pi-provision) was deleted
/// with the Pi path, so every step of it 404'd. It was a live button
/// wired to nothing.
struct AddCameraSheet: View {
    /// Nil when opened from the account roster, where no patient is in
    /// context. Neither tab needs one: a phone paired with no resident
    /// named arrives unassigned, exactly like an installed sensor, and
    /// is given coverage in Sensors.
    let patientId: UUID?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var tab: SourceTab = .phone

    enum SourceTab: String, CaseIterable, Identifiable {
        case phone, sensor
        var id: String { rawValue }
        var label: String {
            switch self {
            case .phone: "Spare phone"
            case .sensor: "Memoria Sensor"
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            NemaraSheetHandle()

            Text("ADD A SENSOR").nemaraEyebrow()

            // Hand-styled rather than `.pickerStyle(.segmented)`: the
            // system control brings its own greys, font and corner radius
            // and cannot be told to use ours, so it read as a piece of
            // iOS dropped into a Memoria sheet.
            HStack(spacing: 6) {
                ForEach(SourceTab.allCases) { t in
                    Button { tab = t } label: {
                        Text(t.label)
                            .font(NemaraFont.bodySmallStrong)
                            .foregroundStyle(tab == t ? NemaraColor.actionInk : NemaraColor.ink2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: NemaraRadius.sm)
                                    .fill(tab == t ? NemaraColor.action : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == t ? [.isSelected] : [])
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: NemaraRadius.md)
                    .fill(NemaraColor.paperDim)
            )
            .padding(.horizontal, 20)

            Group {
                switch tab {
                case .phone:
                    PhoneCameraTab(patientId: patientId, onDone: { dismiss() })
                case .sensor:
                    InstalledSensorTab()
                        .trackScreen("sensor_setup")
                }
            }

            Spacer(minLength: 0)
        }
        .background(NemaraColor.paper)
        // Welcome-tour host: this sheet renders above the patient shell, so
        // the generate-code / pairing steps need their own layer here.
        .tutorialOverlay(.addCameraSheet)
    }
}

// ─────────────────────────────────────────────────────────────
// Memoria Sensor tab.
//
// Deliberately thin: it hands out a code and says what happens next.
// It takes no patientId because an installed sensor belongs to the
// ACCOUNT. Binding it to whoever's screen you happen to be on is the
// exact assumption this migration removed. Coverage is chosen later,
// in Sensors, where one sensor can watch several residents.
// ─────────────────────────────────────────────────────────────

private struct InstalledSensorTab: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingCode = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "shippingbox")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(NemaraColor.ink3)
                .padding(.top, 14)

            Text("Your installer sets these up")
                .font(NemaraFont.title2)
                .foregroundStyle(NemaraColor.ink)
                .multilineTextAlignment(.center)

            Text("Give them a setup code. The sensor starts streaming right away, and you choose who it watches in Sensors.")
                .font(NemaraFont.body)
                .foregroundStyle(NemaraColor.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            NemaraButton("Get a setup code", variant: .primary, size: .lg) {
                showingCode = true
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingCode) {
            SensorSetupCodeSheet()
                .environment(env)
                .presentationDetents([.medium, .large])
                .trackScreen("sensor_setup_code")
        }
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
    /// Nil from the sensor roster. Coverage, not identity: a phone with
    /// no resident named arrives unassigned and is given one in Sensors.
    let patientId: UUID?
    let onDone: () -> Void

    @Environment(AppEnvironment.self) private var env

    @State private var room: String = ""
    @State private var icon: String = "tv"
    @State private var state: TabState = .composing
    @State private var clockTick: Int = 0
    /// The placeholder camera created by the just-generated pairing code.
    /// Watched so the sheet can auto-dismiss the moment THIS camera pairs.
    @State private var generatedCameraId: UUID?

    /// Welcome-tour debounce: true once the room name has sat unchanged
    /// (and non-empty) for 1s — the "done typing" signal that moves the
    /// tour's ring onto Generate code. A length threshold rang mid-word
    /// for longer room names. Tour-only plumbing; no behavior.
    @State private var roomSettled = false
    @State private var roomSettleTask: Task<Void, Never>?

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
        // Welcome-tour debounce: each keystroke resets the 1s settle timer;
        // when the room name rests non-empty for a second, the marker below
        // reports and the tour rings Generate code.
        .onChange(of: room) { _, newValue in
            roomSettled = false
            roomSettleTask?.cancel()
            guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            roomSettleTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !Task.isCancelled { roomSettled = true }
            }
        }
        // Auto-dismiss the moment the wall phone finishes pairing. The
        // placeholder camera created by our pairing code flips `paired` true
        // via Supabase Realtime; when it does, close the sheet so the
        // caregiver doesn't have to tap "Done". Scoped to OUR camera id, so an
        // unrelated camera's update can never dismiss this sheet.
        // Only watchable when a resident is named. From the roster the
        // phone has no patient list to appear in, so the sheet closes on
        // the caregiver's Done instead of auto-dismissing.
        .onChange(of: patientId.flatMap { env.api.camerasByPatient[$0] }) { _, cameras in
            guard let id = generatedCameraId,
                  let cam = cameras?.first(where: { $0.id == id }),
                  cam.paired
            else { return }
            onDone()
        }
    }

    private var composeForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "Which one do I pick?" hint. Phone = a spare iPhone running the
            // Memoria Sensor app; the dedicated-hardware option lives on the
            // other tab. Plain sibling row (no .tutorialTarget) so the welcome
            // tour's spotlight — which keys off the Room field / Generate code
            // frames — is unaffected; the form just sits a row lower.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "iphone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NemaraColor.terra)
                Text("Use this to pair a spare iPhone that has the Memoria Sensor app installed.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NemaraColor.terraSoft)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))

            NemaraField(
                "Room",
                text: $room,
                placeholder: "e.g. Living room",
                autocapitalization: .words,
            )
            // Welcome-tour marker: the field stays spotlit while empty AND
            // while typing; the 1s settle (roomSettled) hands the ring off
            // to Generate code. Clearing the text brings it back here.
            .tutorialTarget(roomSettled ? nil : .roomField)
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
            // Welcome-tour marker, reported once the room name has settled
            // (1s without typing, non-empty — see the debounce above) so the
            // gray-out never slams in mid-word regardless of name length.
            .tutorialTarget(roomSettled ? .generateCode : nil)
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
            // Welcome-tour marker: when the tour moves on while this code
            // sheet is still up ("I'll pair this later"), it spotlights
            // Done to walk the user out of the sheet. Frame only.
            .tutorialTarget(.sheetDone)
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
        // Room names must be unique per patient: duplicates make every
        // name-scoped feature ambiguous (wandering rooms, the Home report,
        // the info panel all key on the name).
        let known = patientId.flatMap { env.api.camerasByPatient[$0] } ?? []
        let taken = known
            .contains { !$0.disabled && $0.room.compare(trimmed, options: .caseInsensitive) == .orderedSame }
        if taken {
            state = .error("A sensor named “\(trimmed)” already exists. Pick a different name.")
            return
        }
        state = .generating
        do {
            let response = try await env.api.createPairingCode(
                room: trimmed, iconName: icon,
                patientIds: patientId.map { [$0] } ?? [],
            )
            generatedCameraId = response.cameraId
            // Welcome-tour: let the tour's keypad illustration show this
            // real code. Fire-and-forget annotation; no behavior.
            TutorialManager.shared.notePairingCode(response.pairingCode)
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
