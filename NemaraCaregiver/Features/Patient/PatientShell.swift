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
            Tab("Live", systemImage: "video.fill", value: PatientTab.live) {
                NavigationStack {
                    patientTab {
                        PatientLiveView(patientId: patientId)
                    } header: {
                        if let patient { PHeader(patient: patient) { dismiss() } }
                    }
                }
            }
            Tab("Events", systemImage: "waveform.path", value: PatientTab.events) {
                NavigationStack {
                    patientTab {
                        PatientEventsView(patientId: patientId)
                    } header: {
                        if let patient { PHeader(patient: patient) { dismiss() } }
                    }
                }
            }
            Tab("Cameras", systemImage: "camera.fill", value: PatientTab.cameras) {
                NavigationStack {
                    patientTab {
                        PatientCamerasView(patientId: patientId)
                    } header: {
                        if let patient { PHeader(patient: patient) { dismiss() } }
                    }
                }
            }
            Tab("Detectors", systemImage: "sensor.tag.radiowaves.forward.fill", value: PatientTab.detectors) {
                NavigationStack {
                    patientTab {
                        PatientDetectorsView(patientId: patientId)
                    } header: {
                        if let patient { PHeader(patient: patient) { dismiss() } }
                    }
                }
            }
            Tab("Settings", systemImage: "gearshape", value: PatientTab.settings) {
                NavigationStack {
                    patientTab {
                        PatientSettingsView(patientId: patientId)
                    } header: {
                        if let patient { PHeader(patient: patient) { dismiss() } }
                    }
                }
            }
        }
        .background(NemaraColor.paper)
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

#Preview {
    let env = AppEnvironment.preview()
    return PatientShell(patientId: env.api.patients[0].id)
        .environment(env)
}
