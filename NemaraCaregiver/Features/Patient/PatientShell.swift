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
    @State private var tab: PatientTab = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-startTab=events") { return .events }
        if args.contains("-startTab=settings") { return .settings }
        #endif
        return .live
    }()

    enum PatientTab: Hashable {
        case live, events, settings
    }

    var body: some View {
        let patient = env.mockStore.patients.first(where: { $0.id == patientId })

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
    let env = AppEnvironment(auth: MockAuthService(), mockStore: MockStore())
    env.auth.currentCaregiver = Caregiver(id: UUID(), displayName: "Jane Patel", email: "jane@patel.co")
    return PatientShell(patientId: env.mockStore.patients[0].id)
        .environment(env)
}
