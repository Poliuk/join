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
            outOfOffice
                .padding(.top, 10)
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

    // MARK: Out of office

    private var outOfOffice: some View {
        @Bindable var preferences = model.preferences

        return SettingsSection(title: "Out of office") {
            SettingsSwitchRow(title: "Alert for out-of-office events", isOn: $preferences.alertForOutOfOffice, separator: false)
            SettingsSeparator()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Title keywords")
                    Spacer(minLength: 0)
                    Button("Restore Defaults") { preferences.resetOutOfOfficeKeywords() }
                        .buttonStyle(.link)
                        .font(.callout)
                        .disabled(preferences.outOfOfficeKeywords == OutOfOfficeDetector.defaultKeywords)
                }
                KeywordTokenField(keywords: $preferences.outOfOfficeKeywords)
                Text("An event counts as out of office when its title contains any of these words. Out-of-office events show dimmed in the menu bar and only alert when the option above is on. Press Return to add a keyword.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
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

/// The out-of-office keywords as removable tokens, with a field that adds one on Return or comma.
private struct KeywordTokenField: View {
    @Binding var keywords: [String]
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        SettingsFlowLayout(spacing: 6) {
            ForEach(Array(keywords.enumerated()), id: \.offset) { index, keyword in
                KeywordToken(text: keyword) { keywords.remove(at: index) }
            }
            TextField("Add keyword", text: $draft)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(.horizontal, 4)
                .frame(height: 22)
                .focused($fieldFocused)
                .onSubmit(commitDraft)
                .onChange(of: draft) { _, newValue in
                    let split = KeywordList.splittingDraft(newValue, into: keywords)
                    guard split.draft != newValue else { return }
                    keywords = split.keywords
                    draft = split.draft
                }
                .onChange(of: fieldFocused) { _, focused in
                    if !focused { commitDraft() }
                }
                .onKeyPress(.delete) {
                    guard draft.isEmpty, !keywords.isEmpty else { return .ignored }
                    keywords.removeLast()
                    return .handled
                }
                .layoutValue(key: SettingsFlowFill.self, value: 120)
        }
        .padding(6)
        .background(SettingsPalette.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(SettingsPalette.fieldBorder, lineWidth: 0.5)
        }
        .overlay {
            if fieldFocused {
                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .padding(-1.5)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

    private func commitDraft() {
        keywords = KeywordList.adding(draft, to: keywords)
        draft = ""
    }
}

private struct KeywordToken: View {
    let text: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 2) {
            Text(text)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(hovering ? .primary : .secondary)
                    .background(hovering ? SettingsPalette.chip : .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Remove “\(text)”")
            .accessibilityLabel("Remove \(text)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .frame(height: 22)
        .background(SettingsPalette.chip, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
