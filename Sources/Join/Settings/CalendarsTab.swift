import SwiftUI
import JoinCore

@MainActor
struct CalendarsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.meetingStore.authorization == .authorized {
                calendarList
            } else {
                permissionPrompt
            }
        }
    }

    private var calendarList: some View {
        let allIDs = model.meetingStore.calendars.map(\.id)
        return VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(model.meetingStore.calendarsBySource, id: \.source) { group in
                    Section(group.source) {
                        ForEach(group.calendars) { calendar in
                            Toggle(isOn: binding(for: calendar.id, allIDs: allIDs)) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(calendar.color))
                                        .frame(width: 10, height: 10)
                                    Text(calendar.title)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()
            HStack(alignment: .top) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Calendars from accounts added in System Settings › Internet Accounts appear here. How quickly changes sync is controlled in Calendar › Settings › Accounts › Refresh Calendars.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Refresh") { model.meetingStore.refresh() }
            }
            .padding(12)

            if model.preferences.enabledCalendarIDs?.isEmpty == true {
                Text("No calendars selected: you won't get any alerts.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding([.horizontal, .bottom], 12)
            }
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Join! needs full access to your calendars")
                .font(.headline)
            Text("Grant it in System Settings › Privacy & Security › Calendars, then come back here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Open System Settings") { model.openCalendarPrivacySettings() }
                Button("Check again") { model.meetingStore.recheckAuthorization() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func binding(for id: String, allIDs: [String]) -> Binding<Bool> {
        Binding(
            get: { model.preferences.isCalendarEnabled(id) },
            set: { model.preferences.setCalendar(id, enabled: $0, allCalendarIDs: allIDs) }
        )
    }
}
