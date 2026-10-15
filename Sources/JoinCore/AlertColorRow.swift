import Foundation

/// The rows of Appearance's **Colors** box that pick a color: each a pop-up of named swatches, a separator
/// and Other…, with a color well before the pop-up while Other… is picked. Backdrop, the tint's Strength and
/// the buttons' legacy Text rows are the box's other rows.
public enum AlertColorRow: String, CaseIterable, Identifiable, Sendable {
    case tint
    case eventText
    case joinButton
    case buttons

    public var id: String { rawValue }

    /// The row's label: "Tint", "Event text", "Join button", "Snooze & Dismiss buttons".
    public var title: String {
        switch self {
        case .tint: return "Tint"
        case .eventText: return "Event text"
        case .joinButton: return "Join button"
        case .buttons: return "Snooze & Dismiss buttons"
        }
    }

    /// The pop-up's name for VoiceOver, with "and" for "&": "Snooze and Dismiss buttons".
    public var accessibilityTitle: String {
        self == .buttons ? "Snooze and Dismiss buttons" : title
    }

    /// The well's name for VoiceOver.
    public var wellLabel: String {
        switch self {
        case .tint: return "Tint color"
        case .eventText: return "Event text color"
        case .joinButton: return "Join button color"
        case .buttons: return "Snooze and Dismiss buttons fill color"
        }
    }

    /// Only the Snooze and Dismiss buttons' well picks an opacity, like their translucent swatches.
    public var wellSupportsOpacity: Bool { self == .buttons }

    /// The button kind whose fill the row picks, and whose legacy Text row sits under it.
    var buttonKind: AlertButtonKind? {
        switch self {
        case .tint, .eventText: return nil
        case .joinButton: return .join
        case .buttons: return .dismissAndSnooze
        }
    }

    public var choice: ColorChoice {
        switch self {
        case .tint: return Self.tintChoice
        case .eventText: return Self.eventTextChoice
        case .joinButton: return Self.joinChoice
        case .buttons: return Self.buttonsChoice
        }
    }

    /// The indented row under Tint while there's one; VoiceOver keeps the longer name.
    public static let tintStrengthTitle = "Strength"
    public static let tintStrengthAccessibilityTitle = "Tint strength"
    public static let backdropTitle = "Backdrop"

    // Every preset's colors are among the swatches (Black, Navy, Yellow, Blue, White at 22 %), so a preset
    // never shows Other….

    static let tintChoice = ColorChoice(swatches: [
        ColorSwatch(name: "None", color: nil),
        ColorSwatch(name: "Black", color: RGBA(rgb: 0x000000)),
        ColorSwatch(name: "Navy", color: RGBA(rgb: 0x1E3A8A)),
        ColorSwatch(name: "Plum", color: RGBA(rgb: 0x6B2D5C)),
        ColorSwatch(name: "Forest", color: RGBA(rgb: 0x1E5631)),
    ])

    static let eventTextChoice = ColorChoice(swatches: [
        ColorSwatch(name: "Automatic", color: nil),
    ])

    /// Orange first: it's the automatic Join color, so picking it stores none.
    static let joinChoice = ColorChoice(swatches: [
        ColorSwatch(name: "Orange", color: AlertAppearance.defaultJoinFill),
        ColorSwatch(name: "Yellow", color: RGBA(rgb: 0xFFD60A)),
        ColorSwatch(name: "Blue", color: RGBA(rgb: 0x2563EB)),
        ColorSwatch(name: "Green", color: RGBA(rgb: 0x2F9E57)),
        ColorSwatch(name: "Purple", color: RGBA(rgb: 0x7C3AED)),
        ColorSwatch(name: "Red", color: RGBA(rgb: 0xDC2626)),
        ColorSwatch(name: "Graphite", color: RGBA(rgb: 0x6E6E73)),
    ])

    /// Translucent, like the automatic fill (white at 16 % on a dark backdrop, black at 7 % on a light one).
    static let buttonsChoice = ColorChoice(swatches: [
        ColorSwatch(name: "Automatic", color: nil),
        ColorSwatch(name: "White", color: RGBA.white.withAlpha(0.22)),
        ColorSwatch(name: "Black", color: RGBA.black.withAlpha(0.22)),
    ])
}

// MARK: Editing by row

extension AlertAppearance {
    /// What the row stores; nil is its automatic item (None for the tint).
    public func storedColor(for row: AlertColorRow) -> RGBA? {
        switch row {
        case .tint: return tint
        case .eventText: return textColor
        case .joinButton: return join.fill
        case .buttons: return dismissAndSnooze.fill
        }
    }

    /// The color the row draws with, opacity included: what its well shows, and what its swatches are matched
    /// against. The tint's is its color at any strength, and with no tint the color Other… would start from.
    public func shownColor(for row: AlertColorRow) -> RGBA {
        switch row {
        case .tint: return tint ?? Self.otherTintSeed
        case .eventText: return palette.text
        case .joinButton: return palette.joinFill
        case .buttons: return palette.buttonFill
        }
    }

    /// The item the row's pop-up shows; see `ColorChoice.selection`.
    public func selection(for row: AlertColorRow, otherPicked: Bool) -> ColorChoice.Item {
        row.choice.selection(stored: storedColor(for: row), shown: shownColor(for: row), otherPicked: otherPicked)
    }

    /// Picking an item from the row's pop-up. A swatch sets its color exactly, opacity included, so Join's
    /// swatches also put a fill opacity from an earlier build back to 100 %. The automatic item clears the
    /// color, and the buttons' Automatic their opacity too. Other… starts from the color shown, so nothing
    /// changes until another one is picked in the well, except from no tint: that adds `otherTintSeed` at
    /// the current strength.
    public mutating func pick(_ item: ColorChoice.Item, for row: AlertColorRow) {
        switch item {
        case .swatch(let swatch):
            setSwatchColor(swatch.color, for: row)
        case .other:
            switch row {
            case .tint: if tint == nil { tint = Self.otherTintSeed }
            case .eventText: if textColor == nil { textColor = palette.text }
            case .joinButton: makeButtonFillCustom(for: .join)
            case .buttons: makeButtonFillCustom(for: .dismissAndSnooze)
            }
        }
    }

    /// The well's color, kept as picked even when it equals the automatic one. Only the buttons' well has
    /// opacity, which becomes their fill opacity; Join keeps its own, below 100 % only in a look saved by an
    /// earlier build.
    public mutating func setColor(_ color: RGBA, for row: AlertColorRow) {
        let opaque = color.withAlpha(1)
        switch row {
        case .tint: tint = opaque
        case .eventText: textColor = opaque
        case .joinButton: join.fill = opaque
        case .buttons:
            dismissAndSnooze.fill = opaque
            dismissAndSnooze.fillOpacity = min(max(color.alpha, 0), 1)
        }
    }

    private mutating func setSwatchColor(_ color: RGBA?, for row: AlertColorRow) {
        switch row {
        case .tint:
            tint = color?.withAlpha(1)
        case .eventText:
            textColor = color?.withAlpha(1)
        case .joinButton:
            // Orange is the automatic Join color, so the look goes back to storing none.
            join.fill = color.flatMap { ColorChoice.matches($0, Self.defaultJoinFill) ? nil : $0.withAlpha(1) }
            join.fillOpacity = 1
        case .buttons:
            dismissAndSnooze.fill = color?.withAlpha(1)
            dismissAndSnooze.fillOpacity = color?.alpha ?? 1
        }
    }

    // MARK: Legacy Text rows

    /// Whether the kind's legacy Text row shows under its Colors row: only while a label color is stored,
    /// which only an earlier build could save. Its Automatic (`clearLegacyText(for:)`) clears it, and the row
    /// goes.
    public func showsLegacyText(for kind: AlertButtonKind) -> Bool {
        self[button: kind].text != nil
    }

    /// The legacy Text row's well.
    public mutating func setLegacyText(_ color: RGBA, for kind: AlertButtonKind) {
        self[button: kind].text = color.withAlpha(1)
    }

    /// The legacy Text row's Automatic: the label follows the fill again.
    public mutating func clearLegacyText(for kind: AlertButtonKind) {
        self[button: kind].text = nil
    }
}
