import CoreGraphics

/// 4px-based spacing scale mirroring theme.css's --s-* tokens.
enum Spacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let s12: CGFloat = 48
    static let s16: CGFloat = 64
}

/// Corner radii mirroring theme.css's --r-* tokens.
enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let pill: CGFloat = 999
}

/// theme.css's `--held-opacity` (4.108.0, ADR-145; design-tokens.md §Spacing /
/// radius / motion / layout): the one dimming a control takes when it cannot
/// be pressed right now — disabled, waiting out a cooldown, or busy
/// (component-kit §6.1 State — Held; since 2026-10-13 every control that
/// cannot be pressed, not only a send). An opacity on the WHOLE control —
/// fill, label and countdown together — never a way to draw quieter text:
/// only an inactive control is exempt from the contrast floor (WCAG 1.4.3).
/// 0.5 is Flutter's `KitButton`, which dimmed first, so every client dims
/// alike.
enum Held {
    static let opacity: Double = 0.5
}
