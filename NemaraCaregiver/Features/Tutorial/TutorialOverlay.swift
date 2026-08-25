import SwiftUI
import UIKit

// ─────────────────────────────────────────────────────────────────────
// In-app welcome tour — spotlight coach-marks, click-by-click.
//
// EVERY tap in the setup flow gets its own red-box guidance: the screen
// grays out except a pulsing cutout over the REAL control to tap next
// (name field → date of birth → Add patient → … → Generate code). The
// user performs the actual action; the tour advances off the resulting
// app state — never by simulating anything.
//
// PHASES VIA CONDITIONAL MARKERS: controls report their frame ONLY when
// they're the next thing to tap (e.g. the name field reports while
// empty; the DOB button reports once a name exists; Add patient reports
// once the form is valid). Each step holds a target PRIORITY list and
// rings the first reported frame — so filling the form walks the ring
// from field to field automatically, with zero logic changes.
//
// FRAME PLUMBING — global frames, not anchor preferences: preferences
// don't reliably escape TabView / NavigationStack (UIKit-backed). Each
// marker reports its GLOBAL frame straight to the manager; each overlay
// host converts global → its own space.
//
// DESIGN CONTRACT — additive only, no behavior changes:
//   • `.tutorialTarget(_:)` only reports a frame. Zero behavior.
//   • Each presentation layer (root tabs, patient cover, the sheets,
//     the post-create enrollment cover) hosts the overlay; only the
//     topmost visible layer renders the current step.
//   • STRICT MODE: no Next button. Forward = tap the spotlighted
//     control / complete the prompted action. "Skip tour" (cancels the
//     tour) is the one exit, so it can never trap anyone. Free-choice
//     screens (detector toggles, face consent) ring without blocking.
//   • Auto-starts once (flag set at sign-up); Settings → "Replay the
//     welcome tour" restarts on demand.
// ─────────────────────────────────────────────────────────────────────

// MARK: - Persistence

enum TutorialFlags {
    static let eligibleKey = "tutorial.eligible"
    static let doneKey = "tutorial.done"
    static let stepKey = "tutorial.step"
    static let skippedPairingKey = "tutorial.skippedPairing"

    /// Called from the sign-up path when a brand-new account is
    /// provisioned. Sign-in / session-restore never set this.
    nonisolated static func markNewAccount() {
        // A brand-new account always gets the tour, regardless of prior
        // device history. UserDefaults is per-DEVICE, so a `done` flag left
        // true by an earlier account/test run would otherwise suppress it —
        // reset to a clean slate (clear done, reset to the welcome step).
        let d = UserDefaults.standard
        d.set(true, forKey: eligibleKey)
        d.set(false, forKey: doneKey)
        d.set(0, forKey: stepKey)   // TutorialStep.welcome.rawValue
        d.set(false, forKey: skippedPairingKey)
    }
}

// MARK: - Targets

enum TutorialTarget: Hashable {
    case addPatient       // empty-state button OR roster "+"
    case nameField        // form: Name (reported while empty)
    case submitPatient    // form: "Add patient" (reported when enabled)
    case enrollContinue   // detector library onboarding "Continue"
    case faceProceed      // face-consent "Proceed" (free choice — ring only)
    case patientCard      // first roster row
    case addSensor        // PatientCamerasView "Add a sensor"
    case roomField        // AddCameraSheet: Room (reported while empty)
    case generateCode     // AddCameraSheet: "Generate code" (when enabled)
    case sheetDone        // AddCameraSheet code display "Done" (to exit the sheet)
    case firstDetector    // first row on the Detectors tab (the info pause)
    case reconnectAll     // Live tab "Reconnect all sensors" (when offline)
}

extension View {
    /// Mark a control as a tour spotlight target: a clear background
    /// GeometryReader reports the control's GLOBAL frame to the manager.
    /// Pass nil to pause reporting — conditional markers (`empty ?
    /// .nameField : nil`) are how the tour walks field-to-field.
    ///
    /// IDENTITY-STABLE BY DESIGN: the background is ALWAYS installed and
    /// the optional target only gates reporting. An `if/else` here would
    /// change the modified view's structural identity when the condition
    /// flips — SwiftUI then recreates the underlying control, and a
    /// focused TextField gets torn down mid-word, resigning the keyboard
    /// (the "ring jumps after the first letter" bug). Pure annotation.
    func tutorialTarget(_ target: TutorialTarget?) -> some View {
        background(
            GeometryReader { g in
                Color.clear
                    .onAppear {
                        if let target {
                            TutorialManager.shared.reportFrame(target, g.frame(in: .global))
                        }
                    }
                    .onChange(of: g.frame(in: .global)) { _, f in
                        if let target {
                            TutorialManager.shared.reportFrame(target, f)
                        }
                    }
                    .onChange(of: target) { old, new in
                        if let old { TutorialManager.shared.clearFrame(old) }
                        if let new {
                            TutorialManager.shared.reportFrame(new, g.frame(in: .global))
                        }
                    }
                    .onDisappear {
                        if let target { TutorialManager.shared.clearFrame(target) }
                    }
            }
        )
    }
}

// MARK: - Surfaces

enum TutorialSurface: Int, Comparable {
    case root = 0          // MainTabView
    case patientShell      // fullScreenCover over root
    case newPatientForm    // sheet
    case addCameraSheet    // sheet over patient shell
    case enrollment        // post-create cover (detectors + face ID) over the form

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - Steps

enum TutorialStep: Int, CaseIterable {
    case welcome
    case addPatient       // ring: Add a patient
    case fillPatient      // ring walks: name → DOB → Add patient
    case chooseDetectors  // enrollment: ring on Continue (toggles stay free)
    case faceDecision     // enrollment: ring on Proceed (user's choice)
    case faceCapture      // enrollment: camera screen (top card, NO ring)
    case openPatient      // ring: patient card
    case addSensor        // ring: Add a sensor
    case generateCode     // ring walks: room field → Generate code
    case pairSensor       // card + Sensor keypad photo; waits for the pair
    case liveTab          // ring: Live tab slot
    case liveInfo         // pause: explain the live view (card + button)
    case detectors        // ring: Detectors tab slot
    case detectorsInfo    // pause: explain detectors (ring on first row + button)
    case events           // ring: Events tab slot
    case eventsInfo       // pause: explain events (card + button)
    case done

    static var countedTotal: Int { allCases.count - 1 }   // welcome excluded

    /// Spotlight target candidates, highest priority first. The host
    /// rings the FIRST candidate with a reported frame — conditional
    /// markers make the ring walk the flow click-by-click.
    var targetPriority: [TutorialTarget] {
        switch self {
        case .addPatient: [.addPatient]
        case .fillPatient: [.submitPatient, .nameField]
        case .chooseDetectors: [.enrollContinue]
        case .faceDecision: [.faceProceed]
        case .openPatient: [.patientCard]
        case .addSensor: [.addSensor]
        case .generateCode: [.generateCode, .roomField]
        case .detectorsInfo: [.firstDetector]
        case .liveInfo: [.reconnectAll]
        default: []
        }
    }

    /// Patient-shell tab-bar slot to highlight (Home 0 · Live 1 ·
    /// Events 2 · Detectors 3 · Settings 4). Indices shifted right when
    /// the Home dashboard became tab one (2026-08-15; previously shifted
    /// left when Sensors folded into Live, 2026-08-05) — they are
    /// positional, so a stale number rings the wrong tab rather than
    /// failing, which is why they live beside the enum that defines the
    /// order.
    var tabSlot: Int? {
        switch self {
        case .liveTab: 1
        case .events: 2
        case .detectors: 3
        default: nil
        }
    }

    /// Dim + tap-block for a given active target. Strict by default;
    /// ring-only (no dim, no block) where the user is choosing freely
    /// or finishing optional fields.
    func dimsAndBlocks(for target: TutorialTarget?) -> Bool {
        // The "close this sheet" Done spotlight is strict: gray out and
        // gate everything except Done.
        if target == .sheetDone { return true }
        switch self {
        case .fillPatient, .generateCode:
            // Every phase of the form walk is strict — gray overlay +
            // red box on the field or button whose turn it is. (Typing
            // itself is never gated: while editing, activeTarget goes
            // nil, so no dim is up at all.)
            return true
        case .chooseDetectors, .faceDecision:
            return false   // free choice — guide, don't gate
        case .liveInfo:
            // Two-phase: while "Reconnect all sensors" is needed, the
            // full strict treatment funnels the user to it; once video
            // is up the step is a plain explanation pause (bookend dim).
            return target == .reconnectAll
        case .detectorsInfo:
            // Attention pause: gate everything (the cutout row + the
            // card's button are the only live spots) so tab-hopping
            // can't desync the explanation.
            return true
        case .addPatient, .openPatient, .addSensor,
             .liveTab, .detectors, .events:
            return true
        default:
            return false
        }
    }
}

// MARK: - Manager (state machine + frame registry)

@MainActor
@Observable
final class TutorialManager {
    static let shared = TutorialManager()

    private(set) var step: TutorialStep?
    /// Reference-counted surface registry. SwiftUI recreates an overlay
    /// host when its wrapped view's internal navigation swaps (observed:
    /// the enrollment flow's detectors→consent switch remounts the host,
    /// and the NEW instance's onAppear fires BEFORE the OLD instance's
    /// onDisappear). A Set can't survive that ordering — the deferred
    /// onDisappear deleted the freshly-registered surface while the
    /// cover was plainly on screen (device logs: "surface up:
    /// enrollment" → spotlights → spurious "surface down: enrollment").
    /// Counting turns remount churn into a 1→2→1 no-op; a surface is
    /// only considered gone at zero.
    private var surfaceCounts: [TutorialSurface: Int] = [:]
    var visibleSurfaces: Set<TutorialSurface> {
        Set(surfaceCounts.filter { $0.value > 0 }.keys)
    }
    /// Marked controls' frames in GLOBAL (window) coordinates.
    private(set) var targetFrames: [TutorialTarget: CGRect] = [:]
    /// The pairing code currently displayed in the add-sensor sheet,
    /// reported by the sheet so the tour's keypad illustration can show
    /// the REAL code (even after the sheet closes). Tour-only plumbing.
    private(set) var pairingCode: String?

    func notePairingCode(_ code: String) {
        pairingCode = code
        print("[Tutorial] pairing code noted")
    }

    /// True while the user is typing in a text field. The field-walking
    /// steps hold their ring during typing — without this, the FIRST
    /// keystroke flips the field's conditional marker and yanks the box
    /// to the next field mid-word. Tracked two ways, because either can
    /// miss alone: keyboard frames (no-op with a hardware keyboard /
    /// simulator's Connect-Hardware-Keyboard) and UITextField focus
    /// notifications (SwiftUI TextFields are UITextField-backed).
    private(set) var keyboardVisible = false
    private(set) var fieldEditing = false
    var typing: Bool { keyboardVisible || fieldEditing }

    /// Which branch the pairing step exited through. Drives the Live
    /// step: the paired path gets the "Reconnect all sensors" walk; the
    /// skipped path must NOT (there are no sensors to reconnect).
    /// Persisted so a mid-tour relaunch keeps the right branch.
    private(set) var skippedPairing = false {
        didSet { defaults.set(skippedPairing, forKey: TutorialFlags.skippedPairingKey) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        skippedPairing = UserDefaults.standard.bool(forKey: TutorialFlags.skippedPairingKey)
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIResponder.keyboardWillShowNotification,
                       object: nil, queue: .main) { _ in
            Task { @MainActor in
                TutorialManager.shared.keyboardVisible = true
                if TutorialManager.shared.step != nil { print("[Tutorial] keyboard show") }
            }
        }
        nc.addObserver(forName: UIResponder.keyboardWillHideNotification,
                       object: nil, queue: .main) { _ in
            Task { @MainActor in
                TutorialManager.shared.keyboardVisible = false
                if TutorialManager.shared.step != nil { print("[Tutorial] keyboard hide") }
            }
        }
        nc.addObserver(forName: UITextField.textDidBeginEditingNotification,
                       object: nil, queue: .main) { _ in
            Task { @MainActor in
                TutorialManager.shared.fieldEditing = true
                if TutorialManager.shared.step != nil { print("[Tutorial] field editing begin") }
            }
        }
        nc.addObserver(forName: UITextField.textDidEndEditingNotification,
                       object: nil, queue: .main) { _ in
            Task { @MainActor in
                TutorialManager.shared.fieldEditing = false
                if TutorialManager.shared.step != nil { print("[Tutorial] field editing end") }
            }
        }
    }

    var topmostSurface: TutorialSurface { visibleSurfaces.max() ?? .root }

    // ── frames ───────────────────────────────────────────────────

    func reportFrame(_ target: TutorialTarget, _ frame: CGRect) {
        guard targetFrames[target] != frame else { return }
        targetFrames[target] = frame
        if step != nil {
            print("[Tutorial] frame \(target) → \(frame)")
        }
        // The face-consent screen appearing (its Proceed button reports)
        // is the "detector picking is done" signal.
        if target == .faceProceed, step == .chooseDetectors {
            set(.faceDecision)
        }
    }

    func clearFrame(_ target: TutorialTarget) {
        targetFrames[target] = nil
        if step != nil {
            print("[Tutorial] frame \(target) cleared")
        }
        // The consent screen's Proceed vanishing while we're on the
        // decision step means the user chose to proceed → the camera
        // capture screen is mounting. Move to the capture step IMMEDIATELY
        // so the ring can never linger at the dead button's coordinates
        // (the "red box flashes then everything disappears" bug).
        if target == .faceProceed, step == .faceDecision {
            set(.faceCapture)
        }
    }

    // ── lifecycle ────────────────────────────────────────────────

    func startIfEligible() {
        print("[Tutorial] startIfEligible: step=\(String(describing: step)) eligible=\(defaults.bool(forKey: TutorialFlags.eligibleKey)) done=\(defaults.bool(forKey: TutorialFlags.doneKey))")
        guard step == nil,
              defaults.bool(forKey: TutorialFlags.eligibleKey),
              !defaults.bool(forKey: TutorialFlags.doneKey)
        else { return }
        let saved = defaults.integer(forKey: TutorialFlags.stepKey)
        step = TutorialStep(rawValue: saved) ?? .welcome
    }

    /// Settings → "Replay the welcome tour". MainTabView watches for
    /// the welcome step and steers to the Home tab.
    func replay() {
        defaults.set(true, forKey: TutorialFlags.eligibleKey)
        defaults.set(false, forKey: TutorialFlags.doneKey)
        skippedPairing = false
        pairingCode = nil
        set(.welcome)
    }

    func finish() {
        step = nil
        pairingCode = nil
        defaults.set(true, forKey: TutorialFlags.doneKey)
        defaults.set(false, forKey: TutorialFlags.eligibleKey)
        defaults.set(TutorialStep.welcome.rawValue, forKey: TutorialFlags.stepKey)
    }

    private func set(_ s: TutorialStep) {
        step = s
        defaults.set(s.rawValue, forKey: TutorialFlags.stepKey)
        print("[Tutorial] step → \(s) (topmost surface: \(topmostSurface))")
    }

    /// Welcome's "Start tour" (the only manual advance left).
    func next(from current: TutorialStep) {
        guard step == current else { return }
        if current == .done { finish(); return }
        set(TutorialStep(rawValue: current.rawValue + 1) ?? .done)
    }

    /// pairSensor card's "I'll pair this later" — no second phone handy.
    /// The tour still walks the Live tab (with not-yet-paired wording) so
    /// every tab gets introduced; only the live video itself is missing.
    func skipPairing() {
        if step == .pairSensor {
            skippedPairing = true
            set(.liveTab)
        }
    }

    // ── observed app events ──────────────────────────────────────

    func patientCountIncreased() {
        // The post-create enrollment cover (detectors + face ID) comes up
        // right after; guide through it, then resume at the roster.
        if step == .addPatient || step == .fillPatient { set(.chooseDetectors) }
    }

    func patientOpened() {
        if step == .openPatient { set(.addSensor) }
        // Replay affordance: a returning user on the add-patient step may
        // open one of their EXISTING patients instead of creating another
        // — continue the tour with that patient at the sensor section.
        if step == .addPatient { set(.addSensor) }
    }

    func cameraCountIncreased() {
        print("[Tutorial] event: cameraCountIncreased (step: \(String(describing: step)))")
        if step == .generateCode || step == .addSensor { set(.pairSensor) }
    }

    func sensorPaired() {
        print("[Tutorial] event: sensorPaired (step: \(String(describing: step)))")
        if step == .pairSensor || step == .generateCode {
            skippedPairing = false
            set(.liveTab)
        }
    }

    /// Patient-shell tab change, by case name ("live"/"events"/
    /// "detectors"/"settings"). "cameras" is gone — Sensors folded into
    /// Live, and the tour now spotlights Add a sensor there directly.
    func patientTabChanged(_ name: String) {
        switch (step, name) {
        case (.liveTab, "live"): set(.liveInfo)
        case (.detectors, "detectors"): set(.detectorsInfo)
        case (.events, "events"): set(.eventsInfo)
        default: break
        }
    }

    func surfaceAppeared(_ s: TutorialSurface) {
        surfaceCounts[s, default: 0] += 1
        print("[Tutorial] surface up: \(s) (counts: \(surfaceCounts), topmost: \(topmostSurface))")
        // Step transitions only on the FIRST registration (0 → 1) — a
        // remount re-register (1 → 2) is not a new presentation.
        guard surfaceCounts[s] == 1 else { return }
        switch (step, s) {
        case (.addPatient, .newPatientForm): set(.fillPatient)
        case (.addSensor, .addCameraSheet): set(.generateCode)
        default: break
        }
    }

    func surfaceDisappeared(_ s: TutorialSurface) {
        surfaceCounts[s] = max(0, (surfaceCounts[s] ?? 0) - 1)
        print("[Tutorial] surface down: \(s) (counts: \(surfaceCounts), topmost: \(topmostSurface))")
        // A real exit is reaching ZERO. A deferred onDisappear from a
        // remounted host (2 → 1) must not be treated as the layer
        // closing — that's exactly what blanked the face-consent screen.
        guard (surfaceCounts[s] ?? 0) == 0 else { return }
        switch (step, s) {
        // Backed out of a sheet without completing it → step back so the
        // ring returns to the button that reopens it.
        case (.fillPatient, .newPatientForm): set(.addPatient)
        case (.generateCode, .addCameraSheet): set(.addSensor)
        // Enrollment flow finished (cover dismissed) → resume at the
        // roster, pointing at the new patient's card. The flow's
        // onFinish ALSO dismisses the presenting form sheet, but SwiftUI
        // skips the form host's onDisappear in this nested double-
        // dismissal (verified by device logs: "surface down: enrollment"
        // arrives, "surface down: newPatientForm" never does) — purge it
        // here or `topmost` stays pointed at the dead sheet and nothing
        // ever renders again.
        case (.chooseDetectors, .enrollment), (.faceDecision, .enrollment),
             (.faceCapture, .enrollment):
            surfaceCounts[.newPatientForm] = 0
            set(.openPatient)
        // Safety: form closed while on an enrollment step and no
        // enrollment cover is up → resume anyway. (Covers the nested
        // double-dismissal case where the cover's own onDisappear is
        // skipped by SwiftUI.)
        case (.chooseDetectors, .newPatientForm),
             (.faceDecision, .newPatientForm),
             (.faceCapture, .newPatientForm):
            // The cover can't outlive its presenter: if the form is gone,
            // drop any stale .enrollment registration a skipped
            // onDisappear left behind (it would strand "topmost" on a
            // dead layer and nothing would ever render again).
            surfaceCounts[.enrollment] = 0
            set(.openPatient)
        default: break
        }
    }
}

// MARK: - Host (per-surface overlay)

private struct TutorialHost: View {
    let surface: TutorialSurface
    let proxy: GeometryProxy

    @Environment(AppEnvironment.self) private var env
    private var manager: TutorialManager { TutorialManager.shared }

    // Flattened observable signals.
    private var patientCount: Int { env.api.patients.count }
    private var cameraCount: Int {
        env.api.camerasByPatient.values.reduce(0) { $0 + $1.count }
    }
    /// IDs of currently-paired cameras. The pair watcher needs identity,
    /// not a global boolean: on accounts that ALREADY have paired cameras
    /// (any replay, any second sensor), "is anything paired" is true
    /// before the tour's code is even generated, so it can never flip —
    /// verified on-device (cameraCount 14 → 15, no transition). A NEW id
    /// joining this set is the real "the sensor just paired" event.
    private var pairedCameraIds: Set<UUID> {
        Set(env.api.camerasByPatient.values.flatMap { $0 }.filter(\.paired).map(\.id))
    }

    var body: some View {
        // NOTE: surface registration does NOT live here — this view's
        // content is conditional, and onAppear on conditional content is
        // exactly the lifecycle trap that made registration flaky (the
        // enrollment cover's host sometimes never registered, stranding
        // `topmost` on the covered sheet → nothing rendered). It hangs
        // off the unconditional GeometryReader in `tutorialOverlay(_:)`.
        content
            // ── auto-advance off real app state ──
            .onChange(of: patientCount) { old, new in
                if new > old { manager.patientCountIncreased() }
            }
            .onChange(of: env.deepLink.openPatientId) { _, opened in
                if opened != nil { manager.patientOpened() }
            }
            .onChange(of: cameraCount) { old, new in
                print("[Tutorial] watch(\(surface)): cameraCount \(old) → \(new)")
                if new > old { manager.cameraCountIncreased() }
            }
            .onChange(of: pairedCameraIds) { old, new in
                let fresh = new.subtracting(old)
                print("[Tutorial] watch(\(surface)): pairedCameraIds \(old.count) → \(new.count) (new: \(fresh.count))")
                if !fresh.isEmpty { manager.sensorPaired() }
            }
    }

    /// The step's currently-active spotlight target: first candidate in
    /// the priority list with a reported frame.
    private func activeTarget(for step: TutorialStep) -> TutorialTarget? {
        // Skipped-pairing branch: there are no sensors, so the Live
        // pause must never ring "Reconnect all sensors" — card only.
        if step == .liveInfo, manager.skippedPairing { return nil }
        // Tab steps reached while a sheet is still up (e.g. "I'll pair
        // this later"): the tab bar is underneath — spotlight the sheet's
        // Done button instead so the user is walked out of the sheet.
        if step.tabSlot != nil, surface != .patientShell {
            return manager.targetFrames[.sheetDone] != nil ? .sheetDone : nil
        }
        let candidate = step.targetPriority.first { manager.targetFrames[$0] != nil }
        // PATIENT-FORM ONLY: while typing, hold the ring off the name
        // field — its marker flips at the first keystroke, and without
        // this the spotlight would churn mid-word. BUTTON targets (Add
        // patient) ring regardless. The sensor sheet's room field is
        // deliberately NOT gated: it stays spotlit while typing, and
        // the 1s settle debounce hands off to Generate code.
        if manager.typing, step == .fillPatient, candidate == .nameField {
            return nil
        }
        return candidate
    }

    @ViewBuilder
    private var content: some View {
        if let step = manager.step, manager.topmostSurface == surface {
            activeLayer(step)
                .transition(.opacity)
        } else {
            // Inert placeholder: keeps onAppear/onChange alive (an empty
            // conditional never "appears"), but can never block a touch.
            Color.clear.allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func activeLayer(_ step: TutorialStep) -> some View {
        let target = activeTarget(for: step)
        let spotlight = spotlightRect(for: step, target: target)
        ZStack {
            if let rect = spotlight {
                // Replay affordance: with existing patients, the add-patient
                // step keeps the gray overlay (visual consistency with the
                // other steps) but does NOT block — the user may tap an
                // existing card instead of creating a duplicate patient.
                let blocking = !(step == .addPatient && patientCount > 0)
                if step.dimsAndBlocks(for: target) {
                    // Strict: outside the cutout, taps are absorbed —
                    // the spotlighted control is the only way forward.
                    DimLayer(cutout: rect, blocking: blocking, size: proxy.size)
                }
                PulseRing(rect: rect)
            } else if step == .welcome || step == .done
                        || step == .liveInfo || step == .eventsInfo {
                // Bookends + the events pause: gray the whole screen
                // (non-blocking) so the tour visibly owns the moment.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            card(step, target: target, spotlight: spotlight)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: spotlight)
    }

    /// The highlight frame in THIS host's local space. Markers report
    /// global (window) frames; convert via the host's own global origin.
    /// Tab slots are estimated from screen size.
    private func spotlightRect(for step: TutorialStep, target: TutorialTarget?) -> CGRect? {
        let hostOrigin = proxy.frame(in: .global).origin
        if let target, let global = manager.targetFrames[target], !global.isEmpty {
            let local = CGRect(
                x: global.minX - hostOrigin.x,
                y: global.minY - hostOrigin.y,
                width: global.width,
                height: global.height,
            ).insetBy(dx: -6, dy: -6)
            print("[Tutorial] spotlight \(target) on \(surface): global=\(global) hostOrigin=\(hostOrigin) → local=\(local)")
            return local
        }
        if let slot = step.tabSlot, surface == .patientShell {
            // Generous full-height strip over the slot's column: the tab
            // is guaranteed inside the hole even if the bar's exact
            // geometry differs, so blocking can never strand the user.
            let size = proxy.size
            let barWidth = size.width - 28
            let slotW = barWidth / 5
            return CGRect(
                x: 14 + slotW * CGFloat(slot),
                y: size.height - 112,
                width: slotW,
                height: 112,
            )
        }
        if !step.targetPriority.isEmpty {
            print("[Tutorial] spotlight on \(surface): no frame for \(step.targetPriority) (known: \(Array(manager.targetFrames.keys)))")
        }
        return nil
    }

    // ── coach card ──────────────────────────────────────────────

    @ViewBuilder
    private func card(_ step: TutorialStep, target: TutorialTarget?, spotlight: CGRect?) -> some View {
        VStack(spacing: 0) {
            if let rect = spotlight, rect.midY < proxy.size.height * 0.55 {
                // target in the upper half → card below it
                Spacer().frame(height: max(0, min(rect.maxY + 18, proxy.size.height - 280)))
                cardBody(step, target: target)
                Spacer(minLength: 0)
            } else if let rect = spotlight {
                // target low (e.g. tab bar / footer button) → card above it
                Spacer(minLength: 0)
                cardBody(step, target: target)
                Spacer().frame(height: max(16, proxy.size.height - rect.minY + 14))
            } else if manager.typing || step == .faceCapture {
                // Typing (keyboard owns the bottom half) and the face-
                // capture screen (camera controls live at the bottom):
                // pin the instruction to the top, out of the way.
                Spacer().frame(height: 16)
                cardBody(step, target: target)
                Spacer(minLength: 0)
            } else {
                // No spotlight yet. Keep clear of bottom CTAs (form
                // footers live there) — the card must never cover the
                // button it's asking the user to reach.
                Spacer(minLength: 0)
                cardBody(step, target: target)
                Spacer().frame(height: step == .welcome || step == .done
                               ? proxy.size.height * 0.18 : 116)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func cardBody(_ step: TutorialStep, target: TutorialTarget?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                NemaraMark(size: 20)
                Text(eyebrow(step))
                    .font(NemaraFont.mono(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(NemaraColor.ink3)
                Spacer()
                if step != .welcome && step != .done {
                    Button("Skip tour") { manager.finish() }
                        .font(NemaraFont.captionStrong)
                        .foregroundStyle(NemaraColor.ink3)
                        .buttonStyle(.plain)
                }
            }

            Text(text(for: step, target: target))
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if step == .pairSensor {
                // Native replica of the Memoria Sensor pairing screen,
                // showing the REAL generated code (a hardcoded screenshot
                // showed a code that didn't match the user's).
                SensorKeypadMock(code: manager.pairingCode)
            }

            // STRICT MODE: no Next. Forward = the spotlighted control.
            if step == .welcome {
                HStack(spacing: 10) {
                    NemaraButton("Maybe later", variant: .ghost, size: .sm) { manager.finish() }
                    Spacer()
                    NemaraButton("Start tour", variant: .primary, size: .sm) { manager.next(from: .welcome) }
                }
            } else if step == .done {
                HStack {
                    Spacer()
                    NemaraButton("Finish", variant: .primary, size: .sm) { manager.finish() }
                }
            } else if step == .detectorsInfo || step == .eventsInfo
                        || (step == .liveInfo && target == nil) {
                // Explanation pause: the user proceeds when ready. (The
                // Live pause hides its button while the Reconnect ring is
                // up — tapping the real button is the way forward there.)
                HStack {
                    Spacer()
                    NemaraButton(step == .detectorsInfo ? "I understand" : "Got it",
                                 variant: .primary, size: .sm) {
                        manager.next(from: step)
                    }
                }
            } else if step == .pairSensor {
                // No second phone handy → gracefully skip the pairing-
                // dependent steps and continue the tour at Detectors.
                HStack {
                    NemaraButton("I'll pair this later", variant: .ghost, size: .sm) {
                        manager.skipPairing()
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .fill(NemaraColor.card)
                .shadow(color: NemaraColor.ink.opacity(0.22), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .strokeBorder(NemaraColor.line, lineWidth: 1)
        )
    }

    private func eyebrow(_ step: TutorialStep) -> String {
        step == .welcome
            ? "WELCOME TOUR"
            : "WELCOME TOUR · \(step.rawValue) OF \(TutorialStep.countedTotal)"
    }

    /// Short, per-click copy. The active target picks the phrasing, so
    /// the message tracks the ring from field to field.
    private func text(for step: TutorialStep, target: TutorialTarget?) -> String {
        // Tab steps shown while a sheet is still up: tell the user to
        // close the sheet first — the tab bar is underneath it.
        if step.tabSlot != nil, surface != .patientShell {
            return "Tap Done to close this first — then follow the highlight at the bottom."
        }
        switch step {
        case .welcome:
            return "Welcome to Memoria 👋 A quick guided setup — about two minutes. You can skip anytime and replay later from Settings."
        case .addPatient:
            return patientCount > 0
                ? "Tap + to add another person — or tap one of your existing patients to continue the tour with them."
                : "Tap the highlighted button to add the person you'll be caring for."
        case .fillPatient:
            if target == .submitPatient { return "Perfect — now tap Add patient." }
            // Name phase while its marker reports (field still empty);
            // afterwards the form is free-fill until Add patient lights up.
            if manager.targetFrames[.nameField] != nil {
                return manager.typing
                    ? "Type their name — then fill out the rest below."
                    : "Tap the name field and type their name."
            }
            return "Fill out the rest of the details."
        case .chooseDetectors:
            return "These starter alerts are pre-selected. Toggle any you like, then tap Continue."
        case .faceDecision:
            return "Your choice — a few photos of \(patientFirstName)'s face make alerts more accurate. Tap whichever you prefer."
        case .faceCapture:
            return "Follow the on-screen prompts to capture \(patientFirstName)'s face. The tour continues when you're done."
        case .openPatient:
            return "Tap \(patientFirstName)'s card to open their space."
        case .addSensor:
            return "Tap Add a sensor to connect your first one."
        case .generateCode:
            if target == .generateCode { return "Great — now tap Generate code." }
            return "Name the room in the highlighted field (like \u{201C}Living room\u{201D}) — pause for a moment when you're done."
        case .pairSensor:
            return surface == .addCameraSheet
                ? "On the spare phone, open the Memoria Sensor app and type in this code. Then place that phone up high with a good view of the room, plugged into power."
                : "On the spare phone, open the Memoria Sensor app and enter your pairing code. The sensor appears here the moment it connects."
        case .liveTab:
            return "Now tap the Live tab."
        case .liveInfo:
            if manager.skippedPairing {
                return "This is where live video appears once a sensor is paired — each room gets its own tile. You don't need to keep the app open; Memoria works in the background."
            }
            if target == .reconnectAll {
                return "Tap Reconnect all sensors to bring it back online."
            }
            return "This is the live view — your sensor's room shows up here as a tile you can tap to expand. You don't need to keep it open; Memoria keeps working in the background."
        case .detectors:
            return "Now tap the Detectors tab."
        case .detectorsInfo:
            return "This is a detector — something Memoria watches for automatically, like Falls. Toggle any on or off, tune sensitivity, or add your own in plain English."
        case .events:
            return "Now tap the Events tab."
        case .eventsInfo:
            return "When Memoria notices something, the alert lands here. Open one to watch the clip and tell Memoria if it got it right — that tunes your alerts over time."
        case .done:
            return "That's it — you're all set! Memoria keeps working even with the app closed. Replay this tour anytime from Settings. (Memoria is a wellness tool, not a medical device.)"
        }
    }

    private var patientFirstName: String {
        guard let p = env.api.patients.first else { return "your patient" }
        let name = p.preferredName.isEmpty ? p.fullName : p.preferredName
        return name.split(separator: " ").first.map(String.init) ?? name
    }
}

/// Miniature replica of the Memoria Sensor app's "Pair this camera"
/// screen, rendered natively so the six boxes show the ACTUAL pairing
/// code (empty boxes if unknown, mirroring the real app pre-entry).
private struct SensorKeypadMock: View {
    let code: String?

    var body: some View {
        VStack(spacing: 10) {
            Text("Pair this camera")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
            Text("Enter the 6-digit code from your dashboard")
                .font(.system(size: 11))
                .foregroundStyle(.gray)
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    Text(digit(i))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(white: 0.96))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(white: 0.85), lineWidth: 1)
                        )
                }
            }
            Text("Pair")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Capsule().fill(Color.blue))
                .padding(.horizontal, 28)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                .strokeBorder(NemaraColor.line, lineWidth: 1)
        )
    }

    private func digit(_ i: Int) -> String {
        guard let code, i < code.count else { return "" }
        return String(Array(code)[i])
    }
}

// MARK: - Spotlight pieces

/// Full-screen dim with a rounded cutout. The dim itself is a pure
/// visual (never hit-testable); four plain rectangles AROUND the cutout
/// absorb touches — the cutout region contains no view at all, so taps
/// there are guaranteed to pass through to the real control. (An
/// even-odd `contentShape` pass-through proved unreliable on iOS 17.)
private struct DimLayer: View {
    let cutout: CGRect
    /// When false, the dim is purely visual — used by the replay
    /// add-patient step (gray overlay for consistency, but the user's
    /// existing patient cards must stay tappable).
    var blocking: Bool = true
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            CutoutShape(cutout: cutout)
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            if blocking {
                blocker(CGRect(x: 0, y: 0,
                               width: size.width, height: max(0, cutout.minY)))
                blocker(CGRect(x: 0, y: cutout.maxY,
                               width: size.width, height: max(0, size.height - cutout.maxY)))
                blocker(CGRect(x: 0, y: cutout.minY,
                               width: max(0, cutout.minX), height: cutout.height))
                blocker(CGRect(x: cutout.maxX, y: cutout.minY,
                               width: max(0, size.width - cutout.maxX), height: cutout.height))
            }
        }
        .transition(.opacity)
    }

    private func blocker(_ r: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {}   // absorb — no-op
            .frame(width: max(0, r.width), height: max(0, r.height))
            .position(x: r.midX, y: r.midY)
    }
}

private struct CutoutShape: Shape {
    let cutout: CGRect

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        p.addRoundedRect(
            in: cutout,
            cornerSize: CGSize(width: 14, height: 14),
            style: .continuous,
        )
        return p
    }
}

/// "Look here" signal: a steady ring + a sonar ripple that expands
/// outward and fades, then restarts.
///
/// The ripple animates via an explicit `withAnimation` transaction in
/// `onAppear`, scoped to ONLY the scale/opacity state. A value-based
/// `.animation(...repeatForever...)` modifier here captured LATER
/// layout changes into the repeating cycle (iOS 17 quirk) — the ring
/// replayed the target's slide-in every pulse ("box starts low and
/// fades upward" instead of pulsing in place).
private struct PulseRing: View {
    let rect: CGRect
    @State private var rippleScale: CGFloat = 1.0
    @State private var rippleOpacity: Double = 0.8

    var body: some View {
        ZStack {
            ring   // steady outline
            ring   // expanding, fading ripple
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)
        }
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                rippleScale = 1.18
                rippleOpacity = 0
            }
        }
    }

    private var ring: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(NemaraColor.terra, lineWidth: 2.5)
            .frame(width: rect.width, height: rect.height)
    }
}

// MARK: - Host extension

extension View {
    /// Attach the tour to a presentation layer. Each sheet/cover needs
    /// its own host because it renders above its presenter; only the
    /// topmost visible layer draws the current step. Footprint-only
    /// when idle.
    func tutorialOverlay(_ surface: TutorialSurface = .root) -> some View {
        overlay(
            GeometryReader { proxy in
                TutorialHost(surface: surface, proxy: proxy)
            }
            .ignoresSafeArea()
            // Surface registration lives HERE, on the unconditional
            // GeometryReader — a concrete, always-present view whose
            // onAppear/onDisappear can't be skipped. (Attached to the
            // host's conditional content, registration was flaky: the
            // enrollment cover sometimes never registered, leaving
            // `topmost` stuck on the sheet beneath it.)
            .onAppear {
                TutorialManager.shared.surfaceAppeared(surface)
                if surface == .root { TutorialManager.shared.startIfEligible() }
            }
            .onDisappear { TutorialManager.shared.surfaceDisappeared(surface) }
        )
    }
}

#if DEBUG
#Preview {
    ZStack {
        NemaraColor.paper.ignoresSafeArea()
        VStack { Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tutorialOverlay(.root)
            .environment(AppEnvironment.preview())
    }
    .onAppear { TutorialManager.shared.replay() }
}
#endif
