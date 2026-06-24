import SwiftUI

/// Patient bundle. Pinned `PHeader` at the top, then a native iOS 26
/// `TabView` whose tabs (Live / Events / Settings) render as the Liquid
/// Glass floating bar at the bottom — replacing the top-level Home /
/// Settings bar while the caregiver is inside a patient.
///
/// Presented as a `.fullScreenCover` from `RosterView` so the swap-out
/// is total (no two tab bars stack).
struct PatientShell: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var tab: PatientTab = .live
    /// Feedback form, reachable from every sub-tab's header via the "Feedback"
    /// pill. Presented once here (not per-tab) so there's a single sheet.
    @State private var showFeedback = false
    /// First-open data-collection consent. Auto-presented exactly once,
    /// only while the patient has never recorded a decision
    /// (`dataCollectionDecidedAt == nil`). Both choices stamp
    /// `decided_at` server-side, so this never re-nags after the first
    /// answer. Changeable later via the Settings `DataCollectionCard`.
    @State private var showConsent = false

    /// Five tabs mirror the web dashboard's IA (Live grid +
    /// per-camera + per-detector + events + patient-level settings).
    /// Five is the practical max iOS allows in a bottom tab bar
    /// without auto-collapsing to "More" — HIG-compliant.
    enum PatientTab: Hashable {
        case live, events, cameras, detectors, settings
    }

    var body: some View {
        let patient = env.api.patients.first(where: { $0.id == patientId })

        TabView(selection: $tab) {
            NavigationStack {
                patientTab {
                    PatientLiveView(patientId: patientId).trackScreen("patient.live")
                } header: {
                    if let patient {
                        PHeader(patient: patient, onFeedback: { showFeedback = true }) { dismiss() }
                    }
                }
            }
            .tabItem { Label("Live", systemImage: "video.fill") }
            .tag(PatientTab.live)

            NavigationStack {
                patientTab {
                    PatientEventsView(patientId: patientId).trackScreen("patient.events")
                } header: {
                    if let patient {
                        PHeader(patient: patient, onFeedback: { showFeedback = true }) { dismiss() }
                    }
                }
            }
            .tabItem { Label("Events", systemImage: "waveform.path") }
            .tag(PatientTab.events)

            NavigationStack {
                patientTab {
                    PatientCamerasView(patientId: patientId).trackScreen("patient.sensors")
                } header: {
                    if let patient {
                        PHeader(patient: patient, onFeedback: { showFeedback = true }) { dismiss() }
                    }
                }
            }
            .tabItem { Label("Sensors", systemImage: "camera.fill") }
            .tag(PatientTab.cameras)

            NavigationStack {
                patientTab {
                    PatientDetectorsView(patientId: patientId).trackScreen("patient.detectors")
                } header: {
                    if let patient {
                        PHeader(patient: patient, onFeedback: { showFeedback = true }) { dismiss() }
                    }
                }
            }
            .tabItem { Label("Detectors", systemImage: "sensor.tag.radiowaves.forward.fill") }
            .tag(PatientTab.detectors)

            NavigationStack {
                patientTab {
                    PatientSettingsView(patientId: patientId).trackScreen("patient.settings")
                } header: {
                    if let patient {
                        PHeader(patient: patient, showsIdentity: false, onFeedback: { showFeedback = true }) { dismiss() }
                    }
                }
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(PatientTab.settings)
        }
        .background(NemaraColor.paper)
        // Perpetual help button — re-applied here because PatientShell is a
        // fullScreenCover over MainTabView, which hides MainTabView's overlay.
        // The expanded single-camera live view (its own cover) intentionally
        // does NOT carry it.
        .supportButtonOverlay()
        // Welcome-tour host must survive into the patient cover (which
        // hides RootView's overlay) — same reasoning as the support button.
        .tutorialOverlay(.patientShell)
        // Pure notification — lets the tour auto-advance when the user taps
        // the tab it's pointing at. No behavior change.
        .onChange(of: tab) { _, t in
            TutorialManager.shared.patientTabChanged(String(describing: t))
        }
        // The single LiveKit teardown point. .onDisappear on the
        // outer TabView fires when the whole patient cover is
        // dismissed, NOT on inner sub-tab switches — so the room
        // stays alive across Live ↔ Events ↔ Settings, and only
        // truly disconnects when the caregiver backs out of the
        // patient. Pairs with `PatientLiveView.bootstrap`'s
        // already-connected short-circuit.
        .onDisappear {
            Task { await env.liveKit.disconnect() }
        }
        // Feedback form — one presentation point for every sub-tab's header
        // pill. NavigationStack gives it the title bar + its own back chevron
        // (which dismisses the sheet).
        .sheet(isPresented: $showFeedback) {
            NavigationStack { FeedbackView().trackScreen("feedback") }
                .environment(env)
        }
        // First-open data-collection consent. Trigger on appearance only
        // while the patient has never decided; both Share/Not now stamp
        // decided_at server-side so it won't re-present afterwards.
        .onAppear {
            if patient?.dataCollectionDecidedAt == nil { showConsent = true }
        }
        .sheet(isPresented: $showConsent) {
            if let patient {
                DataCollectionConsentSheet(
                    patientId: patient.id,
                    patientName: patient.preferredName,
                )
                .environment(env)
                .presentationDetents([.medium, .large])
                .trackScreen("data_collection_consent")
            }
        }
        // APNs deep link: when the router targets THIS patient with an
        // event to open, jump to the Events tab. `initial: true` handles
        // the cold-launch case where `focusEventId` is already set when
        // the shell first appears. PatientEventsView clears it after it
        // presents the sheet — we only steer the tab here.
        .onChange(of: env.deepLink.focusEventId, initial: true) { _, _ in
            if env.deepLink.openPatientId == patientId, env.deepLink.focusEventId != nil {
                tab = .events
            }
        }
    }

    /// A tab body: pinned `PHeader` at the top + scrollable content
    /// below. Header is pinned (not part of the scroll body) so it
    /// stays visible when the user scrolls.
    @ViewBuilder
    private func patientTab<Content: View, Header: View>(
        @ViewBuilder _ content: () -> Content,
        @ViewBuilder header: () -> Header
    ) -> some View {
        VStack(spacing: 0) {
            header()
            content()
        }
        // Tap-outside-to-dismiss is applied to each tab's CONTENT, never
        // to the TabView itself: a simultaneousGesture attached directly
        // to a TabView swallows its tab-bar taps on iOS 17/18 (you get
        // stuck on the initial tab). Here it still covers every text
        // field in the patient screens, but leaves the tab bar alone.
        .dismissKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        // Pin the bottom tab bar to paper in BOTH of its appearances. iOS
        // otherwise swaps to an opaque system material (which reads white in
        // light mode) on tabs whose content sits at the scroll edge — that's
        // why Events/Settings went white while Live/Sensors/Detectors stayed
        // paper. Forcing it visible + paper makes every tab consistent.
        .toolbarBackground(NemaraColor.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(NemaraColor.paper)
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return PatientShell(patientId: env.api.patients[0].id)
        .environment(env)
}
#endif
