import SwiftUI

/// SwiftUI glue for analytics screen tracking.
///
/// `.trackScreen("Roster")` logs a `screen` event when the view appears and
/// makes "Roster" the current screen context, so any button/toggle tapped
/// while it's on screen is attributed to it. Logging is a synchronous,
/// non-throwing side effect in `onAppear` — it changes no view behavior.
extension View {
    func trackScreen(_ name: String) -> some View {
        onAppear { Analytics.shared.logScreen(name) }
    }
}
