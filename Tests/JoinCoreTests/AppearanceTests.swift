import XCTest
@testable import JoinCore

final class AppearanceTests: XCTestCase {
    // MARK: RGBA

    func testHexRoundTrip() {
        let color = RGBA(hex: "#EF990E")
        XCTAssertNotNil(color)
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
        XCTAssertEqual(try JSONDecoder().decode(AlertAppearance.self, from: data), appearance)
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
        XCTAssertEqual(decoded.matchingPreset, .dark)
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
        XCTAssertNil(decoded.join.fill, "No stored Join background meant the default amber, now Automatic")
        XCTAssertEqual(decoded.join.fillOpacity, 0.4, "Clamped to the Join opacity range")
        XCTAssertNil(decoded.matchingPreset)
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
    }

    func testCurrentJSONToleratesMissingKeys() throws {
        let decoded = try JSONDecoder().decode(AlertAppearance.self, from: Data(#"{"version":2,"blurMode":"light"}"#.utf8))
        XCTAssertEqual(decoded, AlertAppearancePreset.light.appearance)
    }

    // MARK: Presets

    func testDefaultIsTheDarkPreset() {
        XCTAssertEqual(AlertAppearance.default, AlertAppearancePreset.dark.appearance)
        XCTAssertTrue(AlertAppearance.default.isDefault)
    }

    func testEveryPresetMatchesItself() {
        for preset in AlertAppearancePreset.allCases {
            XCTAssertEqual(preset.appearance.matchingPreset, preset, preset.name)
        }
        XCTAssertEqual(AlertAppearancePreset.allCases.map(\.name), ["Dark", "Light", "High contrast", "Midnight"])
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
        XCTAssertNil(appearance.matchingPreset, "A custom color equal to the automatic one is still Custom")

        appearance = .default
        appearance.join.fillOpacity = 0.8
        XCTAssertNil(appearance.matchingPreset)
    }

    /// The colors each preset produces are the ones the design draws.
    func testPresetsResolveToTheDesignColors() {
        let dark = AlertAppearancePreset.dark.appearance.palette
        XCTAssertTrue(dark.isDark)
        XCTAssertEqual(dark.text, .white)
        XCTAssertEqual(dark.joinFill.hexString, "#F5A524")
        XCTAssertEqual(dark.joinText.hexString, "#1A1A1A")
        XCTAssertEqual(dark.buttonText, .white)
        XCTAssertEqual(dark.buttonFill.hexString, RGBA.white.withAlpha(0.16).hexString)

        let light = AlertAppearancePreset.light.appearance.palette
        XCTAssertFalse(light.isDark)
        XCTAssertEqual(light.text.hexString, "#1D1D1F")
        XCTAssertEqual(light.joinText.hexString, "#1A1A1A")
        XCTAssertEqual(light.buttonText.hexString, "#1D1D1F")
        XCTAssertEqual(light.buttonFill.hexString, RGBA.black.withAlpha(0.07).hexString)

        let contrast = AlertAppearancePreset.highContrast.appearance.palette
        XCTAssertEqual(contrast.text, .white)
        XCTAssertEqual(contrast.joinText, .black)
        XCTAssertEqual(contrast.joinFill.hexString, "#FFD60A")
        XCTAssertEqual(contrast.buttonText, .white)
        XCTAssertEqual(contrast.buttonFill.hexString, RGBA.white.withAlpha(0.22).hexString)

        let midnight = AlertAppearancePreset.midnight.appearance.palette
        XCTAssertTrue(midnight.isDark)
        XCTAssertEqual(midnight.text, .white)
        XCTAssertEqual(midnight.joinText, .white)
        XCTAssertEqual(midnight.joinFill.hexString, "#2563EB")

        for preset in AlertAppearancePreset.allCases {
            XCTAssertEqual(preset.appearance.contrastWarnings, [], preset.name)
        }
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
        XCTAssertLessThan(warnings[0].ratio, 4.5)
        XCTAssertTrue(warnings[0].message.hasPrefix("Event text contrast is 1."), warnings[0].message)
        XCTAssertTrue(warnings[0].message.hasSuffix("Aim for at least 4.5:1, or set Text color to Automatic."))
    }

    func testLowContrastButtonsWarn() {
        var appearance = AlertAppearance.default
        appearance.join.text = .white
        appearance.dismissAndSnooze.fill = .white
        appearance.dismissAndSnooze.text = .white
        let warnings = appearance.contrastWarnings
        XCTAssertEqual(warnings.map(\.subject), [.button(.join), .button(.dismissAndSnooze)])
        XCTAssertEqual(warnings[0].message, "The Join label contrast is \(AlertContrastWarning.format(warnings[0].ratio)). It may be hard to read; aim for at least 4.5:1.")
        XCTAssertEqual(warnings[1].message, "Dismiss and Snooze label contrast is 1.0:1. It may be hard to read; aim for at least 4.5:1.")
    }

    func testRatioFormatRoundsDown() {
        XCTAssertEqual(AlertContrastWarning.format(4.499), "4.4:1")
        XCTAssertEqual(AlertContrastWarning.format(21), "21.0:1")
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
