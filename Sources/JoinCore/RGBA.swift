import Foundation

/// A device-independent sRGB color that round-trips through JSON.
public struct RGBA: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `0xRRGGBB`, for constants.
    public init(rgb: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Accepts "#RRGGBB" or "#RRGGBBAA", with or without the leading "#".
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let shift = hasAlpha ? 8 : 0
        self.init(
            red: Double((value >> (16 + shift)) & 0xFF) / 255,
            green: Double((value >> (8 + shift)) & 0xFF) / 255,
            blue: Double((value >> shift) & 0xFF) / 255,
            alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1
        )
    }

    public var hexString: String {
        func byte(_ component: Double) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        let base = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return alpha < 1 ? base + String(format: "%02X", byte(alpha)) : base
    }

    public static let white = RGBA(red: 1, green: 1, blue: 1)
    public static let black = RGBA(red: 0, green: 0, blue: 0)
}

// MARK: Compositing and contrast

extension RGBA {
    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Straight blend of the color channels, the way a layer of `other` at `amount` opacity is drawn.
    /// The result is opaque.
    public func mixed(with other: RGBA, amount: Double) -> RGBA {
        let t = min(max(amount, 0), 1)
        return RGBA(
            red: red * (1 - t) + other.red * t,
            green: green * (1 - t) + other.green * t,
            blue: blue * (1 - t) + other.blue * t
        )
    }

    /// This color, honoring its alpha, drawn over an opaque `background`.
    public func composited(over background: RGBA) -> RGBA {
        background.mixed(with: self, amount: alpha)
    }

    /// WCAG 2 relative luminance, 0 for black to 1 for white. Alpha is ignored.
    public var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            let c = min(max(component, 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio, from 1 (none) to 21 (black on white). Alpha is ignored, so composite
    /// translucent colors over what is behind them first.
    public func contrastRatio(to other: RGBA) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Whichever candidate reads better on this color; the first wins a tie.
    public func mostLegible(of first: RGBA, _ second: RGBA) -> RGBA {
        second.contrastRatio(to: self) > first.contrastRatio(to: self) ? second : first
    }
}
