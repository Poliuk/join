import AppKit
import SwiftUI
import JoinCore

/// The panel's colors as light/dark pairs. The design is drawn dark-first; the light values mirror it on
/// a light background. Fills are translucent so they sit on the panel's material in either mode.
enum PanelColors {
    static let title = pair(light: gray(0x1D1D1F), dark: gray(0xF2F2F5))
    static let heroTitle = pair(light: gray(0x1D1D1F), dark: gray(0xF5F5F7))
    static let heading = pair(light: gray(0x48484D), dark: gray(0xC8C8CD))
    static let secondary = pair(light: gray(0x6E6E73), dark: gray(0xA1A1A8))
    static let subtle = pair(light: gray(0x8A8A8F), dark: gray(0x8E8E95))
    static let strong = pair(light: gray(0x2C2C30), dark: gray(0xE3E3E8))
    static let muted = pair(light: gray(0x8E8E93), dark: gray(0x9A9AA1))
    static let mutedBar = pair(light: gray(0xB4B6BC), dark: gray(0x76787F))
    static let icon = pair(light: gray(0x636368), dark: gray(0xB4B4BA))
    static let rowIcon = pair(light: gray(0x3A3A3F), dark: gray(0xD9D9DE))
    static let warning = pair(light: rgb(0xB25E00), dark: rgb(0xF0B35A))
    /// The "Fixture" badge: amber like the alert's Join button with dark text, the same in both modes.
    static let badgeFill = Color(nsColor: rgb(0xF5A524))
    static let badgeText = Color(nsColor: gray(0x1D1D1F))

    static let cardFill = fill(light: 0.04, dark: 0.05)
    static let cardBorder = fill(light: 0.07, dark: 0.07)
    static let rowButtonFill = fill(light: 0.06, dark: 0.08)
    static let rowButtonHoverFill = fill(light: 0.11, dark: 0.15)
    static let buttonFill = fill(light: 0.07, dark: 0.10)
    static let buttonHoverFill = fill(light: 0.12, dark: 0.17)
    static let hoverFill = fill(light: 0.05, dark: 0.06)
    static let track = fill(light: 0.09, dark: 0.10)
    static let stripe = fill(light: 0.04, dark: 0.045)
    static let divider = fill(light: 0.08, dark: 0.07)
    static let hairline = fill(light: 0.12, dark: 0.10)

    static let accent = Color.accentColor
    static let accentSoft = accentTint(light: 0.12, dark: 0.16)
    static let accentLine = accentTint(light: 0.45, dark: 0.5)
    /// The accent lifted toward white on dark backgrounds (and deepened a little on light ones) so the
    /// "Starts in 4 min" label stays readable on the accent-tinted card.
    static let accentText = accentShade(towardWhite: 0.35, towardBlack: 0.12)
    /// The accent button under the pointer.
    static let accentHover = accentShade(towardWhite: 0.12, towardBlack: 0.1)

    /// The accent blended toward white in dark mode, toward black in light mode.
    private static func accentShade(towardWhite: CGFloat, towardBlack: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            var accent = NSColor.controlAccentColor
            appearance.performAsCurrentDrawingAppearance {
                accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.controlAccentColor
            }
            return (isDark ? accent.blended(withFraction: towardWhite, of: .white) : accent.blended(withFraction: towardBlack, of: .black)) ?? accent
        })
    }

    private static func accentTint(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.controlAccentColor.withAlphaComponent(isDark ? dark : light)
        })
    }

    private static func pair(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// Black at `light` opacity in light mode, white at `dark` opacity in dark mode.
    private static func fill(light: CGFloat, dark: CGFloat) -> Color {
        pair(light: NSColor(white: 0, alpha: light), dark: NSColor(white: 1, alpha: dark))
    }

    private static func gray(_ hex: Int) -> NSColor { rgb(hex) }

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// A rounded, filled button that dims while pressed. Under the pointer its fill turns `hoverFill`
/// and the cursor becomes a pointing hand, like every clickable thing in the panel.
struct PanelFillButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color
    var cornerRadius: CGFloat
    var hoverFill: Color

    func makeBody(configuration: Configuration) -> some View {
        PanelFillButtonBody(configuration: configuration, style: self)
    }
}

private struct PanelFillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: PanelFillButtonStyle
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        configuration.label
            .foregroundStyle(style.foreground)
            .background(shape.fill(hovering ? style.hoverFill : style.fill))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .panelHover($hovering)
    }
}

extension View {
    /// What every clickable thing in the panel does under the pointer: `isHovered` follows it, so the
    /// control can brighten its fill, and the cursor becomes a pointing hand.
    func panelHover(_ isHovered: Binding<Bool>) -> some View {
        modifier(PanelHover(isHovered: isHovered))
    }
}

private struct PanelHover: ViewModifier {
    @Binding var isHovered: Bool

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovered = true
                    // Set on every move: AppKit resets the cursor when the pointer moves over the hosting view.
                    NSCursor.pointingHand.set()
                case .ended:
                    isHovered = false
                    NSCursor.arrow.set()
                }
            }
            .onDisappear {
                if isHovered { NSCursor.arrow.set() }
            }
    }
}

/// A thin rounded progress bar: the track, and the elapsed share in `color`.
struct PanelProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(color)
                .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 4)
        .background(Capsule().fill(PanelColors.track))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// The diagonal stripes behind an out-of-office row: 5 pt bands every 10 pt, running bottom-left to top-right.
struct PanelStripes: Shape {
    var bandWidth: CGFloat = 5
    var period: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Bands are measured across the stripes, so along the x axis they are √2 wider.
        let step = period * 2.squareRoot()
        let width = bandWidth * 2.squareRoot()
        let height = rect.height
        var start = rect.minX
        while start < rect.maxX + height {
            path.move(to: CGPoint(x: start, y: rect.minY))
            path.addLine(to: CGPoint(x: start + width, y: rect.minY))
            path.addLine(to: CGPoint(x: start + width - height, y: rect.maxY))
            path.addLine(to: CGPoint(x: start - height, y: rect.maxY))
            path.closeSubpath()
            start += step
        }
        return path
    }
}

extension PanelAction {
    var symbolName: String {
        switch self {
        case .join: return "video"
        case .directions: return "arrow.triangle.turn.up.right.diamond"
        }
    }

    var title: String {
        switch self {
        case .join: return "Join video call"
        case .directions: return "Directions"
        }
    }

    func accessibilityLabel(for meeting: Meeting) -> String {
        switch self {
        case .join: return "Join video call: \(meeting.title)"
        case .directions:
            return "Directions to \(LocationFormatter.physicalPlace(in: meeting.location).map(LocationFormatter.shortLocation) ?? meeting.title)"
        }
    }
}
