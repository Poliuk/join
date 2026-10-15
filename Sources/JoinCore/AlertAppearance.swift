import Foundation

/// What the alert draws over the desktop before the tint.
public enum BlurMode: String, Codable, CaseIterable, Sendable {
    case dark
    case light
    /// Only reachable from themes saved by earlier builds; Settings offers Dark and Light.
    case none

    public var displayName: String {
        switch self {
        case .dark: return "Dark blur"
        case .light: return "Light blur"
        case .none: return "No blur"
        }
    }
}

/// The colors of one kind of alert button. nil means Automatic: derived from the backdrop.
public struct AlertButtonColors: Codable, Hashable, Sendable {
    public var text: RGBA?
    public var fill: RGBA?
    /// Scales the fill's alpha, whether the fill is automatic or custom.
    public var fillOpacity: Double

    public init(text: RGBA? = nil, fill: RGBA? = nil, fillOpacity: Double = 1) {
        self.text = text
        self.fill = fill
        self.fillOpacity = fillOpacity
    }
}

public enum AlertButtonKind: String, CaseIterable, Sendable {
    case join
    case dismissAndSnooze

    public var keyPath: WritableKeyPath<AlertAppearance, AlertButtonColors> {
        switch self {
        case .join: return \.join
        case .dismissAndSnooze: return \.dismissAndSnooze
        }
    }

    /// "Join", "Snooze & Dismiss": named in the order the alert stacks the snooze row and Dismiss.
    public var displayName: String {
        switch self {
        case .join: return "Join"
        case .dismissAndSnooze: return "Snooze & Dismiss"
        }
    }

    /// The Colors row that picks this kind's fill, with the kind's legacy Text row under it.
    public var colorRow: AlertColorRow {
        switch self {
        case .join: return .joinButton
        case .dismissAndSnooze: return .buttons
        }
    }

    /// The legacy Text row's pop-up, for VoiceOver: "Join button text", "Snooze and Dismiss buttons text".
    public var legacyTextAccessibilityTitle: String { colorRow.accessibilityTitle + " text" }

    /// The legacy Text row's well: "Join button text color", "Snooze and Dismiss buttons text color".
    public var legacyTextWellLabel: String { colorRow.accessibilityTitle + " text color" }

    /// What the kind's fill opacity is clamped to. Settings now picks Join's fill at 100 %, so its range only
    /// matters for a look saved by an earlier build; the Snooze and Dismiss buttons' swatches and well set theirs.
    public var fillOpacityRange: ClosedRange<Double> {
        switch self {
        case .join: return 0.4...1
        case .dismissAndSnooze: return 0...1
        }
    }
}

/// Everything the user can change about how the full-screen alert looks.
public struct AlertAppearance: Hashable, Sendable {
    public var blurMode: BlurMode
    /// nil means no tint.
    public var tint: RGBA?
    /// How strongly the tint covers the backdrop, 0...1. Kept while the tint is off.
    public var tintStrength: Double
    /// nil means Automatic: white or near-black, whichever reads better on the backdrop.
    public var textColor: RGBA?
    public var join: AlertButtonColors
    public var dismissAndSnooze: AlertButtonColors

    public init(
        blurMode: BlurMode = .dark,
        tint: RGBA? = nil,
        tintStrength: Double = 0.35,
        textColor: RGBA? = nil,
        join: AlertButtonColors = AlertButtonColors(),
        dismissAndSnooze: AlertButtonColors = AlertButtonColors()
    ) {
        self.blurMode = blurMode
        self.tint = tint
        self.tintStrength = tintStrength
        self.textColor = textColor
        self.join = join
        self.dismissAndSnooze = dismissAndSnooze
    }

    public static let `default` = AlertAppearancePreset.dark.appearance

    public static let defaultJoinFill = RGBA(rgb: 0xF5A524)
    /// Where Tint's Other… starts from None: a color none of the swatches has, so the well shows something new.
    public static let otherTintSeed = RGBA(rgb: 0x7A5AF8)
    public static let minimumContrast = 4.5

    public subscript(button kind: AlertButtonKind) -> AlertButtonColors {
        get { self[keyPath: kind.keyPath] }
        set { self[keyPath: kind.keyPath] = newValue }
    }
}

// MARK: Presets

public enum AlertAppearancePreset: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case highContrast
    case midnight

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .highContrast: return "High contrast"
        case .midnight: return "Midnight"
        }
    }

    public var appearance: AlertAppearance {
        switch self {
        case .dark:
            return AlertAppearance(blurMode: .dark)
        case .light:
            return AlertAppearance(blurMode: .light)
        case .highContrast:
            return AlertAppearance(
                blurMode: .dark,
                tint: .black,
                tintStrength: 0.7,
                join: AlertButtonColors(fill: RGBA(rgb: 0xFFD60A)),
                dismissAndSnooze: AlertButtonColors(fill: .white, fillOpacity: 0.22)
            )
        case .midnight:
            return AlertAppearance(
                blurMode: .dark,
                tint: RGBA(rgb: 0x1E3A8A),
                tintStrength: 0.45,
                join: AlertButtonColors(fill: RGBA(rgb: 0x2563EB))
            )
        }
    }

    /// The miniature drawn on the preset's card: background, text lines and Join bar.
    public var swatch: (background: RGBA, line: RGBA, join: RGBA) {
        switch self {
        case .dark: return (RGBA(rgb: 0x2B2B30), .white, RGBA(rgb: 0xF5A524))
        case .light: return (RGBA(rgb: 0xE9E9EE), RGBA(rgb: 0x1D1D1F), RGBA(rgb: 0xF5A524))
        case .highContrast: return (RGBA(rgb: 0x0C0C0E), .white, RGBA(rgb: 0xFFD60A))
        case .midnight: return (RGBA(rgb: 0x1C2754), .white, RGBA(rgb: 0x2563EB))
        }
    }

    /// Preset definitions earlier builds saved, each loaded as today's preset: until 1.2.0, High contrast
    /// stored a pure black Join label, where Automatic now gives near-black.
    static let earlierDefinitions: [(appearance: AlertAppearance, preset: AlertAppearancePreset)] = [
        (
            AlertAppearance(
                blurMode: .dark,
                tint: .black,
                tintStrength: 0.7,
                join: AlertButtonColors(text: .black, fill: RGBA(rgb: 0xFFD60A)),
                dismissAndSnooze: AlertButtonColors(fill: .white, fillOpacity: 0.22)
            ),
            .highContrast
        ),
    ]
}

/// The Style section's cards: the four presets, then Custom, which holds the user's own look.
public enum AlertStyle: Hashable, Sendable, Identifiable {
    case preset(AlertAppearancePreset)
    case custom

    public static let allCases: [AlertStyle] = AlertAppearancePreset.allCases.map(AlertStyle.preset) + [.custom]

    public var id: String {
        switch self {
        case .preset(let preset): return preset.rawValue
        case .custom: return "custom"
        }
    }

    public var name: String {
        switch self {
        case .preset(let preset): return preset.name
        case .custom: return "Custom"
        }
    }

    /// The card's help tag: Dark says it's the default, and Custom explains itself until a custom look exists.
    public func help(hasCustomLook: Bool) -> String? {
        switch self {
        case .preset(.dark): return "The default style."
        case .preset: return nil
        case .custom: return hasCustomLook ? nil : "Change any color below to make your own style."
        }
    }
}

extension AlertAppearance {
    /// Equal as far as anyone can see: the same backdrop, and the same resolved colors (surface, event text,
    /// Join label and fill, button label and fill) at 8 bits, alpha included. What's stored doesn't count, so
    /// a custom color equal to the automatic one, or a tint strength while there's no tint, changes nothing.
    /// Matching never rewrites what's stored: switching a pop-up to Other… starts from the color shown, which
    /// would otherwise snap straight back to Automatic.
    public func isEquivalent(to other: AlertAppearance) -> Bool {
        fingerprint == other.fingerprint
    }

    /// The preset this appearance looks like, or nil for a look of the user's own.
    public var matchingPreset: AlertAppearancePreset? {
        AlertAppearancePreset.allCases.first { isEquivalent(to: $0.appearance) }
    }

    /// The Style card outlined: the matching preset's, or Custom while the look matches none.
    public var style: AlertStyle {
        matchingPreset.map(AlertStyle.preset) ?? .custom
    }

    /// Whether Appearance's Restore Defaults has nothing to put back, so it's disabled: the look is the Dark
    /// style's, with no legacy Text row and no Colors row on Other… left over, except Join's: its Other…
    /// stores the default Orange, which isn't checked, since the Join button shows Orange either way.
    public var isDefault: Bool {
        isEquivalent(to: .default)
            && tint == nil
            && textColor == nil
            && join.text == nil
            && dismissAndSnooze.text == nil
            && dismissAndSnooze.fill == nil
    }

    private var fingerprint: [String] {
        let palette = self.palette
        return [blurMode.rawValue] + [
            palette.surface, palette.text, palette.joinText, palette.joinFill, palette.buttonText, palette.buttonFill,
        ].map(\.eightBitKey)
    }

    /// The Custom card's miniature, drawn like the presets' (`AlertAppearancePreset.swatch`): the backdrop
    /// with its tint, the event text's color for the lines, and the Join fill for the bar.
    public var swatch: (background: RGBA, line: RGBA, join: RGBA) {
        var background = blurMode == .light ? RGBA(rgb: 0xE9E9EE) : RGBA(rgb: 0x2B2B30)
        if let tint {
            background = background.mixed(with: tint, amount: tintStrength * tint.alpha)
        }
        let palette = self.palette
        return (background, palette.text.composited(over: background), palette.joinFill.composited(over: background))
    }

    /// The Backdrop control's segments: Dark blur and Light blur, and No blur only while a look saved by an
    /// earlier build has it.
    public var backdropChoices: [BlurMode] {
        blurMode == .none ? [.dark, .light, .none] : [.dark, .light]
    }

    static func clamped(_ opacity: Double, to kind: AlertButtonKind) -> Double {
        min(max(opacity, kind.fillOpacityRange.lowerBound), kind.fillOpacityRange.upperBound)
    }
}

// MARK: Resolved colors

/// Concrete colors for one appearance, with Automatic choices resolved.
public struct AlertPalette: Hashable, Sendable {
    /// Light text on a dark backdrop. Picks the countdown colors and the scrim.
    public var isDark: Bool
    /// An opaque stand-in for the blurred, tinted backdrop the text sits on.
    public var surface: RGBA
    public var text: RGBA
    public var joinText: RGBA
    public var joinFill: RGBA
    public var buttonText: RGBA
    public var buttonFill: RGBA
    /// The layer the blur material adds over the desktop; drawn by the Settings preview, which
    /// can't blur what's behind its window. nil without blur.
    public var material: RGBA?
    /// The center of the radial scrim behind the alert's content; it fades to clear at the edges.
    public var scrim: RGBA

    public var textContrast: Double { text.composited(over: surface).contrastRatio(to: surface) }
    public var joinContrast: Double { contrast(of: joinText, on: joinFill) }
    public var buttonContrast: Double { contrast(of: buttonText, on: buttonFill) }

    public func countdownColor(for phase: AlertCountdown.Phase) -> RGBA {
        switch phase {
        case .before: return isDark ? RGBA(rgb: 0xFFB340) : RGBA(rgb: 0xA84B00)
        case .starting: return isDark ? RGBA(rgb: 0xFF9F0A) : RGBA(rgb: 0xA13A00)
        case .started, .ended: return isDark ? RGBA(rgb: 0xFF6961) : RGBA(rgb: 0xC1121F)
        }
    }

    private func contrast(of label: RGBA, on fill: RGBA) -> Double {
        let background = fill.composited(over: surface)
        return label.composited(over: background).contrastRatio(to: background)
    }
}

extension AlertAppearance {
    static let darkSurface = RGBA(rgb: 0x26262B)
    static let lightSurface = RGBA(rgb: 0xECECF0)
    static let darkText = RGBA(rgb: 0x1D1D1F)
    static let darkJoinText = RGBA(rgb: 0x1A1A1A)

    public var palette: AlertPalette {
        var surface = blurMode == .light ? Self.lightSurface : Self.darkSurface
        if let tint {
            surface = surface.mixed(with: tint, amount: tintStrength * tint.alpha)
        }
        let autoText = surface.mostLegible(of: .white, Self.darkText)
        let isDark = autoText == .white

        let joinFill = (join.fill ?? Self.defaultJoinFill).scalingAlpha(by: Self.clamped(join.fillOpacity, to: .join))
        let buttonOpacity = Self.clamped(dismissAndSnooze.fillOpacity, to: .dismissAndSnooze)
        let buttonFill = dismissAndSnooze.fill?.scalingAlpha(by: buttonOpacity)
            ?? Self.automaticButtonFill(isDark: isDark).scalingAlpha(by: buttonOpacity)

        let material: RGBA?
        switch blurMode {
        case .dark: material = RGBA(red: 22 / 255, green: 22 / 255, blue: 26 / 255, alpha: 0.58)
        case .light: material = RGBA(red: 244 / 255, green: 244 / 255, blue: 247 / 255, alpha: 0.7)
        case .none: material = nil
        }

        return AlertPalette(
            isDark: isDark,
            surface: surface,
            text: textColor ?? autoText,
            joinText: join.text ?? joinFill.composited(over: surface).mostLegible(of: .white, Self.darkJoinText),
            joinFill: joinFill,
            buttonText: dismissAndSnooze.text ?? buttonFill.composited(over: surface).mostLegible(of: .white, Self.darkText),
            buttonFill: buttonFill,
            material: material,
            scrim: isDark ? RGBA.black.withAlpha(0.32) : RGBA.white.withAlpha(0.5)
        )
    }

    /// Translucent white on a dark backdrop, translucent black on a light one.
    static func automaticButtonFill(isDark: Bool) -> RGBA {
        isDark ? RGBA.white.withAlpha(0.16) : RGBA.black.withAlpha(0.07)
    }
}

private extension RGBA {
    func scalingAlpha(by factor: Double) -> RGBA { withAlpha(alpha * factor) }
}

// MARK: Contrast warnings

public struct AlertContrastWarning: Hashable, Sendable, Identifiable {
    public enum Subject: Hashable, Sendable {
        case text
        case button(AlertButtonKind)
    }

    public var subject: Subject
    /// The Colors row it shows directly under: Tint (below its Strength row) when the tint makes the automatic
    /// event text hard to read, otherwise the subject's own row (a button's after its legacy Text row).
    public var row: AlertColorRow
    public var ratio: Double
    public var message: String

    public var id: Subject { subject }

    /// "4.2:1", rounded down so a ratio just under the threshold never reads as 4.5:1.
    public static func format(_ ratio: Double) -> String {
        String(format: "%.1f:1", (ratio * 10).rounded(.down) / 10)
    }

    /// The one template every contrast warning uses, the alert's and the menu bar's: "Event text may be hard
    /// to read (3.2:1). Aim for 4.5:1, or choose Automatic." The advice names the fix, or, when the row is
    /// already Automatic, what to try instead.
    public static func message(subject: String, ratio: Double, advice: String) -> String {
        "\(subject) may be hard to read (\(format(ratio))). \(advice)"
    }
}

extension AlertAppearance {
    /// Warnings for text that falls below WCAG's 4.5:1 for body text, each worded for the row it shows under.
    public var contrastWarnings: [AlertContrastWarning] {
        let palette = self.palette
        var warnings: [AlertContrastWarning] = []

        let textRatio = palette.textContrast
        if textRatio < Self.minimumContrast {
            // Automatic text always reads on an untinted backdrop, so with Automatic the tint is the cause.
            let (row, advice): (AlertColorRow, String) =
                if textColor != nil { (.eventText, "Aim for 4.5:1, or choose Automatic.") }
                else if tint != nil { (.tint, "Try a different tint strength.") }
                else { (.eventText, "Aim for 4.5:1.") }
            warnings.append(AlertContrastWarning(
                subject: .text,
                row: row,
                ratio: textRatio,
                message: AlertContrastWarning.message(subject: "Event text", ratio: textRatio, advice: advice)
            ))
        }

        // Every Join swatch reads with its automatic label, so only a legacy label or an Other… fill gets here.
        let joinRatio = palette.joinContrast
        if joinRatio < Self.minimumContrast {
            let advice = join.text != nil ? "Aim for 4.5:1, or set its Text to Automatic." : "Try another color."
            warnings.append(AlertContrastWarning(
                subject: .button(.join),
                row: .joinButton,
                ratio: joinRatio,
                message: AlertContrastWarning.message(subject: "The Join button", ratio: joinRatio, advice: advice)
            ))
        }

        // The buttons' swatches are translucent, so on a swatch it's the tint behind them that falls short.
        let buttonRatio = palette.buttonContrast
        if buttonRatio < Self.minimumContrast {
            let advice =
                if dismissAndSnooze.text != nil { "Aim for 4.5:1, or set their Text to Automatic." }
                else if tint != nil, selection(for: .buttons, otherPicked: false) != .other { "Try a different tint strength." }
                else { "Try another color." }
            warnings.append(AlertContrastWarning(
                subject: .button(.dismissAndSnooze),
                row: .buttons,
                ratio: buttonRatio,
                message: AlertContrastWarning.message(subject: "Snooze and Dismiss", ratio: buttonRatio, advice: advice)
            ))
        }
        return warnings
    }
}

// MARK: Editing

extension AlertAppearance {
    /// Other… for a button's fill keeps its look, like Other… for the event text: Join's automatic Orange
    /// becomes an explicit Orange, and the automatic Snooze & Dismiss fill, a translucent white or black,
    /// becomes that color at the matching opacity in whole percent. A fill already stored stays as it is.
    mutating func makeButtonFillCustom(for kind: AlertButtonKind) {
        guard self[button: kind].fill == nil else { return }
        switch kind {
        case .join:
            join.fill = Self.defaultJoinFill
        case .dismissAndSnooze:
            let automatic = Self.automaticButtonFill(isDark: palette.isDark)
            dismissAndSnooze.fill = automatic.withAlpha(1)
            dismissAndSnooze.fillOpacity = Self.roundedPercent(dismissAndSnooze.fillOpacity * automatic.alpha)
        }
    }

    static func roundedPercent(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

// MARK: Coding

extension AlertAppearance: Codable {
    private enum CodingKeys: String, CodingKey {
        case version
        case blurMode
        case tint
        case tintStrength
        case textColor
        case join
        case dismissAndSnooze
    }

    /// 3 since 1.2.0's swatches; 2 is the same shape, loaded through `migratedToVersion3`.
    private static let currentVersion = 3

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.version) else {
            self = try LegacyAlertAppearance(from: decoder).migrated.migratedToVersion3()
            return
        }
        let fallback = AlertAppearance.default
        self.init(
            blurMode: try container.decodeIfPresent(BlurMode.self, forKey: .blurMode) ?? fallback.blurMode,
            tint: try container.decodeIfPresent(RGBA.self, forKey: .tint),
            tintStrength: try container.decodeIfPresent(Double.self, forKey: .tintStrength) ?? fallback.tintStrength,
            textColor: try container.decodeIfPresent(RGBA.self, forKey: .textColor),
            join: try container.decodeIfPresent(AlertButtonColors.self, forKey: .join) ?? fallback.join,
            dismissAndSnooze: try container.decodeIfPresent(AlertButtonColors.self, forKey: .dismissAndSnooze) ?? fallback.dismissAndSnooze
        )
        if ((try? container.decode(Int.self, forKey: .version)) ?? 0) < Self.currentVersion {
            self = migratedToVersion3()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(blurMode, forKey: .blurMode)
        try container.encodeIfPresent(tint, forKey: .tint)
        try container.encode(tintStrength, forKey: .tintStrength)
        try container.encodeIfPresent(textColor, forKey: .textColor)
        try container.encode(join, forKey: .join)
        try container.encode(dismissAndSnooze, forKey: .dismissAndSnooze)
    }
}

extension AlertAppearance {
    /// A look saved before 1.2.0's swatches (version 2, or the shape before it), as the Colors box can show it. First, a look that matches a preset,
    /// by today's definition or an earlier build's, becomes today's preset exactly: otherwise High contrast's
    /// old black Join label would leave a stray Text row. Then an automatic fill below 100 %, which the
    /// Colors box can't show now that Fill opacity is gone, becomes Other… at the same visible alpha. Custom
    /// label colors stay, each on its legacy Text row.
    func migratedToVersion3() -> AlertAppearance {
        if let preset = matchingPreset { return preset.appearance }
        if let earlier = AlertAppearancePreset.earlierDefinitions.first(where: { isEquivalent(to: $0.appearance) }) {
            return earlier.preset.appearance
        }
        var migrated = self
        for kind in AlertButtonKind.allCases where migrated[button: kind].fill == nil
            && Self.roundedPercent(Self.clamped(migrated[button: kind].fillOpacity, to: kind)) < 1 {
            switch kind {
            case .join:
                migrated.makeButtonFillCustom(for: .join)
            case .dismissAndSnooze:
                // Unrounded, unlike `makeButtonFillCustom`: a whole percent of the automatic fill's 16 % or 7 %
                // can change the alpha, and even round a look of the user's own into a preset's.
                let automatic = Self.automaticButtonFill(isDark: migrated.palette.isDark)
                migrated.dismissAndSnooze.fill = automatic.withAlpha(1)
                migrated.dismissAndSnooze.fillOpacity = Self.clamped(migrated.dismissAndSnooze.fillOpacity, to: kind) * automatic.alpha
            }
        }
        return migrated
    }
}

/// The shape saved by builds before the redesign, where every color was explicit.
private struct LegacyAlertAppearance: Decodable {
    var textColor: RGBA
    var blurMode: BlurMode
    var backgroundTint: RGBA?
    var backgroundOpacity: Double
    var buttonForeground: RGBA
    var buttonBackground: RGBA?
    var buttonOpacity: Double
    var primaryForeground: RGBA
    var primaryBackground: RGBA?
    var primaryOpacity: Double

    /// An untouched old default becomes the new default; anything customized keeps its exact colors.
    var migrated: AlertAppearance {
        if isOldDefault { return .default }
        return AlertAppearance(
            blurMode: blurMode,
            tint: backgroundTint,
            tintStrength: backgroundOpacity,
            textColor: textColor,
            join: AlertButtonColors(
                text: primaryForeground,
                fill: primaryBackground,
                fillOpacity: AlertAppearance.clamped(primaryOpacity, to: .join)
            ),
            dismissAndSnooze: AlertButtonColors(text: buttonForeground, fill: buttonBackground, fillOpacity: buttonOpacity)
        )
    }

    /// The old Settings could leave invisible differences behind (the tint opacity while the tint
    /// was off, an explicit copy of the fallback Join color), so those don't count as changes.
    private var isOldDefault: Bool {
        func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }
        let oldJoinFill = "#EF990E"
        return textColor.hexString == "#FFFFFF"
            && blurMode == .dark
            && backgroundTint == nil
            && buttonForeground.hexString == "#FFFFFF"
            && buttonBackground == nil
            && percent(buttonOpacity) == 100
            && primaryForeground.hexString == "#000000"
            && (primaryBackground?.hexString ?? oldJoinFill) == oldJoinFill
            && percent(primaryOpacity) == 100
    }
}
