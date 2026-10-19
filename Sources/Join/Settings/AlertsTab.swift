import SwiftUI
import JoinCore

/// Both kinds of alert, each with its own time or Never and a button to try it, then the snooze durations they
/// share: the Full-screen alert box (when, where and how loudly it comes up, and when it closes by itself, then
/// Test Full-Screen Alert), the Notification box (when, and whether it plays a sound, then Test Notification),
/// and the Snooze box. How the full-screen alert looks is on Appearance.
struct AlertsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            fullScreenAlertSection
            notificationSection
            snoozeSection
        }
        .padding(SettingsMetrics.panePadding)
    }

    // MARK: Full-screen alert

    /// Custom lead times save on Return or when the field loses focus, so editing "3" → "35" → "5" can't briefly
    /// mean 35 minutes and fire alerts early. Never leaves the rows below in view but dims and disables them, by
    /// the user's choice; their values stay as they were, and picking a time brings them back. Close
    /// automatically is one of them since 1.3.0: it only ever closes the full-screen alert. Test Full-Screen
    /// Alert, under the box at its right, works whatever Alert me says.
    private var fullScreenAlertSection: some View {
        @Bindable var preferences = model.preferences
        let alertsOn = preferences.fullScreenAlertsEnabled

        return SettingsSection(title: SettingsOptions.fullScreenAlertSectionTitle) {
            SettingsMinutesChoice(
                title: SettingsOptions.alertMeTitle,
                separator: false,
                presets: SettingsOptions.leadTimeMinutes,
                range: SettingsOptions.customLeadTimeRange,
                presetTitle: SettingsOptions.leadTimeTitle(minutes:),
                unit: SettingsOptions.minutesBeforeUnit,
                fieldLabel: SettingsOptions.alertMeFieldLabel,
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
                HStack(spacing: SettingsMetrics.controlSpacing) {
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
            // Only while a sound is chosen. Hiding it keeps the stored choice, so picking a sound again brings the
            // switch back as it was.
            if preferences.soundName != nil {
                SettingsSwitchRow(title: "Repeat until it's closed", isOn: $preferences.soundRepeats, indented: true, enabled: alertsOn)
            }
            SettingsRow(title: SettingsOptions.autoCloseRowTitle, tone: alertsOn ? .primary : .disabled) {
                // The tags are `Int?`, nil for Never, the selection's type: a mismatch would show nothing as selected.
                Picker(SettingsOptions.autoCloseRowTitle, selection: autoCloseSelection) {
                    ForEach(autoCloseChoices, id: \.self) { minutes in
                        Text(SettingsOptions.autoCloseTitle(minutes: minutes))
                            .tag(minutes)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!alertsOn)
            }
        } accessory: {
            TestFullScreenAlertButton()
        }
    }

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

    private func soundNames(including current: String?) -> [String] {
        guard let current, !SystemSounds.names.contains(current) else { return SystemSounds.names }
        return (SystemSounds.names + [current]).sorted()
    }

    private func playSound(_ name: String?) {
        guard let sound = SystemSounds.sound(named: name) else { return }
        sound.stop()
        sound.play()
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

    // MARK: Notification

    /// Notify me works as Alert me does, Never included, with its own time. Play sound is its sibling, dimmed
    /// while it's Never. Test Notification, under the box at its right, beside the footnote, works whatever
    /// Notify me says.
    private var notificationSection: some View {
        @Bindable var preferences = model.preferences
        let notificationsOn = preferences.notificationsEnabled

        return SettingsSection(title: SettingsOptions.notificationSectionTitle, footnote: SettingsOptions.notificationFootnote) {
            SettingsMinutesChoice(
                title: SettingsOptions.notifyMeTitle,
                separator: false,
                presets: SettingsOptions.notificationLeadTimeMinutes,
                range: SettingsOptions.customNotificationLeadTimeRange,
                presetTitle: SettingsOptions.leadTimeTitle(minutes:),
                unit: SettingsOptions.minutesBeforeUnit,
                fieldLabel: SettingsOptions.notifyMeFieldLabel,
                minutes: notificationMinutes(preferences),
                never: (SettingsOptions.leadTimeNeverTitle, notificationsOff(preferences)),
                help: SettingsOptions.notifyMeHelp
            )
            SettingsSwitchRow(title: SettingsOptions.playSoundTitle, isOn: $preferences.notificationPlaysSound, enabled: notificationsOn)
        } accessory: {
            TestNotificationButtonView()
        }
    }

    private func notificationMinutes(_ preferences: Preferences) -> Binding<Int> {
        Binding(
            get: { Int(preferences.notificationLeadTime) / 60 },
            set: { preferences.notificationLeadTime = TimeInterval($0 * 60) }
        )
    }

    /// True while Notify me is set to Never.
    private func notificationsOff(_ preferences: Preferences) -> Binding<Bool> {
        Binding(
            get: { !preferences.notificationsEnabled },
            set: { preferences.notificationsEnabled = !$0 }
        )
    }

    // MARK: Snooze

    /// Shared by both kinds, which the footnote spells out, and enabled whatever either is set to, as the user
    /// scoped Never: both test buttons still use it.
    private var snoozeSection: some View {
        SettingsSection(title: SettingsOptions.snoozeSectionTitle, footnote: SettingsOptions.snoozeFootnote) {
            snoozeChoice(SettingsOptions.firstSnoozeTitle, fieldLabel: SettingsOptions.firstSnoozeFieldLabel, \.first, separator: false)
            snoozeChoice(SettingsOptions.secondSnoozeTitle, fieldLabel: SettingsOptions.secondSnoozeFieldLabel, \.second, separator: true)
        }
    }

    private func snoozeChoice(
        _ title: String,
        fieldLabel: String,
        _ snooze: WritableKeyPath<SnoozeDurations, TimeInterval>,
        separator: Bool
    ) -> some View {
        let preferences = model.preferences
        return SettingsMinutesChoice(
            title: title,
            separator: separator,
            presets: SettingsOptions.snoozeMinutes,
            range: SettingsOptions.customSnoozeRange,
            presetTitle: SettingsOptions.durationTitle(minutes:),
            unit: SettingsOptions.minutesUnit,
            fieldLabel: fieldLabel,
            minutes: Binding(
                get: { SettingsOptions.wholeMinutes(preferences.snoozeDurations[keyPath: snooze]) },
                set: { minutes in preferences.snoozeDurations[keyPath: snooze] = TimeInterval(minutes * 60) }
            )
        )
    }
}

/// Test Notification, under the Notification box at its right, outside it: shows the demo event's card. Always
/// enabled.
private struct TestNotificationButtonView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(SettingsOptions.testNotificationTitle) { model.notificationCoordinator.showTestNotification() }
            .help(SettingsOptions.testNotificationHelp)
    }
}

/// Test Full-Screen Alert: shows the demo event's full-screen alert, under the Full-screen alert box at its right
/// and under Appearance's preview box at its right. Off while a real one is on screen, which the test never
/// replaces; the help tag says why.
struct TestFullScreenAlertButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let alerting = model.alertCoordinator.isAlerting
        Button(SettingsOptions.testFullScreenAlertTitle) { model.alertCoordinator.showDemoAlert() }
            .disabled(alerting)
            .help(alerting ? SettingsOptions.testFullScreenAlertUnavailableHelp : SettingsOptions.testFullScreenAlertHelp)
    }
}
