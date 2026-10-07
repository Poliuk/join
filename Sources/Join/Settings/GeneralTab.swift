import AppKit
import ServiceManagement
import SwiftUI
import JoinCore

@MainActor
struct GeneralTab: View {
    @Environment(AppModel.self) private var model
    /// Read from the system on appear and whenever the app or the Settings window comes back, so
    /// approving Join! in System Settings clears the hint. Never read or written in a fixture run.
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    private static let neverTag = 0

    var body: some View {
        @Bindable var preferences = model.preferences

        VStack(alignment: .leading, spacing: 22) {
            SettingsBox {
                SettingsSwitchRow(title: "Open at login", isOn: openAtLogin, separator: false, enabled: !model.isFixture)
                if let note = model.isFixture ? SettingsOptions.openAtLoginFixtureNote : launchAtLoginError {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(model.isFixture ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)
                }
                SettingsRow(title: "Menu bar") {
                    Picker("Menu bar", selection: $preferences.menuBarDisplay) {
                        ForEach(MenuBarDisplay.allCases, id: \.self) { display in
                            Text(display.title).tag(display)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsSection(title: "Alert") {
                // Custom lead times save on Return or when the field loses focus, so editing
                // "3" → "35" → "5" can't briefly mean 35 minutes and fire alerts early.
                SettingsMinutesChoice(
                    title: "Alert me",
                    separator: false,
                    presets: SettingsOptions.leadTimeMinutes,
                    range: SettingsOptions.customLeadTimeRange,
                    presetTitle: SettingsOptions.leadTimeTitle(minutes:),
                    unit: SettingsOptions.minutesBeforeUnit,
                    fieldLabel: "Minutes before the event",
                    minutes: leadMinutes(preferences)
                )
                SettingsRow(title: "Show alert on") {
                    Picker("Show alert on", selection: $preferences.alertScreens) {
                        ForEach(AlertScreens.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(title: "Sound") {
                    HStack(spacing: 8) {
                        Button {
                            playSound(preferences.soundName)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                                .frame(width: 12)
                        }
                        .help("Play alert sound")
                        .accessibilityLabel("Play alert sound")
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
                }
                // Only while a sound is chosen. Hiding it keeps the stored choice, so picking a
                // sound again brings the switch back as it was.
                if preferences.soundName != nil {
                    SettingsSwitchRow(title: "Repeat until the alert is closed", isOn: $preferences.soundRepeats, indented: true)
                }
            }

            eventsSection

            OutOfOfficeSection()

            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: "Snooze & auto-close") {
                    snoozeChoice("First snooze button", preferences: preferences, index: 0)
                    snoozeChoice("Second snooze button", preferences: preferences, index: 1)
                    SettingsRow(title: "Close alerts automatically") {
                        Picker("Close alerts automatically", selection: autoCloseSelection(preferences)) {
                            ForEach(autoCloseChoices(preferences), id: \.self) { minutes in
                                Text(SettingsOptions.autoCloseTitle(minutes: minutes == Self.neverTag ? nil : minutes))
                                    .tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                alertOffers(preferences)
            }

            SettingsSection(title: UpdateCopy.sectionTitle) {
                SettingsSwitchRow(title: UpdateCopy.automaticChecksTitle, isOn: $preferences.checksForUpdates, separator: false)
                SettingsSeparator()
                updateStatusRow
                updateNotes
            }
        }
        .padding(SettingsMetrics.panePadding)
        .onAppear { refreshLaunchAtLogin() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLogin()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if (notification.object as? NSWindow)?.identifier == .settingsWindow { refreshLaunchAtLogin() }
        }
    }

    // MARK: Open at login

    /// Only the user's clicks reach the login item; refreshing from the system just updates the switch.
    private var openAtLogin: Binding<Bool> {
        Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) })
    }

    private static var loginItemStatus: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .notRegistered
        @unknown default: return .notRegistered
        }
    }

    private func refreshLaunchAtLogin() {
        guard !model.isFixture else { return }
        let status = Self.loginItemStatus
        launchAtLogin = SettingsOptions.opensAtLogin(status)
        launchAtLoginError = SettingsOptions.openAtLoginHint(status)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard !model.isFixture else { return }
        do {
            if enabled != SettingsOptions.opensAtLogin(Self.loginItemStatus) {
                try LaunchAtLogin.setEnabled(enabled)
            }
            refreshLaunchAtLogin()
        } catch {
            refreshLaunchAtLogin()
            launchAtLoginError = error.localizedDescription
        }
    }

    // MARK: Lead time

    private func leadMinutes(_ preferences: Preferences) -> Binding<Int> {
        Binding(
            get: { Int(preferences.leadTime) / 60 },
            set: { preferences.leadTime = TimeInterval($0 * 60) }
        )
    }

    // MARK: Events

    /// The switch for events nobody else is on, decided per event rather than per calendar.
    /// Between Alert and Out of office by the user's choice; 1.1.0 had it under the calendar list.
    private var eventsSection: some View {
        @Bindable var preferences = model.preferences

        return SettingsSection(title: SettingsOptions.eventsSectionTitle) {
            SettingsSwitchRow(
                title: SettingsOptions.eventsWithoutParticipantsTitle,
                isOn: $preferences.showsEventsWithoutParticipants,
                separator: false
            )
            Text(SettingsOptions.eventsWithoutParticipantsNote)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
        }
    }

    // MARK: Menu bar and sound

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

    private func snoozeChoice(_ title: String, preferences: Preferences, index: Int) -> some View {
        SettingsMinutesChoice(
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

    private func autoCloseChoices(_ preferences: Preferences) -> [Int] {
        let current = SettingsOptions.autoCloseSelection(enabled: preferences.autoCloseEnabled, after: preferences.autoCloseAfter)
        return [Self.neverTag] + SettingsOptions.autoCloseChoices(including: current)
    }

    private func autoCloseSelection(_ preferences: Preferences) -> Binding<Int> {
        Binding(
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

    // MARK: Updates

    /// "Join! 1.0.0 · Checked 5 minutes ago" or the update on offer, then how an install is going, with
    /// Check Now and the update bar's button: Install, Download Page after a failed install, Show in Finder
    /// once revealed. Install waits for a check under way, which may change the offer.
    private var updateStatusRow: some View {
        let checker = model.updateChecker
        let status = checker.status
        let offered = checker.offeredUpdate
        let lastCheck = checker.lastCheck
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(UpdateCopy.statusLine(
                        current: checker.currentVersion, status: status, offered: offered, lastCheck: lastCheck, now: context.date
                    ))
                }
                if let update = checker.offeredUpdate, checker.install != .idle {
                    Text(UpdateCopy.barMessage(version: update.version, install: checker.install))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(UpdateCopy.checkNowTitle) { checker.checkNow() }
                    .disabled(checker.currentVersion == nil || checker.isChecking || checker.isInstalling)
                if checker.offeredUpdate != nil {
                    let title = UpdateCopy.barButtonTitle(install: checker.install)
                    Button(title ?? UpdateCopy.installTitle) { model.performUpdateAction() }
                        .disabled(title == nil || (checker.install == .idle && (!checker.canInstall || checker.isChecking)))
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 40)
    }

    /// Why the last install failed, or that a fixture run can't install.
    @ViewBuilder
    private var updateNotes: some View {
        let checker = model.updateChecker
        if case .failed(let failure) = checker.install {
            Text(UpdateCopy.failureReason(failure))
                .font(.subheadline)
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
        } else if checker.offeredUpdate != nil, checker.install == .idle, !checker.canInstall {
            Text(UpdateCopy.installFixtureNote)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
        }
    }

    private func alertOffers(_ preferences: Preferences) -> some View {
        HStack(spacing: 6) {
            Text("The alert offers")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
            ForEach(Array(SettingsOptions.alertOffers(snoozeDurations: preferences.snoozeDurations).enumerated()), id: \.offset) { _, label in
                SettingsChip(text: label)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}
