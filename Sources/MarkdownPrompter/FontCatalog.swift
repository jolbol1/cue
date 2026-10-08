import AppKit

enum FontCatalog {
    static let recommended = ["Helvetica Neue", "Arial", "Avenir Next", "Georgia", "Menlo"]

    // Cache enumeration so playback updates don't repeatedly query the font database.
    static let otherFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .filter { family in
            !family.hasPrefix(".") && !recommended.contains(where: {
                $0.caseInsensitiveCompare(family) == .orderedSame
            })
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    static func font(family: String, size: CGFloat) -> NSFont {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
            ?? NSFont(name: family, size: size)
            ?? NSFont.systemFont(ofSize: size)
    }
}
