import Foundation
import Testing
@testable import JoinCore

/// The menu bar's starting-soon pill: its window, its colors and how it's stored.
struct StartingSoonPillTests {
    static let blueAccent = RGBA(rgb: 0x007AFF)
    static let yellowAccent = RGBA(rgb: 0xFFC600)
    static let yellow = RGBA(rgb: 0xFFD60A)
    static let green = RGBA(rgb: 0x34C759)
    static let navy = RGBA(rgb: 0x1E3A8A)
    static let darkText = StartingSoonPill.darkText

    @Test func defaultIsFiveMinutesInTheAccentColorWithWhiteText() {
        let pill = StartingSoonPill.default
        #expect(pill.minutes == 5)
        #expect(pill.window == 300)
        #expect(pill.fill == nil)
        #expect(pill.text == nil)
        #expect(pill.resolvedFill(accent: Self.blueAccent) == Self.blueAccent)
        #expect(pill.resolvedText(accent: Self.blueAccent) == .white)
        #expect(pill.contrastWarning(accent: Self.blueAccent) == nil, "the accent with white text is never flagged")
    }

    /// Clamped to 1...60 both when the pill is made (a stored value) and when the minutes are set.
    @Test(arguments: [(0, 1), (-3, 1), (10, 10), (500, 60)])
    func minutesStayWithinRange(minutes: Int, clamped: Int) {
        #expect(StartingSoonPill(minutes: minutes).minutes == clamped)
        var pill = StartingSoonPill.default
        pill.minutes = minutes
        #expect(pill.minutes == clamped)
        #expect(pill.window == TimeInterval(clamped * 60))
    }

    /// Automatic text stays white while white reaches 3:1 on the fill, and turns near-black below; a text color
    /// stored by an earlier build wins.
    @Test(arguments: [
        ("white on navy", StartingSoonPill(fill: navy), RGBA.white),
        ("white on a custom copy of the blue accent, at about 4:1", StartingSoonPill(fill: blueAccent), .white),
        ("near-black on yellow", StartingSoonPill(fill: yellow), darkText),
        ("near-black on green", StartingSoonPill(fill: green), darkText),
        ("a legacy text color", StartingSoonPill(fill: yellow, text: navy), navy),
    ])
    func automaticTextReadsOnACustomFill(_ name: String, pill: StartingSoonPill, text: RGBA) {
        #expect(pill.resolvedText(accent: Self.blueAccent) == text)
    }

    /// Only custom colors that leave the label under 3:1 are flagged, in the alert's template.
    @Test(arguments: [
        ("a custom copy of the accent", StartingSoonPill(fill: blueAccent), blueAccent, nil),
        ("a legacy black text on a yellow accent", StartingSoonPill(text: .black), yellow, nil),
        ("a legacy white text on yellow", StartingSoonPill(fill: yellow, text: .white), blueAccent,
         "The menu bar item may be hard to read (1.4:1). Aim for 3:1, or set Text to Automatic."),
    ] as [(String, StartingSoonPill, RGBA, String?)])
    func contrastWarningOnlyForUnreadableCustomColors(_ name: String, pill: StartingSoonPill, accent: RGBA, warning: String?) {
        #expect(pill.contrastWarning(accent: accent) == warning)
    }

    /// Automatic text reaches 3:1 on any fill, so a fill alone, swatch or Other…, is never flagged.
    @Test func automaticTextReadsOnEveryFill() {
        for value in 0...255 {
            let gray = RGBA(red: Double(value) / 255, green: Double(value) / 255, blue: Double(value) / 255)
            #expect(StartingSoonPill(fill: gray).contrastWarning(accent: Self.blueAccent) == nil, "\(gray.hexString)")
        }
        for swatch in StartingSoonPill.colorChoice.swatches {
            #expect(StartingSoonPill(fill: swatch.color).contrastWarning(accent: Self.blueAccent) == nil, "\(swatch.name)")
        }
    }

    @Test func colorChoiceHasBlueInsteadOfPurple() {
        #expect(StartingSoonPill.colorChoice.swatches.map(\.name) == ["Accent color", "Red", "Orange", "Green", "Blue", "Graphite"])
        #expect(StartingSoonPill.colorChoice.swatches.map { $0.color?.hexString ?? "accent" }
                == ["accent", "#FF3B30", "#FF9500", "#34C759", "#007AFF", "#8E8E93"])
    }

    @Test func colorSelection() {
        func shown(_ pill: StartingSoonPill, otherPicked: Bool = false) -> String {
            switch pill.colorSelection(accent: Self.blueAccent, otherPicked: otherPicked) {
            case .swatch(let swatch): return swatch.name
            case .other: return "Other…"
            }
        }
        #expect(shown(.default) == "Accent color")
        #expect(shown(StartingSoonPill(fill: Self.green)) == "Green")
        #expect(shown(StartingSoonPill(fill: Self.navy)) == "Other…")

        var pill = StartingSoonPill.default
        pill.pickColor(.other, accent: Self.blueAccent)
        #expect(pill.fill == Self.blueAccent, "Other… starts from the accent shown")
        #expect(shown(pill, otherPicked: true) == "Other…")
        #expect(shown(pill) == "Blue", "reopened, the color is a swatch's")

        pill.pickColor(.swatch(StartingSoonPill.colorChoice.swatches[1]), accent: Self.blueAccent)
        #expect(pill.fill == RGBA(rgb: 0xFF3B30))
        pill.setFillColor(RGBA(rgb: 0x123456, alpha: 0.4))
        #expect(pill.fill == RGBA(rgb: 0x123456), "always opaque")
        pill.pickColor(.swatch(StartingSoonPill.colorChoice.swatches[0]), accent: Self.blueAccent)
        #expect(pill.isDefault)
    }

    /// Other… changes nothing visible: the fill becomes the color shown and the text reads as before (white on
    /// the blue accent, near-black on a yellow one). A pill saved by an earlier build keeps its fill and shows
    /// the legacy Text row, whose Automatic clears the text color; Accent color then brings back the default.
    @Test(arguments: [
        ("the blue accent", StartingSoonPill.default, blueAccent, RGBA.white, false),
        ("a yellow accent", StartingSoonPill.default, yellowAccent, darkText, false),
        ("an earlier build's fill and text", StartingSoonPill(fill: yellow, text: navy), blueAccent, navy, true),
    ])
    func pickingOtherKeepsTheColorsShown(_ name: String, pill: StartingSoonPill, accent: RGBA, text: RGBA, showsLegacyText: Bool) {
        var pill = pill
        let fill = pill.resolvedFill(accent: accent)
        #expect(pill.resolvedText(accent: accent) == text)
        pill.pickColor(.other, accent: accent)
        #expect(pill.fill == fill)
        #expect(pill.resolvedText(accent: accent) == text)
        #expect(pill.contrastWarning(accent: accent) == nil)
        #expect(pill.showsLegacyText == showsLegacyText)

        pill.clearLegacyText()
        #expect(!pill.showsLegacyText)
        pill.pickColor(.swatch(StartingSoonPill.colorChoice.swatches[0]), accent: accent)
        #expect(pill.isDefault)
    }

    /// A pill stored without some keys gets the defaults, and minutes out of range are clamped on loading.
    @Test(arguments: [
        ("{}", StartingSoonPill.default),
        (#"{"minutes": 0}"#, StartingSoonPill(minutes: 1)),
        (#"{"minutes": 90, "text": {"red": 1, "green": 1, "blue": 1, "alpha": 1}}"#, StartingSoonPill(minutes: 60, text: .white)),
    ])
    func decodingFillsInMissingValues(json: String, expected: StartingSoonPill) throws {
        #expect(try JSONDecoder().decode(StartingSoonPill.self, from: Data(json.utf8)) == expected)
    }
}
