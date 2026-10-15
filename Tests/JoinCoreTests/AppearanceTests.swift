import Foundation
import Testing
@testable import JoinCore

struct AppearanceTests {
    // MARK: RGBA

    @Test func hexRoundTrip() {
        let color = RGBA(hex: "#EF990E")
        #expect(color?.hexString == "#EF990E")
        #expect(abs((RGBA(hex: "ff000080")?.alpha ?? 0) - 0.5) <= 0.01)
        #expect(RGBA(red: 1, green: 0, blue: 0, alpha: 0.5).hexString == "#FF000080")
        #expect(RGBA(rgb: 0xF5A524).hexString == "#F5A524")
        #expect(RGBA(hex: "nope") == nil)
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

    @Test func compositing() {
        let half = RGBA.white.withAlpha(0.5).composited(over: .black)
        #expect(abs(half.red - 0.5) <= 0.001)
        #expect(half.alpha == 1)
        #expect(abs(RGBA.black.mixed(with: .white, amount: 0.25).green - 0.25) <= 0.001)
        #expect(RGBA(rgb: 0x2563EB).mostLegible(of: .white, .black) == .white)
        #expect(RGBA(rgb: 0xF5A524).mostLegible(of: .white, .black) == .black)
    }

    // MARK: Coding

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
        #expect(try JSONDecoder().decode(AlertAppearance.self, from: JSONEncoder().encode(AlertAppearance.default)) == .default)
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

    // MARK: Migration from version 2

    private func decodeVersion2(_ appearance: AlertAppearance) throws -> AlertAppearance {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(appearance)) as? [String: Any] ?? [:]
        object["version"] = 2
        return try JSONDecoder().decode(AlertAppearance.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// 1.1 stored High contrast's Join label as pure black; matched as stored, it would show a Text row.
    @Test func version2HighContrastLoadsAsTodaysPreset() throws {
        let stored = AlertAppearancePreset.earlierDefinitions[0].appearance
        #expect(stored.join.text == .black)
        #expect(stored.matchingPreset == nil, "pure black isn't today's near-black")

        let decoded = try decodeVersion2(stored)
        #expect(decoded == AlertAppearancePreset.highContrast.appearance)
        #expect(!decoded.showsLegacyText(for: .join))
        #expect(decoded.selection(for: .buttons, otherPicked: false) == .swatch(ColorSwatch(name: "White", color: RGBA.white.withAlpha(0.22))))
    }

    @Test func version2LooksMatchingAPresetBecomeIt() throws {
        var dark = AlertAppearance.default
        dark.textColor = .white
        dark.join.fill = AlertAppearance.defaultJoinFill
        #expect(try decodeVersion2(dark) == .default, "Custom colors that look automatic go back to Automatic")

        var midnight = AlertAppearancePreset.midnight.appearance
        midnight.dismissAndSnooze.text = .white
        #expect(try decodeVersion2(midnight) == AlertAppearancePreset.midnight.appearance)
    }

    @Test func version2AutomaticFillsBelow100PercentBecomeOtherAtTheSameAlpha() throws {
        var stored = AlertAppearance.default
        stored.tint = RGBA(rgb: 0x123456)
        stored.join.fillOpacity = 0.8
        stored.dismissAndSnooze.fillOpacity = 0.5
        let decoded = try decodeVersion2(stored)

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
        let untouched = try decodeVersion2(full)
        #expect(untouched.join.fill == nil, "100 % stays Automatic")
        #expect(untouched.dismissAndSnooze.fill == nil, "whole percent: 99.9 % reads as 100 %")
    }

    /// 97 % of Dark's 16 % white is #FFFFFF28; rounded to a whole 16 %, it would be Dark's #FFFFFF29.
    @Test func version2AutomaticFillsAreNotRoundedIntoAPreset() throws {
        var stored = AlertAppearance.default
        stored.dismissAndSnooze.fillOpacity = 0.97
        #expect(stored.matchingPreset == nil)

        let decoded = try decodeVersion2(stored)
        #expect(decoded.style == .custom)
        #expect(decoded.isEquivalent(to: stored))
        #expect(decoded.palette.buttonFill.hexString == "#FFFFFF28")
        #expect(decoded.selection(for: .buttons, otherPicked: false) == .other)
        #expect(!decoded.isDefault)
    }

    @Test func version2AutomaticFillsKeepTheirAlphaAtEveryPercent() throws {
        for preset in [AlertAppearancePreset.dark, .light, .midnight] {
            for percent in 1...99 {
                var stored = preset.appearance
                stored.dismissAndSnooze.fillOpacity = Double(percent) / 100
                let decoded = try decodeVersion2(stored)
                #expect(decoded.isEquivalent(to: stored), "\(preset.name) at \(percent) %")
                #expect(decoded.matchingPreset == stored.matchingPreset, "\(preset.name) at \(percent) %")
            }
        }
    }

    @Test func version2CustomLabelColorsKeepTheirLegacyRows() throws {
        var stored = AlertAppearance.default
        stored.join.text = RGBA(rgb: 0x8E8E93)
        let decoded = try decodeVersion2(stored)
        #expect(decoded == stored)
        #expect(decoded.showsLegacyText(for: .join))
        #expect(!decoded.showsLegacyText(for: .dismissAndSnooze))
        #expect(decoded.style == .custom)
    }

    @Test func version3LoadsAsSaved() throws {
        var stored = AlertAppearance.default
        stored.dismissAndSnooze.fillOpacity = 0.5
        let decoded = try JSONDecoder().decode(AlertAppearance.self, from: JSONEncoder().encode(stored))
        #expect(decoded == stored, "only looks saved before version 3 are migrated")
    }

    // MARK: Presets

    @Test func defaultIsTheDarkPreset() {
        #expect(AlertAppearance.default == AlertAppearancePreset.dark.appearance)
    }

    @Test func everyPresetMatchesItself() {
        for preset in AlertAppearancePreset.allCases {
            #expect(preset.appearance.matchingPreset == preset, "\(preset.name)")
            #expect(preset.appearance.style == .preset(preset), "\(preset.name)")
        }
        #expect(AlertAppearancePreset.allCases.map(\.name) == ["Dark", "Light", "High contrast", "Midnight"])
    }

    @Test func styleCards() {
        #expect(AlertStyle.allCases.map(\.name) == ["Dark", "Light", "High contrast", "Midnight", "Custom"])
        #expect(AlertStyle.preset(.dark).help(hasCustomLook: false) == "The default style.")
        #expect(AlertStyle.preset(.midnight).help(hasCustomLook: false) == nil)
        #expect(AlertStyle.custom.help(hasCustomLook: false) == "Change any color below to make your own style.")
        #expect(AlertStyle.custom.help(hasCustomLook: true) == nil)
        #expect(Set(AlertStyle.allCases.map(\.id)).count == 5)
    }

    @Test func customCardDrawsLikeThePresetCards() {
        for preset in [AlertAppearancePreset.dark, .light] {
            let drawn = preset.appearance.swatch
            let designed = preset.swatch
            #expect([drawn.background, drawn.line, drawn.join].map(\.hexString) == [designed.background, designed.line, designed.join].map(\.hexString), "\(preset.name)")
        }
        var custom = AlertAppearance.default
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

    @Test func anyVisibleChangeIsCustom() {
        var appearance = AlertAppearance.default
        appearance.tint = .black
        #expect(appearance.matchingPreset == nil)
        #expect(!appearance.isDefault)

        appearance = .default
        appearance.textColor = .white
        #expect(appearance.matchingPreset == .dark, "a custom color equal to the automatic one looks the same")
        #expect(appearance.textColor == .white, "and stays stored, so Other… doesn't snap back to Automatic")
        #expect(!appearance.isDefault, "Event text shows Other…, which Restore Defaults puts back")

        appearance = .default
        appearance.join.fillOpacity = 0.8
        #expect(appearance.matchingPreset == nil)
    }

    /// The colors each preset produces are the ones the design draws.
    @Test func presetsResolveToTheDesignColors() {
        // isDark, then text, Join fill, Join text, button text, button fill (trailing byte = alpha: 29 = 16%, 12 = 7%, 38 = 22%)
        let expected: [(AlertAppearancePreset, Bool, [String])] = [
            (.dark,         true,  ["#FFFFFF", "#F5A524", "#1A1A1A", "#FFFFFF", "#FFFFFF29"]),
            (.light,        false, ["#1D1D1F", "#F5A524", "#1A1A1A", "#1D1D1F", "#00000012"]),
            (.highContrast, true,  ["#FFFFFF", "#FFD60A", "#1A1A1A", "#FFFFFF", "#FFFFFF38"]),
            (.midnight,     true,  ["#FFFFFF", "#2563EB", "#FFFFFF", "#FFFFFF", "#FFFFFF29"]),
        ]
        for (preset, isDark, colors) in expected {
            let palette = preset.appearance.palette
            #expect(palette.isDark == isDark, "\(preset.name)")
            #expect([palette.text, palette.joinFill, palette.joinText, palette.buttonText, palette.buttonFill].map(\.hexString) == colors, "\(preset.name)")
            #expect(preset.appearance.contrastWarnings == [], "\(preset.name)")
        }
    }

    @Test func isDefault() {
        #expect(AlertAppearance.default.isDefault)
        var appearance = AlertAppearance.default
        appearance.join.fill = AlertAppearance.defaultJoinFill
        #expect(appearance.isDefault, "Join shows Orange either way")
        appearance.tintStrength = 0.8
        #expect(appearance.isDefault, "no tint, so no strength to see")

        let changes: [(String, (inout AlertAppearance) -> Void)] = [
            ("Light", { $0.blurMode = .light }),
            ("a tint at 0 %", { $0.tint = .black; $0.tintStrength = 0 }),
            ("Event text Other…", { $0.pick(.other, for: .eventText) }),
            ("Snooze and Dismiss Other…", { $0.pick(.other, for: .buttons) }),
            ("a legacy Join text", { $0.join.text = RGBA(rgb: 0x1A1A1A) }),
            ("a legacy button text", { $0.dismissAndSnooze.text = .white }),
            ("Join at 80 %", { $0.join.fillOpacity = 0.8 }),
        ]
        for (name, change) in changes {
            var changed = AlertAppearance.default
            change(&changed)
            #expect(!changed.isDefault, "\(name)")
        }
    }

    // MARK: Swatches

    @Test func swatchLists() {
        func names(_ row: AlertColorRow) -> [String] { row.choice.swatches.map(\.name) }
        func colors(_ row: AlertColorRow) -> [String] { row.choice.swatches.map { $0.color?.hexString ?? "auto" } }
        #expect(names(.tint) == ["None", "Black", "Navy", "Plum", "Forest"])
        #expect(colors(.tint) == ["auto", "#000000", "#1E3A8A", "#6B2D5C", "#1E5631"])
        #expect(names(.eventText) == ["Automatic"])
        #expect(names(.joinButton) == ["Orange", "Yellow", "Blue", "Green", "Purple", "Red", "Graphite"])
        #expect(colors(.joinButton) == ["#F5A524", "#FFD60A", "#2563EB", "#2F9E57", "#7C3AED", "#DC2626", "#6E6E73"])
        #expect(names(.buttons) == ["Automatic", "White", "Black"])
        #expect(colors(.buttons) == ["auto", "#FFFFFF38", "#00000038"], "22 % translucent")
        #expect(ColorChoice.otherTitle == "Other…")
    }

    @Test func rowCopy() {
        #expect(AlertColorRow.allCases.map(\.title) == ["Tint", "Event text", "Join button", "Snooze & Dismiss buttons"])
        #expect(AlertColorRow.allCases.map(\.accessibilityTitle) == ["Tint", "Event text", "Join button", "Snooze and Dismiss buttons"])
        #expect(AlertColorRow.allCases.map(\.wellLabel) == ["Tint color", "Event text color", "Join button color", "Snooze and Dismiss buttons fill color"])
        #expect(AlertColorRow.allCases.filter(\.wellSupportsOpacity) == [.buttons])
        #expect(AlertColorRow.tintStrengthTitle == "Strength")
        #expect(AlertColorRow.tintStrengthAccessibilityTitle == "Tint strength")
        #expect(AlertButtonKind.allCases.map(\.displayName) == ["Join", "Snooze & Dismiss"])
        #expect(AlertButtonKind.allCases.map(\.colorRow) == [.joinButton, .buttons])
        #expect(AlertButtonKind.allCases.map { $0.colorRow.buttonKind } == [.join, .dismissAndSnooze])
        #expect(AlertButtonKind.allCases.map(\.legacyTextAccessibilityTitle) == ["Join button text", "Snooze and Dismiss buttons text"])
        #expect(AlertButtonKind.allCases.map(\.legacyTextWellLabel) == ["Join button text color", "Snooze and Dismiss buttons text color"])
        #expect([LegacyTextRow.title, LegacyTextRow.automaticTitle, LegacyTextRow.customTitle] == ["Text", "Automatic", "Custom"])
    }

    /// Every preset's colors are swatches, so choosing a preset never shows Other….
    @Test func everyPresetShowsASwatchInEveryRow() {
        for preset in AlertAppearancePreset.allCases {
            for row in AlertColorRow.allCases {
                #expect(preset.appearance.selection(for: row, otherPicked: false) != .other, "\(preset.name), \(row.title)")
            }
        }
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

    @Test func pickingOtherKeepsTheLook() {
        for preset in AlertAppearancePreset.allCases {
            for row in AlertColorRow.allCases where !(row == .tint && preset.appearance.tint == nil) {
                var appearance = preset.appearance
                appearance.pick(.other, for: row)
                #expect(appearance.isEquivalent(to: preset.appearance), "\(preset.name), \(row.title)")
                #expect(appearance.matchingPreset == preset, "\(preset.name), \(row.title)")
                #expect(appearance.selection(for: row, otherPicked: true) == .other)
                #expect(appearance.shownColor(for: row).eightBitKey == preset.appearance.shownColor(for: row).eightBitKey, "the well starts from the color shown")
            }
        }
        var untinted = AlertAppearance.default
        untinted.pick(.other, for: .tint)
        #expect(untinted.tint == AlertAppearance.otherTintSeed, "from None, a color no swatch has")
        #expect(untinted.selection(for: .tint, otherPicked: false) == .other)
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

    @Test func editingAnyColorSelectsTheCustomCard() {
        var appearance = AlertAppearance.default
        appearance.pick(.swatch(AlertColorRow.joinChoice.swatches[2]), for: .joinButton)
        #expect(appearance.style == .custom)
        appearance.pick(.swatch(AlertColorRow.joinChoice.swatches[0]), for: .joinButton)
        #expect(appearance.style == .preset(.dark))
    }

    @Test func legacyTextRows() {
        var appearance = AlertAppearance.default
        #expect(!appearance.showsLegacyText(for: .join))
        appearance.setLegacyText(RGBA(rgb: 0x8E8E93, alpha: 0.5), for: .join)
        #expect(appearance.join.text == RGBA(rgb: 0x8E8E93))
        #expect(appearance.showsLegacyText(for: .join))
        appearance.setButtonTextCustom(false, for: .join)
        #expect(!appearance.showsLegacyText(for: .join), "Automatic hides the row")
        #expect(appearance.isDefault)
    }

    // MARK: Automatic colors and warnings

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

    @Test func automaticFillOpacityScalesTheTranslucentFill() {
        var appearance = AlertAppearance.default
        appearance.dismissAndSnooze.fillOpacity = 0.5
        #expect(abs(appearance.palette.buttonFill.alpha - 0.08) <= 0.000_1)
        appearance.join.fillOpacity = 0.1
        #expect(abs(appearance.palette.joinFill.alpha - 0.4) <= 0.000_1, "Join never drops below 40%")
    }

    @Test func lowContrastTextWarns() {
        var appearance = AlertAppearance.default
        appearance.textColor = RGBA(rgb: 0x444444)
        let warnings = appearance.contrastWarnings
        #expect(warnings.map(\.subject) == [.text])
        #expect(warnings.map(\.row) == [.eventText])
        #expect(warnings.map(\.message) == ["Event text may be hard to read (1.5:1). Aim for 4.5:1, or choose Automatic."])
    }

    @Test func aTintThatDimsAutomaticTextWarnsUnderTint() {
        let appearance = AlertAppearance(blurMode: .dark, tint: .white, tintStrength: 0.4)
        let warnings = appearance.contrastWarnings
        #expect(warnings.map(\.subject) == [.text])
        #expect(warnings.map(\.row) == [.tint], "under Strength, which caused it")
        #expect(warnings.map(\.message) == ["Event text may be hard to read (4.1:1). Try a different tint strength."])
    }

    @Test func aTintBehindTheButtonSwatchesSuggestsTheStrength() {
        var appearance = AlertAppearance(blurMode: .dark, tint: .white, tintStrength: 0.45)
        #expect(appearance.contrastWarnings.map(\.message) == ["Snooze and Dismiss may be hard to read (4.1:1). Try a different tint strength."])
        #expect(appearance.contrastWarnings.map(\.row) == [.buttons])

        appearance.dismissAndSnooze.fill = RGBA(rgb: 0x808080)
        #expect(appearance.selection(for: .buttons, otherPicked: false) == .other)
        #expect(appearance.contrastWarnings.last?.message.hasSuffix("Try another color.") == true, "Other…'s color is the likelier cause")
    }

    @Test func otherColorsSuggestAnotherColor() {
        var join = AlertAppearance.default
        join.join.fill = RGBA(rgb: 0x808080)
        #expect(join.contrastWarnings.map(\.message) == ["The Join button may be hard to read (4.4:1). Try another color."])
        #expect(join.contrastWarnings.map(\.row) == [.joinButton])

        var buttons = AlertAppearance.default
        buttons.dismissAndSnooze.fill = RGBA(rgb: 0x808080)
        #expect(buttons.contrastWarnings.map(\.message) == ["Snooze and Dismiss may be hard to read (4.2:1). Try another color."])
    }

    @Test func everySwatchReadsOnEveryPreset() {
        for preset in AlertAppearancePreset.allCases {
            for row in [AlertColorRow.joinButton, .buttons] {
                for swatch in row.choice.swatches {
                    var appearance = preset.appearance
                    appearance.pick(.swatch(swatch), for: row)
                    #expect(appearance.contrastWarnings == [], "\(preset.name), \(row.title) \(swatch.name)")
                }
            }
        }
    }

    @Test func lowContrastButtonsWarn() {
        var appearance = AlertAppearance.default
        appearance.join.text = .white
        appearance.dismissAndSnooze.fill = .white
        appearance.dismissAndSnooze.text = .white
        let warnings = appearance.contrastWarnings
        #expect(warnings.map(\.subject) == [.button(.join), .button(.dismissAndSnooze)])
        #expect(warnings.map(\.row) == [.joinButton, .buttons])
        #expect(warnings.map(\.message) == [
            "The Join button may be hard to read (2.0:1). Aim for 4.5:1, or set its Text to Automatic.",
            "Snooze and Dismiss may be hard to read (1.0:1). Aim for 4.5:1, or set their Text to Automatic.",
        ])
    }

    @Test func ratioFormatRoundsDown() {
        #expect(AlertContrastWarning.format(4.499) == "4.4:1")
        #expect(AlertContrastWarning.format(21) == "21.0:1")
        #expect(AlertContrastWarning.message(subject: "Event text", ratio: 3.29, advice: "Aim for 4.5:1, or choose Automatic.")
                == "Event text may be hard to read (3.2:1). Aim for 4.5:1, or choose Automatic.")
    }

    // MARK: Editing

    @Test func switchingToCustomKeepsTheLook() {
        for preset in AlertAppearancePreset.allCases {
            var appearance = preset.appearance
            let before = appearance.palette
            appearance.setTextColorCustom(true)
            appearance.setButtonTextCustom(true, for: .join)
            appearance.setButtonTextCustom(true, for: .dismissAndSnooze)
            appearance.setButtonFillCustom(true, for: .join)
            appearance.setButtonFillCustom(true, for: .dismissAndSnooze)
            let after = appearance.palette
            #expect(after.text == before.text, "\(preset.name)")
            #expect(after.joinText == before.joinText, "\(preset.name)")
            #expect(after.buttonText == before.buttonText, "\(preset.name)")
            #expect(after.joinFill.hexString == before.joinFill.hexString, "\(preset.name)")
            #expect(after.buttonFill.hexString == before.buttonFill.hexString, "\(preset.name)")
        }
    }

    @Test func dismissFillRoundTripsBetweenAutomaticAndCustom() {
        var appearance = AlertAppearance.default
        appearance.setButtonFillCustom(true, for: .dismissAndSnooze)
        #expect(appearance.dismissAndSnooze.fill == .white)
        #expect(abs(appearance.dismissAndSnooze.fillOpacity - 0.16) <= 0.000_1)
        appearance.setButtonFillCustom(false, for: .dismissAndSnooze)
        #expect(appearance.dismissAndSnooze.fill == nil)
        #expect(abs(appearance.dismissAndSnooze.fillOpacity - 1) <= 0.000_1)
        #expect(appearance.isDefault)
    }

    @Test func tintToggle() {
        var appearance = AlertAppearance.default
        appearance.setTintEnabled(true)
        #expect(appearance.tint == .black)
        #expect(appearance.tintStrength == 0.35)
        appearance.tint = .white
        appearance.setTintEnabled(true)
        #expect(appearance.tint == .white, "Already on: unchanged")
        appearance.setTintEnabled(false)
        #expect(appearance.tint == nil)
        #expect(appearance.isDefault)
    }
}
