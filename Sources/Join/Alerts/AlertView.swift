import AppKit
import SwiftUI
import JoinCore

@MainActor
struct AlertRootView: View {
    let session: AlertSession
    /// The Settings preview can't blur what's behind its window, so it blurs within the window instead.
    var blurWithinWindow = false

    var body: some View {
        ZStack {
            AlertBackground(appearance: session.appearance, blurWithinWindow: blurWithinWindow)
            AlertContentView(session: session)
        }
    }
}

@MainActor
struct AlertBackground: View {
    let appearance: AlertAppearance
    var blurWithinWindow = false

    var body: some View {
        ZStack {
            if appearance.blurMode != .none {
                VisualEffectView(
                    material: .fullScreenUI,
                    blendingMode: blurWithinWindow ? .withinWindow : .behindWindow,
                    appearance: appearance.blurMode == .dark ? .darkAqua : .aqua
                )
            }
            if let tint = appearance.backgroundTint {
                Color(tint).opacity(appearance.backgroundOpacity)
            }
        }
        .ignoresSafeArea()
    }
}

@MainActor
struct AlertContentView: View {
    let session: AlertSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let textColor = Color(session.appearance.textColor)
            ZStack(alignment: .topTrailing) {
                Text(context.date, style: .time)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(textColor.opacity(0.7))
                    .padding(24)

                VStack(spacing: 40) {
                    VStack(spacing: 32) {
                        ForEach(session.meetings) { meeting in
                            MeetingBlock(meeting: meeting, now: context.date, textColor: textColor)
                        }
                    }

                    VStack(spacing: 28) {
                        HStack(spacing: 12) {
                            if let joinable = session.meetings.first(where: { $0.joinURL != nil }) {
                                AlertButton(
                                    title: "Join",
                                    systemImage: "video.fill",
                                    role: .primary,
                                    appearance: session.appearance
                                ) {
                                    session.actions.join(joinable)
                                }
                            }
                            AlertButton(title: "Dismiss", role: .secondary, appearance: session.appearance) {
                                session.actions.dismiss()
                            }
                        }

                        VStack(spacing: 10) {
                            Text("Snooze")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(textColor.opacity(0.75))
                            HStack(spacing: 10) {
                                ForEach(Array(session.snoozeDurations.enumerated()), id: \.offset) { _, duration in
                                    AlertButton(title: snoozeLabel(duration), role: .small, appearance: session.appearance) {
                                        session.actions.snooze(duration)
                                    }
                                }
                                if session.meetings.contains(where: { $0.start > context.date.addingTimeInterval(1) }) {
                                    AlertButton(title: "Until event", role: .small, appearance: session.appearance) {
                                        session.actions.snoozeUntilEvent()
                                    }
                                }
                            }
                        }
                    }

                    if session.isDemo {
                        Text("This is a demo alert. Press Esc to close it.")
                            .font(.system(size: 12))
                            .foregroundStyle(textColor.opacity(0.6))
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func snoozeLabel(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

@MainActor
private struct MeetingBlock: View {
    let meeting: Meeting
    let now: Date
    let textColor: Color

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(meeting.calendarColor))
                    .frame(width: 6, height: 44)
                Text(meeting.title)
                    .font(.system(size: 40, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Text(MeetingTimeFormatter.timeRange(start: meeting.start, end: meeting.end))
                .font(.system(size: 20, weight: .medium))
                .opacity(0.9)
            Text(MeetingTimeFormatter.countdown(start: meeting.start, end: meeting.end, now: now))
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .monospacedDigit()
                .opacity(0.8)
            if let location = meeting.location, meeting.joinURL?.absoluteString != location {
                Text(location)
                    .font(.system(size: 15))
                    .opacity(0.7)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 32)
    }
}

@MainActor
private struct AlertButton: View {
    enum Role { case primary, secondary, small }

    let title: String
    var systemImage: String? = nil
    let role: Role
    let appearance: AlertAppearance
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: role == .small ? 12 : 14, weight: .semibold))
            .frame(minWidth: role == .small ? 96 : 150)
            .padding(.vertical, role == .small ? 7 : 9)
            .padding(.horizontal, 14)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch role {
        case .primary: return Color(appearance.primaryForeground)
        case .secondary, .small: return Color(appearance.buttonForeground)
        }
    }

    private var background: Color {
        switch role {
        case .primary:
            return Color(appearance.primaryBackground ?? RGBA(hex: "#EF990E") ?? .white).opacity(appearance.primaryOpacity)
        case .secondary, .small:
            if let custom = appearance.buttonBackground {
                return Color(custom).opacity(appearance.buttonOpacity)
            }
            let fallback: Color = appearance.blurMode == .light ? .black.opacity(0.08) : .white.opacity(0.16)
            return fallback.opacity(appearance.buttonOpacity)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var appearance: NSAppearance.Name

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.appearance = NSAppearance(named: appearance)
    }
}
