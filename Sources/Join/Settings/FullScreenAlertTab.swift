import SwiftUI
import JoinCore

/// When, where and how loudly the full-screen alert comes up, its snooze buttons and auto-close, and Show
/// Demo to try them, beside the settings it shows. How the alert looks is on Appearance.
@MainActor
struct FullScreenAlertTab: View {
    @Environment(AppModel.self) private var model

    /// The auto-close pop-up's tag for Never.
    private static let neverTag = 0

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
                        Picker("Sound", selection: soundSelection(preferences)) {
                            Text("None").tag("")
                            Divider()
                            ForEach(soundNames(including: preferences.soundName), id: \.self) { name in
                                Text(name).tag(name)
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
                snoozeChoice("First snooze button", index: 0)
                snoozeChoice("Second snooze button", index: 1)
                SettingsRow(title: SettingsOptions.autoCloseRowTitle) {
                    Picker(SettingsOptions.autoCloseRowTitle, selection: autoCloseSelection) {
                        ForEach(autoCloseChoices, id: \.self) { minutes in
                            Text(SettingsOptions.autoCloseTitle(minutes: minutes == Self.neverTag ? nil : minutes))
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

    private func soundSelection(_ preferences: Preferences) -> Binding<String> {
        Binding(
            get: { preferences.soundName ?? "" },
            set: { preferences.soundName = $0.isEmpty ? nil : $0 }
        )
    }

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

    private func snoozeChoice(_ title: String, index: Int) -> some View {
        let preferences = model.preferences
        return SettingsMinutesChoice(
            title: title,
            separator: index > 0,
            presets: SettingsOptions.snoozeMinutes,
            range: SettingsOptions.customSnoozeRange,
            presetTitle: SettingsOptions.durationTitle(minutes:),
            unit: SettingsOptions.minutesUnit,
            fieldLabel: "\(title), minutes",
            minutes: Binding(
                get: { SettingsOptions.wholeMinutes(preferences.snoozeDurations[index]) },
                set: { minutes in
                    var durations = preferences.snoozeDurations
                    durations[index] = TimeInterval(minutes * 60)
                    preferences.snoozeDurations = durations
                }
            )
        )
    }

    private var autoCloseChoices: [Int] {
        let preferences = model.preferences
        let current = SettingsOptions.autoCloseSelection(enabled: preferences.autoCloseEnabled, after: preferences.autoCloseAfter)
        return [Self.neverTag] + SettingsOptions.autoCloseChoices(including: current)
    }

    private var autoCloseSelection: Binding<Int> {
        let preferences = model.preferences
        return Binding(
            get: {
                SettingsOptions.autoCloseSelection(enabled: preferences.autoCloseEnabled, after: preferences.autoCloseAfter)
                    ?? Self.neverTag
            },
            set: { minutes in
                if minutes == Self.neverTag {
                    preferences.autoCloseEnabled = false
                } else {
                    preferences.autoCloseAfter = TimeInterval(minutes * 60)
                    preferences.autoCloseEnabled = true
                }
            }
        )
    }
}

/// Shows the demo full-screen alert, on this pane and beside Appearance's preview. Off while a real one
/// is on screen, which the demo never replaces; the help tag says why.
@MainActor
struct ShowDemoButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let alerting = model.alertCoordinator.isAlerting
        Button("Show Demo") { model.alertCoordinator.showDemoAlert() }
            .disabled(alerting)
            .help(alerting ? SettingsOptions.showDemoUnavailableHelp : SettingsOptions.showDemoHelp)
    }
}
