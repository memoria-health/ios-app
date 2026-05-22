import SwiftUI

/// `@main` — Nemara caregiver iOS app entry point.
///
/// Builds the `AppEnvironment` once and injects it into the view tree
/// via the modern `@Observable`-based environment pattern. Read it in
/// any view with `@Environment(AppEnvironment.self) private var env`.
@main
struct NemaraCaregiverApp: App {
    @State private var environment: AppEnvironment

    init() {
        _environment = State(initialValue: AppEnvironment.live())
        #if DEBUG
        NemaraFont.logRegisteredFonts()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .preferredColorScheme(.light)   // design is light-only
                .tint(NemaraColor.terra)
                .background(NemaraColor.paper)
        }
    }
}
