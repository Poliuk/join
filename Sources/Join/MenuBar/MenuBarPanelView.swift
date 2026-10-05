import SwiftUI
import JoinCore

@MainActor
struct MenuBarPanelView: View {
    @Environment(AppModel.self) private var model
    @State private var todayOnly = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.meetingStore.authorization == .authorized {
                meetingList
            } else {
                PermissionPrompt(authorization: model.meetingStore.authorization)
            }
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Join!")
                .font(.headline)
            if model.alertCoordinator.isPaused {
                Text("Alerts paused")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.2), in: Capsule())
            }
            Spacer()
            Button {
                model.alertCoordinator.setPaused(!model.alertCoordinator.isPaused)
            } label: {
                Image(systemName: model.alertCoordinator.isPaused ? "play.fill" : "pause.fill")
            }
            .help(model.alertCoordinator.isPaused ? "Resume alerts" : "Pause alerts")

            SettingsLink {
                Image(systemName: "gearshape.fill")
            }
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            .help("Settings")

            Button {
                model.quit()
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Join!")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var meetingList: some View {
        let now = model.now
        let ongoing = model.meetingStore.ongoing(at: now)
        let upcoming = model.meetingStore.upcoming(at: now, todayOnly: todayOnly)

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Ongoing")
                if ongoing.isEmpty {
                    EmptyRow(text: "Nothing happening right now")
                } else {
                    ForEach(ongoing) { meeting in
                        MeetingRow(meeting: meeting, now: now) { model.join(meeting) }
                    }
                }

                HStack {
                    SectionHeader(title: "Upcoming")
                    Spacer()
                    Picker("", selection: $todayOnly) {
                        Text("Today").tag(true)
                        Text("All").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)
                }

                if upcoming.isEmpty {
                    EmptyRow(text: todayOnly ? "No more meetings today" : "Nothing in the next 7 days")
                } else {
                    ForEach(groupedByDay(upcoming, now: now), id: \.heading) { group in
                        if !todayOnly {
                            Text(group.heading)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                        ForEach(group.meetings) { meeting in
                            MeetingRow(meeting: meeting, now: now) { model.join(meeting) }
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(maxHeight: 520)
    }

    private func groupedByDay(_ meetings: [Meeting], now: Date) -> [(heading: String, meetings: [Meeting])] {
        var order: [String] = []
        var groups: [String: [Meeting]] = [:]
        for meeting in meetings {
            let heading = MeetingTimeFormatter.dayHeading(for: meeting.start, now: now)
            if groups[heading] == nil { order.append(heading) }
            groups[heading, default: []].append(meeting)
        }
        return order.map { (heading: $0, meetings: groups[$0] ?? []) }
    }
}

@MainActor
private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .kerning(0.6)
    }
}

@MainActor
private struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
}

@MainActor
private struct MeetingRow: View {
    let meeting: Meeting
    let now: Date
    let join: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(meeting.calendarColor))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(MeetingTimeFormatter.timeRange(start: meeting.start, end: meeting.end))
                    if let detail = MeetingTimeFormatter.rowDetail(start: meeting.start, end: meeting.end, now: now) {
                        Text("·")
                        Text(detail)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let location = meeting.location, meeting.joinURL?.absoluteString != location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let url = meeting.joinURL {
                Button(action: join) {
                    Image(systemName: "video.fill")
                        .padding(6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Join via \(MeetingLinkDetector.providerName(for: url) ?? "link")")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
private struct PermissionPrompt: View {
    @Environment(AppModel.self) private var model
    let authorization: CalendarAuthorization

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar access needed")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open System Settings") { model.openCalendarPrivacySettings() }
                Button("Check again") { model.meetingStore.recheckAuthorization() }
            }
        }
        .padding(14)
    }

    private var message: String {
        switch authorization {
        case .notDetermined:
            return "Join! needs to read your calendars to alert you before meetings. Approve the permission request to continue."
        case .writeOnly:
            return "Join! has write-only access. Grant full calendar access in System Settings › Privacy & Security › Calendars."
        case .denied, .restricted, .authorized:
            return "Grant Join! full calendar access in System Settings › Privacy & Security › Calendars, then come back here."
        }
    }
}
