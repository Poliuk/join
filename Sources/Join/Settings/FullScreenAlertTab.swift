import SwiftUI
import JoinCore

/// When, where and how loudly the full-screen alert comes up, its snooze buttons and auto-close, and Show
/// Demo to try them, beside the settings it shows. How the alert looks is on Appearance.
struct FullScreenAlertTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences

        VStack(alignment: .leading, spacing: 22) {
            // No heading: the pane names the subject.
            SettingsBox {
                // Custom lead times save on Return or when the field loses focus, so editing
                // "3" → "35" → "5" can't briefly mean 35 minutes and fire alerts early. Never leaves the
                // rows below in view but dims and disables them, by the user's choice; their values stay
                // as they were, and picking a time brings them back.
                let alertsOn = preferences.fullScreenAlertsEnabled
                SettingsMinutesChoice(
                    title: "Alert me",
                    separator: false,
                    presets: SettingsOptions.leadTimeMinutes,
                    range: SettingsOptions.customLeadTimeRange,
                    presetTitle: SettingsOptions.leadTimeTitle(minutes:),
                    unit: SettingsOptions.minutesBeforeUnit,
                    fieldLabel: "Minutes before the event",
                    minutes: leadMinutes(preferences),
                    never: (SettingsOptions.leadTimeNeverTitle, alertsOff(preferences))
                )
                SettingsRow(title: "Show on", tone: alertsOn ? .primary : .disabled) {
                    Picker("Show on", selection: $preferences.alertScreens) {
                        ForEach(AlertScreens.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!alertsOn)
                }
                SettingsRow(title: "Sound", tone: alertsOn ? .primary : .disabled) {
                    HStack(spacing: 8) {
                        Button {
                            playSound(preferences.soundName)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                                .frame(width: 12)
                        }
                        .help("Play the sound")
                        .accessibilityLabel("Play the sound")
                        .disabled(preferences.soundName == nil)
                        // The tags are `String?`, the selection's type: a mismatch would show nothing as selected.
                        Picker("Sound", selection: $preferences.soundName) {
                            Text("None").tag(String?.none)
                            Divider()
                            ForEach(soundNames(including: preferences.soundName), id: \.self) { name in
                                Text(name).tag(Optional(name))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .disabled(!alertsOn)
                }
                // Only while a sound is chosen. Hiding it keeps the stored choice, so picking a
                // sound again brings the switch back as it was.
                if preferences.soundName != nil {
                    SettingsSwitchRow(title: "Repeat until it's closed", isOn: $preferences.soundRepeats, indented: true, enabled: alertsOn)
                }
            }

            // Stays enabled while Alert me is Never, as the user scoped Never: Show Demo still uses it.
            SettingsSection(title: "Snooze & auto-close") {
                snoozeChoice("First snooze button", \.first, separator: false)
                snoozeChoice("Second snooze button", \.second, separator: true)
                SettingsRow(title: SettingsOptions.autoCloseRowTitle) {
                    // The tags are `Int?`, nil for Never, the selection's type: a mismatch would show nothing as selected.
                    Picker(SettingsOptions.autoCloseRowTitle, selection: autoCloseSelection) {
                        ForEach(autoCloseChoices, id: \.self) { minutes in
                            Text(SettingsOptions.autoCloseTitle(minutes: minutes))
                                .tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            HStack {
                Spacer()
                ShowDemoButton()
            }
        }
        .padding(SettingsMetrics.panePadding)
    }

    // MARK: Lead time

    private func leadMinutes(_ preferences: Preferences) -> Binding<Int> {
        Binding(
            get: { Int(preferences.leadTime) / 60 },
            set: { preferences.leadTime = TimeInterval($0 * 60) }
        )
    }

    /// True while Alert me is set to Never.
    private func alertsOff(_ preferences: Preferences) -> Binding<Bool> {
        Binding(
            get: { !preferences.fullScreenAlertsEnabled },
            set: { preferences.fullScreenAlertsEnabled = !$0 }
        )
    }

    // MARK: Sound

    private func soundNames(including current: String?) -> [String] {
        guard let current, !SystemSounds.names.contains(current) else { return SystemSounds.names }
        return (SystemSounds.names + [current]).sorted()
    }

    private func playSound(_ name: String?) {
        guard let sound = SystemSounds.sound(named: name) else { return }
        sound.stop()
        sound.play()
    }

    // MARK: Snooze and auto-close

    private func snoozeChoice(_ title: String, _ button: WritableKeyPath<SnoozeDurations, TimeInterval>, separator: Bool) -> some View {
        let preferences = model.preferences
        return SettingsMinutesChoice(
            title: title,
            separator: separator,
            presets: SettingsOptions.snoozeMinutes,
            range: SettingsOptions.customSnoozeRange,
            presetTitle: SettingsOptions.durationTitle(minutes:),
            unit: SettingsOptions.minutesUnit,
            fieldLabel: "\(title), minutes",
            minutes: Binding(
                get: { SettingsOptions.wholeMinutes(preferences.snoozeDurations[keyPath: button]) },
                set: { minutes in preferences.snoozeDurations[keyPath: button] = TimeInterval(minutes * 60) }
            )
        )
    }

    /// Never (nil), then the minutes.
    private var autoCloseChoices: [Int?] {
        let preferences = model.preferences
        let current = SettingsOptions.autoCloseSelection(enabled: preferences.autoCloseEnabled, after: preferences.autoCloseAfter)
        return [nil] + SettingsOptions.autoCloseChoices(including: current)
    }

    private var autoCloseSelection: Binding<Int?> {
        let preferences = model.preferences
        return Binding(
            get: { SettingsOptions.autoCloseSelection(enabled: preferences.autoCloseEnabled, after: preferences.autoCloseAfter) },
            set: { minutes in
                if let minutes {
                    preferences.autoCloseAfter = TimeInterval(minutes * 60)
                    preferences.autoCloseEnabled = true
                } else {
                    preferences.autoCloseEnabled = false
                }
            }
        )
    }
}

/// Shows the demo full-screen alert, on this pane and beside Appearance's preview. Off while a real one
/// is on screen, which the demo never replaces; the help tag says why.
struct ShowDemoButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let alerting = model.alertCoordinator.isAlerting
        Button("Show Demo") { model.alertCoordinator.showDemoAlert() }
            .disabled(alerting)
            .help(alerting ? SettingsOptions.showDemoUnavailableHelp : SettingsOptions.showDemoHelp)
    }
}
