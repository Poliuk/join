import Foundation
import Testing
@testable import JoinCore

/// The full-screen alert's look: colors, saved looks and their migration, the presets, the Colors rows and
/// the contrast warnings.
struct AppearanceTests {
    /// A named edit to a look, so a parameterized test says which one failed.
    struct Change: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let apply: @Sendable (inout AlertAppearance) -> Void

        init(_ name: String, _ apply: @escaping @Sendable (inout AlertAppearance) -> Void) {
            testDescription = name
            self.apply = apply
        }

        func applied(to appearance: AlertAppearance = .default) -> AlertAppearance {
            var changed = appearance
            apply(&changed)
            return changed
        }
    }

    /// Text the user sees, beside what it must say: one string or a list, in order.
    struct Copy: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let actual: [String?]
        let expected: [String?]

        init(_ name: String, _ actual: [String?], _ expected: [String?]) {
            testDescription = name
            self.actual = actual
            self.expected = expected
        }

        init(_ name: String, _ actual: String?, _ expected: String?) {
            self.init(name, [actual], [expected])
        }
    }

    // MARK: RGBA

    struct Colors {
        /// Alpha is written only below 100 %.
        @Test(arguments: [
            ("#EF990E", "#EF990E"),
            ("ff000080", "#FF000080"),
            ("#F5A524FF", "#F5A524"),
            ("nope", nil),
        ] as [(String, String?)])
        func hexRoundTrip(hex: String, expected: String?) {
            #expect(RGBA(hex: hex)?.hexString == expected)
        }

        @Test func contrastRatio() {
            #expect(abs(RGBA.black.contrastRatio(to: .white) - 21) <= 0.001)
            #expect(abs(RGBA.white.contrastRatio(to: .black) - 21) <= 0.001)
            #expect(abs(RGBA.white.contrastRatio(to: .white) - 1) <= 0.001)
            // The classic WCAG pair: #767676 is the lightest gray that passes 4.5:1 on white.
            #expect(abs(RGBA(rgb: 0x767676).contrastRatio(to: .white) - 4.54) <= 0.01)
            #expect(RGBA(rgb: 0x777777).contrastRatio(to: .white) < 4.5)
        }

        @Test func eightBitKeyAlwaysCarriesAlpha() {
            let nearlyOpaque = RGBA.white.withAlpha(0.999_9)
            #expect(nearlyOpaque.hexString != RGBA.white.hexString)
            #expect(nearlyOpaque.eightBitKey == RGBA.white.eightBitKey)
            #expect(RGBA(rgb: 0xF5A524).eightBitKey == "F5A524FF")
            #expect(ColorChoice.matches(RGBA(red: 0x1E / 255 + 0.000_01, green: 0x3A / 255, blue: 0x8A / 255), RGBA(rgb: 0x1E3A8A)))
            #expect(!ColorChoice.matches(RGBA.white.withAlpha(0.22), .white), "alpha counts")
        }
    }

    // MARK: Coding

    struct Coding {
        @Test func appearanceRoundTripsThroughJSON() throws {
            var appearance = AlertAppearance.default
            appearance.blurMode = .light
            appearance.tint = RGBA(hex: "#FBF5DD")
            appearance.tintStrength = 0.6
            appearance.textColor = .black
            appearance.join.fill = RGBA(rgb: 0x123456)
            appearance.dismissAndSnooze.fillOpacity = 0.3
            let data = try JSONEncoder().encode(appearance)
            #expect(try JSONDecoder().decode(AlertAppearance.self, from: data) == appearance, "saved as it is: no migration")
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect((object?["version"] as? Int) == 3)
        }

        /// The exact shape earlier builds stored for an untouched theme.
        @Test func legacyDefaultJSONBecomesTheNewDefault() throws {
            let json = """
            {"textColor":{"red":1,"green":1,"blue":1,"alpha":1},"blurMode":"dark","backgroundOpacity":0.35,
             "buttonForeground":{"red":1,"green":1,"blue":1,"alpha":1},"buttonOpacity":1,
             "primaryForeground":{"red":0,"green":0,"blue":0,"alpha":1},
             "primaryBackground":{"red":0.9372549019607843,"green":0.6,"blue":0.054901960784313725,"alpha":1},
             "primaryOpacity":1}
            """
            let decoded = try JSONDecoder().decode(AlertAppearance.self, from: Data(json.utf8))
            #expect(decoded == .default)
        }

        @Test func customizedLegacyJSONKeepsItsColors() throws {
            let json = """
            {"textColor":{"red":0,"green":0,"blue":0,"alpha":1},"blurMode":"light",
             "backgroundTint":{"red":1,"green":0,"blue":0,"alpha":1},"backgroundOpacity":0.2,
             "buttonForeground":{"red":0,"green":0,"blue":1,"alpha":1},
             "buttonBackground":{"red":0,"green":1,"blue":0,"alpha":1},"buttonOpacity":0.5,
             "primaryForeground":{"red":1,"green":1,"blue":1,"alpha":1},"primaryOpacity":0.1}
            """
            let decoded = try JSONDecoder().decode(AlertAppearance.self, from: Data(json.utf8))
            #expect(decoded.blurMode == .light)
            #expect(decoded.tint == RGBA(red: 1, green: 0, blue: 0))
            #expect(decoded.tintStrength == 0.2)
            #expect(decoded.textColor == .black)
            #expect(decoded.dismissAndSnooze == AlertButtonColors(text: RGBA(red: 0, green: 0, blue: 1), fill: RGBA(red: 0, green: 1, blue: 0), fillOpacity: 0.5))
            #expect(decoded.join.text == .white)
            #expect(decoded.join.fill == AlertAppearance.defaultJoinFill, "the default amber below 100 % becomes Other… at the same alpha")
            #expect(decoded.join.fillOpacity == 0.4, "Clamped to the Join opacity range")
            #expect(decoded.matchingPreset == nil)
            #expect(decoded.showsLegacyText(for: .join))
            #expect(decoded.showsLegacyText(for: .dismissAndSnooze))
        }

        @Test func legacyNoBlurSurvives() throws {
            let json = """
            {"textColor":{"red":1,"green":1,"blue":1,"alpha":1},"blurMode":"none","backgroundOpacity":0.35,
             "buttonForeground":{"red":1,"green":1,"blue":1,"alpha":1},"buttonOpacity":1,
             "primaryForeground":{"red":0,"green":0,"blue":0,"alpha":1},"primaryOpacity":1}
            """
            let decoded = try JSONDecoder().decode(AlertAppearance.self, from: Data(json.utf8))
            #expect(decoded.blurMode == .none)
            #expect(decoded.palette.material == nil)
            #expect(decoded.backdropChoices == [.dark, .light, .none], "offered only while it's stored")
            #expect(AlertAppearance.default.backdropChoices == [.dark, .light])
        }

        @Test func currentJSONToleratesMissingKeys() throws {
            let decoded = try JSONDecoder().decode(AlertAppearance.self, from: Data(#"{"version":2,"blurMode":"light"}"#.utf8))
            #expect(decoded == AlertAppearancePreset.light.appearance)
        }

        /// A field that can't be read, such as a backdrop from a newer build, fails the whole look, and
        /// Preferences falls back to the default (see `PreferencesTests`). Not lenient per field, as decided.
        @Test(arguments: [
            #"{"version":3,"blurMode":"frosted"}"#,
            #"{"version":3,"tint":"navy"}"#,
            #"{"version":3,"join":{"fill":{"red":1}}}"#,
        ])
        func anUnreadableFieldFailsTheLook(json: String) {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(AlertAppearance.self, from: Data(json.utf8))
            }
        }

        /// Only versions before 3 are migrated: a look from a newer build loads as saved, here with an automatic
        /// Snooze and Dismiss fill at 50 % that version 2 would turn into Other….
        @Test func aLookFromANewerBuildLoadsAsSaved() throws {
            let json = #"{"version":4,"blurMode":"dark","tintStrength":0.35,"join":{"fillOpacity":1},"dismissAndSnooze":{"fillOpacity":0.5}}"#
            let decoded = try JSONDecoder().decode(AlertAppearance.self, from: Data(json.utf8))
            #expect(decoded == AlertAppearance.default.with { $0.dismissAndSnooze.fillOpacity = 0.5 })
        }
    }

    // MARK: Migration from version 2

    struct Migration {
        static func decodeVersion2(_ appearance: AlertAppearance) throws -> AlertAppearance {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(appearance)) as? [String: Any] ?? [:]
            object["version"] = 2
            return try JSONDecoder().decode(AlertAppearance.self, from: JSONSerialization.data(withJSONObject: object))
        }

        struct LookMatchingAPreset: Sendable, CustomTestStringConvertible {
            let testDescription: String
            let stored: AlertAppearance
            /// The preset the stored look matches by today's definitions; nil when only an earlier build's does.
            let matchesToday: AlertAppearancePreset?
            let loadsAs: AlertAppearancePreset
        }

        static let looksMatchingAPreset: [LookMatchingAPreset] = [
            LookMatchingAPreset(
                testDescription: "1.1's High contrast, with a pure black Join label",
                stored: AlertAppearancePreset.earlierDefinitions[0].appearance,
                matchesToday: nil,
                loadsAs: .highContrast
            ),
            LookMatchingAPreset(
                testDescription: "Dark with its automatic colors stored",
                stored: AlertAppearance.default.with {
                    $0.textColor = .white
                    $0.join.fill = AlertAppearance.defaultJoinFill
                },
                matchesToday: .dark,
                loadsAs: .dark
            ),
            LookMatchingAPreset(
                testDescription: "Midnight with white button text",
                stored: AlertAppearancePreset.midnight.appearance.with { $0.dismissAndSnooze.text = .white },
                matchesToday: .midnight,
                loadsAs: .midnight
            ),
        ]

        /// A version 2 look that matches a preset, by today's definition or an earlier build's, becomes that preset
        /// exactly: custom colors that look automatic go back to Automatic, and 1.1's High contrast doesn't show
        /// a Text row for its pure black Join label.
        @Test(arguments: looksMatchingAPreset)
        func version2LookMatchingAPresetLoadsAsThatPreset(_ look: LookMatchingAPreset) throws {
            #expect(look.stored.matchingPreset == look.matchesToday)
            #expect(try Self.decodeVersion2(look.stored) == look.loadsAs.appearance)
        }

        @Test func version2AutomaticFillsBelow100PercentBecomeOtherAtTheSameAlpha() throws {
            var stored = AlertAppearance.default
            stored.tint = RGBA(rgb: 0x123456)
            stored.join.fillOpacity = 0.8
            stored.dismissAndSnooze.fillOpacity = 0.5
            let decoded = try Self.decodeVersion2(stored)

            #expect(decoded.join.fill == AlertAppearance.defaultJoinFill)
            #expect(abs(decoded.join.fillOpacity - 0.8) <= 0.000_1)
            #expect(decoded.dismissAndSnooze.fill == .white)
            #expect(abs(decoded.dismissAndSnooze.fillOpacity - 0.08) <= 0.000_1)
            #expect(decoded.isEquivalent(to: stored), "the look doesn't change")
            #expect(decoded.palette.buttonFill.hexString == "#FFFFFF14")
            #expect(decoded.selection(for: .joinButton, otherPicked: false) == .other)
            #expect(decoded.selection(for: .buttons, otherPicked: false) == .other)

            var full = stored
            full.join.fillOpacity = 1
            full.dismissAndSnooze.fillOpacity = 0.999
            let untouched = try Self.decodeVersion2(full)
            #expect(untouched.join.fill == nil, "100 % stays Automatic")
            #expect(untouched.dismissAndSnooze.fill == nil, "whole percent: 99.9 % reads as 100 %")
        }

        /// The migration doesn't round: 97 % of Dark's 16 % white is #FFFFFF28, and rounded to a whole 16 % it
        /// would be Dark's own #FFFFFF29, turning a look of the user's own into the preset.
        @Test(arguments: [AlertAppearancePreset.dark, .light, .midnight], 1...99)
        func version2AutomaticFillsKeepTheirAlphaAtEveryPercent(preset: AlertAppearancePreset, percent: Int) throws {
            var stored = preset.appearance
            stored.dismissAndSnooze.fillOpacity = Double(percent) / 100
            let decoded = try Self.decodeVersion2(stored)
            #expect(decoded.isEquivalent(to: stored))
            #expect(decoded.matchingPreset == stored.matchingPreset)
        }

        @Test func version2CustomLabelColorsKeepTheirLegacyRows() throws {
            var stored = AlertAppearance.default
            stored.join.text = RGBA(rgb: 0x8E8E93)
            let decoded = try Self.decodeVersion2(stored)
            #expect(decoded == stored)
            #expect(decoded.showsLegacyText(for: .join))
            #expect(!decoded.showsLegacyText(for: .dismissAndSnooze))
            #expect(decoded.style == .custom)
        }
    }

    // MARK: Presets and the Style cards

    struct Presets {
        /// `matchingPreset` returns the first match, so the presets must stay visually distinct.
        @Test(arguments: AlertAppearancePreset.allCases)
        func everyPresetMatchesItself(_ preset: AlertAppearancePreset) {
            #expect(preset.appearance.matchingPreset == preset)
            #expect(preset.appearance.style == .preset(preset))
        }

        /// The colors each preset produces are the ones the design draws: text, Join fill, Join text, button
        /// text and button fill (trailing byte = alpha: 29 = 16 %, 12 = 7 %, 38 = 22 %).
        @Test(arguments: [
            (AlertAppearancePreset.dark, true, ["#FFFFFF", "#F5A524", "#1A1A1A", "#FFFFFF", "#FFFFFF29"]),
            (.light, false, ["#1D1D1F", "#F5A524", "#1A1A1A", "#1D1D1F", "#00000012"]),
            (.highContrast, true, ["#FFFFFF", "#FFD60A", "#1A1A1A", "#FFFFFF", "#FFFFFF38"]),
            (.midnight, true, ["#FFFFFF", "#2563EB", "#FFFFFF", "#FFFFFF", "#FFFFFF29"]),
        ])
        func presetsResolveToTheDesignColors(preset: AlertAppearancePreset, isDark: Bool, colors: [String]) {
            let palette = preset.appearance.palette
            #expect(palette.isDark == isDark)
            #expect([palette.text, palette.joinFill, palette.joinText, palette.buttonText, palette.buttonFill].map(\.hexString) == colors)
            #expect(preset.appearance.contrastWarnings == [])
        }

        /// The Custom card's miniature is computed, the presets' are designed: computed for Dark and Light,
        /// it must come out as designed.
        @Test(arguments: [AlertAppearancePreset.dark, .light])
        func customCardDrawsLikeThePresetCards(_ preset: AlertAppearancePreset) {
            let drawn = preset.appearance.swatch
            let designed = preset.swatch
            #expect([drawn.background, drawn.line, drawn.join].map(\.hexString) == [designed.background, designed.line, designed.join].map(\.hexString))

            var custom = preset.appearance
            custom.pick(.swatch(AlertColorRow.joinChoice.swatches[2]), for: .joinButton)
            #expect(custom.swatch.join.hexString == "#2563EB")
        }

        @Test func presetMatchingIgnoresInvisibleDifferences() {
            var appearance = AlertAppearance.default
            appearance.tintStrength = 0.9
            #expect(appearance.matchingPreset == .dark, "Tint strength doesn't matter while the tint is off")
            appearance.dismissAndSnooze.fillOpacity = 0.999_9
            #expect(appearance.matchingPreset == .dark, "Opacities compare in whole percent")

            var midnight = AlertAppearancePreset.midnight.appearance
            midnight.tint = RGBA(red: 0x1E / 255 + 0.000_01, green: 0x3A / 255, blue: 0x8A / 255)
            #expect(midnight.matchingPreset == .midnight, "Colors compare at 8 bits")
        }

        @Test(arguments: [
            Change("a black tint") { $0.tint = .black },
            Change("Join at 80 %") { $0.join.fillOpacity = 0.8 },
            Change("a Blue Join") { $0.pick(.swatch(AlertColorRow.joinChoice.swatches[2]), for: .joinButton) },
        ])
        func anyVisibleChangeSelectsTheCustomCard(_ change: Change) {
            let changed = change.applied()
            #expect(changed.matchingPreset == nil)
            #expect(changed.style == .custom)
            #expect(!changed.isDefault)
        }

        /// Restore Defaults is disabled while there's nothing to put back: no other style and no leftover
        /// Other… or legacy Text row, except Join's Other… at the default Orange, which shows Orange either way.
        @Test(arguments: [
            (Change("nothing") { _ in }, true),
            (Change("Join's Other… at Orange") { $0.join.fill = AlertAppearance.defaultJoinFill }, true),
            (Change("a tint strength with no tint") { $0.tintStrength = 0.8 }, true),
            (Change("Light") { $0.blurMode = .light }, false),
            (Change("a tint at 0 %") { $0.tint = .black; $0.tintStrength = 0 }, false),
            (Change("Event text Other…") { $0.pick(.other, for: .eventText) }, false),
            (Change("Snooze and Dismiss Other…") { $0.pick(.other, for: .buttons) }, false),
            (Change("a legacy Join text") { $0.join.text = RGBA(rgb: 0x1A1A1A) }, false),
            (Change("a legacy button text") { $0.dismissAndSnooze.text = .white }, false),
            (Change("Join at 80 %") { $0.join.fillOpacity = 0.8 }, false),
        ])
        func isDefault(after change: Change, isDefault: Bool) {
            #expect(change.applied().isDefault == isDefault)
        }

        static let copy: [Copy] = [
            Copy("Style cards", AlertStyle.allCases.map(\.name), ["Dark", "Light", "High contrast", "Midnight", "Custom"]),
            Copy("Dark's help tag", AlertStyle.preset(.dark).help(hasCustomLook: false), "The default style."),
            Copy("Midnight's help tag", AlertStyle.preset(.midnight).help(hasCustomLook: false), nil),
            Copy("Custom's help tag before a look of one's own", AlertStyle.custom.help(hasCustomLook: false), "Change any color below to make your own style."),
            Copy("Custom's help tag with one", AlertStyle.custom.help(hasCustomLook: true), nil),
            Copy("Backdrop row", AlertColorRow.backdropTitle, "Backdrop"),
            Copy("Backdrop segments", BlurMode.allCases.map(\.displayName), ["Dark blur", "Light blur", "No blur"]),
            Copy("Colors rows", AlertColorRow.allCases.map(\.title), ["Tint", "Event text", "Join button", "Snooze & Dismiss buttons"]),
            Copy("Colors rows for VoiceOver", AlertColorRow.allCases.map(\.accessibilityTitle), ["Tint", "Event text", "Join button", "Snooze and Dismiss buttons"]),
            Copy("Colors wells for VoiceOver", AlertColorRow.allCases.map(\.wellLabel), ["Tint color", "Event text color", "Join button color", "Snooze and Dismiss buttons fill color"]),
            Copy("Tint strength row", AlertColorRow.tintStrengthTitle, "Strength"),
            Copy("Tint strength for VoiceOver", AlertColorRow.tintStrengthAccessibilityTitle, "Tint strength"),
            Copy("Other… item", ColorChoice.otherTitle, "Other…"),
            Copy("Button kinds", AlertButtonKind.allCases.map(\.displayName), ["Join", "Snooze & Dismiss"]),
            Copy("Legacy Text row", [LegacyTextRow.title, LegacyTextRow.automaticTitle, LegacyTextRow.customTitle], ["Text", "Automatic", "Custom"]),
            Copy("Legacy Text rows for VoiceOver", AlertButtonKind.allCases.map(\.legacyTextAccessibilityTitle), ["Join button text", "Snooze and Dismiss buttons text"]),
            Copy("Legacy Text wells for VoiceOver", AlertButtonKind.allCases.map(\.legacyTextWellLabel), ["Join button text color", "Snooze and Dismiss buttons text color"]),
        ]

        @Test(arguments: copy)
        func appearanceCopy(_ copy: Copy) {
            #expect(copy.actual == copy.expected)
        }
    }

    // MARK: The Colors rows

    struct ColorRows {
        @Test func eachButtonKindHasItsColorRow() {
            #expect(AlertButtonKind.allCases.map(\.colorRow) == [.joinButton, .buttons])
            #expect(AlertButtonKind.allCases.map { $0.colorRow.buttonKind } == [.join, .dismissAndSnooze])
            #expect(AlertColorRow.allCases.filter(\.wellSupportsOpacity) == [.buttons])
        }

        @Test(arguments: [
            (AlertColorRow.tint, ["None", "Black", "Navy", "Plum", "Forest"], ["auto", "#000000", "#1E3A8A", "#6B2D5C", "#1E5631"]),
            (.eventText, ["Automatic"], ["auto"]),
            (.joinButton, ["Orange", "Yellow", "Blue", "Green", "Purple", "Red", "Graphite"], ["#F5A524", "#FFD60A", "#2563EB", "#2F9E57", "#7C3AED", "#DC2626", "#6E6E73"]),
            // 22 % translucent, like the automatic fill.
            (.buttons, ["Automatic", "White", "Black"], ["auto", "#FFFFFF38", "#00000038"]),
        ])
        func swatchLists(row: AlertColorRow, names: [String], colors: [String]) {
            #expect(row.choice.swatches.map(\.name) == names)
            #expect(row.choice.swatches.map { $0.color?.hexString ?? "auto" } == colors)
        }

        /// Every preset's colors are swatches, so choosing a preset never shows Other….
        @Test(arguments: AlertAppearancePreset.allCases, AlertColorRow.allCases)
        func everyPresetShowsASwatchInEveryRow(preset: AlertAppearancePreset, row: AlertColorRow) {
            #expect(preset.appearance.selection(for: row, otherPicked: false) != .other)
        }

        @Test func whichItemShows() {
            func shown(_ appearance: AlertAppearance, _ row: AlertColorRow, otherPicked: Bool = false) -> String {
                switch appearance.selection(for: row, otherPicked: otherPicked) {
                case .swatch(let swatch): return swatch.name
                case .other: return "Other…"
                }
            }
            var appearance = AlertAppearance.default
            #expect(AlertColorRow.allCases.map { shown(appearance, $0) } == ["None", "Automatic", "Orange", "Automatic"])
            #expect(shown(appearance, .joinButton, otherPicked: true) == "Other…", "Other… stays picked until another item is")

            appearance.join.fill = AlertAppearance.defaultJoinFill
            #expect(shown(appearance, .joinButton) == "Orange", "an explicit orange is Orange too")
            appearance.join.fill = RGBA(rgb: 0x2563EB)
            #expect(shown(appearance, .joinButton) == "Blue")
            appearance.join.fillOpacity = 0.6
            #expect(shown(appearance, .joinButton) == "Other…", "Blue at 60 % is no swatch")
            appearance.join.fill = RGBA(rgb: 0x123456)
            #expect(shown(appearance, .joinButton) == "Other…")

            appearance.textColor = .white
            #expect(shown(appearance, .eventText) == "Other…", "a stored color is never Automatic, even when it looks the same")
            appearance.dismissAndSnooze = AlertButtonColors(fill: .white, fillOpacity: 0.16)
            #expect(shown(appearance, .buttons) == "Other…")
            appearance.dismissAndSnooze.fillOpacity = 0.22
            #expect(shown(appearance, .buttons) == "White")
            appearance.tint = RGBA(rgb: 0x1E3A8A)
            #expect(shown(appearance, .tint) == "Navy")
        }

        @Test func pickingASwatchSetsItExactly() {
            var appearance = AlertAppearance.default
            let join = AlertColorRow.joinChoice.swatches
            appearance.join.fillOpacity = 0.6
            appearance.pick(.swatch(join[1]), for: .joinButton)
            #expect(appearance.join == AlertButtonColors(fill: RGBA(rgb: 0xFFD60A)), "Yellow at 100 %")
            appearance.pick(.swatch(join[0]), for: .joinButton)
            #expect(appearance.join == AlertButtonColors(), "Orange is the automatic Join color")

            let buttons = AlertColorRow.buttonsChoice.swatches
            appearance.pick(.swatch(buttons[2]), for: .buttons)
            #expect(appearance.dismissAndSnooze == AlertButtonColors(fill: .black, fillOpacity: 0.22))
            #expect(appearance.palette.buttonFill.hexString == "#00000038")
            appearance.dismissAndSnooze.fillOpacity = 0.5
            appearance.pick(.swatch(buttons[0]), for: .buttons)
            #expect(appearance.dismissAndSnooze == AlertButtonColors(), "Automatic at 100 %")

            // Automatic is what the Event text warning tells the user to choose, so it must clear the color.
            appearance.textColor = RGBA(rgb: 0x444444)
            appearance.pick(.swatch(AlertColorRow.eventTextChoice.swatches[0]), for: .eventText)
            #expect(appearance.textColor == nil)
            #expect(appearance.contrastWarnings == [])

            let tints = AlertColorRow.tintChoice.swatches
            appearance.pick(.swatch(tints[2]), for: .tint)
            #expect(appearance.tint == RGBA(rgb: 0x1E3A8A))
            appearance.pick(.swatch(tints[0]), for: .tint)
            #expect(appearance.tint == nil)
            #expect(appearance.isDefault)

            // The High contrast preset is its swatches.
            appearance.pick(.swatch(tints[1]), for: .tint)
            appearance.tintStrength = 0.7
            appearance.pick(.swatch(join[1]), for: .joinButton)
            appearance.pick(.swatch(buttons[1]), for: .buttons)
            #expect(appearance == AlertAppearancePreset.highContrast.appearance)
        }

        /// Other… starts from the color shown, so the look doesn't change and doesn't snap back to Automatic;
        /// from no tint, it adds a color no swatch has.
        @Test(arguments: AlertAppearancePreset.allCases, AlertColorRow.allCases)
        func pickingOtherKeepsTheLook(preset: AlertAppearancePreset, row: AlertColorRow) {
            var appearance = preset.appearance
            appearance.pick(.other, for: row)
            if row == .tint, preset.appearance.tint == nil {
                #expect(appearance.tint == AlertAppearance.otherTintSeed)
                #expect(appearance.selection(for: .tint, otherPicked: false) == .other)
            } else {
                #expect(appearance.isEquivalent(to: preset.appearance))
                #expect(appearance.matchingPreset == preset)
                #expect(appearance.shownColor(for: row).eightBitKey == preset.appearance.shownColor(for: row).eightBitKey, "the well starts from the color shown")
            }
        }

        @Test func wellColorsAreKeptAsPicked() {
            var appearance = AlertAppearance.default
            appearance.setColor(.white, for: .eventText)
            #expect(appearance.textColor == .white, "not turned back into Automatic")

            appearance.setColor(RGBA(rgb: 0x2F7CF6, alpha: 0.3), for: .buttons)
            #expect(appearance.dismissAndSnooze.fill == RGBA(rgb: 0x2F7CF6))
            #expect(abs(appearance.dismissAndSnooze.fillOpacity - 0.3) <= 0.000_1, "the buttons' well has opacity")
            #expect(appearance.shownColor(for: .buttons).hexString == "#2F7CF64D")

            appearance.join.fillOpacity = 0.6
            appearance.setColor(RGBA(rgb: 0xE86A92, alpha: 0.5), for: .joinButton)
            #expect(appearance.join.fill == RGBA(rgb: 0xE86A92))
            #expect(appearance.join.fillOpacity == 0.6, "Join's well has no opacity; an earlier build's stays")

            appearance.setColor(RGBA(rgb: 0x123456, alpha: 0.5), for: .tint)
            #expect(appearance.tint == RGBA(rgb: 0x123456))
        }

        @Test func legacyTextRows() {
            var appearance = AlertAppearance.default
            #expect(!appearance.showsLegacyText(for: .join))
            appearance.setLegacyText(RGBA(rgb: 0x8E8E93, alpha: 0.5), for: .join)
            #expect(appearance.join.text == RGBA(rgb: 0x8E8E93))
            #expect(appearance.showsLegacyText(for: .join))
            appearance.clearLegacyText(for: .join)
            #expect(!appearance.showsLegacyText(for: .join), "Automatic hides the row")
            #expect(appearance.isDefault)
        }
    }

    // MARK: Automatic colors and warnings

    struct Readability {
        @Test func automaticTextFollowsTheTint() {
            var appearance = AlertAppearance(blurMode: .dark, tint: .white, tintStrength: 0.9)
            #expect(!appearance.palette.isDark)
            #expect(appearance.palette.text.hexString == "#1D1D1F")
            #expect(appearance.palette.countdownColor(for: .before).hexString == "#A84B00")

            appearance = AlertAppearance(blurMode: .light, tint: .black, tintStrength: 0.9)
            #expect(appearance.palette.isDark)
            #expect(appearance.palette.text == .white)
            #expect(appearance.palette.countdownColor(for: .starting).hexString == "#FF9F0A")
            #expect(appearance.palette.countdownColor(for: .started).hexString == "#FF6961")
            #expect(appearance.palette.buttonFill.hexString == RGBA.white.withAlpha(0.16).hexString)
        }

        /// The countdown is the alert's main time text: in every phase it reads at 4.5:1 on every preset.
        @Test(arguments: AlertAppearancePreset.allCases, [AlertCountdown.Phase.before, .starting, .started, .ended])
        func theCountdownReadsOnEveryPreset(preset: AlertAppearancePreset, phase: AlertCountdown.Phase) {
            let palette = preset.appearance.palette
            #expect(palette.countdownColor(for: phase).contrastRatio(to: palette.surface) >= AlertAppearance.minimumContrast)
        }

        /// Once the event is over, the countdown keeps the started color, on a dark backdrop and a light one.
        @Test(arguments: [AlertAppearancePreset.dark, .light])
        func anEndedCountdownKeepsTheStartedColor(_ preset: AlertAppearancePreset) {
            let palette = preset.appearance.palette
            #expect(palette.countdownColor(for: .ended) == palette.countdownColor(for: .started))
        }

        @Test func automaticFillOpacityScalesTheTranslucentFill() {
            var appearance = AlertAppearance.default
            appearance.dismissAndSnooze.fillOpacity = 0.5
            #expect(abs(appearance.palette.buttonFill.alpha - 0.08) <= 0.000_1)
            appearance.join.fillOpacity = 0.1
            #expect(abs(appearance.palette.joinFill.alpha - 0.4) <= 0.000_1, "Join never drops below 40%")
        }

        struct Warnings: Sendable, CustomTestStringConvertible {
            let testDescription: String
            let look: AlertAppearance
            /// The Colors rows the warnings show under, in order.
            let rows: [AlertColorRow]
            let messages: [String]
        }

        static let warnings: [Warnings] = [
            Warnings(
                testDescription: "gray Event text",
                look: AlertAppearance.default.with { $0.textColor = RGBA(rgb: 0x444444) },
                rows: [.eventText],
                messages: ["Event text may be hard to read (1.5:1). Aim for 4.5:1, or choose Automatic."]
            ),
            // Under Tint's Strength, which caused it.
            Warnings(
                testDescription: "a white tint at 40 % dimming the automatic text",
                look: AlertAppearance(blurMode: .dark, tint: .white, tintStrength: 0.4),
                rows: [.tint],
                messages: ["Event text may be hard to read (4.1:1). Try a different tint strength."]
            ),
            Warnings(
                testDescription: "a white tint at 45 % behind the button swatches",
                look: AlertAppearance(blurMode: .dark, tint: .white, tintStrength: 0.45),
                rows: [.buttons],
                messages: ["Snooze and Dismiss may be hard to read (4.1:1). Try a different tint strength."]
            ),
            // Other…'s color is the likelier cause.
            Warnings(
                testDescription: "the same tint behind an Other… button fill",
                look: AlertAppearance(blurMode: .dark, tint: .white, tintStrength: 0.45, dismissAndSnooze: AlertButtonColors(fill: RGBA(rgb: 0x808080))),
                rows: [.buttons],
                messages: ["Snooze and Dismiss may be hard to read (4.2:1). Try another color."]
            ),
            Warnings(
                testDescription: "a gray Other… Join fill",
                look: AlertAppearance.default.with { $0.join.fill = RGBA(rgb: 0x808080) },
                rows: [.joinButton],
                messages: ["The Join button may be hard to read (4.4:1). Try another color."]
            ),
            Warnings(
                testDescription: "a gray Other… Snooze and Dismiss fill",
                look: AlertAppearance.default.with { $0.dismissAndSnooze.fill = RGBA(rgb: 0x808080) },
                rows: [.buttons],
                messages: ["Snooze and Dismiss may be hard to read (4.2:1). Try another color."]
            ),
            // Join first, then the buttons.
            Warnings(
                testDescription: "legacy labels on both buttons",
                look: AlertAppearance.default.with {
                    $0.join.text = .white
                    $0.dismissAndSnooze.fill = .white
                    $0.dismissAndSnooze.text = .white
                },
                rows: [.joinButton, .buttons],
                messages: [
                    "The Join button may be hard to read (2.0:1). Aim for 4.5:1, or set its Text to Automatic.",
                    "Snooze and Dismiss may be hard to read (1.0:1). Aim for 4.5:1, or set their Text to Automatic.",
                ]
            ),
        ]

        /// Each warning shows under the row whose change fixes it, and its advice names that change.
        @Test(arguments: warnings)
        func lowContrastWarns(_ expected: Warnings) {
            let warnings = expected.look.contrastWarnings
            #expect(warnings.map(\.row) == expected.rows)
            #expect(warnings.map(\.message) == expected.messages)
        }

        /// The warning code relies on it: every Join swatch reads with its automatic label, and so does every
        /// Snooze and Dismiss swatch.
        @Test(arguments: AlertAppearancePreset.allCases, [AlertColorRow.joinButton, .buttons].flatMap { row in
            row.choice.swatches.map { SwatchPick(row: row, swatch: $0) }
        })
        func everySwatchReadsOnEveryPreset(preset: AlertAppearancePreset, pick: SwatchPick) {
            var appearance = preset.appearance
            appearance.pick(.swatch(pick.swatch), for: pick.row)
            #expect(appearance.contrastWarnings == [])
        }

        struct SwatchPick: Sendable, CustomTestStringConvertible {
            let row: AlertColorRow
            let swatch: ColorSwatch
            var testDescription: String { "\(row.title): \(swatch.name)" }
        }

        /// Rounded down, so a ratio just under the threshold never reads as 4.5:1.
        @Test func ratioFormatRoundsDown() {
            #expect(AlertContrastWarning.format(4.499) == "4.4:1")
            #expect(AlertContrastWarning.format(21) == "21.0:1")
        }
    }
}

fileprivate extension AlertAppearance {
    func with(_ change: (inout AlertAppearance) -> Void) -> AlertAppearance {
        var changed = self
        change(&changed)
        return changed
    }
}
