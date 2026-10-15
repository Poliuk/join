import Foundation
import Testing
@testable import JoinCore

struct StartingSoonPillTests {
    private let blueAccent = RGBA(rgb: 0x007AFF)
    private let yellow = RGBA(rgb: 0xFFD60A)
    private let navy = RGBA(rgb: 0x1E3A8A)

    @Test func defaultIsFiveMinutesInTheAccentColorWithWhiteText() {
        let pill = StartingSoonPill.default
        #expect(pill.minutes == 5)
        #expect(pill.window == 300)
        #expect(pill.fill == nil)
        #expect(pill.text == nil)
        #expect(pill.resolvedFill(accent: blueAccent) == blueAccent)
        #expect(pill.resolvedText(accent: blueAccent) == .white)
        #expect(pill.contrastWarning(accent: blueAccent) == nil, "the accent with white text is never flagged")
    }

    @Test func minutesStayWithinRange() {
        #expect(StartingSoonPill(minutes: 0).minutes == 1)
        #expect(StartingSoonPill(minutes: 500).minutes == 60)
        var pill = StartingSoonPill.default
        pill.minutes = -3
        #expect(pill.minutes == 1)
        pill.minutes = 10
        #expect(pill.window == 600)
        #expect(!pill.isDefault)
    }

    @Test func automaticTextReadsOnACustomFill() {
        #expect(StartingSoonPill(fill: yellow).resolvedText(accent: blueAccent) == StartingSoonPill.darkText)
        #expect(StartingSoonPill(fill: navy).resolvedText(accent: blueAccent) == .white)
        #expect(StartingSoonPill(fill: blueAccent).resolvedText(accent: blueAccent) == .white, "white stays while it reaches 3:1")
        #expect(StartingSoonPill(fill: RGBA(rgb: 0x34C759)).resolvedText(accent: blueAccent) == StartingSoonPill.darkText)
        #expect(StartingSoonPill(fill: yellow, text: navy).resolvedText(accent: blueAccent) == navy)
    }

    @Test func contrastWarningOnlyForUnreadableCustomColors() {
        #expect(StartingSoonPill(fill: yellow).contrastWarning(accent: blueAccent) == nil)
        #expect(StartingSoonPill(fill: blueAccent).contrastWarning(accent: blueAccent) == nil, "a custom copy of the accent isn't flagged")
        #expect(StartingSoonPill(text: .black).contrastWarning(accent: yellow) == nil)
        let warning = StartingSoonPill(fill: yellow, text: .white).contrastWarning(accent: blueAccent)
        #expect(warning == "The menu bar item may be hard to read (1.4:1). Aim for 3:1, or set Text to Automatic.")
    }

    /// Automatic text reaches 3:1 on any fill, so a fill alone, swatch or Other…, is never flagged.
    @Test func automaticTextReadsOnEveryFill() {
        for value in 0...255 {
            let gray = RGBA(red: Double(value) / 255, green: Double(value) / 255, blue: Double(value) / 255)
            #expect(StartingSoonPill(fill: gray).contrastWarning(accent: blueAccent) == nil, "\(gray.hexString)")
        }
        for swatch in StartingSoonPill.colorChoice.swatches {
            #expect(StartingSoonPill(fill: swatch.color).contrastWarning(accent: blueAccent) == nil, "\(swatch.name)")
        }
    }

    @Test func colorChoiceHasBlueInsteadOfPurple() {
        #expect(StartingSoonPill.colorChoice.swatches.map(\.name) == ["Accent color", "Red", "Orange", "Green", "Blue", "Graphite"])
        #expect(StartingSoonPill.colorChoice.swatches.map { $0.color?.hexString ?? "accent" }
                == ["accent", "#FF3B30", "#FF9500", "#34C759", "#007AFF", "#8E8E93"])
    }

    @Test func colorSelection() {
        func shown(_ pill: StartingSoonPill, otherPicked: Bool = false) -> String {
            switch pill.colorSelection(accent: blueAccent, otherPicked: otherPicked) {
            case .swatch(let swatch): return swatch.name
            case .other: return "Other…"
            }
        }
        #expect(shown(.default) == "Accent color")
        #expect(shown(StartingSoonPill(fill: RGBA(rgb: 0x34C759))) == "Green")
        #expect(shown(StartingSoonPill(fill: navy)) == "Other…")
        #expect(shown(.default, otherPicked: true) == "Other…")

        var pill = StartingSoonPill.default
        pill.pickColor(.other, accent: blueAccent)
        #expect(pill.fill == blueAccent, "Other… starts from the accent shown")
        #expect(shown(pill, otherPicked: true) == "Other…")
        #expect(shown(pill) == "Blue", "reopened, the color is a swatch's")

        pill.pickColor(.swatch(StartingSoonPill.colorChoice.swatches[1]), accent: blueAccent)
        #expect(pill.fill == RGBA(rgb: 0xFF3B30))
        pill.setFillColor(RGBA(rgb: 0x123456, alpha: 0.4))
        #expect(pill.fill == RGBA(rgb: 0x123456), "always opaque")
        pill.pickColor(.swatch(StartingSoonPill.colorChoice.swatches[0]), accent: blueAccent)
        #expect(pill.isDefault)
    }

    @Test func legacyTextRow() {
        #expect(!StartingSoonPill.default.showsLegacyText)
        var pill = StartingSoonPill(fill: yellow, text: navy)
        #expect(pill.showsLegacyText)
        pill.setTextCustom(false, accent: blueAccent)
        #expect(!pill.showsLegacyText, "Automatic hides the row")
    }

    @Test func switchingToCustomKeepsTheColorsShown() {
        // White text on the blue accent; under 3:1 on a yellow accent, so dark text.
        for (accent, text) in [(blueAccent, RGBA.white), (RGBA(rgb: 0xFFC600), StartingSoonPill.darkText)] {
            var pill = StartingSoonPill.default
            #expect(pill.resolvedText(accent: accent) == text, "\(accent.hexString)")
            pill.setFillCustom(true, accent: accent)
            #expect(pill.fill == accent, "\(accent.hexString)")
            #expect(pill.resolvedText(accent: accent) == text, "\(accent.hexString)")
            pill.setTextCustom(true, accent: accent)
            #expect(pill.text == text, "\(accent.hexString)")
            #expect(pill.contrastWarning(accent: accent) == nil, "\(accent.hexString)")
        }

        var pill = StartingSoonPill(fill: yellow, text: navy)
        pill.setFillCustom(true, accent: blueAccent)
        #expect(pill.fill == yellow, "already custom: the picked color stays")
        pill.setFillCustom(false, accent: blueAccent)
        pill.setTextCustom(false, accent: blueAccent)
        #expect(pill.isDefault)
    }

    @Test func codingRoundTripsAndFillsInMissingValues() throws {
        let pill = StartingSoonPill(minutes: 10, fill: yellow, text: navy)
        let decoded = try JSONDecoder().decode(StartingSoonPill.self, from: JSONEncoder().encode(pill))
        #expect(decoded == pill)

        let empty = try JSONDecoder().decode(StartingSoonPill.self, from: Data("{}".utf8))
        #expect(empty == .default)
        let outOfRange = try JSONDecoder().decode(StartingSoonPill.self, from: Data(#"{"minutes": 0}"#.utf8))
        #expect(outOfRange.minutes == 1)
    }
}
