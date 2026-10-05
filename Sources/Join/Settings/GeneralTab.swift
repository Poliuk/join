import SwiftUI
import JoinCore

@MainActor
struct GeneralTab: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    /// What's typed in the lead-time field. Written to Preferences only on Return or when the field
    /// loses focus: saving every keystroke would make "3" → "35" → "5" briefly mean 35 minutes and
    /// fire alerts early.
    @State private var leadMinutesDraft = Int(Preferences.defaultLeadTime) / 60
    @FocusState private var leadFieldFocused: Bool

    var body: some View {
        @Bindable var preferences = model.preferences

        Form {
            Section("Alerts") {
                HStack(spacing: 8) {
                    Text("Alert me")
                    TextField("Minutes", value: $leadMinutesDraft, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44)
                        .focused($leadFieldFocused)
                        .onSubmit { commitLeadMinutes(preferences) }
                        .onChange(of: leadFieldFocused) { _, focused in
                            if !focused { commitLeadMinutes(preferences) }
                        }
                        .onDisappear { commitLeadMinutes(preferences) }
                    Stepper("Minutes", value: leadMinutes(preferences), in: 0...120)
                        .labelsHidden()
                    Text(Int(preferences.leadTime) / 60 == 1 ? "minute before the event" : "minutes before the event")
                }

                Picker("Show alert on", selection: $preferences.alertScreens) {
                    ForEach(AlertScreens.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }

                Toggle("Show next event in the menu bar", isOn: $preferences.menuBarShowsNextEvent)
            }

            Section("Out of office") {
                Toggle("Alert for out-of-office events", isOn: $preferences.alertForOutOfOffice)
                TextField("Keywords", text: keywordsText(preferences), prompt: Text("out of office, OOO, …"), axis: .vertical)
                    .lineLimit(2...4)
                HStack {
                    Text("An event whose title contains one of these words counts as out of office. It still shows in the menu bar panel, dimmed. Separate keywords with commas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { preferences.resetOutOfOfficeKeywords() }
                }
            }

            Section("Sound") {
                Picker("Sound", selection: soundSelection(preferences)) {
                    Text("None").tag("")
                    Divider()
                    ForEach(SystemSounds.names, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                HStack {
                    Toggle("Play repeatedly until the alert is closed", isOn: $preferences.soundRepeats)
                        .disabled(preferences.soundName == nil)
                    Spacer()
                    Button("Preview") {
                        SystemSounds.sound(named: preferences.soundName)?.play()
                    }
                    .disabled(preferences.soundName == nil)
                }
            }

            Section("Snooze durations") {
                ForEach(0..<2, id: \.self) { index in
                    HStack {
                        Slider(value: snoozeMinutes(preferences, index: index), in: 1...60, step: 1)
                        Text(snoozeLabel(preferences.snoozeDurations[index]))
                            .monospacedDigit()
                            .frame(width: 90, alignment: .trailing)
                    }
                }
            }

            Section("Behavior") {
                Toggle("Automatically close alerts", isOn: $preferences.autoCloseEnabled)
                Stepper(value: autoCloseMinutes(preferences), in: 1...120) {
                    Text("Close alerts after \(Int(preferences.autoCloseAfter) / 60) minutes")
                }
                .disabled(!preferences.autoCloseEnabled)

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.setEnabled(enabled)
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { leadMinutesDraft = Int(preferences.leadTime) / 60 }
        .onChange(of: preferences.leadTime) { _, newValue in
            leadMinutesDraft = Int(newValue) / 60
        }
    }

    private func commitLeadMinutes(_ preferences: Preferences) {
        let minutes = min(max(leadMinutesDraft, 0), 120)
        leadMinutesDraft = minutes
        if Int(preferences.leadTime) / 60 != minutes {
            preferences.leadTime = TimeInterval(minutes * 60)
        }
    }

    private func leadMinutes(_ preferences: Preferences) -> Binding<Int> {
        Binding(
            get: { Int(preferences.leadTime) / 60 },
            set: { preferences.leadTime = TimeInterval(min(max($0, 0), 120) * 60) }
        )
    }

    private func keywordsText(_ preferences: Preferences) -> Binding<String> {
        Binding(
            get: { preferences.outOfOfficeKeywords.joined(separator: ", ") },
            set: { preferences.outOfOfficeKeywords = OutOfOfficeDetector.parseKeywords($0) }
        )
    }

    private func soundSelection(_ preferences: Preferences) -> Binding<String> {
        Binding(
            get: { preferences.soundName ?? "" },
            set: { preferences.soundName = $0.isEmpty ? nil : $0 }
        )
    }

    private func snoozeMinutes(_ preferences: Preferences, index: Int) -> Binding<Double> {
        Binding(
            get: { preferences.snoozeDurations[index] / 60 },
            set: { minutes in
                var durations = preferences.snoozeDurations
                durations[index] = minutes.rounded() * 60
                preferences.snoozeDurations = durations
            }
        )
    }

    private func autoCloseMinutes(_ preferences: Preferences) -> Binding<Int> {
        Binding(
            get: { Int(preferences.autoCloseAfter) / 60 },
            set: { preferences.autoCloseAfter = TimeInterval($0 * 60) }
        )
    }

    private func snoozeLabel(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
