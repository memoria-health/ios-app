import SwiftUI
import UIKit

/// Nemara typography — Fraunces (serif), Inter (sans), JetBrains Mono (mono).
///
/// Fraunces is shipped as a **pre-baked SOFT-75 / opsz-144 static cut**
/// (sourced from Google Fonts with the SOFT and opsz axes pinned). This
/// satisfies the design system requirement `font-variation-settings:
/// "SOFT" 75, "opsz" 144` everywhere we render the serif, without
/// pulling in the multi-megabyte variable font.
///
/// PostScript names embedded in the bundled .ttfs:
/// - Fraunces 144pt Soft → `Fraunces144ptSoft-Regular` / `-Medium` / `-SemiBold`
/// - Inter 18pt          → `Inter18pt-Regular` / `-Medium` / `-SemiBold` / `-Bold`
/// - JetBrains Mono      → `JetBrainsMono-Regular` / `-Medium` / `-SemiBold` / `-Bold`
enum NemaraFont {

    // MARK: - Display & headlines (Fraunces / serif)
    static let display    = serif(size: 44, weight: .regular)   // 44/1.02 · -1.5
    static let largeTitle = serif(size: 32, weight: .regular)   // 32/1.05 · -1
    static let title1     = serif(size: 28, weight: .regular)   // 28/1.1 · -0.8
    static let title2     = serif(size: 22, weight: .regular)   // card heading
    static let title3     = serif(size: 18, weight: .regular)   // small serif
    static let eventTitle = serif(size: 17, weight: .semibold)  // event card title

    // MARK: - Body (Inter / sans)
    static let bodyLarge     = sans(size: 16, weight: .regular)
    static let body          = sans(size: 14, weight: .regular)
    static let bodyMedium    = sans(size: 14, weight: .medium)
    static let bodySemibold  = sans(size: 14, weight: .semibold)
    static let bodySmall     = sans(size: 13, weight: .regular)
    static let bodySmallStrong = sans(size: 13, weight: .semibold)
    static let labelStrong   = sans(size: 12, weight: .semibold)
    static let label         = sans(size: 12, weight: .medium)
    static let caption       = sans(size: 11, weight: .regular)
    static let captionStrong = sans(size: 11, weight: .semibold)

    // MARK: - Mono (JetBrains Mono)
    static let eyebrow   = mono(size: 11, weight: .semibold)
    static let monoSmall = mono(size: 10, weight: .semibold)
    static let monoMicro = mono(size: 9,  weight: .bold)
    static let monoValue = mono(size: 12, weight: .semibold)

    // MARK: - Builders

    static func serif(size: CGFloat, weight: Font.Weight) -> Font {
        .custom(serifName(weight), size: size)
    }

    static func sans(size: CGFloat, weight: Font.Weight) -> Font {
        .custom(sansName(weight), size: size)
    }

    static func mono(size: CGFloat, weight: Font.Weight) -> Font {
        .custom(monoName(weight), size: size)
    }

    // MARK: - PostScript-name resolvers

    /// Fraunces 144pt Soft ships Regular / Medium / SemiBold (weights
    /// 400 / 500 / 600). No Bold cut — bold requests round to SemiBold.
    private static func serifName(_ w: Font.Weight) -> String {
        let stem = "Fraunces144ptSoft"
        switch w {
        case .ultraLight, .thin, .light: return "\(stem)-Regular"
        case .regular:                   return "\(stem)-Regular"
        case .medium:                    return "\(stem)-Medium"
        case .semibold:                  return "\(stem)-SemiBold"
        case .bold, .heavy, .black:      return "\(stem)-SemiBold"
        default:                         return "\(stem)-Regular"
        }
    }

    /// Inter 18pt ships the full weight axis as static files.
    private static func sansName(_ w: Font.Weight) -> String {
        let stem = "Inter18pt"
        switch w {
        case .ultraLight, .thin, .light: return "\(stem)-Regular"
        case .regular:                   return "\(stem)-Regular"
        case .medium:                    return "\(stem)-Medium"
        case .semibold:                  return "\(stem)-SemiBold"
        case .bold, .heavy, .black:      return "\(stem)-Bold"
        default:                         return "\(stem)-Regular"
        }
    }

    /// JetBrains Mono ships the full weight axis.
    private static func monoName(_ w: Font.Weight) -> String {
        let stem = "JetBrainsMono"
        switch w {
        case .ultraLight, .thin, .light: return "\(stem)-Regular"
        case .regular:                   return "\(stem)-Regular"
        case .medium:                    return "\(stem)-Medium"
        case .semibold:                  return "\(stem)-SemiBold"
        case .bold, .heavy, .black:      return "\(stem)-Bold"
        default:                         return "\(stem)-Regular"
        }
    }

    // MARK: - Diagnostics

    /// Logs every Nemara font family + its registered names. Call once at
    /// app startup if fonts aren't rendering — verifies UIAppFonts wiring.
    @MainActor
    static func logRegisteredFonts() {
        let families = UIFont.familyNames.filter {
            $0.contains("Fraunces") || $0.contains("Inter") || $0.contains("JetBrains")
        }.sorted()
        for family in families {
            let names = UIFont.fontNames(forFamilyName: family).sorted()
            print("👁 \(family) → \(names)")
        }
        if families.isEmpty {
            print("⚠️ Nemara fonts not registered. Check UIAppFonts in Info.plist and the .ttf paths in the bundle.")
        }
    }
}
