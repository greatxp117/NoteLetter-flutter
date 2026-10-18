import CoreText
import Foundation

/// Registers the bundled Source Serif 4 / Geist / Geist Mono variable fonts
/// at runtime so they don't require UIAppFonts entries in Info.plist.
enum FontLoader {
    static func registerBundledFonts() {
        let names = [
            // The Flutter app's own files (assets/fonts, pubspec.yaml), copied
            // into the extension's bundle by its Resources phase.
            "SourceSerif4-Variable",
            "SourceSerif4-Italic-Variable",
            "Geist-Light", "Geist-Regular", "Geist-Medium", "Geist-SemiBold", "Geist-Bold",
            "GeistMono-Regular", "GeistMono-Medium",
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}
