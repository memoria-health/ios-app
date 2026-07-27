import Foundation

/// Full ISO 3166-1 country list for the onboarding/signup country picker.
///
/// The wire value is the 2-letter alpha-2 code; the backend derives the
/// data-residency `region` (US/IN) from it. Names come from `Locale` so we
/// localize for free and never hand-maintain 200+ labels. Mirrors the web
/// `lib/countries.ts`.
enum Countries {
    struct Option: Identifiable, Hashable, Sendable {
        let code: String
        let name: String
        var id: String { code }
    }

    /// Every ISO country as `{ code, name }`, sorted by localized name.
    /// Filtered to 2-letter alpha codes so macro-regions (e.g. "419") drop out.
    static let all: [Option] = {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
            .compactMap { code -> Option? in
                guard let name = Locale.current.localizedString(forRegionCode: code) else { return nil }
                return Option(code: code, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// Localized display name for a single code (falls back to the raw code).
    static func name(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}
