import AppKit
import OSLog
import SwiftUI
import JoinCore

/// Which calendars Join! reads: a line saying what the checks do, with the count checked at its right, then one
/// section per account, each calendar a row with its checkbox at the right, the account's count under its box and,
/// with more than one calendar, Select All or Deselect All beside it. Then a footer: where to add a missing calendar,
/// when the calendars were last read, and the buttons for both. Without calendar access, a prompt instead.
struct CalendarsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            if model.meetingStore.authorization == .authorized {
                calendarList
                footer
            } else {
                permissionPrompt
            }
        }
        .padding(SettingsMetrics.panePadding)
    }

    // MARK: Calendars

    @ViewBuilder
    private var calendarList: some View {
        let allIDs = model.meetingStore.calendars.map(\.id)
        let enabled = model.preferences.enabledCalendarIDs
        let selected = CalendarSelection.enabledCount(of: allIDs, in: enabled)

        SettingsNoteLine(
            footnote: "Join! alerts you about events in the checked calendars.",
            warning: !allIDs.isEmpty && selected == 0 ? SettingsOptions.noCalendarsWarning : nil
        ) {
            if !allIDs.isEmpty {
                SettingsFootnote(SettingsOptions.calendarsSelected(selected, of: allIDs.count))
            }
        }

        if allIDs.isEmpty {
            SettingsBox {
                SettingsStatusRow(
                    message: "No calendars yet. Add an account in System Settings › Internet Accounts, or create a calendar in Calendar.",
                    separator: false
                )
            }
        } else {
            ForEach(model.meetingStore.calendarsBySource, id: \.source) { group in
                calendarGroup(source: group.source, calendars: group.calendars, enabled: enabled, allIDs: allIDs)
            }
        }
    }

    /// Select All and Deselect All act on the whole account, so they sit under its box, as the Test buttons do.
    private func calendarGroup(source: String, calendars: [CalendarInfo], enabled: Set<String>?, allIDs: [String]) -> some View {
        let ids = calendars.map(\.id)
        let count = CalendarSelection.enabledCount(of: ids, in: enabled)
        let allOn = count == ids.count

        return SettingsSection(title: source, footnote: SettingsOptions.calendarsSelected(count, of: ids.count)) {
            ForEach(Array(calendars.enumerated()), id: \.element.id) { index, calendar in
                calendarRow(calendar, separator: index > 0, allIDs: allIDs)
            }
        } accessory: {
            if ids.count > 1 {
                Button(allOn ? "Deselect All" : "Select All") {
                    model.preferences.enabledCalendarIDs = CalendarSelection.setting(
                        ids, enabled: !allOn, in: model.preferences.enabledCalendarIDs, allCalendarIDs: allIDs
                    )
                }
                .accessibilityLabel(allOn ? "Deselect all \(source) calendars" : "Select all \(source) calendars")
            }
        }
    }

    /// The calendar's name, then its checkbox at the right. A click anywhere on the row toggles it; one on the
    /// checkbox goes to the checkbox alone, whose button takes it before the row's tap gesture.
    private func calendarRow(_ calendar: CalendarInfo, separator: Bool, allIDs: [String]) -> some View {
        let isOn = binding(for: calendar.id, allIDs: allIDs)
        return SettingsRow(title: calendar.title, separator: separator) {
            CalendarCheckbox(color: Color(calendar.color), isOn: isOn, title: calendar.title)
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.wrappedValue.toggle() }
    }

    /// Two lines under the last account: where to add a missing calendar, then when the calendars were last read,
    /// with the buttons at the right, on the line the boxes' controls end on.
    private var footer: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.underBoxSpacing) {
            SettingsNoteLine(footnote: "Missing a calendar? Add its account in System Settings › Internet Accounts. How often calendars sync is set in Calendar › Settings › Accounts.")
            TimelineView(.periodic(from: .now, by: 30)) { context in
                SettingsNoteLine(footnote: model.meetingStore.lastRefreshed.map {
                    SettingsOptions.updatedLabel(lastRefreshed: $0, now: context.date)
                }) {
                    Button("Open Internet Accounts…") { openInternetAccounts() }
                    Button("Refresh Calendars") { model.meetingStore.refresh() }
                }
            }
        }
    }

    private var permissionPrompt: some View {
        SettingsBox {
            VStack(spacing: 10) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Join! needs full access to your calendars")
                    .font(.headline)
                Text("Grant it in System Settings › Privacy & Security › Calendars, then come back here.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open System Settings") { model.openCalendarPrivacySettings() }
                    Button("Check Again") { model.meetingStore.recheckAuthorization() }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func binding(for id: String, allIDs: [String]) -> Binding<Bool> {
        Binding(
            get: { model.preferences.isCalendarEnabled(id) },
            set: { model.preferences.setCalendar(id, enabled: $0, allCalendarIDs: allIDs) }
        )
    }

    private func openInternetAccounts() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension",
            "x-apple.systempreferences:com.apple.preferences.internetaccounts",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
        // Fixed URLs: nothing personal.
        Logger.settings.error("Couldn't open Internet Accounts; System Settings took none of \(candidates.joined(separator: ", "), privacy: .public)")
    }
}

/// A checkbox filled with its calendar's color, a calendar row's control. VoiceOver sees a standard checkbox named
/// after the calendar.
private struct CalendarCheckbox: View {
    let color: Color
    @Binding var isOn: Bool
    let title: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? color : .clear)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(color, lineWidth: 1.5)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
        }
    }
}
