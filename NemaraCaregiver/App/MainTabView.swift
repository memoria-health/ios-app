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
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack { RosterView() }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { AppSettingsView() }
            }
        }
        .background(NemaraColor.paper)
    }
}

#Preview {
    MainTabView().environment(AppEnvironment.preview())
}
