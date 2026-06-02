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
                    PatientLiveView(patientId: patientId)
                } header: {
                    if let patient { PHeader(patient: patient) { dismiss() } }
                }
            }
            .tabItem { Label("Live", systemImage: "video.fill") }
            .tag(PatientTab.live)

            NavigationStack {
                patientTab {
                    PatientEventsView(patientId: patientId)
                } header: {
                    if let patient { PHeader(patient: patient) { dismiss() } }
                }
            }
            .tabItem { Label("Events", systemImage: "waveform.path") }
            .tag(PatientTab.events)

            NavigationStack {
                patientTab {
                    PatientCamerasView(patientId: patientId)
                } header: {
                    if let patient { PHeader(patient: patient) { dismiss() } }
                }
            }
            .tabItem { Label("Sensors", systemImage: "camera.fill") }
            .tag(PatientTab.cameras)

            NavigationStack {
                patientTab {
                    PatientDetectorsView(patientId: patientId)
                } header: {
                    if let patient { PHeader(patient: patient) { dismiss() } }
                }
            }
            .tabItem { Label("Detectors", systemImage: "sensor.tag.radiowaves.forward.fill") }
            .tag(PatientTab.detectors)

            NavigationStack {
                patientTab {
                    PatientSettingsView(patientId: patientId)
                } header: {
                    if let patient { PHeader(patient: patient, showsIdentity: false) { dismiss() } }
                }
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(PatientTab.settings)
        }
        .background(NemaraColor.paper)
        // Tap-outside-to-dismiss for the whole patient experience. The
        // app-root copy on RootView doesn't reach here — PatientShell is
        // a fullScreenCover (separate hosting context) — so the gesture
        // has to be re-applied inside the cover.
        .dismissKeyboardOnTap()
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
        .toolbar(.hidden, for: .navigationBar)
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
