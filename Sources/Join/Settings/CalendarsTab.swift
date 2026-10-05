import AppKit
import SwiftUI
import JoinCore

@MainActor
struct CalendarsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Join! alerts you about events in the checked calendars.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !allIDs.isEmpty {
                    Text("\(selected) of \(allIDs.count) selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if !allIDs.isEmpty && selected == 0 {
                Label("No calendars selected: you won't get any alerts.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 2)

        if allIDs.isEmpty {
            SettingsBox {
                Text("No calendars yet. Add an account in System Settings › Internet Accounts, or create a calendar in Calendar.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            }
        } else {
            ForEach(model.meetingStore.calendarsBySource, id: \.source) { group in
                calendarGroup(source: group.source, calendars: group.calendars, enabled: enabled, allIDs: allIDs)
            }
        }
    }

    private func calendarGroup(source: String, calendars: [CalendarInfo], enabled: Set<String>?, allIDs: [String]) -> some View {
        let ids = calendars.map(\.id)
        let count = CalendarSelection.enabledCount(of: ids, in: enabled)
        let allOn = count == ids.count

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(source)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Text("\(count) of \(ids.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if ids.count > 1 {
                        Button(allOn ? "Deselect All" : "Select All") {
                            model.preferences.enabledCalendarIDs = CalendarSelection.setting(
                                ids, enabled: !allOn, in: model.preferences.enabledCalendarIDs, allCalendarIDs: allIDs
                            )
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                        .accessibilityLabel(allOn ? "Deselect all \(source) calendars" : "Select all \(source) calendars")
                    }
                }
            }
            .frame(minHeight: 24)
            .padding(.horizontal, 2)

            SettingsBox {
                ForEach(Array(calendars.enumerated()), id: \.element.id) { index, calendar in
                    if index > 0 { SettingsSeparator() }
                    Toggle(isOn: binding(for: calendar.id, allIDs: allIDs)) {
                        Text(calendar.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .toggleStyle(CalendarCheckboxStyle(color: Color(calendar.color)))
                    .frame(minHeight: 36)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle")
                Text("Missing a calendar? Add its account in System Settings › Internet Accounts. How often calendars sync is set in Calendar › Settings › Accounts.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let lastRefreshed = model.meetingStore.lastRefreshed {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(SettingsOptions.updatedLabel(lastRefreshed: lastRefreshed, now: context.date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Open Internet Accounts…") { openInternetAccounts() }
                Button {
                    model.meetingStore.refresh()
                } label: {
                    Label("Refresh Calendars", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(.horizontal, 2)
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
    }
}

/// A checkbox filled with its calendar's color.
private struct CalendarCheckboxStyle: ToggleStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(configuration.isOn ? color : .clear)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(color, lineWidth: 1.5)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 16, height: 16)
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.checkbox)
        }
    }
}
