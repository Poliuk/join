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

    public var displayName: String {
        switch self {
        case .join: return "Join"
        case .dismissAndSnooze: return "Dismiss & Snooze"
        }
    }

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
    public static let defaultTint = RGBA.black
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
                join: AlertButtonColors(text: .black, fill: RGBA(rgb: 0xFFD60A)),
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
}

extension AlertAppearance {
    /// Equal as far as anyone can see: colors compared at 8 bits, opacities in whole percent, and
    /// the tint strength ignored while there's no tint.
    public func isEquivalent(to other: AlertAppearance) -> Bool {
        fingerprint == other.fingerprint
    }

    /// The preset this appearance looks like, or nil for a custom style.
    public var matchingPreset: AlertAppearancePreset? {
        AlertAppearancePreset.allCases.first { isEquivalent(to: $0.appearance) }
    }

    public var isDefault: Bool { isEquivalent(to: .default) }

    private var fingerprint: [String] {
        func color(_ value: RGBA?) -> String { value?.hexString ?? "auto" }
        func percent(_ value: Double) -> String { String(Int((value * 100).rounded())) }
        return [
            blurMode.rawValue,
            tint.map { $0.hexString + "/" + percent(tintStrength) } ?? "none",
            color(textColor),
            color(join.text), color(join.fill), percent(Self.clamped(join.fillOpacity, to: .join)),
            color(dismissAndSnooze.text), color(dismissAndSnooze.fill), percent(Self.clamped(dismissAndSnooze.fillOpacity, to: .dismissAndSnooze)),
        ]
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
    public var ratio: Double
    public var message: String

    public var id: Subject { subject }

    /// "4.2:1", rounded down so a ratio just under the threshold never reads as 4.5:1.
    public static func format(_ ratio: Double) -> String {
        String(format: "%.1f:1", (ratio * 10).rounded(.down) / 10)
    }
}

extension AlertAppearance {
    /// Warnings for text that falls below WCAG's 4.5:1 for body text.
    public var contrastWarnings: [AlertContrastWarning] {
        let palette = self.palette
        var warnings: [AlertContrastWarning] = []
        let textRatio = palette.textContrast
        if textRatio < Self.minimumContrast {
            let advice = textColor == nil ? "Aim for at least 4.5:1." : "Aim for at least 4.5:1, or set Text color to Automatic."
            warnings.append(AlertContrastWarning(
                subject: .text,
                ratio: textRatio,
                message: "Event text contrast is \(AlertContrastWarning.format(textRatio)) on this backdrop. \(advice)"
            ))
        }
        let joinRatio = palette.joinContrast
        if joinRatio < Self.minimumContrast {
            warnings.append(AlertContrastWarning(
                subject: .button(.join),
                ratio: joinRatio,
                message: "The Join label contrast is \(AlertContrastWarning.format(joinRatio)). It may be hard to read; aim for at least 4.5:1."
            ))
        }
        let buttonRatio = palette.buttonContrast
        if buttonRatio < Self.minimumContrast {
            warnings.append(AlertContrastWarning(
                subject: .button(.dismissAndSnooze),
                ratio: buttonRatio,
                message: "Dismiss and Snooze label contrast is \(AlertContrastWarning.format(buttonRatio)). It may be hard to read; aim for at least 4.5:1."
            ))
        }
        return warnings
    }
}

// MARK: Editing

extension AlertAppearance {
    /// Turning the tint on starts from black; the strength is kept either way.
    public mutating func setTintEnabled(_ enabled: Bool) {
        if enabled {
            if tint == nil { tint = Self.defaultTint }
        } else {
            tint = nil
        }
    }

    /// Switching to Custom starts from the color currently shown, so nothing changes until the
    /// user picks a new one.
    public mutating func setTextColorCustom(_ custom: Bool) {
        if custom {
            if textColor == nil { textColor = palette.text }
        } else {
            textColor = nil
        }
    }

    public mutating func setButtonTextCustom(_ custom: Bool, for kind: AlertButtonKind) {
        if custom {
            if self[button: kind].text == nil {
                let palette = self.palette
                self[button: kind].text = kind == .join ? palette.joinText : palette.buttonText
            }
        } else {
            self[button: kind].text = nil
        }
    }

    /// Like the text, a fill switched to Custom keeps its look: the automatic Dismiss & Snooze fill
    /// is a translucent white or black, so it becomes that color at the matching opacity, and the
    /// opacity is scaled back when switching to Automatic again.
    public mutating func setButtonFillCustom(_ custom: Bool, for kind: AlertButtonKind) {
        guard custom != (self[button: kind].fill != nil) else { return }
        switch kind {
        case .join:
            join.fill = custom ? Self.defaultJoinFill : nil
        case .dismissAndSnooze:
            let automatic = Self.automaticButtonFill(isDark: palette.isDark)
            let opacity = dismissAndSnooze.fillOpacity
            if custom {
                dismissAndSnooze.fill = automatic.withAlpha(1)
                dismissAndSnooze.fillOpacity = Self.roundedPercent(opacity * automatic.alpha)
            } else {
                dismissAndSnooze.fill = nil
                dismissAndSnooze.fillOpacity = min(1, Self.roundedPercent(opacity / automatic.alpha))
            }
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

    private static let currentVersion = 2

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.version) else {
            self = try LegacyAlertAppearance(from: decoder).migrated
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
