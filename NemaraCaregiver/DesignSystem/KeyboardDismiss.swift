import SwiftUI
import UIKit

extension View {
    /// Dismisses the keyboard when the user taps outside the focused
    /// field. Uses `simultaneousGesture` so it never swallows taps on
    /// buttons or other controls; `resignFirstResponder` targets
    /// whatever is first responder at tap time, so tapping a *different*
    /// field still focuses it (no flicker). Apply once at the app root
    /// to cover every screen's text fields and editors.
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                Self.resignFirstResponder()
            }
        )
    }

    /// Resigns whatever is currently first responder — the universal
    /// "close the keyboard" action, independent of `@FocusState`.
    static func resignFirstResponder() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil,
        )
    }
}
