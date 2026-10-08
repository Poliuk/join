import XCTest
@testable import JoinCore

final class AppearanceTests: XCTestCase {
    // MARK: RGBA

    func testHexRoundTrip() {
        let color = RGBA(hex: "#EF990E")
        XCTAssertEqual(color?.hexString, "#EF990E")
        XCTAssertEqual(RGBA(hex: "ff000080")?.alpha ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(RGBA(red: 1, green: 0, blue: 0, alpha: 0.5).hexString, "#FF000080")
        XCTAssertEqual(RGBA(rgb: 0xF5A524).hexString, "#F5A524")
        XCTAssertNil(RGBA(hex: "nope"))
    }

    func testContrastRatio() {
        XCTAssertEqual(RGBA.black.contrastRatio(to: .white), 21, accuracy: 0.001)
        XCTAssertEqual(RGBA.white.contrastRatio(to: .black), 21, accuracy: 0.001)
        XCTAssertEqual(RGBA.white.contrastRatio(to: .white), 1, accuracy: 0.001)
        // The classic WCAG pair: #767676 is the lightest gray that passes 4.5:1 on white.
        XCTAssertEqual(RGBA(rgb: 0x767676).contrastRatio(to: .white), 4.54, accuracy: 0.01)
        XCTAssertLessThan(RGBA(rgb: 0x777777).contrastRatio(to: .white), 4.5)
    }

    func testEightBitKeyAlwaysCarriesAlpha() {
        let nearlyOpaque = RGBA.white.withAlpha(0.999_9)
        XCTAssertNotEqual(nearlyOpaque.hexString, RGBA.white.hexString)
        XCTAssertEqual(nearlyOpaque.eightBitKey, RGBA.white.eightBitKey)
        XCTAssertEqual(RGBA(rgb: 0xF5A524).eightBitKey, "F5A524FF")
        XCTAssertTrue(ColorChoice.matches(RGBA(red: 0x1E / 255 + 0.000_01, green: 0x3A / 255, blue: 0x8A / 255), RGBA(rgb: 0x1E3A8A)))
        XCTAssertFalse(ColorChoice.matches(RGBA.white.withAlpha(0.22), .white), "alpha counts")
    }

    func testCompositing() {
        let half = RGBA.white.withAlpha(0.5).composited(over: .black)
        XCTAssertEqual(half.red, 0.5, accuracy: 0.001)
        XCTAssertEqual(half.alpha, 1)
        XCTAssertEqual(RGBA.black.mixed(with: .white, amount: 0.25).green, 0.25, accuracy: 0.001)
        XCTAssertEqual(RGBA(rgb: 0x2563EB).mostLegible(of: .white, .black), .white)
        XCTAssertEqual(RGBA(rgb: 0xF5A524).mostLegible(of: .white, .black), .black)
    }

    // MARK: Coding

    func testAppearanceRoundTripsThroughJSON() throws {
        var appearance = AlertAppearance.default
        appearance.blurMode = .light
        appearance.tint = RGBA(hex: "#FBF5DD")
        appearance.tintStrength = 0.6
        appearance.textColor = .black
        appearance.join.fill = RGBA(rgb: 0x123456)
        appearance.dismissAndSnooze.fillOpacity = 0.3
        let data = try JSONEncoder().encode(appearance)
        XCTAssertEqual(try JSONDecoder().decode(AlertAppearance.self, from: data), appearance, "saved as it is: no migration")
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["version"] as? Int, 3)
        XCTAssertEqual(try JSONDecoder().decode(AlertAppearance.self, from: JSONEncoder().encode(AlertAppearance.default)), .default)
    }

    /// The exact shape earlier builds stored for an untouched theme.
    func testLegacyDefaultJSONBecomesTheNewDefault() throws {
        let json = """
        {"textColor":{"red":1,"green":1,"blue":1,"alpha":1},"blurMode":"dark","backgroundOpacity":0.35,
         "buttonForeground":{"red":1,"green":1,"blue":1,"alpha":1},"buttonOpacity":1,
         "primaryForeground":{"red":0,"green":0,"blue":0,"alpha":1},
         "primaryBackground":{"red":0.9372549019607843,"green":0.6,"blue":0.054901960784313725,"alpha":1},
         "primaryOpacity":1}
        """
        let decoded = try JSONDecoder().decode(AlertAppearance.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, .default)
    }

    func testCustomizedLegacyJSONKeepsItsColors() throws {
        let json = """
        {"textColor":{"red":0,"green":0,"blue":0,"alpha":1},"blurMode":"light",
         "backgroundTint":{"red":1,"green":0,"blue":0,"alpha":1},"backgroundOpacity":0.2,
         "buttonForeground":{"red":0,"green":0,"blue":1,"alpha":1},
         "buttonBackground":{"red":0,"green":1,"blue":0,"alpha":1},"buttonOpacity":0.5,
         "primaryForeground":{"red":1,"green":1,"blue":1,"alpha":1},"primaryOpacity":0.1}
        """
        let decoded = try JSONDecoder().decode(AlertAppearance.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.blurMode, .light)
        XCTAssertEqual(decoded.tint, RGBA(red: 1, green: 0, blue: 0))
        XCTAssertEqual(decoded.tintStrength, 0.2)
        XCTAssertEqual(decoded.textColor, .black)
        XCTAssertEqual(decoded.dismissAndSnooze, AlertButtonColors(text: RGBA(red: 0, green: 0, blue: 1), fill: RGBA(red: 0, green: 1, blue: 0), fillOpacity: 0.5))
        XCTAssertEqual(decoded.join.text, .white)
        XCTAssertEqual(decoded.join.fill, AlertAppearance.defaultJoinFill, "the default amber below 100 % becomes Other… at the same alpha")
        XCTAssertEqual(decoded.join.fillOpacity, 0.4, "Clamped to the Join opacity range")
        XCTAssertNil(decoded.matchingPreset)
        XCTAssertTrue(decoded.showsLegacyText(for: .join))
        XCTAssertTrue(decoded.showsLegacyText(for: .dismissAndSnooze))
    }

    func testLegacyNoBlurSurvives() throws {
        let json = """
        {"textColor":{"red":1,"green":1,"blue":1,"alpha":1},"blurMode":"none","backgroundOpacity":0.35,
         "buttonForeground":{"red":1,"green":1,"blue":1,"alpha":1},"buttonOpacity":1,
         "primaryForeground":{"red":0,"green":0,"blue":0,"alpha":1},"primaryOpacity":1}
        """
        let decoded = try JSONDecoder().decode(AlertAppearance.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.blurMode, .none)
        XCTAssertNil(decoded.palette.material)
        XCTAssertEqual(decoded.backdropChoices, [.dark, .light, .none], "offered only while it's stored")
        XCTAssertEqual(AlertAppearance.default.backdropChoices, [.dark, .light])
    }

    func testCurrentJSONToleratesMissingKeys() throws {
        let decoded = try JSONDecoder().decode(AlertAppearance.self, from: Data(#"{"version":2,"blurMode":"light"}"#.utf8))
        XCTAssertEqual(decoded, AlertAppearancePreset.light.appearance)
    }

    // MARK: Migration from version 2

    private func decodeVersion2(_ appearance: AlertAppearance) throws -> AlertAppearance {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(appearance)) as? [String: Any] ?? [:]
        object["version"] = 2
        return try JSONDecoder().decode(AlertAppearance.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// 1.1 stored High contrast's Join label as pure black; matched as stored, it would show a Text row.
    func testVersion2HighContrastLoadsAsTodaysPreset() throws {
        let stored = AlertAppearancePreset.earlierDefinitions[0].appearance
        XCTAssertEqual(stored.join.text, .black)
        XCTAssertNil(stored.matchingPreset, "pure black isn't today's near-black")

        let decoded = try decodeVersion2(stored)
        XCTAssertEqual(decoded, AlertAppearancePreset.highContrast.appearance)
        XCTAssertFalse(decoded.showsLegacyText(for: .join))
        XCTAssertEqual(decoded.selection(for: .buttons, otherPicked: false), .swatch(ColorSwatch(name: "White", color: RGBA.white.withAlpha(0.22))))
    }

    func testVersion2LooksMatchingAPresetBecomeIt() throws {
        var dark = AlertAppearance.default
        dark.textColor = .white
        dark.join.fill = AlertAppearance.defaultJoinFill
        XCTAssertEqual(try decodeVersion2(dark), .default, "Custom colors that look automatic go back to Automatic")

        var midnight = AlertAppearancePreset.midnight.appearance
        midnight.dismissAndSnooze.text = .white
        XCTAssertEqual(try decodeVersion2(midnight), AlertAppearancePreset.midnight.appearance)
    }

    func testVersion2AutomaticFillsBelow100PercentBecomeOtherAtTheSameAlpha() throws {
        var stored = AlertAppearance.default
        stored.tint = RGBA(rgb: 0x123456)
        stored.join.fillOpacity = 0.8
        stored.dismissAndSnooze.fillOpacity = 0.5
        let decoded = try decodeVersion2(stored)

        XCTAssertEqual(decoded.join.fill, AlertAppearance.defaultJoinFill)
        XCTAssertEqual(decoded.join.fillOpacity, 0.8, accuracy: 0.000_1)
        XCTAssertEqual(decoded.dismissAndSnooze.fill, .white)
        XCTAssertEqual(decoded.dismissAndSnooze.fillOpacity, 0.08, accuracy: 0.000_1)
        XCTAssertTrue(decoded.isEquivalent(to: stored), "the look doesn't change")
        XCTAssertEqual(decoded.palette.buttonFill.hexString, "#FFFFFF14")
        XCTAssertEqual(decoded.selection(for: .joinButton, otherPicked: false), .other)
        XCTAssertEqual(decoded.selection(for: .buttons, otherPicked: false), .other)

        var full = stored
        full.join.fillOpacity = 1
        full.dismissAndSnooze.fillOpacity = 0.999
        let untouched = try decodeVersion2(full)
        XCTAssertNil(untouched.join.fill, "100 % stays Automatic")
        XCTAssertNil(untouched.dismissAndSnooze.fill, "whole percent: 99.9 % reads as 100 %")
    }

    /// 97 % of Dark's 16 % white is #FFFFFF28; rounded to a whole 16 %, it would be Dark's #FFFFFF29.
    func testVersion2AutomaticFillsAreNotRoundedIntoAPreset() throws {
        var stored = AlertAppearance.default
        stored.dismissAndSnooze.fillOpacity = 0.97
        XCTAssertNil(stored.matchingPreset)

        let decoded = try decodeVersion2(stored)
        XCTAssertEqual(decoded.style, .custom)
        XCTAssertTrue(decoded.isEquivalent(to: stored))
        XCTAssertEqual(decoded.palette.buttonFill.hexString, "#FFFFFF28")
        XCTAssertEqual(decoded.selection(for: .buttons, otherPicked: false), .other)
        XCTAssertFalse(decoded.isDefault)
    }

    func testVersion2AutomaticFillsKeepTheirAlphaAtEveryPercent() throws {
        for preset in [AlertAppearancePreset.dark, .light, .midnight] {
            for percent in 1...99 {
                var stored = preset.appearance
                stored.dismissAndSnooze.fillOpacity = Double(percent) / 100
                let decoded = try decodeVersion2(stored)
                XCTAssertTrue(decoded.isEquivalent(to: stored), "\(preset.name) at \(percent) %")
                XCTAssertEqual(decoded.matchingPreset, stored.matchingPreset, "\(preset.name) at \(percent) %")
            }
        }
    }

    func testVersion2CustomLabelColorsKeepTheirLegacyRows() throws {
        var stored = AlertAppearance.default
        stored.join.text = RGBA(rgb: 0x8E8E93)
        let decoded = try decodeVersion2(stored)
        XCTAssertEqual(decoded, stored)
        XCTAssertTrue(decoded.showsLegacyText(for: .join))
        XCTAssertFalse(decoded.showsLegacyText(for: .dismissAndSnooze))
        XCTAssertEqual(decoded.style, .custom)
    }

    func testVersion3LoadsAsSaved() throws {
        var stored = AlertAppearance.default
        stored.dismissAndSnooze.fillOpacity = 0.5
        let decoded = try JSONDecoder().decode(AlertAppearance.self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(decoded, stored, "only looks saved before version 3 are migrated")
    }

    // MARK: Presets

    func testDefaultIsTheDarkPreset() {
        XCTAssertEqual(AlertAppearance.default, AlertAppearancePreset.dark.appearance)
    }

    func testEveryPresetMatchesItself() {
        for preset in AlertAppearancePreset.allCases {
            XCTAssertEqual(preset.appearance.matchingPreset, preset, preset.name)
            XCTAssertEqual(preset.appearance.style, .preset(preset), preset.name)
        }
        XCTAssertEqual(AlertAppearancePreset.allCases.map(\.name), ["Dark", "Light", "High contrast", "Midnight"])
    }

    func testStyleCards() {
        XCTAssertEqual(AlertStyle.allCases.map(\.name), ["Dark", "Light", "High contrast", "Midnight", "Custom"])
        XCTAssertEqual(AlertStyle.preset(.dark).help(hasCustomLook: false), "The default style.")
        XCTAssertNil(AlertStyle.preset(.midnight).help(hasCustomLook: false))
        XCTAssertEqual(AlertStyle.custom.help(hasCustomLook: false), "Change any color below to make your own style.")
        XCTAssertNil(AlertStyle.custom.help(hasCustomLook: true))
        XCTAssertEqual(Set(AlertStyle.allCases.map(\.id)).count, 5)
    }

    func testCustomCardDrawsLikeThePresetCards() {
        for preset in [AlertAppearancePreset.dark, .light] {
            let drawn = preset.appearance.swatch
            let designed = preset.swatch
            XCTAssertEqual([drawn.background, drawn.line, drawn.join].map(\.hexString), [designed.background, designed.line, designed.join].map(\.hexString), preset.name)
        }
        var custom = AlertAppearance.default
        custom.pick(.swatch(AlertColorRow.joinChoice.swatches[2]), for: .joinButton)
        XCTAssertEqual(custom.swatch.join.hexString, "#2563EB")
    }

    func testPresetMatchingIgnoresInvisibleDifferences() {
        var appearance = AlertAppearance.default
        appearance.tintStrength = 0.9
        XCTAssertEqual(appearance.matchingPreset, .dark, "Tint strength doesn't matter while the tint is off")
        appearance.dismissAndSnooze.fillOpacity = 0.999_9
        XCTAssertEqual(appearance.matchingPreset, .dark, "Opacities compare in whole percent")

        var midnight = AlertAppearancePreset.midnight.appearance
        midnight.tint = RGBA(red: 0x1E / 255 + 0.000_01, green: 0x3A / 255, blue: 0x8A / 255)
        XCTAssertEqual(midnight.matchingPreset, .midnight, "Colors compare at 8 bits")
    }

    func testAnyVisibleChangeIsCustom() {
        var appearance = AlertAppearance.default
        appearance.tint = .black
        XCTAssertNil(appearance.matchingPreset)
        XCTAssertFalse(appearance.isDefault)

        appearance = .default
        appearance.textColor = .white
        XCTAssertEqual(appearance.matchingPreset, .dark, "a custom color equal to the automatic one looks the same")
        XCTAssertEqual(appearance.textColor, .white, "and stays stored, so Other… doesn't snap back to Automatic")
        XCTAssertFalse(appearance.isDefault, "Event text shows Other…, which Restore Defaults puts back")

        appearance = .default
        appearance.join.fillOpacity = 0.8
        XCTAssertNil(appearance.matchingPreset)
    }

    /// The colors each preset produces are the ones the design draws.
    func testPresetsResolveToTheDesignColors() {
        // isDark, then text, Join fill, Join text, button text, button fill (trailing byte = alpha: 29 = 16%, 12 = 7%, 38 = 22%)
        let expected: [(AlertAppearancePreset, Bool, [String])] = [
            (.dark,         true,  ["#FFFFFF", "#F5A524", "#1A1A1A", "#FFFFFF", "#FFFFFF29"]),
            (.light,        false, ["#1D1D1F", "#F5A524", "#1A1A1A", "#1D1D1F", "#00000012"]),
            (.highContrast, true,  ["#FFFFFF", "#FFD60A", "#1A1A1A", "#FFFFFF", "#FFFFFF38"]),
            (.midnight,     true,  ["#FFFFFF", "#2563EB", "#FFFFFF", "#FFFFFF", "#FFFFFF29"]),
        ]
        for (preset, isDark, colors) in expected {
            let palette = preset.appearance.palette
            XCTAssertEqual(palette.isDark, isDark, preset.name)
            XCTAssertEqual([palette.text, palette.joinFill, palette.joinText, palette.buttonText, palette.buttonFill].map(\.hexString), colors, preset.name)
            XCTAssertEqual(preset.appearance.contrastWarnings, [], preset.name)
        }
    }

    func testIsDefault() {
        XCTAssertTrue(AlertAppearance.default.isDefault)
        var appearance = AlertAppearance.default
        appearance.join.fill = AlertAppearance.defaultJoinFill
        XCTAssertTrue(appearance.isDefault, "Join shows Orange either way")
        appearance.tintStrength = 0.8
        XCTAssertTrue(appearance.isDefault, "no tint, so no strength to see")

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
            XCTAssertFalse(changed.isDefault, name)
        }
    }

    // MARK: Swatches

    func testSwatchLists() {
        func names(_ row: AlertColorRow) -> [String] { row.choice.swatches.map(\.name) }
        func colors(_ row: AlertColorRow) -> [String] { row.choice.swatches.map { $0.color?.hexString ?? "auto" } }
        XCTAssertEqual(names(.tint), ["None", "Black", "Navy", "Plum", "Forest"])
        XCTAssertEqual(colors(.tint), ["auto", "#000000", "#1E3A8A", "#6B2D5C", "#1E5631"])
        XCTAssertEqual(names(.eventText), ["Automatic"])
        XCTAssertEqual(names(.joinButton), ["Orange", "Yellow", "Blue", "Green", "Purple", "Red", "Graphite"])
        XCTAssertEqual(colors(.joinButton), ["#F5A524", "#FFD60A", "#2563EB", "#2F9E57", "#7C3AED", "#DC2626", "#6E6E73"])
        XCTAssertEqual(names(.buttons), ["Automatic", "White", "Black"])
        XCTAssertEqual(colors(.buttons), ["auto", "#FFFFFF38", "#00000038"], "22 % translucent")
        XCTAssertEqual(ColorChoice.otherTitle, "Other…")
    }

    func testRowCopy() {
        XCTAssertEqual(AlertColorRow.allCases.map(\.title), ["Tint", "Event text", "Join button", "Snooze & Dismiss buttons"])
        XCTAssertEqual(AlertColorRow.allCases.map(\.accessibilityTitle), ["Tint", "Event text", "Join button", "Snooze and Dismiss buttons"])
        XCTAssertEqual(AlertColorRow.allCases.map(\.wellLabel), ["Tint color", "Event text color", "Join button color", "Snooze and Dismiss buttons fill color"])
        XCTAssertEqual(AlertColorRow.allCases.filter(\.wellSupportsOpacity), [.buttons])
        XCTAssertEqual(AlertColorRow.tintStrengthTitle, "Strength")
        XCTAssertEqual(AlertColorRow.tintStrengthAccessibilityTitle, "Tint strength")
        XCTAssertEqual(AlertButtonKind.allCases.map(\.displayName), ["Join", "Snooze & Dismiss"])
        XCTAssertEqual(AlertButtonKind.allCases.map(\.colorRow), [.joinButton, .buttons])
        XCTAssertEqual(AlertButtonKind.allCases.map { $0.colorRow.buttonKind }, [.join, .dismissAndSnooze])
        XCTAssertEqual(AlertButtonKind.allCases.map(\.legacyTextAccessibilityTitle), ["Join button text", "Snooze and Dismiss buttons text"])
        XCTAssertEqual(AlertButtonKind.allCases.map(\.legacyTextWellLabel), ["Join button text color", "Snooze and Dismiss buttons text color"])
        XCTAssertEqual([LegacyTextRow.title, LegacyTextRow.automaticTitle, LegacyTextRow.customTitle], ["Text", "Automatic", "Custom"])
    }

    /// Every preset's colors are swatches, so choosing a preset never shows Other….
    func testEveryPresetShowsASwatchInEveryRow() {
        for preset in AlertAppearancePreset.allCases {
            for row in AlertColorRow.allCases {
                XCTAssertNotEqual(preset.appearance.selection(for: row, otherPicked: false), .other, "\(preset.name), \(row.title)")
            }
        }
    }

    func testWhichItemShows() {
        func shown(_ appearance: AlertAppearance, _ row: AlertColorRow, otherPicked: Bool = false) -> String {
            switch appearance.selection(for: row, otherPicked: otherPicked) {
            case .swatch(let swatch): return swatch.name
            case .other: return "Other…"
            }
        }
        var appearance = AlertAppearance.default
        XCTAssertEqual(AlertColorRow.allCases.map { shown(appearance, $0) }, ["None", "Automatic", "Orange", "Automatic"])
        XCTAssertEqual(shown(appearance, .joinButton, otherPicked: true), "Other…", "Other… stays picked until another item is")

        appearance.join.fill = AlertAppearance.defaultJoinFill
        XCTAssertEqual(shown(appearance, .joinButton), "Orange", "an explicit orange is Orange too")
        appearance.join.fill = RGBA(rgb: 0x2563EB)
        XCTAssertEqual(shown(appearance, .joinButton), "Blue")
        appearance.join.fillOpacity = 0.6
        XCTAssertEqual(shown(appearance, .joinButton), "Other…", "Blue at 60 % is no swatch")
        appearance.join.fill = RGBA(rgb: 0x123456)
        XCTAssertEqual(shown(appearance, .joinButton), "Other…")

        appearance.textColor = .white
        XCTAssertEqual(shown(appearance, .eventText), "Other…", "a stored color is never Automatic, even when it looks the same")
        appearance.dismissAndSnooze = AlertButtonColors(fill: .white, fillOpacity: 0.16)
        XCTAssertEqual(shown(appearance, .buttons), "Other…")
        appearance.dismissAndSnooze.fillOpacity = 0.22
        XCTAssertEqual(shown(appearance, .buttons), "White")
        appearance.tint = RGBA(rgb: 0x1E3A8A)
        XCTAssertEqual(shown(appearance, .tint), "Navy")
    }

    func testPickingASwatchSetsItExactly() {
        var appearance = AlertAppearance.default
        let join = AlertColorRow.joinChoice.swatches
        appearance.join.fillOpacity = 0.6
        appearance.pick(.swatch(join[1]), for: .joinButton)
        XCTAssertEqual(appearance.join, AlertButtonColors(fill: RGBA(rgb: 0xFFD60A)), "Yellow at 100 %")
        appearance.pick(.swatch(join[0]), for: .joinButton)
        XCTAssertEqual(appearance.join, AlertButtonColors(), "Orange is the automatic Join color")

        let buttons = AlertColorRow.buttonsChoice.swatches
        appearance.pick(.swatch(buttons[2]), for: .buttons)
        XCTAssertEqual(appearance.dismissAndSnooze, AlertButtonColors(fill: .black, fillOpacity: 0.22))
        XCTAssertEqual(appearance.palette.buttonFill.hexString, "#00000038")
        appearance.dismissAndSnooze.fillOpacity = 0.5
        appearance.pick(.swatch(buttons[0]), for: .buttons)
        XCTAssertEqual(appearance.dismissAndSnooze, AlertButtonColors(), "Automatic at 100 %")

        let tints = AlertColorRow.tintChoice.swatches
        appearance.pick(.swatch(tints[2]), for: .tint)
        XCTAssertEqual(appearance.tint, RGBA(rgb: 0x1E3A8A))
        appearance.pick(.swatch(tints[0]), for: .tint)
        XCTAssertNil(appearance.tint)
        XCTAssertTrue(appearance.isDefault)

        // The High contrast preset is its swatches.
        appearance.pick(.swatch(tints[1]), for: .tint)
        appearance.tintStrength = 0.7
        appearance.pick(.swatch(join[1]), for: .joinButton)
        appearance.pick(.swatch(buttons[1]), for: .buttons)
        XCTAssertEqual(appearance, AlertAppearancePreset.highContrast.appearance)
    }

    func testPickingOtherKeepsTheLook() {
        for preset in AlertAppearancePreset.allCases {
            for row in AlertColorRow.allCases where !(row == .tint && preset.appearance.tint == nil) {
                var appearance = preset.appearance
                appearance.pick(.other, for: row)
                XCTAssertTrue(appearance.isEquivalent(to: preset.appearance), "\(preset.name), \(row.title)")
                XCTAssertEqual(appearance.matchingPreset, preset, "\(preset.name), \(row.title)")
                XCTAssertEqual(appearance.selection(for: row, otherPicked: true), .other)
                XCTAssertEqual(appearance.shownColor(for: row).eightBitKey, preset.appearance.shownColor(for: row).eightBitKey, "the well starts from the color shown")
            }
        }
        var untinted = AlertAppearance.default
        untinted.pick(.other, for: .tint)
        XCTAssertEqual(untinted.tint, AlertAppearance.otherTintSeed, "from None, a color no swatch has")
        XCTAssertEqual(untinted.selection(for: .tint, otherPicked: false), .other)
    }

    func testWellColorsAreKeptAsPicked() {
        var appearance = AlertAppearance.default
        appearance.setColor(.white, for: .eventText)
        XCTAssertEqual(appearance.textColor, .white, "not turned back into Automatic")

        appearance.setColor(RGBA(rgb: 0x2F7CF6, alpha: 0.3), for: .buttons)
        XCTAssertEqual(appearance.dismissAndSnooze.fill, RGBA(rgb: 0x2F7CF6))
        XCTAssertEqual(appearance.dismissAndSnooze.fillOpacity, 0.3, accuracy: 0.000_1, "the buttons' well has opacity")
        XCTAssertEqual(appearance.shownColor(for: .buttons).hexString, "#2F7CF64D")

        appearance.join.fillOpacity = 0.6
        appearance.setColor(RGBA(rgb: 0xE86A92, alpha: 0.5), for: .joinButton)
        XCTAssertEqual(appearance.join.fill, RGBA(rgb: 0xE86A92))
        XCTAssertEqual(appearance.join.fillOpacity, 0.6, "Join's well has no opacity; an earlier build's stays")

        appearance.setColor(RGBA(rgb: 0x123456, alpha: 0.5), for: .tint)
        XCTAssertEqual(appearance.tint, RGBA(rgb: 0x123456))
    }

    func testEditingAnyColorSelectsTheCustomCard() {
        var appearance = AlertAppearance.default
        appearance.pick(.swatch(AlertColorRow.joinChoice.swatches[2]), for: .joinButton)
        XCTAssertEqual(appearance.style, .custom)
        appearance.pick(.swatch(AlertColorRow.joinChoice.swatches[0]), for: .joinButton)
        XCTAssertEqual(appearance.style, .preset(.dark))
    }

    func testLegacyTextRows() {
        var appearance = AlertAppearance.default
        XCTAssertFalse(appearance.showsLegacyText(for: .join))
        appearance.setLegacyText(RGBA(rgb: 0x8E8E93, alpha: 0.5), for: .join)
        XCTAssertEqual(appearance.join.text, RGBA(rgb: 0x8E8E93))
        XCTAssertTrue(appearance.showsLegacyText(for: .join))
        appearance.setButtonTextCustom(false, for: .join)
        XCTAssertFalse(appearance.showsLegacyText(for: .join), "Automatic hides the row")
        XCTAssertTrue(appearance.isDefault)
    }

    // MARK: Automatic colors and warnings

    func testAutomaticTextFollowsTheTint() {
        var appearance = AlertAppearance(blurMode: .dark, tint: .white, tintStrength: 0.9)
        XCTAssertFalse(appearance.palette.isDark)
        XCTAssertEqual(appearance.palette.text.hexString, "#1D1D1F")
        XCTAssertEqual(appearance.palette.countdownColor(for: .before).hexString, "#A84B00")

        appearance = AlertAppearance(blurMode: .light, tint: .black, tintStrength: 0.9)
        XCTAssertTrue(appearance.palette.isDark)
        XCTAssertEqual(appearance.palette.text, .white)
        XCTAssertEqual(appearance.palette.countdownColor(for: .starting).hexString, "#FF9F0A")
        XCTAssertEqual(appearance.palette.countdownColor(for: .started).hexString, "#FF6961")
        XCTAssertEqual(appearance.palette.buttonFill.hexString, RGBA.white.withAlpha(0.16).hexString)
    }

    func testAutomaticFillOpacityScalesTheTranslucentFill() {
        var appearance = AlertAppearance.default
        appearance.dismissAndSnooze.fillOpacity = 0.5
        XCTAssertEqual(appearance.palette.buttonFill.alpha, 0.08, accuracy: 0.000_1)
        appearance.join.fillOpacity = 0.1
        XCTAssertEqual(appearance.palette.joinFill.alpha, 0.4, accuracy: 0.000_1, "Join never drops below 40%")
    }

    func testLowContrastTextWarns() {
        var appearance = AlertAppearance.default
        appearance.textColor = RGBA(rgb: 0x444444)
        let warnings = appearance.contrastWarnings
        XCTAssertEqual(warnings.map(\.subject), [.text])
        XCTAssertEqual(warnings.map(\.row), [.eventText])
        XCTAssertEqual(warnings.map(\.message), ["Event text may be hard to read (1.5:1). Aim for 4.5:1, or choose Automatic."])
    }

    func testATintThatDimsAutomaticTextWarnsUnderTint() {
        let appearance = AlertAppearance(blurMode: .dark, tint: .white, tintStrength: 0.4)
        let warnings = appearance.contrastWarnings
        XCTAssertEqual(warnings.map(\.subject), [.text])
        XCTAssertEqual(warnings.map(\.row), [.tint], "under Strength, which caused it")
        XCTAssertEqual(warnings.map(\.message), ["Event text may be hard to read (4.1:1). Try a different tint strength."])
    }

    func testATintBehindTheButtonSwatchesSuggestsTheStrength() {
        var appearance = AlertAppearance(blurMode: .dark, tint: .white, tintStrength: 0.45)
        XCTAssertEqual(appearance.contrastWarnings.map(\.message), ["Snooze and Dismiss may be hard to read (4.1:1). Try a different tint strength."])
        XCTAssertEqual(appearance.contrastWarnings.map(\.row), [.buttons])

        appearance.dismissAndSnooze.fill = RGBA(rgb: 0x808080)
        XCTAssertEqual(appearance.selection(for: .buttons, otherPicked: false), .other)
        XCTAssertTrue(appearance.contrastWarnings.last?.message.hasSuffix("Try another color.") ?? false, "Other…'s color is the likelier cause")
    }

    func testOtherColorsSuggestAnotherColor() {
        var join = AlertAppearance.default
        join.join.fill = RGBA(rgb: 0x808080)
        XCTAssertEqual(join.contrastWarnings.map(\.message), ["The Join button may be hard to read (4.4:1). Try another color."])
        XCTAssertEqual(join.contrastWarnings.map(\.row), [.joinButton])

        var buttons = AlertAppearance.default
        buttons.dismissAndSnooze.fill = RGBA(rgb: 0x808080)
        XCTAssertEqual(buttons.contrastWarnings.map(\.message), ["Snooze and Dismiss may be hard to read (4.2:1). Try another color."])
    }

    func testEverySwatchReadsOnEveryPreset() {
        for preset in AlertAppearancePreset.allCases {
            for row in [AlertColorRow.joinButton, .buttons] {
                for swatch in row.choice.swatches {
                    var appearance = preset.appearance
                    appearance.pick(.swatch(swatch), for: row)
                    XCTAssertEqual(appearance.contrastWarnings, [], "\(preset.name), \(row.title) \(swatch.name)")
                }
            }
        }
    }

    func testLowContrastButtonsWarn() {
        var appearance = AlertAppearance.default
        appearance.join.text = .white
        appearance.dismissAndSnooze.fill = .white
        appearance.dismissAndSnooze.text = .white
        let warnings = appearance.contrastWarnings
        XCTAssertEqual(warnings.map(\.subject), [.button(.join), .button(.dismissAndSnooze)])
        XCTAssertEqual(warnings.map(\.row), [.joinButton, .buttons])
        XCTAssertEqual(warnings.map(\.message), [
            "The Join button may be hard to read (2.0:1). Aim for 4.5:1, or set its Text to Automatic.",
            "Snooze and Dismiss may be hard to read (1.0:1). Aim for 4.5:1, or set their Text to Automatic.",
        ])
    }

    func testRatioFormatRoundsDown() {
        XCTAssertEqual(AlertContrastWarning.format(4.499), "4.4:1")
        XCTAssertEqual(AlertContrastWarning.format(21), "21.0:1")
        XCTAssertEqual(AlertContrastWarning.message(subject: "Event text", ratio: 3.29, advice: "Aim for 4.5:1, or choose Automatic."),
                       "Event text may be hard to read (3.2:1). Aim for 4.5:1, or choose Automatic.")
    }

    // MARK: Editing

    func testSwitchingToCustomKeepsTheLook() {
        for preset in AlertAppearancePreset.allCases {
            var appearance = preset.appearance
            let before = appearance.palette
            appearance.setTextColorCustom(true)
            appearance.setButtonTextCustom(true, for: .join)
            appearance.setButtonTextCustom(true, for: .dismissAndSnooze)
            appearance.setButtonFillCustom(true, for: .join)
            appearance.setButtonFillCustom(true, for: .dismissAndSnooze)
            let after = appearance.palette
            XCTAssertEqual(after.text, before.text, preset.name)
            XCTAssertEqual(after.joinText, before.joinText, preset.name)
            XCTAssertEqual(after.buttonText, before.buttonText, preset.name)
            XCTAssertEqual(after.joinFill.hexString, before.joinFill.hexString, preset.name)
            XCTAssertEqual(after.buttonFill.hexString, before.buttonFill.hexString, preset.name)
        }
    }

    func testDismissFillRoundTripsBetweenAutomaticAndCustom() {
        var appearance = AlertAppearance.default
        appearance.setButtonFillCustom(true, for: .dismissAndSnooze)
        XCTAssertEqual(appearance.dismissAndSnooze.fill, .white)
        XCTAssertEqual(appearance.dismissAndSnooze.fillOpacity, 0.16, accuracy: 0.000_1)
        appearance.setButtonFillCustom(false, for: .dismissAndSnooze)
        XCTAssertNil(appearance.dismissAndSnooze.fill)
        XCTAssertEqual(appearance.dismissAndSnooze.fillOpacity, 1, accuracy: 0.000_1)
        XCTAssertTrue(appearance.isDefault)
    }

    func testTintToggle() {
        var appearance = AlertAppearance.default
        appearance.setTintEnabled(true)
        XCTAssertEqual(appearance.tint, .black)
        XCTAssertEqual(appearance.tintStrength, 0.35)
        appearance.tint = .white
        appearance.setTintEnabled(true)
        XCTAssertEqual(appearance.tint, .white, "Already on: unchanged")
        appearance.setTintEnabled(false)
        XCTAssertNil(appearance.tint)
        XCTAssertTrue(appearance.isDefault)
    }
}
