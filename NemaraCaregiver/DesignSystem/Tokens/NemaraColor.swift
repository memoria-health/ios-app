import SwiftUI

/// Nemara color palette — single source of truth lives in the asset catalog
/// (`NemaraCaregiver/Resources/Assets.xcassets/Colors/`). Every token is a
/// named `.colorset`; this Swift facade just looks them up by name so feature
/// code can keep using `NemaraColor.paper` etc.
///
/// Why asset-catalog-as-source: iOS launch screens can only reference
/// asset-catalog colors, not Swift code. Putting the canonical hex in the
/// catalog means the launch screen and the in-app palette literally read
/// the same byte.
///
/// "Warm cream paper carries the interface. Terra rust is the brand
/// primary. Warm near-black is the action color. Sky blue is the
/// dedicated routine-event palette."
enum NemaraColor {

    // MARK: - Surfaces
    static let paper      = Color("Colors/Paper",      bundle: .main)
    static let paperDim   = Color("Colors/PaperDim",   bundle: .main)
    static let card       = Color("Colors/Card",       bundle: .main)
    static let cardAlt    = Color("Colors/CardAlt",    bundle: .main)

    // MARK: - Ink (text)
    static let ink        = Color("Colors/Ink",        bundle: .main)
    static let ink2       = Color("Colors/Ink2",       bundle: .main)
    static let ink3       = Color("Colors/Ink3",       bundle: .main)
    static let ink4       = Color("Colors/Ink4",       bundle: .main)
    static let line       = Color("Colors/Line",       bundle: .main)

    // MARK: - Brand · terra rust (primary)
    static let terra      = Color("Colors/Terra",      bundle: .main)
    static let terraSoft  = Color("Colors/TerraSoft",  bundle: .main)
    static let terraDeep  = Color("Colors/TerraDeep",  bundle: .main)
    static let terraInk   = Color("Colors/TerraInk",   bundle: .main)

    // MARK: - Action · warm near-black (primary CTA, active states)
    static let action     = Color("Colors/Action",     bundle: .main)
    static let actionSoft = Color("Colors/ActionSoft", bundle: .main)
    static let actionInk  = Color("Colors/ActionInk",  bundle: .main)

    // MARK: - Routine · sky blue (dedicated for routine events)
    static let sky        = Color("Colors/Sky",        bundle: .main)
    static let skySoft    = Color("Colors/SkySoft",    bundle: .main)

    // MARK: - Behaviour · plum  /  Care · sage
    // Muted on purpose so all four category hues carry the same weight
    // beside terra and sky; a category chip should read as one family, not
    // as one shouting colour and three quiet ones.
    static let plum       = Color("Colors/Plum",       bundle: .main)
    static let plumSoft   = Color("Colors/PlumSoft",   bundle: .main)
    static let sage       = Color("Colors/Sage",       bundle: .main)
    static let sageSoft   = Color("Colors/SageSoft",   bundle: .main)

    // MARK: - Semantic aliases
    static let success    = Color("Colors/Success",    bundle: .main)
    static let warning    = Color("Colors/Warning",    bundle: .main)
    static let danger     = Color("Colors/Danger",     bundle: .main)  // = terra
    static let info       = Color("Colors/Info",       bundle: .main)  // = sky
}
