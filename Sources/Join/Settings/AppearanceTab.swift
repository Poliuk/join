import SwiftUI
import JoinCore

@MainActor
struct AppearanceTab: View {
    @Environment(AppModel.self) private var model
    @State private var previewBackdrop: AppearancePreviewBackdrop = .wallpaper

    private enum Column {
        static let name: CGFloat = 132
        static let color: CGFloat = 160
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            preview

            VStack(alignment: .leading, spacing: 8) {
                styleHeader
                SettingsBox {
                    presetCards
                        .padding(.vertical, 12)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: "Alert") {
                    alertRows
                }
                warnings { $0 == .text }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: "Buttons") {
                    buttonsHeader
                    buttonRow(.join)
                    buttonRow(.dismissAndSnooze)
                }
                warnings { $0 != .text }
            }

            HStack {
                Spacer()
                Button("Restore Defaults") { model.preferences.resetAppearance() }
                    .disabled(appearance.isDefault)
            }
        }
        .padding(SettingsMetrics.panePadding)
    }

    private var appearance: AlertAppearance { model.preferences.appearance }

    private func update(_ change: (inout AlertAppearance) -> Void) {
        var updated = model.preferences.appearance
        change(&updated)
        model.preferences.appearance = updated
    }

    // MARK: Preview and style

    private var preview: some View {
        VStack(spacing: 10) {
            AppearancePreview(
                appearance: appearance,
                backdrop: previewBackdrop,
                snoozeDurations: model.preferences.snoozeDurations
            )
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("Preview on")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Picker("Preview on", selection: $previewBackdrop) {
                        ForEach(AppearancePreviewBackdrop.allCases) { backdrop in
                            Text(backdrop.title).tag(backdrop)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                Spacer()
                Button("Show Demo Alert") { model.alertCoordinator.showDemoAlert() }
            }
        }
        .font(.system(size: 13))
    }

    private var styleHeader: some View {
        HStack {
            Text("Style")
                .font(.body.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if appearance.matchingPreset == nil {
                Text("Custom")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var presetCards: some View {
        let selected = appearance.matchingPreset
        return HStack(spacing: 12) {
            ForEach(AlertAppearancePreset.allCases) { preset in
                AppearancePresetCard(preset: preset, isSelected: preset == selected) {
                    model.preferences.appearance = preset.appearance
                }
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Alert

    @ViewBuilder
    private var alertRows: some View {
        SettingsRow(title: "Backdrop", separator: false) {
            Picker("Backdrop", selection: Binding(
                get: { appearance.blurMode },
                set: { mode in update { $0.blurMode = mode } }
            )) {
                Text(BlurMode.dark.displayName).tag(BlurMode.dark)
                Text(BlurMode.light.displayName).tag(BlurMode.light)
                if appearance.blurMode == .none {
                    Text(BlurMode.none.displayName).tag(BlurMode.none)
                }
            }
            .labelsHidden()
            .fixedSize()
        }

        SettingsRow(title: "Tint") {
            AppearanceColorChoice(
                title: "Tint",
                offTitle: "None",
                wellFirst: true,
                isCustom: Binding(
                    get: { appearance.tint != nil },
                    set: { enabled in update { $0.setTintEnabled(enabled) } }
                ),
                color: colorBinding(get: { $0.tint }, set: { $0.tint = $1 })
            )
        }

        if appearance.tint != nil {
            SettingsRow(title: "Tint strength", indented: true) {
                AppearancePercentSlider(
                    title: "Tint strength",
                    value: Binding(get: { appearance.tintStrength }, set: { value in update { $0.tintStrength = value } }),
                    range: 0...1
                )
                .frame(width: 220)
            }
        }

        SettingsRow(title: "Text color") {
            AppearanceColorChoice(
                title: "Text color",
                offTitle: "Automatic",
                wellFirst: true,
                isCustom: Binding(
                    get: { appearance.textColor != nil },
                    set: { custom in update { $0.setTextColorCustom(custom) } }
                ),
                color: colorBinding(get: { $0.textColor }, set: { $0.textColor = $1 })
            )
        }
    }

    // MARK: Buttons

    private var buttonsHeader: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: Column.name, height: 1)
            Text("Text").frame(width: Column.color, alignment: .leading)
            Text("Fill").frame(width: Column.color, alignment: .leading)
            Text("Fill opacity").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(minHeight: 30)
        .accessibilityHidden(true)
    }

    private func buttonRow(_ kind: AlertButtonKind) -> some View {
        let name = kind == .join ? "Join button" : "Dismiss and Snooze"
        return VStack(spacing: 0) {
            SettingsSeparator()
            buttonRowControls(kind, name: name)
                .padding(.vertical, 6)
                .frame(minHeight: 40)
        }
    }

    private func buttonRowControls(_ kind: AlertButtonKind, name: String) -> some View {
        HStack(spacing: 12) {
            Text(kind.displayName)
                .frame(width: Column.name, alignment: .leading)
            AppearanceColorChoice(
                title: "\(name) text",
                offTitle: "Automatic",
                wellFirst: false,
                isCustom: Binding(
                    get: { appearance[button: kind].text != nil },
                    set: { custom in update { $0.setButtonTextCustom(custom, for: kind) } }
                ),
                color: colorBinding(get: { $0[button: kind].text }, set: { $0[button: kind].text = $1 })
            )
            .frame(width: Column.color, alignment: .leading)
            AppearanceColorChoice(
                title: "\(name) fill",
                offTitle: "Automatic",
                wellFirst: false,
                isCustom: Binding(
                    get: { appearance[button: kind].fill != nil },
                    set: { custom in update { $0.setButtonFillCustom(custom, for: kind) } }
                ),
                color: colorBinding(get: { $0[button: kind].fill }, set: { $0[button: kind].fill = $1 })
            )
            .frame(width: Column.color, alignment: .leading)
            AppearancePercentSlider(
                title: "\(name) fill opacity",
                value: Binding(
                    get: { appearance[button: kind].fillOpacity },
                    set: { value in update { $0[button: kind].fillOpacity = value } }
                ),
                range: kind.fillOpacityRange
            )
        }
    }

    // MARK: Helpers

    private func warnings(where include: @escaping (AlertContrastWarning.Subject) -> Bool) -> some View {
        let shown = appearance.contrastWarnings.filter { include($0.subject) }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(shown) { warning in
                AppearanceContrastWarning(message: warning.message)
            }
        }
    }

    /// Only shown while the color is custom, so the getter's fallback is never on screen.
    private func colorBinding(
        get: @escaping (AlertAppearance) -> RGBA?,
        set: @escaping (inout AlertAppearance, RGBA) -> Void
    ) -> Binding<Color> {
        Binding(
            get: { Color(get(model.preferences.appearance) ?? .white) },
            set: { color in
                var rgba = RGBA(color)
                rgba.alpha = 1
                update { set(&$0, rgba) }
            }
        )
    }
}

/// An Automatic (or None) / Custom pop-up, with a color well while Custom.
private struct AppearanceColorChoice: View {
    let title: String
    let offTitle: String
    /// The Alert rows put the well before the pop-up; the Buttons table after it.
    let wellFirst: Bool
    @Binding var isCustom: Bool
    @Binding var color: Color

    var body: some View {
        HStack(spacing: 8) {
            if wellFirst && isCustom { well }
            Picker(title, selection: $isCustom) {
                Text(offTitle).tag(false)
                Text("Custom").tag(true)
            }
            .labelsHidden()
            .fixedSize()
            if !wellFirst && isCustom { well }
        }
    }

    private var well: some View {
        ColorPicker("\(title) color", selection: $color, supportsOpacity: false)
            .labelsHidden()
    }
}

/// A slider in whole percent, with its value beside it.
private struct AppearancePercentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { min(max(value, range.lowerBound), range.upperBound) },
                    set: { value = ($0 * 100).rounded() / 100 }
                ),
                in: range
            ) {
                Text(title)
            }
            .labelsHidden()
            .frame(minWidth: 60)
            Text("\(Int((min(max(value, range.lowerBound), range.upperBound) * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 40, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

private struct AppearancePresetCard: View {
    let preset: AlertAppearancePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                swatch
                Text(preset.name)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var swatch: some View {
        let colors = preset.swatch
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return GeometryReader { proxy in
            VStack(spacing: 5) {
                Capsule()
                    .fill(Color(colors.line))
                    .frame(width: proxy.size.width * 0.46, height: 4)
                Capsule()
                    .fill(Color(colors.line))
                    .opacity(0.6)
                    .frame(width: proxy.size.width * 0.28, height: 3)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(colors.join))
                    .frame(width: proxy.size.width * 0.4, height: 9)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 58)
        .background(shape.fill(Color(colors.background)))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(-2)
            } else {
                shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
    }
}

private struct AppearanceContrastWarning: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color(light: RGBA(rgb: 0xA15C00), dark: RGBA(rgb: 0xFFB340)))
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
