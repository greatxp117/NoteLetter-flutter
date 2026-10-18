import SwiftUI
import UIKit

/// Font family names mirroring theme.css's --font-serif / --font-sans / --font-mono.
enum AppFont {
    static let serif = "SourceSerif4Roman-Regular"
    static let serifItalic = "SourceSerif4Italic-Italic"
    static let sans = "Geist-Regular"
    static let mono = "GeistMono-Regular"
}

extension Font {
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.serif, size: size).weight(weight)
    }
    static func serifItalic(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.serifItalic, size: size).weight(weight)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.sans, size: size).weight(weight)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.mono, size: size).weight(weight)
    }

    /// The serif at an EXPLICIT optical size and weight — the reference's
    /// `font-variation-settings: "opsz" N` (§7's title 30, its standfirst and
    /// rows 18). Left to itself CoreText chooses the optical size, and that
    /// is not the number web names, so a screen that the kit sets by opsz
    /// draws a different cut of the same face.
    static func serif(_ size: CGFloat, weight: CGFloat, opsz: CGFloat, italic: Bool = false) -> Font {
        Font(SerifAxes.uiFont(size, weight: weight, opsz: opsz, italic: italic) as CTFont)
    }
}

/// Source Serif 4's variation axes: `wght` 200–900 and `opsz` 8–60 (default
/// 20), in both the roman and the italic file.
enum SerifAxes {
    static let wght = 0x7767_6874   // 'wght'
    static let opsz = 0x6F70_737A   // 'opsz'

    static func uiFont(_ size: CGFloat, weight: CGFloat, opsz: CGFloat, italic: Bool) -> UIFont {
        let name = italic ? AppFont.serifItalic : AppFont.serif
        let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: name,
            variation: [wght: weight, Self.opsz: opsz],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// Semantic text styles mirroring theme.css's .h1/.h2/.eyebrow/.lede/etc classes.
extension View {
    func h1Style() -> some View {
        font(.serif(32, weight: .semibold))
            .tracking(-0.4)
            .foregroundStyle(Theme.fg)
    }

    func h2Style() -> some View {
        font(.serif(26, weight: .semibold))
            .tracking(-0.3)
            .foregroundStyle(Theme.fg)
    }

    func h3Style() -> some View {
        font(.serif(21, weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(Theme.fg)
    }

    func h4Style() -> some View {
        font(.serif(17, weight: .semibold))
            .foregroundStyle(Theme.fg)
    }

    func eyebrowStyle() -> some View {
        font(.sans(11, weight: .semibold))
            .tracking(2.0)
            .textCase(.uppercase)
            .foregroundStyle(Theme.fgMuted)
    }

    func ledeStyle() -> some View {
        font(.serifItalic(17))
            .foregroundStyle(Theme.fgLede)
    }

    func bodyStyle() -> some View {
        font(.sans(16))
            .foregroundStyle(Theme.fg)
    }

    func bodyReadingStyle() -> some View {
        font(.serif(18))
            .lineSpacing(6)
            .foregroundStyle(Theme.fg)
    }

    func metaStyle() -> some View {
        font(.sans(13))
            .foregroundStyle(Theme.fgSubtle)
    }

    func capsLabelStyle() -> some View {
        font(.mono(11, weight: .medium))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Theme.fgMuted)
    }
}
