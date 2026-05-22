import CoreGraphics

/// Nemara corner radii. Per `nemara_design_system.html` §04 Geometry.
enum NemaraRadius {
    /// 6 — chips, small inset surfaces.
    static let sm: CGFloat = 6
    /// 10 — text fields, buttons.
    static let md: CGFloat = 10
    /// 14 — primary card.
    static let lg: CGFloat = 14
    /// 20 — extra-large surfaces.
    static let xl: CGFloat = 20
    /// Pill (effectively infinite); use a large fixed value so the SwiftUI
    /// renderer settles. UIKit ≥ height/2 reads as a true pill.
    static let pill: CGFloat = 999
}
