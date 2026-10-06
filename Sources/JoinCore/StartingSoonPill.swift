import Foundation

/// The menu bar's "starting soon" pill: how long before a meeting it replaces the countdown, and
/// its colors. The panel's starting-soon card appears at the same time.
public struct StartingSoonPill: Hashable, Sendable {
    /// Whole minutes before the start, within `minuteRange`.
    public var minutes: Int {
        didSet { minutes = Self.clamped(minutes) }
    }
    /// nil means the system accent color.
    public var fill: RGBA?
    /// nil means Automatic: white, unless the fill shown (the accent or a custom color) gives it less
    /// than `minimumContrast`, then near-black.
    public var text: RGBA?

    public init(minutes: Int = 5, fill: RGBA? = nil, text: RGBA? = nil) {
        self.minutes = Self.clamped(minutes)
        self.fill = fill
        self.text = text
    }

    public static let `default` = StartingSoonPill()
    public static let minuteRange: ClosedRange<Int> = 1...60
    /// Lower than the alert's 4.5:1 by choice: white on macOS's blue accent is about 4:1, and the pill
    /// should keep that look by default. Below 3:1 (the orange, yellow and green accents, or a light
    /// custom fill) Automatic text turns near-black, and custom colors get a warning.
    public static let minimumContrast = 3.0
    static let darkText = RGBA(rgb: 0x1D1D1F)

    public var window: TimeInterval { TimeInterval(minutes * 60) }

    public var isDefault: Bool { self == .default }

    /// `accent` is the system accent color as currently drawn.
    public func resolvedFill(accent: RGBA) -> RGBA {
        fill ?? accent
    }

    /// The same rule for the accent and a custom fill, so switching Fill to Custom (which starts
    /// from the accent) changes nothing.
    public func resolvedText(accent: RGBA) -> RGBA {
        if let text { return text }
        let shown = resolvedFill(accent: accent)
        guard RGBA.white.contrastRatio(to: shown) < Self.minimumContrast else { return .white }
        return shown.mostLegible(of: .white, Self.darkText)
    }

    /// Warns when custom colors leave the label below `minimumContrast`. Automatic text always clears
    /// it, so the default pill is never flagged.
    public func contrastWarning(accent: RGBA) -> String? {
        guard fill != nil || text != nil else { return nil }
        let ratio = resolvedText(accent: accent).contrastRatio(to: resolvedFill(accent: accent))
        guard ratio < Self.minimumContrast else { return nil }
        return "The pill's label contrast is \(AlertContrastWarning.format(ratio)). It may be hard to read; aim for at least 3:1."
    }

    /// Switching to Custom starts from the color currently shown, so nothing changes until the
    /// user picks a new one.
    public mutating func setFillCustom(_ custom: Bool, accent: RGBA) {
        if custom {
            if fill == nil { fill = accent.withAlpha(1) }
        } else {
            fill = nil
        }
    }

    public mutating func setTextCustom(_ custom: Bool, accent: RGBA) {
        if custom {
            if text == nil { text = resolvedText(accent: accent) }
        } else {
            text = nil
        }
    }

    private static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, minuteRange.lowerBound), minuteRange.upperBound)
    }
}

extension StartingSoonPill: Codable {
    private enum CodingKeys: String, CodingKey {
        case minutes
        case fill
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            minutes: try container.decodeIfPresent(Int.self, forKey: .minutes) ?? Self.default.minutes,
            fill: try container.decodeIfPresent(RGBA.self, forKey: .fill),
            text: try container.decodeIfPresent(RGBA.self, forKey: .text)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minutes, forKey: .minutes)
        try container.encodeIfPresent(fill, forKey: .fill)
        try container.encodeIfPresent(text, forKey: .text)
    }
}
