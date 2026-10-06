import SwiftUI
import JoinCore

@MainActor
struct AppearanceTab: View {
    @Environment(AppModel.self) private var model
    @State private var previewBackdrop: AppearancePreviewBackdrop = .wallpaper
    /// The contrast warnings VoiceOver has been told about, or that were already shown.
    @State private var announcedWarnings: Set<AlertContrastWarning.Subject> = []
    /// Whether the pill's contrast warning has been announced, or was already shown.
    @State private var announcedPillWarning = false

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

            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: "Starting soon") {
                    startingSoonRows
                }
                if let warning = pill.contrastWarning(accent: accent) {
                    AppearanceContrastWarning(message: warning)
                }
            }

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    model.preferences.resetAppearance()
                    model.preferences.startingSoonPill = .default
                }
                .disabled(appearance.isDefault && pill.isDefault)
            }
        }
        .padding(SettingsMetrics.panePadding)
        .onAppear {
            announcedWarnings = Set(appearance.contrastWarnings.map(\.subject))
            announcedPillWarning = pill.contrastWarning(accent: accent) != nil
        }
        .task(id: appearance) { await announceNewWarnings() }
        .task(id: pill) { await announcePillWarning() }
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
                    .disabled(model.alertCoordinator.isAlerting)
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
                wellLabel: "Tint color",
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
                wellLabel: "Text color",
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
                wellLabel: "\(name) text color",
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
                wellLabel: "\(name) fill color",
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

    // MARK: Starting soon

    private var pill: StartingSoonPill { model.preferences.startingSoonPill }

    /// The system accent as the pill draws it now.
    private var accent: RGBA { NSColor.controlAccentColor.rgba }

    private func updatePill(_ change: (inout StartingSoonPill) -> Void) {
        var updated = model.preferences.startingSoonPill
        change(&updated)
        model.preferences.startingSoonPill = updated
    }

    @ViewBuilder
    private var startingSoonRows: some View {
        StartingSoonPreview(pill: pill, showsText: model.preferences.menuBarShowsNextEvent)

        SettingsMinutesChoice(
            title: "Appears",
            presets: SettingsOptions.startingSoonMinutes,
            range: StartingSoonPill.minuteRange,
            presetTitle: SettingsOptions.startingSoonTitle(minutes:),
            unit: SettingsOptions.minutesBeforeUnit,
            fieldLabel: "Minutes before the meeting the pill appears",
            minutes: Binding(get: { pill.minutes }, set: { minutes in updatePill { $0.minutes = minutes } })
        )

        SettingsRow(title: "Fill") {
            AppearanceColorChoice(
                title: "Pill fill",
                wellLabel: "Pill fill color",
                offTitle: "Accent color",
                wellFirst: true,
                isCustom: Binding(
                    get: { pill.fill != nil },
                    set: { custom in updatePill { $0.setFillCustom(custom, accent: accent) } }
                ),
                color: pillColorBinding(get: { $0.fill }, set: { $0.fill = $1 })
            )
        }

        SettingsRow(title: "Text color") {
            AppearanceColorChoice(
                title: "Pill text color",
                wellLabel: "Pill text color",
                offTitle: "Automatic",
                wellFirst: true,
                isCustom: Binding(
                    get: { pill.text != nil },
                    set: { custom in updatePill { $0.setTextCustom(custom, accent: accent) } }
                ),
                color: pillColorBinding(get: { $0.text }, set: { $0.text = $1 })
            )
        }
    }

    private func pillColorBinding(
        get: @escaping (StartingSoonPill) -> RGBA?,
        set: @escaping (inout StartingSoonPill, RGBA) -> Void
    ) -> Binding<Color> {
        Binding(
            get: { Color(get(model.preferences.startingSoonPill) ?? .white) },
            set: { color in
                var rgba = RGBA(color)
                rgba.alpha = 1
                updatePill { set(&$0, rgba) }
            }
        )
    }

    // MARK: Helpers

    /// Tells VoiceOver about warnings that appeared since the last announcement. Debounced, so
    /// dragging in the color panel is read out once, with the ratio it settles on.
    private func announceNewWarnings() async {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        let warnings = appearance.contrastWarnings
        let new = warnings.filter { !announcedWarnings.contains($0.subject) }
        announcedWarnings = Set(warnings.map(\.subject))
        guard !new.isEmpty else { return }
        AccessibilityNotification.Announcement(new.map(\.message).joined(separator: " ")).post()
    }

    /// Like `announceNewWarnings`, for the pill's warning.
    private func announcePillWarning() async {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        let warning = pill.contrastWarning(accent: accent)
        defer { announcedPillWarning = warning != nil }
        guard let warning, !announcedPillWarning else { return }
        AccessibilityNotification.Announcement(warning).post()
    }

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

/// The pill as the menu bar will draw it, on a strip like the menu bar, above its settings.
private struct StartingSoonPreview: View {
    let pill: StartingSoonPill
    /// Icon only in the menu bar means a pill without text.
    let showsText: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Starting in \(pill.minutes) min or less")
                Text("Replaces the countdown in the menu bar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(nsImage: StatusItemImages.pill(text: showsText ? "Next in \(min(4, pill.minutes)) min" : nil, style: pill))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(light: RGBA(rgb: 0xE4E4E9), dark: RGBA(rgb: 0x1E1E21)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SettingsPalette.boxBorder, lineWidth: 1)
                )
                .accessibilityLabel("Preview of the starting-soon pill")
        }
        .padding(.vertical, 8)
        .frame(minHeight: 48)
    }
}

/// An Automatic (or None) / Custom pop-up, with a color well while Custom.
private struct AppearanceColorChoice: View {
    let title: String
    let wellLabel: String
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
        ColorPicker(wellLabel, selection: $color, supportsOpacity: false)
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
                    get: { clamped },
                    set: { value = ($0 * 100).rounded() / 100 }
                ),
                in: range
            ) {
                Text(title)
            }
            .labelsHidden()
            // The platform slider would report its position within the range, not the percentage.
            .accessibilityValue(percent)
            .frame(minWidth: 60)
            Text(percent)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 40, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var clamped: Double { min(max(value, range.lowerBound), range.upperBound) }

    private var percent: String { "\(Int((clamped * 100).rounded()))%" }
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
