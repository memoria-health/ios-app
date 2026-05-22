import CoreGraphics

/// Nemara spacing scale. Per `nemara_design_system.html` §04 Geometry.
///
/// Use the named tokens rather than raw numbers at call sites — keeps
/// rhythm consistent across screens.
enum NemaraSpacing {
    static let xxs: CGFloat = 4
    static let xs:  CGFloat = 8
    static let sm:  CGFloat = 12
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 20
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let huge: CGFloat = 56
}
