import SwiftUI
import JoinCore

/// How the full-screen alert looks, and nothing else: the preview, Style's five cards, the Colors box, and
/// Restore Defaults for the look. When and how it alerts is on the Alerts pane, beside the notification, which
/// has no look to set. Laid out like the other panes, with every control at the right of its row as on Alerts (the
/// user's ask, 2026-10-19).
struct AppearanceTab: View {
    @Environment(AppModel.self) private var model
    @State private var previewBackdrop: AppearancePreviewBackdrop = .wallpaper
    /// The contrast warnings VoiceOver has been told about, or that were already shown.
    @State private var announcedWarnings: Set<AlertContrastWarning.Subject> = []

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            preview

            SettingsSection(title: "Style") {
                styleCards
                    .padding(.vertical, SettingsMetrics.boxInset)
            }

            // Every color row stays in view; editing any of them makes the look the Custom card's.
            SettingsSection(title: SettingsOptions.colorsSectionTitle) {
                colorRows
            } accessory: {
                // The look only: the Custom card's saved look, snooze, auto-close and the menu bar's pill stay.
                Button("Restore Defaults") { model.preferences.resetAppearance() }
                    .disabled(appearance.isDefault)
                    .help(SettingsOptions.restoreAppearanceHelp)
            }
        }
        .padding(SettingsMetrics.panePadding)
        .onAppear {
            announcedWarnings = Set(appearance.contrastWarnings.map(\.subject))
        }
        .task(id: appearance) { await announceNewWarnings() }
    }

    private var appearance: AlertAppearance { model.preferences.appearance }

    private func update(_ change: (inout AlertAppearance) -> Void) {
        var updated = model.preferences.appearance
        change(&updated)
        model.preferences.appearance = updated
    }

    // MARK: Preview

    /// The pane's first box, with no heading, since the preview names itself: the preview, then what it's drawn
    /// over, a row like any other. Under the box, Test Full-Screen Alert at its right, as on Alerts, and, while Alert
    /// me is Never, a note beside it that only real alerts stop.
    private var preview: some View {
        SettingsSection(
            title: nil,
            warning: model.preferences.fullScreenAlertsEnabled ? nil : SettingsOptions.alertMeNeverNote
        ) {
            AppearancePreview(
                appearance: appearance,
                backdrop: previewBackdrop,
                snoozeDurations: model.preferences.snoozeDurations.all
            )
            .padding(.vertical, SettingsMetrics.boxInset)
            SettingsRow(title: "Preview over") {
                Picker("Preview over", selection: $previewBackdrop) {
                    ForEach(AppearancePreviewBackdrop.allCases) { backdrop in
                        Text(backdrop.title).tag(backdrop)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        } accessory: {
            TestFullScreenAlertButton()
        }
    }

    // MARK: Style

    /// Dark, Light, High contrast, Midnight and Custom. The card outlined is the one the look matches,
    /// Custom while it matches no preset. Custom holds the user's own look, which a preset or Restore
    /// Defaults leaves alone, and shows a placeholder until there is one.
    private var styleCards: some View {
        let selected = appearance.style
        let customLook = model.preferences.customAppearance ?? (selected == .custom ? appearance : nil)
        return HStack(spacing: 12) {
            ForEach(AlertStyle.allCases) { style in
                AppearanceStyleCard(
                    name: style.name,
                    swatch: swatch(for: style, customLook: customLook),
                    isSelected: style == selected,
                    help: style.help(hasCustomLook: customLook != nil)
                ) {
                    switch style {
                    case .preset(let preset): model.preferences.appearance = preset.appearance
                    case .custom: model.preferences.applyCustomAppearance()
                    }
                }
            }
        }
    }

    private func swatch(for style: AlertStyle, customLook: AlertAppearance?) -> AppearanceStyleCard.Swatch? {
        switch style {
        case .preset(let preset): return preset.swatch
        case .custom: return customLook?.swatch
        }
    }

    // MARK: Colors

    /// Backdrop, then a pop-up of named swatches for each color, with Strength under a tint and an earlier
    /// build's label color on a Text row under its button. Each contrast warning sits under the row to change.
    /// Every control sits at the right of its row, and a well goes before its pop-up, so the pop-up keeps that edge.
    @ViewBuilder
    private var colorRows: some View {
        let warnings = appearance.contrastWarnings

        SettingsRow(title: AlertColorRow.backdropTitle, separator: false) {
            Picker(AlertColorRow.backdropTitle, selection: Binding(
                get: { appearance.blurMode },
                set: { mode in update { $0.blurMode = mode } }
            )) {
                ForEach(appearance.backdropChoices, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }

        colorRow(.tint)
        if appearance.tint != nil {
            SettingsRow(title: AlertColorRow.tintStrengthTitle, indented: true) {
                AppearancePercentSlider(
                    title: AlertColorRow.tintStrengthAccessibilityTitle,
                    value: Binding(get: { appearance.tintStrength }, set: { value in update { $0.tintStrength = value } }),
                    range: 0...1
                )
                .frame(width: 220)
            }
        }
        warningRows(under: .tint, in: warnings)

        colorRow(.eventText)
        warningRows(under: .eventText, in: warnings)

        colorRow(.joinButton)
        legacyTextRow(.join)
        warningRows(under: .joinButton, in: warnings)

        colorRow(.buttons)
        legacyTextRow(.dismissAndSnooze)
        warningRows(under: .buttons, in: warnings)
    }

    private func colorRow(_ row: AlertColorRow) -> some View {
        SettingsRow(title: row.title) {
            SettingsColorChoice(
                title: row.accessibilityTitle,
                wellLabel: row.wellLabel,
                choice: row.choice,
                automaticDot: row == .tint ? .none : .automatic,
                supportsOpacity: row.wellSupportsOpacity,
                stored: { model.preferences.appearance.storedColor(for: row) },
                shown: { model.preferences.appearance.shownColor(for: row) },
                pick: { item in update { $0.pick(item, for: row) } },
                setColor: { color in update { $0.setColor(color, for: row) } }
            )
        }
    }

    /// Only while an earlier build's label color is stored for the kind; its Automatic clears it.
    @ViewBuilder
    private func legacyTextRow(_ kind: AlertButtonKind) -> some View {
        if appearance.showsLegacyText(for: kind), let text = appearance[button: kind].text {
            SettingsRow(title: LegacyTextRow.title, indented: true) {
                SettingsLegacyTextChoice(
                    title: kind.legacyTextAccessibilityTitle,
                    wellLabel: kind.legacyTextWellLabel,
                    color: text,
                    clear: { update { $0.clearLegacyText(for: kind) } },
                    setColor: { color in update { $0.setLegacyText(color, for: kind) } }
                )
            }
        }
    }

    /// The tint's warning hangs under Strength, so it takes that row's indent.
    private func warningRows(under row: AlertColorRow, in warnings: [AlertContrastWarning]) -> some View {
        ForEach(warnings.filter { $0.row == row }) { warning in
            SettingsRowWarning(message: warning.message, indented: row == .tint)
        }
    }

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

/// One of Style's cards: a miniature of the alert (backdrop, text lines, Join bar) over its name. Every
/// name stays primary, so a row with no card outlined never looks disabled.
private struct AppearanceStyleCard: View {
    typealias Swatch = (background: RGBA, line: RGBA, join: RGBA)

    let name: String
    /// nil draws the Custom card's placeholder, until there's a look of the user's own.
    let swatch: Swatch?
    let isSelected: Bool
    let help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                tile
                Text(name)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .helpTag(help)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return Group {
            if let swatch {
                miniature(swatch)
                    .background(shape.fill(Color(swatch.background)))
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(shape.fill(SettingsPalette.chip))
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 58)
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

    private func miniature(_ swatch: Swatch) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 5) {
                Capsule()
                    .fill(Color(swatch.line))
                    .frame(width: proxy.size.width * 0.46, height: 4)
                Capsule()
                    .fill(Color(swatch.line))
                    .opacity(0.6)
                    .frame(width: proxy.size.width * 0.28, height: 3)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(swatch.join))
                    .frame(width: proxy.size.width * 0.4, height: 9)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
