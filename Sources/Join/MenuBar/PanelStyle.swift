import AppKit
import SwiftUI
import JoinCore

/// The panel's colors, from `PanelPalette`: five inks and translucent fills over the frosted glass, each
/// resolved for the drawing appearance (light or dark) and for Increase Contrast. The inks are fixed
/// sRGB, never vibrant, so their contrast on the frost is what the palette's tests check.
enum PanelColors {
    static let primary = palette { $0.palette.primary }
    static let strong = palette { $0.palette.strong }
    static let secondary = palette { $0.palette.secondary }
    static let tertiary = palette { $0.palette.tertiary }
    static let warning = palette { $0.palette.warning }
    static let mutedBar = palette { $0.palette.mutedBar }
    /// Opaque; `PanelFrost` draws it at the frost opacity.
    static let frost = palette { $0.palette.frost }
    static let card = palette { $0.palette.card }
    /// The "Fixture" badge: amber like the alert's Join button with dark text, the same in both modes.
    static let badgeFill = Color(nsColor: NSColor(RGBA(rgb: 0xF5A524)))
    static let badgeText = Color(nsColor: NSColor(RGBA(rgb: 0x1D1D1F)))

    /// The panel's outline, the header divider and card borders; stronger with Increase Contrast.
    static let separator = palette { $0.inkAt($0.increasedContrast ? PanelPalette.increasedContrastSeparator(dark: $0.dark) : PanelPalette.separator) }
    /// A border that filled buttons and the switch's track get with Increase Contrast only, so they keep
    /// a 3:1 edge.
    static let controlBorder = palette { $0.inkAt($0.increasedContrast ? PanelPalette.increasedContrastControlBorder(dark: $0.dark) : 0) }
    static let buttonFill = palette { $0.inkAt(PanelPalette.buttonFill) }
    static let buttonHoverFill = palette { $0.inkAt(PanelPalette.buttonHoverFill) }
    static let rowButtonFill = palette { $0.inkAt(PanelPalette.rowButtonFill) }
    static let rowButtonHoverFill = palette { $0.inkAt(PanelPalette.rowButtonHoverFill) }
    static let hoverFill = palette { $0.inkAt(PanelPalette.hoverFill) }
    static let stripe = palette { $0.inkAt(PanelPalette.stripe) }
    static let track = palette { $0.inkAt(PanelPalette.progressTrack(dark: $0.dark)) }

    // The Today | 7 Days switch: a faint track and a raised thumb, no accent color.
    static let segmentTrack = palette { $0.inkAt(PanelPalette.stripe) }
    static let segmentThumb = palette { $0.dark ? RGBA.white.withAlpha(PanelPalette.buttonFill) : .white }
    /// Drawn 1 pt wide with Increase Contrast (`PanelFilterToggle`), so the chosen half keeps a 3:1 edge.
    static let segmentThumbEdge = palette { $0.inkAt($0.increasedContrast ? ($0.dark ? 0.45 : 0.55) : PanelPalette.separator) }
    static let segmentThumbShadow = palette { $0.dark || $0.increasedContrast ? RGBA.black.withAlpha(0) : RGBA.black.withAlpha(0.08) }
    static let segmentHover = palette { $0.inkAt(PanelPalette.stripe) }
    static let segmentPressed = palette { $0.inkAt(PanelPalette.buttonFill) }
    static let segmentTrackEdge = controlBorder
    static let segmentDisabled = palette { $0.palette.tertiary.withAlpha(0.4) }

    static let accent = Color.accentColor
    /// The starting-soon card's tint, drawn over the regular card (`PanelHeroView`).
    static let accentSoft = palette { $0.accent.withAlpha($0.palette.startingSoonTint(accent: $0.accent, dark: $0.dark)) }
    static let accentLine = palette { $0.accent.withAlpha($0.dark ? 0.5 : 0.45) }
    /// "Starts in 4 min": the accent stepped toward white or black until it reads at 4.6:1 on the
    /// accent-tinted card over the frost, whatever the accent.
    static let accentText = palette { resolved in
        let envelope = resolved.dark ? PanelPalette.darkGlassEnvelope : PanelPalette.lightGlassEnvelope
        let surface = resolved.palette.surface(over: envelope)
        let card = resolved.palette.startingSoonCard(accent: resolved.accent, over: surface, dark: resolved.dark)
        return PanelPalette.legibleAccent(resolved.accent, on: card, dark: resolved.dark)
    }
    /// The prominent button, solved per accent so its label reads at 4.5:1 at rest and under the pointer.
    static let accentButton = palette { PanelPalette.accentButton($0.accent, dark: $0.dark).fill }
    static let accentButtonHover = palette { PanelPalette.accentButton($0.accent, dark: $0.dark).hover }
    /// White, or near-black on accents where it reads better (yellow, orange, green).
    static let accentButtonLabel = palette { PanelPalette.accentButton($0.accent, dark: $0.dark).label }

    /// What a color is worked out from: the palette for the drawing appearance, and the accent in it.
    struct Resolved {
        let palette: PanelPalette
        let dark: Bool
        let increasedContrast: Bool
        let accent: RGBA

        /// The ink (white in dark mode, black in light mode) at `opacity`.
        func inkAt(_ opacity: Double) -> RGBA { palette.ink.withAlpha(opacity) }
    }

    private static func palette(_ make: @escaping (Resolved) -> RGBA) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(make(resolve(appearance)))
        })
    }

    private static func resolve(_ appearance: NSAppearance) -> Resolved {
        let name = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
        let dark = name == .darkAqua || name == .accessibilityHighContrastDarkAqua
        // AppKit names the high-contrast appearances when Increase Contrast is on; the workspace flag
        // covers drawing paths that don't pass them on.
        let increasedContrast = name == .accessibilityHighContrastAqua || name == .accessibilityHighContrastDarkAqua
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        var accent = NSColor.controlAccentColor
        appearance.performAsCurrentDrawingAppearance {
            accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.controlAccentColor
        }
        return Resolved(
            palette: .standard(dark: dark, increasedContrast: increasedContrast),
            dark: dark,
            increasedContrast: increasedContrast,
            accent: accent.rgba
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
    var border: Color = PanelColors.controlBorder

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
            .overlay(shape.strokeBorder(style.border, lineWidth: 1))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .panelHover($hovering)
    }
}

extension View {
    /// A card on the frost: the card fill with a separator edge, which keeps it visible in light mode,
    /// where the white card sits on near-white frost.
    func panelCard(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(PanelColors.card))
            .overlay(shape.strokeBorder(PanelColors.separator, lineWidth: 1))
    }

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
