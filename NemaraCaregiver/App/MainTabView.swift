import SwiftUI

/// Two top-level tabs: Home (Roster) and Settings (App Settings).
///
/// Uses SwiftUI's native `TabView` on iOS 26 — which automatically
/// renders as the Liquid Glass floating tab bar with backdrop blur
/// and scroll-behind content. Brand tint is applied via the
/// `.tint(NemaraColor.terra)` modifier from `NemaraCaregiverApp`.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection: AppTab = .home

    enum AppTab: Hashable {
        case home, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            // dismissKeyboardOnTap goes on each tab's CONTENT, never on the
            // TabView — attaching a tap gesture to a TabView swallows its
            // tab-bar taps on iOS 17/18 (you get stuck on the initial tab).
            NavigationStack { RosterView().dismissKeyboardOnTap() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            NavigationStack { AppSettingsView().dismissKeyboardOnTap() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .background(NemaraColor.paper)
        // The SINGLE PatientShell presenter. Both roster and settings row
        // taps (and APNs deep links) funnel through `deepLink.openPatientId`,
        // so only one fullScreenCover can ever be up — no two-cover fights.
        .fullScreenCover(item: Binding(
            get: { env.deepLink.openPatientId.map(IdentifiableUUID.init) },
            set: { env.deepLink.openPatientId = $0?.id }
        )) { wrap in
            PatientShell(patientId: wrap.id)
                .environment(env)
        }
        // Drain a buffered notification tap once the signed-in surface is
        // mounted. Covers cold launch (tap before `onEventTap` existed) and
        // sign-in-after-cold-tap. Idempotent — a stale appear finds an empty
        // buffer and no-ops.
        .onAppear { env.deepLink.drainPendingTap() }
    }
}

/// `fullScreenCover(item:)` requires `Identifiable`; `UUID` can't safely
/// conform directly (potential stdlib conflict), so we wrap.
private struct IdentifiableUUID: Identifiable, Hashable { let id: UUID }

#if DEBUG
#Preview {
    MainTabView().environment(AppEnvironment.preview())
}
#endif
