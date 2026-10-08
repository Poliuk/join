import XCTest
@testable import JoinCore

final class StartingSoonPillTests: XCTestCase {
    private let blueAccent = RGBA(rgb: 0x007AFF)
    private let yellow = RGBA(rgb: 0xFFD60A)
    private let navy = RGBA(rgb: 0x1E3A8A)

    func testDefaultIsFiveMinutesInTheAccentColorWithWhiteText() {
        let pill = StartingSoonPill.default
        XCTAssertEqual(pill.minutes, 5)
        XCTAssertEqual(pill.window, 300)
        XCTAssertNil(pill.fill)
        XCTAssertNil(pill.text)
        XCTAssertEqual(pill.resolvedFill(accent: blueAccent), blueAccent)
        XCTAssertEqual(pill.resolvedText(accent: blueAccent), .white)
        XCTAssertNil(pill.contrastWarning(accent: blueAccent), "the accent with white text is never flagged")
    }

    func testMinutesStayWithinRange() {
        XCTAssertEqual(StartingSoonPill(minutes: 0).minutes, 1)
        XCTAssertEqual(StartingSoonPill(minutes: 500).minutes, 60)
        var pill = StartingSoonPill.default
        pill.minutes = -3
        XCTAssertEqual(pill.minutes, 1)
        pill.minutes = 10
        XCTAssertEqual(pill.window, 600)
        XCTAssertFalse(pill.isDefault)
    }

    func testAutomaticTextReadsOnACustomFill() {
        XCTAssertEqual(StartingSoonPill(fill: yellow).resolvedText(accent: blueAccent), StartingSoonPill.darkText)
        XCTAssertEqual(StartingSoonPill(fill: navy).resolvedText(accent: blueAccent), .white)
        XCTAssertEqual(StartingSoonPill(fill: blueAccent).resolvedText(accent: blueAccent), .white, "white stays while it reaches 3:1")
        XCTAssertEqual(StartingSoonPill(fill: RGBA(rgb: 0x34C759)).resolvedText(accent: blueAccent), StartingSoonPill.darkText)
        XCTAssertEqual(StartingSoonPill(fill: yellow, text: navy).resolvedText(accent: blueAccent), navy)
    }

    func testContrastWarningOnlyForUnreadableCustomColors() {
        XCTAssertNil(StartingSoonPill(fill: yellow).contrastWarning(accent: blueAccent))
        XCTAssertNil(StartingSoonPill(fill: blueAccent).contrastWarning(accent: blueAccent), "a custom copy of the accent isn't flagged")
        XCTAssertNil(StartingSoonPill(text: .black).contrastWarning(accent: yellow))
        let warning = StartingSoonPill(fill: yellow, text: .white).contrastWarning(accent: blueAccent)
        XCTAssertEqual(warning, "The menu bar item may be hard to read (1.4:1). Aim for 3:1, or set Text to Automatic.")
    }

    /// Automatic text reaches 3:1 on any fill, so a fill alone, swatch or Other…, is never flagged.
    func testAutomaticTextReadsOnEveryFill() {
        for value in 0...255 {
            let gray = RGBA(red: Double(value) / 255, green: Double(value) / 255, blue: Double(value) / 255)
            XCTAssertNil(StartingSoonPill(fill: gray).contrastWarning(accent: blueAccent), gray.hexString)
        }
        for swatch in StartingSoonPill.colorChoice.swatches {
            XCTAssertNil(StartingSoonPill(fill: swatch.color).contrastWarning(accent: blueAccent), swatch.name)
        }
    }

    func testColorChoiceHasBlueInsteadOfPurple() {
        XCTAssertEqual(StartingSoonPill.colorChoice.swatches.map(\.name), ["Accent color", "Red", "Orange", "Green", "Blue", "Graphite"])
        XCTAssertEqual(StartingSoonPill.colorChoice.swatches.map { $0.color?.hexString ?? "accent" },
                       ["accent", "#FF3B30", "#FF9500", "#34C759", "#007AFF", "#8E8E93"])
    }

    func testColorSelection() {
        func shown(_ pill: StartingSoonPill, otherPicked: Bool = false) -> String {
            switch pill.colorSelection(accent: blueAccent, otherPicked: otherPicked) {
            case .swatch(let swatch): return swatch.name
            case .other: return "Other…"
            }
        }
        XCTAssertEqual(shown(.default), "Accent color")
        XCTAssertEqual(shown(StartingSoonPill(fill: RGBA(rgb: 0x34C759))), "Green")
        XCTAssertEqual(shown(StartingSoonPill(fill: navy)), "Other…")
        XCTAssertEqual(shown(.default, otherPicked: true), "Other…")

        var pill = StartingSoonPill.default
        pill.pickColor(.other, accent: blueAccent)
        XCTAssertEqual(pill.fill, blueAccent, "Other… starts from the accent shown")
        XCTAssertEqual(shown(pill, otherPicked: true), "Other…")
        XCTAssertEqual(shown(pill), "Blue", "reopened, the color is a swatch's")

        pill.pickColor(.swatch(StartingSoonPill.colorChoice.swatches[1]), accent: blueAccent)
        XCTAssertEqual(pill.fill, RGBA(rgb: 0xFF3B30))
        pill.setFillColor(RGBA(rgb: 0x123456, alpha: 0.4))
        XCTAssertEqual(pill.fill, RGBA(rgb: 0x123456), "always opaque")
        pill.pickColor(.swatch(StartingSoonPill.colorChoice.swatches[0]), accent: blueAccent)
        XCTAssertTrue(pill.isDefault)
    }

    func testLegacyTextRow() {
        XCTAssertFalse(StartingSoonPill.default.showsLegacyText)
        var pill = StartingSoonPill(fill: yellow, text: navy)
        XCTAssertTrue(pill.showsLegacyText)
        pill.setTextCustom(false, accent: blueAccent)
        XCTAssertFalse(pill.showsLegacyText, "Automatic hides the row")
    }

    func testSwitchingToCustomKeepsTheColorsShown() {
        // White text on the blue accent; under 3:1 on a yellow accent, so dark text.
        for (accent, text) in [(blueAccent, RGBA.white), (RGBA(rgb: 0xFFC600), StartingSoonPill.darkText)] {
            var pill = StartingSoonPill.default
            XCTAssertEqual(pill.resolvedText(accent: accent), text, accent.hexString)
            pill.setFillCustom(true, accent: accent)
            XCTAssertEqual(pill.fill, accent, accent.hexString)
            XCTAssertEqual(pill.resolvedText(accent: accent), text, accent.hexString)
            pill.setTextCustom(true, accent: accent)
            XCTAssertEqual(pill.text, text, accent.hexString)
            XCTAssertNil(pill.contrastWarning(accent: accent), accent.hexString)
        }

        var pill = StartingSoonPill(fill: yellow, text: navy)
        pill.setFillCustom(true, accent: blueAccent)
        XCTAssertEqual(pill.fill, yellow, "already custom: the picked color stays")
        pill.setFillCustom(false, accent: blueAccent)
        pill.setTextCustom(false, accent: blueAccent)
        XCTAssertTrue(pill.isDefault)
    }

    func testCodingRoundTripsAndFillsInMissingValues() throws {
        let pill = StartingSoonPill(minutes: 10, fill: yellow, text: navy)
        let decoded = try JSONDecoder().decode(StartingSoonPill.self, from: JSONEncoder().encode(pill))
        XCTAssertEqual(decoded, pill)

        let empty = try JSONDecoder().decode(StartingSoonPill.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, .default)
        let outOfRange = try JSONDecoder().decode(StartingSoonPill.self, from: Data(#"{"minutes": 0}"#.utf8))
        XCTAssertEqual(outOfRange.minutes, 1)
    }
}
