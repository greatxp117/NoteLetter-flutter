import SwiftUI
#if canImport(UIKit)
import UIKit
/// The platform's dynamic-colour type. Two of them, one token layer.
///
/// The macOS host drew the app's one colour it can draw — the feather — as
/// `Color(red: 0.48, green: 0.16, blue: 0.13)` under a comment reading
/// "brick-700", which is `#7A2921` and brick-700 is `#6E1F18`. It was written
/// that way because this file was iOS-only, so the Mac target had no token to
/// reach for; it did not flip either, on a platform that has had a dark mode
/// for a decade. Making the file portable is smaller than it looks — the
/// palette is the same, and only the two constructors differ (4.34.7).
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

extension PlatformColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255
        let b = CGFloat(rgb & 0x0000FF) / 255
        #if canImport(UIKit)
        self.init(red: r, green: g, blue: b, alpha: alpha)
        #else
        // sRGB explicitly: NSColor's `init(red:…)` is deviceRGB, which is not
        // the space these hexes were measured in.
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
        #endif
    }
}

extension Color {
    /// One token, two appearances. The pair is resolved by the SYSTEM at draw
    /// time on both platforms, which is what makes a token flip at all.
    static func token(light: PlatformColor, dark: PlatformColor) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
        #endif
    }
}

/// Design tokens mirroring NoteLetter-web's theme.css custom properties.
enum Theme {
    // Surfaces
    static let bg = Color.token(light: PlatformColor(hex: "FAFAF7"), dark: PlatformColor(hex: "14171F"))
    static let surface = Color.token(light: PlatformColor.white, dark: PlatformColor(hex: "1F2330"))
    static let surfaceRaised = Color.token(light: PlatformColor(hex: "F3F2EC"), dark: PlatformColor(hex: "2C3142"))
    static let surfaceSunken = Color.token(light: PlatformColor(hex: "E9E7DF"), dark: PlatformColor(hex: "0B0D13"))

    // Text
    static let fg = Color.token(light: PlatformColor(hex: "14171F"), dark: PlatformColor(hex: "FAFAF7"))
    static let fgMuted = Color.token(light: PlatformColor(hex: "2C3142"), dark: PlatformColor(white: 1, alpha: 0.65))
    // --fg-subtle is the quietest TEXT tier, not a dot: 170 web rules set it as
    // 9–18px copy, so 4.31.0 (ADR-068) moved it off --ink-300 (3.15:1 in light)
    // onto --ink-350 and lifted the dark alpha to .52.
    static let fgSubtle = Color.token(light: PlatformColor(hex: "686E7D"), dark: PlatformColor(white: 1, alpha: 0.52))
    static let fgLede = Color.token(light: PlatformColor(hex: "4E5566"), dark: PlatformColor(white: 1, alpha: 0.72))

    // Lines
    static let border = Color.token(light: PlatformColor(hex: "14171F", alpha: 0.10), dark: PlatformColor(white: 1, alpha: 0.10))
    static let borderStrong = Color.token(light: PlatformColor(hex: "14171F", alpha: 0.18), dark: PlatformColor(white: 1, alpha: 0.18))

    // Primary CTA — brick (400 is vermilion #D9482F since 4.29.0, ADR-066)
    static let accent = Color.token(light: PlatformColor(hex: "9D352D"), dark: PlatformColor(hex: "D9482F"))
    static let accentHover = Color.token(light: PlatformColor(hex: "6E1F18"), dark: PlatformColor(hex: "E85940"))
    static let accentFg = Color.token(light: PlatformColor(hex: "FAFAF7"), dark: PlatformColor(hex: "0B0D13"))
    static let accentSoft = Color.token(light: PlatformColor(hex: "9D352D", alpha: 0.10), dark: PlatformColor(hex: "D9482F", alpha: 0.16))

    // Secondary CTA + chrome — plum
    static let secondary = Color.token(light: PlatformColor(hex: "2D1F2E"), dark: PlatformColor(white: 1, alpha: 0.08))
    static let secondaryHover = Color.token(light: PlatformColor(hex: "3F2C3E"), dark: PlatformColor(white: 1, alpha: 0.14))
    static let secondaryFg = Color.token(light: PlatformColor(hex: "FAFAF7"), dark: PlatformColor(hex: "FAFAF7"))
    static let chrome = Color.token(light: PlatformColor(hex: "2D1F2E"), dark: PlatformColor(hex: "2D1F2E"))
    static let chromeFg = Color.token(light: PlatformColor(hex: "FAFAF7"), dark: PlatformColor(hex: "FAFAF7"))

    // Shelves / positive — sage
    static let positive = Color.token(light: PlatformColor(hex: "6F8159"), dark: PlatformColor(hex: "93A87A"))
    // The `--positive-chip-*` pair (the shelf chip fill and its text). Dark is a
    // translucent wash of the DARK-mode positive step and its own lighter text
    // step, --sage-300 — the positive family's answer to --brick-300 (4.31.0,
    // ADR-068), not the light-mode chip reused.
    static let sageBg = Color.token(light: PlatformColor(hex: "E2E8DC"), dark: PlatformColor(hex: "93A87A", alpha: 0.16))
    static let sageFg = Color.token(light: PlatformColor(hex: "495936"), dark: PlatformColor(hex: "A8BC8F"))

    // The family TEXT step (4.32.0, ADR-069). --positive is a dot, a bar and a
    // 3px rule; set as copy it is 4.23:1 in light, so every hue the app writes
    // in has a second step. `Text(...).foregroundStyle(Theme.positive)` was
    // doing exactly that in two places — gated now by the ROLE direction of
    // token_contrast_check.py, which reads this client's views.
    static let positiveText = Color.token(light: PlatformColor(hex: "495936"), dark: PlatformColor(hex: "A8BC8F"))
    /// The accent's TEXT step, and the same argument: `--accent` is a fill, a
    /// 3px rule and a glyph, and set as 9–13px copy it measures 3.16–4.23:1.
    /// Five views drew accent copy in `accent` itself — the listen panel's
    /// active transcript line, the speed-read preview's current word, its
    /// pivot, the sweep review's "Add all N" and Sources' "See all". Four
    /// moved here; the pivot stayed and says why. ROLE could not object to any
    /// of them: it fails a token drawn as text against a token floored as a
    /// GRAPHIC, and `--accent` carries no such claim (4.34.6, ADR-069).
    static let accentText = Color.token(light: PlatformColor(hex: "6E1F18"), dark: PlatformColor(hex: "EE7B62"))

    // Status — the three severities `level` carries (data-model.md
    // /activity_events). `warning` has been a level since 2.5.0 (ADR-014) with
    // no token to render it on any client; 4.21.0 (ADR-057) gives it one.
    // 4.29.0 (ADR-066) gives it a colour of its OWN — ochre, not brick. Once
    // the accent became vermilion, a brick-family warning sat beside critical
    // and read as a dimmer error, on the one screen that must tell them apart.
    static let warning = Color.token(light: PlatformColor(hex: "8A5A12"), dark: PlatformColor(hex: "F2A63B"))
    /// The severity when it is DRAWN. Not the reference's `--critical`, which
    /// is the fill of a destructive control: this client has none, and every
    /// one of the thirteen sites that reached for it wrote WORDS. The fill
    /// step measures 3.99:1 on a raised card and 4.16:1 inside its own tint in
    /// dark — under the small-text floor on both grounds a failure message
    /// lands on. Same shape as `accentText` above (4.35.0, ADR-072).
    static let criticalText = Color.token(light: PlatformColor(hex: "9D352D"), dark: PlatformColor(hex: "F08C7E"))
    /// The FILL of a destructive control, and its label (§6.1 danger). Absent
    /// here until §18's confirmation gave this client its first filled
    /// destructive control (2026-09-23): before that, nothing painted it, and
    /// a token nothing draws is a claim nobody checks. Never set as copy —
    /// that is `criticalText`, above, for the reason given there. Dark takes
    /// ink on the lifted step, because paper-50 on #E4695E is 3.10:1.
    static let critical = Color.token(light: PlatformColor(hex: "9D352D"), dark: PlatformColor(hex: "E4695E"))
    static let criticalFg = Color.token(light: PlatformColor(hex: "FAFAF7"), dark: PlatformColor(hex: "0B0D13"))

    /// §15's scrim, which §18 borrows: `rgba(11,13,19,0.42)` in both themes.
    /// A scrim, not a surface — the ground beneath it is unknown by
    /// construction, so it has no palette identity and does not flip.
    static let scrim = Color(PlatformColor(hex: "0B0D13", alpha: 0.42))

    // Event-family tones — the four node colours component-kit §4.2 names.
    // Plum reads as near-black on the dark ground, so dark takes the lifted
    // step: a family colour that vanishes in dark mode is the feed failing at
    // the one thing it does.
    //
    // Three of the four were missing until 4.34.5 and the feed drew them
    // anyway, out of whatever token was nearest: the sage tone was `positive`
    // (the sage-500 FILL step, where the tone is sage-700 — a whole step off in
    // light) and the ink tone was `fgSubtle` (where the tone is --fg-muted, a
    // step off in both themes). MIRROR listed all three as absent and failed
    // nothing, correctly — absence is not drift. What made them owed is the
    // lesson LITERAL taught on Flutter at 4.34.4: read the views before
    // believing a missing token is a surface this client does not have.
    /// The family's TEXT step, like the other three — not the fill. It was
    /// `accent` here and on the reference, which is 3.67:1 on --surface in
    /// dark: under the floor its siblings clear (4.34.9).
    static let toneAccent = accentText
    static let toneSage = Color.token(light: PlatformColor(hex: "495936"), dark: PlatformColor(hex: "93A87A"))
    static let tonePlum = Color.token(light: PlatformColor(hex: "2D1F2E"), dark: PlatformColor(hex: "C9A6C6"))
    static let toneInk = fgMuted

    // The accent chip (`--accent-chip-*`) — the eyebrow chip and the file
    // badge. `--accent-chip-fg` is its own step because the accent FILL set as
    // 12px copy inside its own tint is 3.16:1 in dark (ADR-067), and it is what
    // `.proc-pill.work` labels an in-flight status with. 4.34.5 introduced
    // these to iOS on the reading that `StatusChip` was a mis-spelled accent
    // chip; it is the `.proc-pill`, a different component, and 4.34.8 moved it
    // back to an `--accent-soft` fill with a tone per state.
    static let accentChipBg = Color.token(light: PlatformColor(hex: "F6E1DC"),
                                          dark: PlatformColor(hex: "D9482F", alpha: 0.16))
    static let accentChipFg = Color.token(light: PlatformColor(hex: "6E1F18"), dark: PlatformColor(hex: "EE7B62"))
    static let accentChipBorder = Color.token(light: PlatformColor(hex: "9D352D", alpha: 0.22),
                                              dark: PlatformColor(hex: "D9482F", alpha: 0.32))

    // `--rule` — a hairline INSIDE a surface, quieter than --border, which
    // separates one. The single `Divider()` in this app drew the system
    // separator, a colour from a palette that is not ours.
    static let rule = Color.token(light: PlatformColor(hex: "14171F", alpha: 0.06),
                                  dark: PlatformColor(white: 1, alpha: 0.06))

    // `--link` / `--link-decor` — an underlined control whose colour alone
    // would not read as one: `--link` is near-black ink in light. The support
    // footer (kit §13) is the first thing outside the reader to draw a link;
    // the reader's links stay in `ChunkHTMLView`'s embedded stylesheet, which
    // spells its own tokens out because a WKWebView inherits nothing (4.34.6).
    static let link = Color.token(light: PlatformColor(hex: "14171F"), dark: PlatformColor(hex: "FAFAF7"))
    static let linkDecor = Color.token(light: PlatformColor(hex: "9D352D"), dark: PlatformColor(hex: "D9482F"))

    // ── Deliberately not mirrored, and why ───────────────────────────────────
    // MIRROR prints every reference token this client does not declare and
    // fails on none of them, because a client draws a subset of the app. That
    // is only true while somebody has checked — so the checked answers live
    // here rather than in the gate's silence (4.34.5):
    //
    //   --hover, --hover-strong, --critical-hover, --secondary-hover(*),
    //   --solid-hover        there is no hover on a touch surface. (*declared,
    //                        left over from an earlier pass.)
    //   --solid, --solid-fg  no neutral solid control exists here; the two
    //                        buttons are PrimaryButton (accent) and
    //                        SecondaryButton (plum).
    //   --highlight-strong   the reader has no passage mark yet, so even
    //                        --highlight (declared) is currently undrawn.
    //   --positive-chip-border  the shelf chip is borderless here; the border is
    //                        composition drift from the web chip, not a missing
    //                        token, and belongs to the /parity ios pass.

    // Decorative
    /// The wax seal and its siblings — decorative, floored at the 3:1 a graphic
    /// gets (ADR-069). The app has no seal glyph of its own yet; the macOS
    /// host's feather is the first, and it is why this token is here.
    static let seal = Color.token(light: PlatformColor(hex: "6E1F18"),
                                  dark: PlatformColor(hex: "EE7B62"))
    static let highlight = Color.token(light: PlatformColor(hex: "9D352D", alpha: 0.15), dark: PlatformColor(hex: "D9482F", alpha: 0.24))
}

/// `--shadow-1`, `--shadow-2` and `--letterpress` (`theme.css`). The shadows
/// are cast in ink-700 at low alpha in **both** themes — warm-tinted, never
/// black — and the letterpress edge is not redefined for dark either; both are
/// the reference's own choices, mirrored as Flutter's `AppShadows` mirrors
/// them. Each CSS shadow is two layers, so each is two `.shadow` calls.
extension View {
    func shadow1() -> some View {
        shadow(color: Color(PlatformColor(hex: "14171F", alpha: 0.04)), radius: 0, y: 1)
            .shadow(color: Color(PlatformColor(hex: "14171F", alpha: 0.06)), radius: 1, y: 1)
    }

    /// CSS's `-4px` spread has no SwiftUI spelling; a blur of 14 at radius 5
    /// (SwiftUI's radius is roughly half the CSS blur) with the offset kept is
    /// the nearest drawable, and it is only ever cast by a small tile here.
    func shadow2() -> some View {
        shadow(color: Color(PlatformColor(hex: "14171F", alpha: 0.04)), radius: 0, y: 1)
            .shadow(color: Color(PlatformColor(hex: "14171F", alpha: 0.10)), radius: 5, y: 4)
    }

    func letterpress() -> some View {
        shadow(color: Color(PlatformColor(white: 1, alpha: 0.5)), radius: 0, y: 1)
    }
}

// iOS only: the macOS host compiles this file for its colours but not
// `Spacing.swift`, so `Radius` does not exist there — and it draws no field.
#if canImport(UIKit)
extension View {
    /// A one-line text field on the app's own ground: `--surface` with a
    /// `--border` edge. `.roundedBorder` paints the system's field instead —
    /// black in dark (Settings' "Add topic", ruled 2026-10-14; the Add Source
    /// and share sheets' fields drew the same). About 36pt tall, so the
    /// curvature rule's 0.25 × height is 9, which rounds to `Radius.md` (10).
    func kitField() -> some View {
        textFieldStyle(.plain)
            .foregroundStyle(Theme.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
#endif
