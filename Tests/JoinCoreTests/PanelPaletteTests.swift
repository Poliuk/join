import XCTest
@testable import JoinCore

/// The panel's inks must read at 4.5:1 on the frost over the worst glass measured on screen.
final class PanelPaletteTests: XCTestCase {
    private struct Case {
        let dark: Bool
        let increasedContrast: Bool
        var palette: PanelPalette { .standard(dark: dark, increasedContrast: increasedContrast) }
        var glass: RGBA { dark ? PanelPalette.darkGlassEnvelope : PanelPalette.lightGlassEnvelope }
        var frostOpacity: Double { increasedContrast ? PanelPalette.increasedContrastFrostOpacity : PanelPalette.frostOpacity }
        var surface: RGBA { palette.surface(over: glass, frostOpacity: frostOpacity) }
        var name: String { "\(dark ? "dark" : "light")\(increasedContrast ? ", increased contrast" : "")" }
    }

    private let cases = [false, true].flatMap { dark in [false, true].map { Case(dark: dark, increasedContrast: $0) } }

    func testInksReadOnTheFrost() {
        for item in cases {
            let palette = item.palette
            let inks = [("primary", palette.primary), ("strong", palette.strong), ("secondary", palette.secondary),
                        ("tertiary", palette.tertiary), ("warning", palette.warning)]
            for (name, ink) in inks {
                XCTAssertGreaterThanOrEqual(ink.contrastRatio(to: item.surface), 4.5, "\(name), \(item.name)")
            }
        }
    }

    func testOutOfOfficeTextReadsOnItsStripes() {
        for item in cases {
            let stripe = item.palette.ink.withAlpha(PanelPalette.stripe).composited(over: item.surface)
            XCTAssertGreaterThanOrEqual(item.palette.tertiary.contrastRatio(to: stripe), 4.5, item.name)
        }
    }

    func testHeroCardTextReadsOnTheCard() {
        for item in cases {
            let card = item.palette.card.composited(over: item.surface)
            for ink in [item.palette.primary, item.palette.secondary, item.palette.warning] {
                XCTAssertGreaterThanOrEqual(ink.contrastRatio(to: card), 4.5, item.name)
            }
        }
    }

    /// The system accents as `controlAccentColor` reports them on macOS 27 (light, dark), plus the
    /// brighter system colors some accents resolve to.
    private let accents: [(name: String, light: RGBA, dark: RGBA)] = [
        ("blue", RGBA(rgb: 0x007AFF), RGBA(rgb: 0x007AFF)),
        ("purple", RGBA(rgb: 0x953D96), RGBA(rgb: 0xA550A7)),
        ("pink", RGBA(rgb: 0xF74F9E), RGBA(rgb: 0xF74F9E)),
        ("red", RGBA(rgb: 0xE0383E), RGBA(rgb: 0xFF5257)),
        ("orange", RGBA(rgb: 0xF7821B), RGBA(rgb: 0xF7821B)),
        ("yellow", RGBA(rgb: 0xFFC726), RGBA(rgb: 0xFFC600)),
        ("green", RGBA(rgb: 0x62BA46), RGBA(rgb: 0x62BA46)),
        ("graphite", RGBA(rgb: 0x989898), RGBA(rgb: 0x8C8C8C)),
        ("system orange", RGBA(rgb: 0xFF8D28), RGBA(rgb: 0xFF9230)),
        ("system green", RGBA(rgb: 0x34C759), RGBA(rgb: 0x30D158)),
        ("system red", RGBA(rgb: 0xFF383C), RGBA(rgb: 0xFF4245)),
        ("default blue, dark", RGBA(rgb: 0x0A84FF), RGBA(rgb: 0x0A84FF)),
    ]

    func testTheAccentButtonLabelReadsForEveryAccentAtRestAndUnderThePointer() {
        for accent in accents {
            for dark in [false, true] {
                let button = PanelPalette.accentButton(dark ? accent.dark : accent.light, dark: dark)
                let mode = "\(accent.name), \(dark ? "dark" : "light")"
                XCTAssertGreaterThanOrEqual(button.label.contrastRatio(to: button.fill), 4.5, mode)
                XCTAssertGreaterThanOrEqual(button.label.contrastRatio(to: button.hover), button.label.contrastRatio(to: button.fill), "hover can only raise the contrast: \(mode)")
                XCTAssertNotEqual(button.hover, button.fill, mode)
            }
        }
    }

    func testTheDefaultBlueKeepsAWhiteLabelAndYellowGetsADarkOne() {
        XCTAssertEqual(PanelPalette.accentButton(RGBA(rgb: 0x007AFF), dark: false).label, .white)
        XCTAssertEqual(PanelPalette.accentButton(RGBA(rgb: 0x0A84FF), dark: true).label, .white)
        XCTAssertNotEqual(PanelPalette.accentButton(RGBA(rgb: 0xFFC726), dark: false).label, .white)
    }

    func testStartingSoonCardTextReadsForEveryAccent() {
        for item in cases {
            for accent in accents {
                let card = item.palette.startingSoonCard(accent: item.dark ? accent.dark : accent.light, over: item.surface, dark: item.dark)
                for (name, ink) in [("primary", item.palette.primary), ("secondary", item.palette.secondary), ("warning", item.palette.warning)] {
                    XCTAssertGreaterThanOrEqual(ink.contrastRatio(to: card), 4.5, "\(name) on \(accent.name), \(item.name)")
                }
            }
        }
    }

    func testStartingSoonLabelIsSolvedForEveryAccent() {
        for item in cases {
            for accent in accents {
                let color = item.dark ? accent.dark : accent.light
                let card = item.palette.startingSoonCard(accent: color, over: item.surface, dark: item.dark)
                let label = PanelPalette.legibleAccent(color, on: card, dark: item.dark)
                XCTAssertGreaterThanOrEqual(label.contrastRatio(to: card), 4.6, "\(accent.name), \(item.name)")
            }
        }
    }
}
