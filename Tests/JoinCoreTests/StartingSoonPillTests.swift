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
        XCTAssertTrue(pill.isDefault)
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
        XCTAssertNil(StartingSoonPill(text: .black).contrastWarning(accent: RGBA(rgb: 0xFFD60A)))
        let warning = StartingSoonPill(fill: yellow, text: .white).contrastWarning(accent: blueAccent)
        XCTAssertEqual(warning, "The pill's label contrast is 1.4:1. It may be hard to read; aim for at least 3:1.")
    }

    func testSwitchingToCustomKeepsTheColorsShown() {
        var pill = StartingSoonPill.default
        pill.setFillCustom(true, accent: blueAccent)
        XCTAssertEqual(pill.fill, blueAccent)
        pill.setTextCustom(true, accent: blueAccent)
        XCTAssertEqual(pill.text, .white)

        pill.fill = yellow
        pill.setFillCustom(true, accent: blueAccent)
        XCTAssertEqual(pill.fill, yellow, "already custom: the picked color stays")

        pill.setFillCustom(false, accent: blueAccent)
        pill.setTextCustom(false, accent: blueAccent)
        XCTAssertTrue(pill.isDefault)
    }

    func testALightAccentGetsDarkTextAndSwitchingToCustomChangesNothing() {
        let yellowAccent = RGBA(rgb: 0xFFC600)
        var pill = StartingSoonPill.default
        XCTAssertEqual(pill.resolvedText(accent: yellowAccent), StartingSoonPill.darkText, "white is under 3:1 on yellow")
        XCTAssertNil(pill.contrastWarning(accent: yellowAccent))

        pill.setFillCustom(true, accent: yellowAccent)
        XCTAssertEqual(pill.resolvedText(accent: yellowAccent), StartingSoonPill.darkText)
        XCTAssertNil(pill.contrastWarning(accent: yellowAccent))

        pill.setTextCustom(true, accent: yellowAccent)
        XCTAssertEqual(pill.text, StartingSoonPill.darkText)
        XCTAssertNil(pill.contrastWarning(accent: yellowAccent))
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
