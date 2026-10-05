import AppKit
import SwiftUI

/// The Settings window's colors, as light and dark pairs.
enum SettingsPalette {
    static let window = dynamic(light: NSColor(srgbRed: 0xF1 / 255, green: 0xF1 / 255, blue: 0xF3 / 255, alpha: 1),
                                dark: NSColor(srgbRed: 0x23 / 255, green: 0x23 / 255, blue: 0x25 / 255, alpha: 1))
    static let box = Color(nsColor: dynamic(light: NSColor(srgbRed: 0xFB / 255, green: 0xFB / 255, blue: 0xFC / 255, alpha: 1),
                                            dark: NSColor(srgbRed: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1)))
    static let boxBorder = Color(nsColor: dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.06)))
    static let separator = Color(nsColor: dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.08)))
    static let chip = Color(nsColor: dynamic(light: NSColor(white: 0, alpha: 0.065), dark: NSColor(white: 1, alpha: 0.1)))
    static let field = Color(nsColor: dynamic(light: .white,
                                              dark: NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x20 / 255, alpha: 1)))
    static let fieldBorder = Color(nsColor: dynamic(light: NSColor(white: 0, alpha: 0.14), dark: NSColor(white: 1, alpha: 0.08)))
    static let connector = Color(nsColor: dynamic(light: NSColor(white: 0, alpha: 0.22), dark: NSColor(white: 1, alpha: 0.24)))

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

enum SettingsMetrics {
    static let paneWidth: CGFloat = 720
    static let panePadding = EdgeInsets(top: 20, leading: 20, bottom: 24, trailing: 20)
    /// How far a dependent row sits in from its parent; its connector line lives in this gutter.
    static let indent: CGFloat = 30
}

/// A heading above a grouped box.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.semibold))
                .padding(.leading, 2)
                .accessibilityAddTraits(.isHeader)
            SettingsBox { content }
        }
    }
}

/// The rounded box that groups rows.
struct SettingsBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsPalette.box, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(SettingsPalette.boxBorder, lineWidth: 1)
            }
    }
}

struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(SettingsPalette.separator)
            .frame(height: 1)
    }
}

/// Label on the left, control on the right, with a hairline above unless it opens its box.
struct SettingsRow<Control: View>: View {
    enum Tone {
        case primary
        case secondary
        case disabled
    }

    let title: String
    var tone: Tone = .primary
    var indented = false
    var separator = true
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            if separator {
                SettingsSeparator()
                    .padding(.leading, indented ? SettingsMetrics.indent : 0)
            }
            HStack(spacing: 16) {
                Text(title)
                    .foregroundStyle(labelStyle)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                control
            }
            .padding(.leading, indented ? SettingsMetrics.indent : 0)
            .padding(.vertical, 6)
            .frame(minHeight: 40)
        }
        // A dependent row hangs off its parent: its hairline starts at the indent and an elbow
        // runs down from under the parent's label to its own.
        .background(alignment: .leading) {
            if indented {
                SettingsChildConnector()
                    .frame(width: SettingsMetrics.indent)
            }
        }
    }

    private var labelStyle: HierarchicalShapeStyle {
        switch tone {
        case .primary: return .primary
        case .secondary: return .secondary
        case .disabled: return .tertiary
        }
    }
}

private struct SettingsChildConnector: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let x: CGFloat = 9
                let mid = proxy.size.height / 2
                let radius: CGFloat = 5
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: mid - radius))
                path.addQuadCurve(to: CGPoint(x: x + radius, y: mid), control: CGPoint(x: x, y: mid))
                path.addLine(to: CGPoint(x: proxy.size.width - 8, y: mid))
            }
            .stroke(SettingsPalette.connector, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

/// A switch row. The visible label doubles as the switch's accessibility label.
struct SettingsSwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    var indented = false
    var separator = true
    var enabled = true

    var body: some View {
        SettingsRow(title: title, tone: enabled ? .primary : .disabled, indented: indented, separator: separator) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!enabled)
        }
    }
}

/// A small rounded label, as in "The alert offers 1 min · 5 min".
struct SettingsChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(SettingsPalette.chip, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Lays subviews out left to right and wraps them onto new lines. A subview tagged with
/// `SettingsFlowFill` takes the rest of its line, wrapping first when less than its minimum is left.
struct SettingsFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let frames = arrange(subviews: subviews, width: width)
        let height = frames.map(\.maxY).max() ?? 0
        let usedWidth = frames.map(\.maxX).max() ?? 0
        return CGSize(width: proposal.width ?? usedWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews: subviews, width: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [CGRect] {
        struct Line {
            var items: [(index: Int, size: CGSize)] = []
            var width: CGFloat = 0
        }
        var lines: [Line] = [Line()]
        for (index, subview) in subviews.enumerated() {
            let fillMinimum = subview[SettingsFlowFill.self]
            var size = subview.sizeThatFits(.unspecified)
            if let fillMinimum { size.width = fillMinimum }
            size.width = min(size.width, width)
            let needed = (lines[lines.count - 1].items.isEmpty ? 0 : spacing) + size.width
            if !lines[lines.count - 1].items.isEmpty, lines[lines.count - 1].width + needed > width {
                lines.append(Line())
            }
            var line = lines[lines.count - 1]
            if fillMinimum != nil, width.isFinite {
                let used = line.width + (line.items.isEmpty ? 0 : spacing)
                size.width = max(fillMinimum ?? 0, width - used)
            }
            line.width += (line.items.isEmpty ? 0 : spacing) + size.width
            line.items.append((index, size))
            lines[lines.count - 1] = line
        }

        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        var y: CGFloat = 0
        for line in lines where !line.items.isEmpty {
            let lineHeight = line.items.map(\.size.height).max() ?? 0
            var x: CGFloat = 0
            for item in line.items {
                frames[item.index] = CGRect(x: x, y: y + (lineHeight - item.size.height) / 2,
                                            width: item.size.width, height: item.size.height)
                x += item.size.width + spacing
            }
            y += lineHeight + spacing
        }
        return frames
    }
}

/// Marks a `SettingsFlowLayout` subview that fills the rest of its line; the value is its minimum width.
struct SettingsFlowFill: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

private struct SettingsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Scrolls a pane's content and reports the content's natural height, so the window can fit it
/// and only scroll when the screen is too short.
struct SettingsPaneScroll<Content: View>: View {
    let onContentHeightChange: (CGFloat) -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: SettingsContentHeightKey.self, value: proxy.size.height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(SettingsContentHeightKey.self, perform: onContentHeightChange)
    }
}
