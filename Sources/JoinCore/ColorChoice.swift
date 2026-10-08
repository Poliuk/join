import Foundation

/// A named color in one of Settings' color pop-ups, or the pop-up's automatic item.
public struct ColorSwatch: Hashable, Sendable, Identifiable {
    public let name: String
    /// The color, alpha included. nil for the automatic item (Automatic, None, Accent color), which stores
    /// no color and follows the rest of the look, or the system accent.
    public let color: RGBA?

    public init(name: String, color: RGBA?) {
        self.name = name
        self.color = color
    }

    public var id: String { name }
}

/// A Settings color pop-up: its swatches, a separator, then **Other…**, which shows a color well beside it.
/// Like `MinutesChoice`, the view remembers whether Other… was picked; this decides which item shows.
public struct ColorChoice: Hashable, Sendable {
    /// A pop-up item, and its tag.
    public enum Item: Hashable, Sendable {
        case swatch(ColorSwatch)
        case other
    }

    public static let otherTitle = "Other…"

    public let swatches: [ColorSwatch]

    public init(swatches: [ColorSwatch]) {
        self.swatches = swatches
    }

    /// The item the pop-up shows. Other… from picking it until another item is picked, even while its color
    /// matches a swatch: it starts from the color shown, which often does. Otherwise the automatic item while
    /// no color is stored, then the swatch the shown color matches at 8 bits (alpha included), then Other…
    /// for any other color. A stored color never shows as the automatic item, even when it looks the same,
    /// since it doesn't follow the backdrop or the accent the way the automatic one does.
    ///
    /// - Parameters:
    ///   - stored: the row's stored color, nil for its automatic item.
    ///   - shown: the color the row draws with, opacity included.
    public func selection(stored: RGBA?, shown: RGBA, otherPicked: Bool) -> Item {
        if otherPicked { return .other }
        if stored == nil, let automatic = swatches.first(where: { $0.color == nil }) {
            return .swatch(automatic)
        }
        if let match = swatches.first(where: { $0.color.map { Self.matches($0, shown) } ?? false }) {
            return .swatch(match)
        }
        return .other
    }

    /// Equal at 8 bits a channel, alpha included: the same as far as anyone can see.
    public static func matches(_ first: RGBA, _ second: RGBA) -> Bool {
        first.eightBitKey == second.eightBitKey
    }
}

/// The legacy **Text** row under a color row, shown only while a custom label color saved by an earlier
/// build is stored. Its pop-up offers Automatic, which clears the color and so hides the row, and Custom,
/// with a well.
public enum LegacyTextRow {
    public static let title = "Text"
    public static let automaticTitle = "Automatic"
    public static let customTitle = "Custom"
}
