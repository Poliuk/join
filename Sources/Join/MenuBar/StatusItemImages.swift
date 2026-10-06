import AppKit
import JoinCore

/// Images for the menu bar item. Plain states use template images so the menu bar tints them;
/// the "starting soon" pill is drawn in full color, the system accent unless Settings changes it.
@MainActor
enum StatusItemImages {
    static let iconConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    static let textFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    private static let pillFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(iconConfiguration)
        image?.isTemplate = true
        return image
    }

    /// A 16 pt ring over a faint track; the arc is the share of the meeting still to run, from 12 o'clock clockwise.
    static func ring(remaining: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6
            let circle = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

            let track = NSBezierPath(ovalIn: circle)
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.35).setStroke()
            track.stroke()

            let fraction = min(max(remaining, 0), 1)
            guard fraction > 0.005 else { return true }
            let arc: NSBezierPath
            if fraction > 0.995 {
                arc = NSBezierPath(ovalIn: circle)
            } else {
                arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
                arc.lineCapStyle = .round
            }
            arc.lineWidth = 2
            NSColor.black.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The "starting soon" pill: a video icon and, optionally, the countdown, in `label` on `fill`.
    static func pill(text: String?, fill: NSColor, label: NSColor) -> NSImage {
        let height = max(16, NSStatusBar.system.thickness - 2)
        let icon = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [label]))
            )
        let iconSize = icon?.size ?? .zero
        let title = text.map { NSAttributedString(string: $0, attributes: [.font: pillFont, .foregroundColor: label]) }
        let titleWidth = ceil(title?.size().width ?? 0)
        let leading: CGFloat = 8
        let trailing: CGFloat = title == nil ? 8 : 9
        let gap: CGFloat = 6
        let width = ceil(leading + iconSize.width + (title == nil ? 0 : gap + titleWidth) + trailing)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            icon?.draw(in: NSRect(
                x: leading,
                y: ((rect.height - iconSize.height) / 2).rounded(),
                width: iconSize.width,
                height: iconSize.height
            ))
            if let title {
                // Center the cap height, so digits sit in the visual middle of the pill.
                let baseline = (rect.height - pillFont.capHeight) / 2
                title.draw(at: NSPoint(x: leading + iconSize.width + gap, y: (baseline + pillFont.descender).rounded()))
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The pill in the colors `pill` asks for, with the system accent for its automatic fill. The
    /// label is worked out when the pill is drawn, against the accent as drawn in that appearance.
    static func pill(text: String?, style pill: StartingSoonPill) -> NSImage {
        let label = NSColor(name: nil) { appearance in
            var accent = RGBA.white
            appearance.performAsCurrentDrawingAppearance { accent = NSColor.controlAccentColor.rgba }
            return NSColor(pill.resolvedText(accent: accent))
        }
        return self.pill(text: text, fill: pill.fill.map(NSColor.init) ?? .controlAccentColor, label: label)
    }
}
