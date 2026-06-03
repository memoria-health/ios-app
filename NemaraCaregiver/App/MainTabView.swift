import SwiftUI

/// Two top-level tabs: Home (Roster) and Settings (App Settings).
///
/// Uses SwiftUI's native `TabView` on iOS 26 — which automatically
/// renders as the Liquid Glass floating tab bar with backdrop blur
/// and scroll-behind content. Brand tint is applied via the
/// `.tint(NemaraColor.terra)` modifier from `NemaraCaregiverApp`.
struct MainTabView: View {
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
    }
}

#if DEBUG
#Preview {
    MainTabView().environment(AppEnvironment.preview())
}
#endif
