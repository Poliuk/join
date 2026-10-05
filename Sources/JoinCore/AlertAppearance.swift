import Foundation

public enum BlurMode: String, Codable, CaseIterable, Sendable {
    case dark
    case light
    case none

    public var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .none: return "None"
        }
    }
}

/// Everything the user can change about how the full-screen alert looks.
public struct AlertAppearance: Codable, Hashable, Sendable {
    public var textColor: RGBA
    public var blurMode: BlurMode
    public var backgroundTint: RGBA?
    public var backgroundOpacity: Double
    public var buttonForeground: RGBA
    public var buttonBackground: RGBA?
    public var buttonOpacity: Double
    public var primaryForeground: RGBA
    public var primaryBackground: RGBA?
    public var primaryOpacity: Double

    public init(
        textColor: RGBA,
        blurMode: BlurMode,
        backgroundTint: RGBA?,
        backgroundOpacity: Double,
        buttonForeground: RGBA,
        buttonBackground: RGBA?,
        buttonOpacity: Double,
        primaryForeground: RGBA,
        primaryBackground: RGBA?,
        primaryOpacity: Double
    ) {
        self.textColor = textColor
        self.blurMode = blurMode
        self.backgroundTint = backgroundTint
        self.backgroundOpacity = backgroundOpacity
        self.buttonForeground = buttonForeground
        self.buttonBackground = buttonBackground
        self.buttonOpacity = buttonOpacity
        self.primaryForeground = primaryForeground
        self.primaryBackground = primaryBackground
        self.primaryOpacity = primaryOpacity
    }

    public static let `default` = AlertAppearance(
        textColor: .white,
        blurMode: .dark,
        backgroundTint: nil,
        backgroundOpacity: 0.35,
        buttonForeground: .white,
        buttonBackground: nil,
        buttonOpacity: 1,
        primaryForeground: .black,
        primaryBackground: RGBA(hex: "#EF990E"),
        primaryOpacity: 1
    )
}
