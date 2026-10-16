import AppKit
import SwiftUI
import JoinCore

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
    /// A warning's words: an orange that keeps 4.5:1 on the window and the boxes, darker than the system
    /// orange in light mode, the system orange itself in dark mode.
    static let warning = Color(nsColor: dynamic(light: NSColor(srgbRed: 0xA1 / 255, green: 0x4C / 255, blue: 0, alpha: 1),
                                                dark: .systemOrange))

    /// Nonisolated: AppKit asks a dynamic color for its value on whatever thread is drawing.
    nonisolated private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
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

/// A heading above a grouped box, and optionally a footnote under it, for what the box's rows can't say.
struct SettingsSection<Content: View>: View {
    let title: String
    var footnote: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.semibold))
                .padding(.leading, 2)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                SettingsBox { content }
                if let footnote {
                    Text(footnote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                }
            }
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
/// An indented row depends on the row above it, and is left out, not dimmed, while that row is
/// off: no sound, no tint, a preset rather than Custom…. The disabled tone is for rows beside a
/// setting that turns them off, as Show on and Sound are while Alert me is Never, and Play sound while
/// Notify me is.
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

/// A line that reads as an alert: an orange warning sign, then the message in orange. Contrast warnings
/// sit directly under the row that causes them; Appearance's Never note sits under the preview.
struct SettingsWarning: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: .systemOrange))
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(SettingsPalette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A help tag, or none for nil.
    @ViewBuilder
    func helpTag(_ text: String?) -> some View {
        if let text {
            help(text)
        } else {
            self
        }
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
            if let fillMinimum, width.isFinite {
                let used = line.width + (line.items.isEmpty ? 0 : spacing)
                size.width = max(fillMinimum, width - used)
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
/// Nonisolated because the layout reads it, and SwiftUI may run a `Layout` (a `Sendable` protocol) off
/// the main actor.
nonisolated struct SettingsFlowFill: LayoutValueKey {
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

/// A row with a pop-up of preset minutes, optionally "Never", and "Custom…". Custom adds an indented
/// row with a minutes field and a stepper, and the pop-up keeps showing Custom while the custom value
/// happens to match a preset. The field saves only on Return or when it loses focus: saving every
/// keystroke would let "3" → "35" → "5" briefly mean 35 minutes. What the pop-up shows and what each
/// choice changes is `MinutesChoice`, in JoinCore.
struct SettingsMinutesChoice: View {
    let title: String
    var separator = true
    let presets: [Int]
    let range: ClosedRange<Int>
    /// The pop-up item for a preset: "5 minutes before", "5 minutes".
    let presetTitle: (Int) -> String
    /// After the field: "minutes before", "minutes".
    let unit: (Int) -> String
    /// What VoiceOver calls the field and the stepper.
    let fieldLabel: String
    @Binding var minutes: Int
    /// Alert me only: the item after the presets, and whether it is chosen. `minutes` keeps the last
    /// time meanwhile. A preset or Custom… turns it off at once, Custom… with the kept time in its field.
    var never: (title: String, isChosen: Binding<Bool>)? = nil
    /// Drawn before the pop-up, as General's Starting soon row draws the menu bar's preview.
    var accessory: AnyView? = nil
    /// The row's help tag.
    var help: String? = nil

    @State private var customChosen = false
    @State private var draft = 0
    /// The value this control last wrote, to tell its own edits from outside ones (Restore Defaults).
    @State private var ownWrite: Int?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        SettingsRow(title: title, separator: separator) {
            HStack(spacing: 10) {
                if let accessory { accessory }
                Picker(title, selection: selection) {
                    ForEach(presets, id: \.self) { minutes in
                        Text(presetTitle(minutes)).tag(MinutesChoice.Item.preset(minutes))
                    }
                    if let never {
                        Text(never.title).tag(MinutesChoice.Item.never)
                    }
                    Divider()
                    Text("Custom…").tag(MinutesChoice.Item.custom)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .helpTag(help)
        .onAppear {
            draft = minutes
            customChosen = rule.opensAsCustom(minutes: minutes, neverChosen: isNever)
        }
        .onChange(of: minutes) { _, newValue in
            // Draft first, so the custom row's commit as it disappears writes nothing.
            draft = newValue
            let savedHere = newValue == ownWrite
            if savedHere { ownWrite = nil }
            customChosen = rule.customPicked(afterChangeTo: newValue, neverChosen: isNever, customPicked: customChosen, savedHere: savedHere)
        }
        if showsCustom {
            SettingsRow(title: "Custom time", tone: .secondary, indented: true) {
                HStack(spacing: 6) {
                    TextField(fieldLabel, value: $draft, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .focused($fieldFocused)
                        .onSubmit(commit)
                        .onChange(of: fieldFocused) { _, focused in
                            if !focused { commit() }
                        }
                        .onDisappear(perform: commit)
                    Stepper(fieldLabel, value: stepped, in: range)
                        .labelsHidden()
                    Text(unit(draft))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rule: MinutesChoice {
        MinutesChoice(presets: presets, offersNever: never != nil)
    }

    private var isNever: Bool {
        never?.isChosen.wrappedValue ?? false
    }

    private var showsCustom: Bool {
        rule.showsCustomRow(minutes: minutes, neverChosen: isNever, customPicked: customChosen)
    }

    private var selection: Binding<MinutesChoice.Item> {
        Binding(
            get: { rule.selection(minutes: minutes, neverChosen: isNever, customPicked: customChosen) },
            set: { item in
                let pick = rule.picking(item)
                // Set the draft first: the custom field's commit as it disappears must find nothing to
                // save, so it can't undo a preset or end Never.
                draft = pick.minutes ?? minutes
                customChosen = pick.customPicked
                if let value = pick.minutes { write(value) }
                // After the time, so alerts come back with it rather than with the one before.
                if let neverChosen = pick.neverChosen { setNever(neverChosen) }
                if item == .custom { DispatchQueue.main.async { fieldFocused = true } }
            }
        )
    }

    private var stepped: Binding<Int> {
        Binding(get: { minutes }, set: { saveCustom(clamped($0)) })
    }

    private func commit() {
        let value = clamped(draft)
        draft = value
        saveCustom(value)
    }

    /// A value from the custom row. Picking Custom… already left Never, so this only saves the time.
    private func saveCustom(_ value: Int) {
        write(value)
    }

    private func setNever(_ chosen: Bool) {
        guard let never, never.isChosen.wrappedValue != chosen else { return }
        never.isChosen.wrappedValue = chosen
    }

    private func write(_ value: Int) {
        guard value != minutes else { return }
        ownWrite = value
        minutes = value
    }

    private func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
