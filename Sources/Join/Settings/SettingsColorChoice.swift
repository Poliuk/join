import AppKit
import SwiftUI
import JoinCore

/// A color pop-up, fitted to its items: named swatches, a separator and Other…. While Other… is picked a well sits
/// before the pop-up, so the pop-up keeps the row's trailing edge whether the well shows or not, and picking Other…
/// opens the color panel on that well. Which item
/// shows is `ColorChoice.selection`, in JoinCore. Like `SettingsMinutesChoice` with Custom…, this view keeps
/// whether Other… was picked: until another item is, or the color changes from elsewhere (a Style card,
/// Restore Defaults).
struct SettingsColorChoice: View {
    /// The pop-up's name for VoiceOver.
    let title: String
    /// The well's name for VoiceOver.
    let wellLabel: String
    let choice: ColorChoice
    /// The dot of the swatch that stores no color: the accent, no tint, or Automatic.
    var automaticDot: SettingsSwatchDot = .automatic
    /// Whether the well picks an opacity too.
    var supportsOpacity = false
    /// The row's stored color, nil for its automatic item. Read live, so a write can be told apart.
    let stored: () -> RGBA?
    /// The color the row draws with, opacity included: what the well shows and the swatches are matched to.
    let shown: () -> RGBA
    let pick: (ColorChoice.Item) -> Void
    /// The well's color, as picked in the color panel.
    let setColor: (RGBA) -> Void

    @State private var other: OtherItem = .unpicked
    /// The colors as this control's last write left them, to tell its own changes from outside ones.
    @State private var ownWrite: Colors?

    /// Whether Other… was picked here, and, once it is, whether its well still has to open the color panel.
    private enum OtherItem: Equatable {
        case unpicked
        case picked(opensPanel: Bool)
    }

    private struct Colors: Equatable {
        var stored: RGBA?
        var shown: RGBA
    }

    var body: some View {
        let current = colors
        let selected = choice.selection(stored: current.stored, shown: current.shown, otherPicked: other != .unpicked)
        HStack(spacing: SettingsMetrics.controlSpacing) {
            if selected == .other {
                well(showing: current.shown)
            }
            // A closure, not `set: select`: Swift 6.3's IR generation crashes on the thunk it makes for the method.
            Picker(title, selection: Binding(get: { selected }, set: { select($0) })) {
                ForEach(choice.swatches) { swatch in
                    SettingsSwatchItem(name: swatch.name, dot: swatch.color.map(SettingsSwatchDot.color) ?? automaticDot)
                        .tag(ColorChoice.Item.swatch(swatch))
                }
                Divider()
                SettingsSwatchItem(name: ColorChoice.otherTitle, dot: .other)
                    .tag(ColorChoice.Item.other)
            }
            .labelsHidden()
            .fixedSize()
        }
        .onChange(of: current) { _, newValue in
            if newValue == ownWrite {
                ownWrite = nil
            } else {
                // A Style card, Restore Defaults or another pane put a color here: show what it is.
                other = .unpicked
            }
        }
    }

    private var colors: Colors {
        Colors(stored: stored(), shown: shown())
    }

    private func well(showing color: RGBA) -> some View {
        SettingsColorWell(
            label: wellLabel,
            color: color,
            supportsOpacity: supportsOpacity,
            opensPanel: other == .picked(opensPanel: true),
            panelDidOpen: { if other == .picked(opensPanel: true) { other = .picked(opensPanel: false) } },
            onChange: { color in write { setColor(color) } }
        )
    }

    private func select(_ item: ColorChoice.Item) {
        other = item == .other ? .picked(opensPanel: true) : .unpicked
        write { pick(item) }
    }

    private func write(_ change: () -> Void) {
        let before = colors
        change()
        let after = colors
        if after != before { ownWrite = after }
    }
}

/// The legacy **Text** row's control: a well, then Automatic / Custom, fitted to its items, like a color pop-up's.
/// It only shows while a label color saved by an earlier build is stored, so Custom is always the item shown;
/// Automatic clears the color, and the row goes.
struct SettingsLegacyTextChoice: View {
    /// The pop-up's name for VoiceOver.
    let title: String
    let wellLabel: String
    let color: RGBA
    let clear: () -> Void
    let setColor: (RGBA) -> Void

    var body: some View {
        HStack(spacing: SettingsMetrics.controlSpacing) {
            SettingsColorWell(label: wellLabel, color: color, onChange: setColor)
            Picker(title, selection: Binding(get: { true }, set: { custom in if !custom { clear() } })) {
                Text(LegacyTextRow.automaticTitle).tag(false)
                Text(LegacyTextRow.customTitle).tag(true)
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// A pop-up item: its dot, then its name.
private struct SettingsSwatchItem: View {
    let name: String
    let dot: SettingsSwatchDot

    var body: some View {
        Label {
            Text(name)
        } icon: {
            Image(nsImage: dot.image)
        }
    }
}

/// The dot before a color pop-up's item. Never a template image, so the menu and the pop-up draw it in
/// its own colors rather than tinting it.
enum SettingsSwatchDot: Hashable {
    case color(RGBA)
    /// The system accent, as drawn now.
    case accent
    /// No color: the tint's None.
    case none
    /// Half white, half black: a color that follows the rest of the look.
    case automatic
    /// A color wheel, for Other….
    case other

    nonisolated private static let size = NSSize(width: 12, height: 12)
    private static var cache: [SettingsSwatchDot: NSImage] = [:]

    var image: NSImage {
        if let cached = Self.cache[self] { return cached }
        let image = draw()
        Self.cache[self] = image
        return image
    }

    /// Drawn whenever the image is, so the accent and the outline follow the current appearance. Nonisolated,
    /// with the drawing below it: AppKit runs an image's drawing handler on whatever thread draws the image.
    nonisolated private func draw() -> NSImage {
        let image = NSImage(size: Self.size, flipped: false) { rect in
            let dot = rect.insetBy(dx: 0.5, dy: 0.5)
            let circle = NSBezierPath(ovalIn: dot)
            NSGraphicsContext.saveGraphicsState()
            circle.addClip()
            fill(dot)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            let outline = NSBezierPath(ovalIn: dot.insetBy(dx: 0.25, dy: 0.25))
            outline.lineWidth = 0.5
            outline.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    nonisolated private func fill(_ rect: NSRect) {
        switch self {
        case .color(let color):
            // A translucent swatch shows over a checkerboard, as the color panel shows opacity.
            if color.alpha < 1 { Self.checkerboard(in: rect) }
            NSColor(color).setFill()
            rect.fill(using: .sourceOver)
        case .accent:
            NSColor.controlAccentColor.setFill()
            rect.fill()
        case .none:
            NSColor.white.setFill()
            rect.fill()
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + 1.5, y: rect.minY + 1.5))
            slash.line(to: NSPoint(x: rect.maxX - 1.5, y: rect.maxY - 1.5))
            slash.lineWidth = 1.5
            NSColor.systemRed.setStroke()
            slash.stroke()
        case .automatic:
            NSColor.white.setFill()
            rect.fill()
            let half = NSBezierPath()
            half.move(to: NSPoint(x: rect.maxX, y: rect.maxY))
            half.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            half.line(to: NSPoint(x: rect.minX, y: rect.minY))
            half.close()
            NSColor(RGBA(rgb: 0x1D1D1F)).setFill()
            half.fill()
        case .other:
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let steps = 24
            for step in 0..<steps {
                let start = CGFloat(step) * 360 / CGFloat(steps)
                let wedge = NSBezierPath()
                wedge.move(to: center)
                wedge.appendArc(withCenter: center, radius: rect.width, startAngle: start, endAngle: start + 360 / CGFloat(steps) + 1)
                wedge.close()
                NSColor(hue: CGFloat(step) / CGFloat(steps), saturation: 0.8, brightness: 1, alpha: 1).setFill()
                wedge.fill()
            }
        }
    }

    nonisolated private static func checkerboard(in rect: NSRect) {
        NSColor.white.setFill()
        rect.fill()
        NSColor(white: 0.8, alpha: 1).setFill()
        let square: CGFloat = 3
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX + (row.isMultiple(of: 2) ? 0 : square)
            while x < rect.maxX {
                NSRect(x: x, y: y, width: square, height: square).fill()
                x += square * 2
            }
            y += square
            row += 1
        }
    }
}

/// An `NSColorWell`, which, unlike SwiftUI's ColorPicker, can open the color panel from code: picking
/// Other… opens it at once. The color panel is shared, so opening it here takes it from any other well.
private struct SettingsColorWell: NSViewRepresentable {
    let label: String
    let color: RGBA
    var supportsOpacity = false
    /// Opens the color panel on this well, once; `panelDidOpen` then lets the caller clear its request.
    var opensPanel = false
    var panelDidOpen: () -> Void = {}
    let onChange: (RGBA) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(style: .default)
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorDidChange(_:))
        well.isContinuous = true
        well.setContentHuggingPriority(.required, for: .horizontal)
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        coordinator.supportsOpacity = supportsOpacity
        well.supportsAlpha = supportsOpacity
        well.setAccessibilityLabel(label)
        // A well without opacity shows its color opaque, as it picks it. Only a change from elsewhere is set:
        // setting the color back while it's being dragged in the panel would fight the drag.
        let shown = supportsOpacity ? color : color.withAlpha(1)
        if !ColorChoice.matches(coordinator.normalized(well.color.rgba), shown) {
            well.color = NSColor(shown)
        }
        if opensPanel, !coordinator.isOpening {
            coordinator.isOpening = true
            let panelDidOpen = self.panelDidOpen
            DispatchQueue.main.async {
                // Dismantled meanwhile (`dismantleNSView` called it off): no panel for a well that's gone.
                guard coordinator.isOpening else { panelDidOpen(); return }
                coordinator.isOpening = false
                well.activate(true)
                panelDidOpen()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSColorWell, context: Context) -> CGSize? {
        CGSize(width: 38, height: 22)
    }

    static func dismantleNSView(_ well: NSColorWell, coordinator: Coordinator) {
        // A panel about to open on this well doesn't, and an open one closes: either would have no well to change.
        coordinator.isOpening = false
        guard well.isActive else { return }
        well.deactivate()
        NSColorPanel.shared.orderOut(nil)
    }

    final class Coordinator: NSObject {
        var onChange: (RGBA) -> Void = { _ in }
        var supportsOpacity = false
        /// Between asking for the panel and opening it on the next turn of the main queue; cleared if the
        /// well is dismantled meanwhile.
        var isOpening = false

        func normalized(_ color: RGBA) -> RGBA {
            supportsOpacity ? color : color.withAlpha(1)
        }

        @objc func colorDidChange(_ sender: NSColorWell) {
            onChange(normalized(sender.color.rgba))
        }
    }
}
