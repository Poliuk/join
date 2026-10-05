import SwiftUI
import JoinCore

@MainActor
struct AppearanceTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Form {
                Section {
                    ColorPicker("Alert text", selection: color(\.textColor))
                }

                Section("Alert background") {
                    Picker("Blur", selection: binding(\.blurMode)) {
                        ForEach(BlurMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    optionalColorRow("Tint", keyPath: \.backgroundTint, defaultColor: .black)
                    opacityRow("Tint opacity", keyPath: \.backgroundOpacity)
                        .disabled(appearance.backgroundTint == nil)
                }

                Section("Buttons") {
                    ColorPicker("Text", selection: color(\.buttonForeground))
                    optionalColorRow("Background", keyPath: \.buttonBackground, defaultColor: RGBA(red: 1, green: 1, blue: 1, alpha: 0.2))
                    opacityRow("Opacity", keyPath: \.buttonOpacity)
                }

                Section("Join button") {
                    ColorPicker("Text", selection: color(\.primaryForeground))
                    optionalColorRow("Background", keyPath: \.primaryBackground, defaultColor: RGBA(hex: "#EF990E") ?? .white)
                    opacityRow("Opacity", keyPath: \.primaryOpacity)
                }

                Section {
                    Button("Reset to defaults") { model.preferences.resetAppearance() }
                }
            }
            .formStyle(.grouped)
            .frame(width: 360)

            Divider()

            VStack(spacing: 16) {
                Spacer()
                AlertPreview(appearance: appearance, snoozeDurations: model.preferences.snoozeDurations)
                Button("Show Demo Alert") { model.alertCoordinator.showDemoAlert() }
                Text("The demo shows the real alert on your screen with a sample event.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var appearance: AlertAppearance { model.preferences.appearance }

    private func binding<Value>(_ keyPath: WritableKeyPath<AlertAppearance, Value>) -> Binding<Value> {
        Binding(
            get: { model.preferences.appearance[keyPath: keyPath] },
            set: { newValue in
                var updated = model.preferences.appearance
                updated[keyPath: keyPath] = newValue
                model.preferences.appearance = updated
            }
        )
    }

    private func color(_ keyPath: WritableKeyPath<AlertAppearance, RGBA>) -> Binding<Color> {
        Binding(
            get: { Color(model.preferences.appearance[keyPath: keyPath]) },
            set: { binding(keyPath).wrappedValue = RGBA($0) }
        )
    }

    @ViewBuilder
    private func optionalColorRow(_ title: String, keyPath: WritableKeyPath<AlertAppearance, RGBA?>, defaultColor: RGBA) -> some View {
        let enabled = Binding(
            get: { model.preferences.appearance[keyPath: keyPath] != nil },
            set: { binding(keyPath).wrappedValue = $0 ? defaultColor : nil }
        )
        let colorBinding = Binding(
            get: { Color(model.preferences.appearance[keyPath: keyPath] ?? defaultColor) },
            set: { binding(keyPath).wrappedValue = RGBA($0) }
        )
        HStack {
            Toggle(title, isOn: enabled)
            Spacer()
            ColorPicker("", selection: colorBinding)
                .labelsHidden()
                .disabled(!enabled.wrappedValue)
        }
    }

    private func opacityRow(_ title: String, keyPath: WritableKeyPath<AlertAppearance, Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: binding(keyPath), in: 0...1)
            Text("\(Int((appearance[keyPath: keyPath] * 100).rounded())) %")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// A scaled-down live rendering of the real alert over a sample wallpaper.
@MainActor
private struct AlertPreview: View {
    let appearance: AlertAppearance
    let snoozeDurations: [TimeInterval]

    private static let previewSize = CGSize(width: 1280, height: 800)
    private static let scale: CGFloat = 0.28

    var body: some View {
        let session = AlertSession(
            meetings: [sampleMeeting],
            appearance: appearance,
            snoozeDurations: snoozeDurations,
            actions: AlertActions(dismiss: {}, snooze: { _ in }, snoozeUntilEvent: {}, join: { _ in })
        )
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.26, green: 0.14, blue: 0.36), Color(red: 0.72, green: 0.31, blue: 0.16), Color(red: 0.16, green: 0.33, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            AlertRootView(session: session, blurWithinWindow: true)
        }
        .frame(width: Self.previewSize.width, height: Self.previewSize.height)
        .scaleEffect(Self.scale)
        .frame(width: Self.previewSize.width * Self.scale, height: Self.previewSize.height * Self.scale)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.6), lineWidth: 6))
        .allowsHitTesting(false)
    }

    private var sampleMeeting: Meeting {
        let start = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date().addingTimeInterval(86400)) ?? Date()
        return Meeting(
            id: "preview",
            title: "Hello, I'm a demo event",
            start: start,
            end: start.addingTimeInterval(3600),
            calendarColor: RGBA(hex: "#4A90D9") ?? .white,
            location: "Conference Room A",
            joinURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )
    }
}
