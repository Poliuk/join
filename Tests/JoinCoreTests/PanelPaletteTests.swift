import Testing
@testable import JoinCore

/// The panel's inks must read at 4.5:1 on the frost over the worst glass measured on screen.
struct PanelPaletteTests {
    /// The panel's light or dark mode, with or without Increase Contrast, which thickens the frost. The thinner
    /// frost over the menu material before macOS 26 (`legacyMaterialFrostOpacity`) isn't checked: that material
    /// was never measured, and the glass envelope doesn't stand in for it (at 40 % over it, inks dip to 4.0:1).
    struct Mode: Sendable, CustomTestStringConvertible {
        let dark: Bool
        let increasedContrast: Bool

        var palette: PanelPalette { .standard(dark: dark, increasedContrast: increasedContrast) }
        var glass: RGBA { dark ? PanelPalette.darkGlassEnvelope : PanelPalette.lightGlassEnvelope }
        var frostOpacity: Double { increasedContrast ? PanelPalette.increasedContrastFrostOpacity : PanelPalette.frostOpacity }
        var surface: RGBA { palette.surface(over: glass, frostOpacity: frostOpacity) }
        var testDescription: String { "\(dark ? "dark" : "light")\(increasedContrast ? ", increased contrast" : "")" }
    }

    static let modes = [false, true].flatMap { dark in [false, true].map { Mode(dark: dark, increasedContrast: $0) } }

    /// Every ink on the frost, the out-of-office text on its stripes, and the hero card's text on the card.
    @Test(arguments: modes)
    func inksReadOnEverySurface(_ mode: Mode) {
        let palette = mode.palette
        let frost = [("primary", palette.primary), ("strong", palette.strong), ("secondary", palette.secondary),
                     ("tertiary", palette.tertiary), ("warning", palette.warning)]
        for (name, ink) in frost {
            #expect(ink.contrastRatio(to: mode.surface) >= 4.5, "\(name) on the frost")
        }

        let stripe = palette.ink.withAlpha(PanelPalette.stripe).composited(over: mode.surface)
        #expect(palette.tertiary.contrastRatio(to: stripe) >= 4.5, "out of office on its stripes")

        let card = palette.card.composited(over: mode.surface)
        for (name, ink) in [("primary", palette.primary), ("secondary", palette.secondary), ("warning", palette.warning)] {
            #expect(ink.contrastRatio(to: card) >= 4.5, "\(name) on the hero card")
        }
    }

    /// A system accent as `controlAccentColor` reports it on macOS 27, in light and dark mode.
    struct Accent: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let light: RGBA
        let dark: RGBA

        init(_ name: String, _ light: UInt32, _ dark: UInt32) {
            testDescription = name
            self.light = RGBA(rgb: light)
            self.dark = RGBA(rgb: dark)
        }

        func color(dark: Bool) -> RGBA { dark ? self.dark : light }
    }

    /// The system accents, plus the brighter system colors some accents resolve to.
    static let accents = [
        Accent("blue", 0x007AFF, 0x007AFF),
        Accent("purple", 0x953D96, 0xA550A7),
        Accent("pink", 0xF74F9E, 0xF74F9E),
        Accent("red", 0xE0383E, 0xFF5257),
        Accent("orange", 0xF7821B, 0xF7821B),
        Accent("yellow", 0xFFC726, 0xFFC600),
        Accent("green", 0x62BA46, 0x62BA46),
        Accent("graphite", 0x989898, 0x8C8C8C),
        Accent("system orange", 0xFF8D28, 0xFF9230),
        Accent("system green", 0x34C759, 0x30D158),
        Accent("system red", 0xFF383C, 0xFF4245),
        Accent("default blue, dark", 0x0A84FF, 0x0A84FF),
    ]

    @Test(arguments: accents, [false, true])
    func theAccentButtonLabelReadsAtRestAndUnderThePointer(_ accent: Accent, dark: Bool) {
        let button = PanelPalette.accentButton(accent.color(dark: dark), dark: dark)
        #expect(button.label.contrastRatio(to: button.fill) >= 4.5)
        #expect(button.label.contrastRatio(to: button.hover) >= button.label.contrastRatio(to: button.fill),
                "hover can only raise the contrast")
        #expect(button.hover != button.fill)
    }

    /// The contrast tests alone would pass if the default blue switched to a near-black label.
    @Test(arguments: [
        ("the default blue", 0x007AFF, false, true),
        ("the default blue, dark", 0x0A84FF, true, true),
        ("yellow", 0xFFC726, false, false),
    ] as [(String, UInt32, Bool, Bool)])
    func theDefaultBlueKeepsAWhiteLabelAndYellowGetsADarkOne(_ name: String, accent: UInt32, dark: Bool, whiteLabel: Bool) {
        #expect((PanelPalette.accentButton(RGBA(rgb: accent), dark: dark).label == .white) == whiteLabel)
    }

    /// The starting-soon card's text reads on its accent tint, and its label is solved to 4.6:1.
    @Test(arguments: modes, accents)
    func theStartingSoonCardReads(_ mode: Mode, _ accent: Accent) {
        let color = accent.color(dark: mode.dark)
        let card = mode.palette.startingSoonCard(accent: color, over: mode.surface, dark: mode.dark)
        for (name, ink) in [("primary", mode.palette.primary), ("secondary", mode.palette.secondary), ("warning", mode.palette.warning)] {
            #expect(ink.contrastRatio(to: card) >= 4.5, "\(name)")
        }
        #expect(PanelPalette.legibleAccent(color, on: card, dark: mode.dark).contrastRatio(to: card) >= 4.6, "the label")
    }
}
