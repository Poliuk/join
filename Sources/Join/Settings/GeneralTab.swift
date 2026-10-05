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
    /// Whether "Custom…" is chosen; it stays chosen while the custom value happens to match a preset.
    @State private var customLeadTime = false
    /// What's typed in the custom lead-time field. Written to Preferences only on Return or when the
    /// field loses focus: saving every keystroke would make "3" → "35" → "5" briefly mean 35 minutes
    /// and fire alerts early.
    @State private var leadMinutesDraft = Int(Preferences.defaultLeadTime) / 60
    @FocusState private var leadFieldFocused: Bool

    private static let customLeadTag = -1
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
                SettingsRow(title: "Alert me", separator: false) {
                    Picker("Alert me", selection: leadTimeSelection(preferences)) {
                        ForEach(SettingsOptions.leadTimeMinutes, id: \.self) { minutes in
                            Text(SettingsOptions.leadTimeTitle(minutes: minutes)).tag(minutes)
                        }
                        Divider()
                        Text("Custom…").tag(Self.customLeadTag)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if showsCustomLeadTime(preferences) {
                    customLeadTimeRow(preferences)
                }
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
                SettingsSwitchRow(
                    title: "Repeat until the alert is closed",
                    isOn: soundRepeats(preferences),
                    indented: true,
                    enabled: preferences.soundName != nil
                )
            }

            OutOfOfficeSection()

            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: "Snooze & auto-close") {
                    SettingsRow(title: "First snooze button", separator: false) {
                        snoozePicker("First snooze button", preferences: preferences, index: 0)
                    }
                    SettingsRow(title: "Second snooze button") {
                        snoozePicker("Second snooze button", preferences: preferences, index: 1)
                    }
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
        }
        .padding(SettingsMetrics.panePadding)
        .onAppear {
            refreshLaunchAtLogin()
            leadMinutesDraft = Int(preferences.leadTime) / 60
            customLeadTime = !SettingsOptions.isPresetLeadTime(preferences.leadTime)
        }
        .onChange(of: preferences.leadTime) { _, newValue in
            leadMinutesDraft = Int(newValue) / 60
            if !SettingsOptions.isPresetLeadTime(newValue) { customLeadTime = true }
        }
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

    private func showsCustomLeadTime(_ preferences: Preferences) -> Bool {
        customLeadTime || !SettingsOptions.isPresetLeadTime(preferences.leadTime)
    }

    private func leadTimeSelection(_ preferences: Preferences) -> Binding<Int> {
        Binding(
            get: { showsCustomLeadTime(preferences) ? Self.customLeadTag : Int(preferences.leadTime) / 60 },
            set: { selection in
                if selection == Self.customLeadTag {
                    leadMinutesDraft = Int(preferences.leadTime) / 60
                    customLeadTime = true
                    DispatchQueue.main.async { leadFieldFocused = true }
                } else {
                    // Set the draft first: the custom field's commit on disappear must not undo this.
                    leadMinutesDraft = selection
                    customLeadTime = false
                    preferences.leadTime = TimeInterval(selection * 60)
                }
            }
        )
    }

    private func customLeadTimeRow(_ preferences: Preferences) -> some View {
        SettingsRow(title: "Custom time", tone: .secondary, indented: true) {
            HStack(spacing: 6) {
                TextField("Minutes before the event", value: $leadMinutesDraft, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .focused($leadFieldFocused)
                    .onSubmit { commitLeadMinutes(preferences) }
                    .onChange(of: leadFieldFocused) { _, focused in
                        if !focused { commitLeadMinutes(preferences) }
                    }
                    .onDisappear { commitLeadMinutes(preferences) }
                Stepper("Minutes before the event", value: leadMinutes(preferences), in: SettingsOptions.customLeadTimeRange)
                    .labelsHidden()
                Text(leadMinutesDraft == 1 ? "minute before" : "minutes before")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func commitLeadMinutes(_ preferences: Preferences) {
        let range = SettingsOptions.customLeadTimeRange
        let minutes = min(max(leadMinutesDraft, range.lowerBound), range.upperBound)
        leadMinutesDraft = minutes
        if Int(preferences.leadTime) / 60 != minutes {
            preferences.leadTime = TimeInterval(minutes * 60)
        }
    }

    private func leadMinutes(_ preferences: Preferences) -> Binding<Int> {
        Binding(
            get: { Int(preferences.leadTime) / 60 },
            set: { minutes in
                let range = SettingsOptions.customLeadTimeRange
                preferences.leadTime = TimeInterval(min(max(minutes, range.lowerBound), range.upperBound) * 60)
            }
        )
    }

    // MARK: Menu bar and sound

    /// Dependent switches read as off while the setting they depend on is off.
    private func soundRepeats(_ preferences: Preferences) -> Binding<Bool> {
        Binding(
            get: { preferences.soundName != nil && preferences.soundRepeats },
            set: { preferences.soundRepeats = $0 }
        )
    }

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

    private func snoozePicker(_ title: String, preferences: Preferences, index: Int) -> some View {
        let current = SettingsOptions.wholeMinutes(preferences.snoozeDurations[index])
        return Picker(title, selection: snoozeMinutes(preferences, index: index)) {
            ForEach(SettingsOptions.snoozeChoices(including: current), id: \.self) { minutes in
                Text(SettingsOptions.durationTitle(minutes: minutes)).tag(minutes)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func snoozeMinutes(_ preferences: Preferences, index: Int) -> Binding<Int> {
        Binding(
            get: { SettingsOptions.wholeMinutes(preferences.snoozeDurations[index]) },
            set: { minutes in
                var durations = preferences.snoozeDurations
                durations[index] = TimeInterval(minutes * 60)
                preferences.snoozeDurations = durations
            }
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
