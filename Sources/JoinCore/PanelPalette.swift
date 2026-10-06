import Foundation

/// The menu bar panel's colors. The panel is Liquid Glass with a frost laid over it, so its text sits on a
/// known surface whatever is behind the window: clear glass let wallpapers and windows through at any
/// brightness, and the old grays, tuned for a solid panel, fell to 1–2:1 on it. Five inks replace them.
/// Each keeps 4.5:1 on the frost over the brightest dark glass and the darkest light glass measured on
/// screen (`darkGlassEnvelope`, `lightGlassEnvelope`). The frost is light enough to keep the glass
/// showing, so a backdrop brighter (dark mode) or darker (light mode) than those can dip below that.
public struct PanelPalette: Equatable, Sendable {
    /// Header date, meeting titles, button labels, row icons.
    public var primary: RGBA
    /// Start times, the active header glyph, the paused message.
    public var strong: RGBA
    /// Section headings, the hero card's label, time range and location, the bell and gear.
    public var secondary: RGBA
    /// End times, date subtitles, out-of-office rows.
    public var tertiary: RGBA
    /// "Overlaps …".
    public var warning: RGBA
    /// The bar of an out-of-office row; decorative.
    public var mutedBar: RGBA
    /// Opaque; drawn over the glass at `frostOpacity`.
    public var frost: RGBA
    /// White in dark mode, black in light mode: the base of every translucent fill.
    public var ink: RGBA
    /// The hero card. In light mode it's white, away from the dark text, so it lifts the text's contrast.
    public var card: RGBA

    /// Frost opacity over Liquid Glass: half the glass still shows. Chosen on screen; 70% kept more
    /// contrast margin.
    public static let frostOpacity = 0.50
    /// Frost opacity with Increase Contrast on. Reduce Transparency makes the frost opaque.
    public static let increasedContrastFrostOpacity = 0.88
    /// Frost opacity over the pre-Liquid Glass menu material, which is already thick.
    public static let legacyMaterialFrostOpacity = 0.40

    /// The lightest glass measured behind dark-mode text (over a white window) and the darkest behind
    /// light-mode text (over a dark window), on screenshots of the panel on macOS 27.
    public static let darkGlassEnvelope = RGBA(rgb: 0x7A7A7A)
    public static let lightGlassEnvelope = RGBA(rgb: 0x8D8E8F)

    // Fills, as opacities of `ink`. They match the system fills (systemFill, secondarySystemFill,
    // tertiarySystemFill, separatorColor) but stay fixed, so their contrast is predictable.
    public static let separator = 0.098
    public static let buttonFill = 0.098
    public static let buttonHoverFill = 0.16
    public static let rowButtonFill = 0.078
    public static let rowButtonHoverFill = 0.14
    public static let hoverFill = 0.078
    public static let stripe = 0.047

    /// Borders under Increase Contrast: the panel's outline, cards and dividers, and every control.
    public static func increasedContrastSeparator(dark: Bool) -> Double { dark ? 0.40 : 0.45 }
    public static func increasedContrastControlBorder(dark: Bool) -> Double { dark ? 0.45 : 0.50 }
    public static func progressTrack(dark: Bool) -> Double { dark ? 0.12 : 0.11 }

    public static func standard(dark: Bool, increasedContrast: Bool = false) -> PanelPalette {
        if dark {
            return PanelPalette(
                primary: RGBA(rgb: increasedContrast ? 0xFFFFFF : 0xF5F5F7),
                strong: RGBA(rgb: increasedContrast ? 0xF5F5F7 : 0xEBEBF0),
                secondary: RGBA(rgb: increasedContrast ? 0xE0E0E5 : 0xCCCCD1),
                tertiary: RGBA(rgb: increasedContrast ? 0xD2D2D7 : 0xC8C8CD),
                warning: RGBA(rgb: increasedContrast ? 0xFFC46E : 0xF7C37B),
                mutedBar: RGBA(rgb: 0x6E6E73),
                frost: RGBA(rgb: 0x1E1E20),
                ink: .white,
                card: RGBA.white.withAlpha(0.06)
            )
        }
        return PanelPalette(
            primary: RGBA(rgb: increasedContrast ? 0x000000 : 0x1D1D1F),
            strong: RGBA(rgb: increasedContrast ? 0x1D1D1F : 0x2A2A2E),
            secondary: RGBA(rgb: increasedContrast ? 0x38383D : 0x4D4D52),
            tertiary: RGBA(rgb: increasedContrast ? 0x3E3E43 : 0x4B4B4F),
            warning: RGBA(rgb: increasedContrast ? 0x6E3800 : 0x804100),
            mutedBar: RGBA(rgb: 0xA2A4AA),
            frost: RGBA(rgb: 0xFAFAFC),
            ink: .black,
            card: RGBA.white.withAlpha(0.55)
        )
    }

    /// The frost drawn over `glass`.
    public func surface(over glass: RGBA, frostOpacity: Double = PanelPalette.frostOpacity) -> RGBA {
        frost.withAlpha(frostOpacity).composited(over: glass)
    }

    /// How strongly the starting-soon card is tinted with `accent`. The tint sits on the regular card: in
    /// light mode that's white, and 12% keeps the card's text above 4.5:1 for every accent. In dark mode
    /// it's up to 10%, less for bright accents (yellow, orange, green), down to none, until the card's
    /// text reads at 4.5:1 over the brightest glass; the accent border still marks the card.
    public func startingSoonTint(accent: RGBA, dark: Bool) -> Double {
        guard dark else { return 0.12 }
        let cardSurface = card.composited(over: surface(over: Self.darkGlassEnvelope))
        for percent in stride(from: 10, to: 0, by: -1) {
            let tint = Double(percent) / 100
            let tinted = accent.withAlpha(tint).composited(over: cardSurface)
            if [primary, secondary, warning].allSatisfy({ $0.contrastRatio(to: tinted) >= 4.5 }) { return tint }
        }
        return 0
    }

    /// The starting-soon card over `surface`: the regular card, then the accent tint.
    public func startingSoonCard(accent: RGBA, over surface: RGBA, dark: Bool) -> RGBA {
        accent.withAlpha(startingSoonTint(accent: accent, dark: dark)).composited(over: card.composited(over: surface))
    }

    /// The accent stepped toward white (dark mode) or black (light mode) until it reads at `minimum` on
    /// `surface`, for the starting-soon card's label. A fixed blend only suited the default blue.
    public static func legibleAccent(_ accent: RGBA, on surface: RGBA, dark: Bool, minimum: Double = 4.6) -> RGBA {
        var color = accent
        var amount = 0.0
        while color.contrastRatio(to: surface) < minimum, amount < 1 {
            amount = min(amount + 0.05, 1)
            color = accent.mixed(with: dark ? .white : .black, amount: amount)
        }
        return color
    }

    /// The prominent (accent) button: its fill, its fill under the pointer, and its label.
    public struct AccentButton: Equatable, Sendable {
        public var fill: RGBA
        public var hover: RGBA
        public var label: RGBA
    }

    /// Solves the prominent button for any accent: the accent darkened a little (white on the plain
    /// default blue is only 3.65:1 in dark mode, 4.0:1 in light mode), the better of white and near-black
    /// as its label, and the fill stepped further away from the label until it reads at 4.5:1. The hover
    /// fill moves further the same way, so pointing at the button can only raise the contrast.
    public static func accentButton(_ accent: RGBA, dark: Bool) -> AccentButton {
        let nearBlack = RGBA(rgb: 0x1D1D1F)
        let base = accent.withAlpha(1).mixed(with: .black, amount: dark ? 0.20 : 0.15)
        let label = base.mostLegible(of: .white, nearBlack)
        let away: RGBA = label == .white ? .black : .white
        var fill = base
        var amount = 0.0
        while label.contrastRatio(to: fill) < 4.5, amount < 1 {
            amount = min(amount + 0.05, 1)
            fill = base.mixed(with: away, amount: amount)
        }
        return AccentButton(fill: fill, hover: fill.mixed(with: away, amount: 0.08), label: label)
    }
}
