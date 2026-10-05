import SwiftUI
import JoinCore

@MainActor
struct GeneralTab: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        @Bindable var preferences = model.preferences

        Form {
            Section("Alerts") {
                HStack(spacing: 8) {
                    Text("Alert me")
                    Stepper(value: leadMinutes(preferences), in: 0...120) {
                        Text("\(Int(preferences.leadTime) / 60) min").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                    Stepper(value: leadSeconds(preferences), in: 0...59, step: 5) {
                        Text("\(Int(preferences.leadTime) % 60) sec").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                    Text("before the event")
                }

                Picker("Show alert on", selection: $preferences.showOnAllScreens) {
                    Text("All screens").tag(true)
                    Text("Main screen only").tag(false)
                }

                Toggle("Show next event in the menu bar", isOn: $preferences.menuBarShowsNextEvent)
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
    }

    private func leadMinutes(_ preferences: Preferences) -> Binding<Int> {
        Binding(
            get: { Int(preferences.leadTime) / 60 },
            set: { preferences.leadTime = TimeInterval($0 * 60 + Int(preferences.leadTime) % 60) }
        )
    }

    private func leadSeconds(_ preferences: Preferences) -> Binding<Int> {
        Binding(
            get: { Int(preferences.leadTime) % 60 },
            set: { preferences.leadTime = TimeInterval((Int(preferences.leadTime) / 60) * 60 + $0) }
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
