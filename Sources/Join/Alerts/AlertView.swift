import AppKit
import SwiftUI
import JoinCore

@MainActor
struct AlertRootView: View {
    let session: AlertSession

    var body: some View {
        ZStack {
            AlertBackdrop(appearance: session.appearance)
            AlertContentView(session: session)
        }
    }
}

/// The desktop blurred through the system material, then the tint and the scrim.
@MainActor
struct AlertBackdrop: View {
    let appearance: AlertAppearance

    var body: some View {
        ZStack {
            if appearance.blurMode != .none {
                VisualEffectView(
                    material: .fullScreenUI,
                    blendingMode: .behindWindow,
                    appearance: appearance.blurMode == .dark ? .darkAqua : .aqua
                )
            }
            AlertTintAndScrim(appearance: appearance, scrimSize: CGSize(width: 1200, height: 760))
        }
        .ignoresSafeArea()
    }
}

/// Drawn above the blur by both the alert and its Settings preview. The radial scrim keeps the
/// text legible over busy wallpapers.
struct AlertTintAndScrim: View {
    let appearance: AlertAppearance
    let scrimSize: CGSize

    var body: some View {
        let scrim = appearance.palette.scrim
        ZStack {
            if let tint = appearance.tint {
                Color(tint).opacity(appearance.tintStrength)
            }
            // An overlay, so a screen smaller than the scrim clips it instead of being sized by it.
            Color.clear.overlay {
                EllipticalGradient(
                    colors: [Color(scrim), Color(scrim.withAlpha(0))],
                    center: .center,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
                .frame(width: scrimSize.width, height: scrimSize.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
struct AlertContentView: View {
    let session: AlertSession
    /// A fixed clock, for the Settings preview. nil ticks every second.
    var now: Date? = nil
    /// false for the Settings preview: the buttons are drawn, but there is nothing to click or focus.
    var isInteractive = true

    var body: some View {
        if let now {
            content(at: now)
        } else {
            TimelineView(.periodic(from: Self.lastWholeSecond(), by: 1)) { context in
                content(at: context.date)
            }
        }
    }

    /// Meetings that scroll fade out at the edges, so a cut-off one reads as more to scroll to.
    private static let scrollFade: CGFloat = 24

    /// Ticks land just after each whole second, where meeting starts fall, so the countdown steps evenly.
    private static func lastWholeSecond() -> Date {
        Date(timeIntervalSinceReferenceDate: Date.timeIntervalSinceReferenceDate.rounded(.down))
    }

    private func content(at now: Date) -> some View {
        let palette = session.appearance.palette
        let meetings = session.meetings
        let joinable = meetings.first { $0.joinURL != nil }
        let nextStart = meetings.map(\.start).filter { $0 > now.addingTimeInterval(1) }.min()

        return VStack(spacing: 0) {
            // The buttons always keep their room; meetings that don't fit above them scroll.
            ViewThatFits(in: .vertical) {
                headers(meetings, now: now, palette: palette)
                ScrollView(.vertical) {
                    headers(meetings, now: now, palette: palette)
                        .padding(.vertical, Self.scrollFade)
                        .frame(maxWidth: .infinity)
                }
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.scrollFade)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.scrollFade)
                    }
                }
            }

            VStack(spacing: 0) {
                if let joinable {
                    AlertJoinButton(
                        title: joinTitle(for: joinable, now: now, isOneOfMany: meetings.count > 1),
                        palette: palette,
                        isInteractive: isInteractive
                    ) {
                        session.actions.join(joinable)
                    }
                    .padding(.bottom, 18)
                }
                AlertSnoozeRow(
                    options: snoozeOptions(nextStart: nextStart),
                    palette: palette,
                    isInteractive: isInteractive
                )
                AlertSecondaryButton(palette: palette, isInteractive: isInteractive, action: session.actions.dismiss) {
                    Text("Dismiss")
                    AlertKeyHint(label: "esc", isLarge: false)
                }
                .padding(.top, 30)
            }
            .padding(.top, 40)

            if session.isDemo {
                Text("This is a demo alert. Press Esc to close it.")
                    .font(.system(size: 13))
                    .opacity(0.6)
                    .padding(.top, 24)
            }
        }
        .foregroundStyle(Color(palette.text))
        .multilineTextAlignment(.center)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func headers(_ meetings: [Meeting], now: Date, palette: AlertPalette) -> some View {
        VStack(spacing: 36) {
            ForEach(meetings) { meeting in
                AlertMeetingHeader(meeting: meeting, now: now, palette: palette, isOneOfMany: meetings.count > 1)
            }
        }
    }

    private func joinTitle(for meeting: Meeting, now: Date, isOneOfMany: Bool) -> String {
        if isOneOfMany { return "Join \(meeting.title)" }
        return AlertCountdown.joinTitle(for: AlertCountdown.phase(start: meeting.start, end: meeting.end, now: now))
    }

    private func snoozeOptions(nextStart: Date?) -> [AlertSnoozeOption] {
        var options = session.snoozeDurations.enumerated().map { index, duration in
            AlertSnoozeOption(
                id: "duration-\(index)",
                label: AlertCountdown.snoozeLabel(duration),
                accessibilityLabel: AlertCountdown.snoozeAccessibilityLabel(duration),
                action: { session.actions.snooze(duration) }
            )
        }
        if let nextStart {
            options.append(AlertSnoozeOption(
                id: "start",
                label: AlertCountdown.snoozeUntilStartLabel,
                accessibilityLabel: AlertCountdown.snoozeUntilStartAccessibilityLabel(nextStart),
                action: session.actions.snoozeUntilEvent
            ))
        }
        return options
    }
}

@MainActor
private struct AlertMeetingHeader: View {
    let meeting: Meeting
    let now: Date
    let palette: AlertPalette
    /// Several meetings share the alert, so each title is a little smaller.
    let isOneOfMany: Bool

    var body: some View {
        let phase = AlertCountdown.phase(start: meeting.start, end: meeting.end, now: now)
        let titleSize: CGFloat = isOneOfMany ? 40 : 52
        VStack(spacing: 0) {
            if !meeting.calendarTitle.isEmpty {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(meeting.calendarColor.withAlpha(1)))
                        .frame(width: 10, height: 10)
                    Text(meeting.calendarTitle)
                        .lineLimit(1)
                }
                .font(.system(size: 15, weight: .medium))
                .opacity(0.8)
                .padding(.bottom, 14)
            }

            Text(AlertCountdown.text(start: meeting.start, end: meeting.end, now: now))
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color(palette.countdownColor(for: phase)))

            Text(meeting.title)
                .font(.system(size: titleSize, weight: .bold))
                .tracking(-0.02 * titleSize)
                .lineLimit(2)
                .frame(maxWidth: 960)
                .padding(.top, 6)

            details
                .padding(.top, 14)
        }
    }

    private var details: some View {
        let time = AlertDetail(systemImage: "clock", text: MeetingTimeFormatter.timeRange(start: meeting.start, end: meeting.end))
        let place = location.map { AlertDetail(systemImage: "mappin.and.ellipse", text: $0) }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) {
                time
                place
            }
            VStack(spacing: 8) {
                time
                place
            }
        }
        .font(.system(size: 18))
        .opacity(0.75)
        .frame(maxWidth: 960)
    }

    /// The location, unless it's just the join link again.
    private var location: String? {
        guard let raw = meeting.location else { return nil }
        let text = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !text.isEmpty, text != meeting.joinURL?.absoluteString else { return nil }
        return text
    }
}

private struct AlertDetail: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
        }
    }
}

private struct AlertJoinButton: View {
    let title: String
    let palette: AlertPalette
    let isInteractive: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        AlertButton(isInteractive: isInteractive, action: action) {
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(1)
                AlertKeyHint(label: "↩", isLarge: true)
                    .padding(.leading, 6)
            }
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color(palette.joinText))
            .padding(.horizontal, 24)
            .frame(width: 440, height: 56)
            .background {
                shape
                    .fill(Color(palette.joinFill))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
            }
            .contentShape(shape)
        }
    }
}

struct AlertSnoozeOption: Identifiable {
    let id: String
    let label: String
    let accessibilityLabel: String
    let action: () -> Void
}

private struct AlertSnoozeRow: View {
    let options: [AlertSnoozeOption]
    let palette: AlertPalette
    let isInteractive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("Snooze")
                .font(.system(size: 15))
                .opacity(0.72)
                .frame(width: 70, alignment: .leading)
                .accessibilityHidden(true)
            ForEach(options) { option in
                AlertSecondaryButton(palette: palette, height: 44, isInteractive: isInteractive, action: option.action) {
                    Text(option.label)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(option.accessibilityLabel)
            }
        }
        .frame(width: 440)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Snooze")
    }
}

/// Dismiss and the snooze choices.
private struct AlertSecondaryButton<Label: View>: View {
    let palette: AlertPalette
    var height: CGFloat = 36
    let isInteractive: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        AlertButton(isInteractive: isInteractive, action: action) {
            HStack(spacing: 8) { label }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(palette.buttonText))
                .padding(.horizontal, 16)
                .frame(height: height)
                .background(shape.fill(Color(palette.buttonFill)))
                .contentShape(shape)
        }
    }
}

/// A button, or for the Settings preview only its label.
private struct AlertButton<Label: View>: View {
    let isInteractive: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        if isInteractive {
            Button(action: action) { label }
                .buttonStyle(AlertPressableStyle())
        } else {
            label
        }
    }
}

/// The key that triggers a button, outlined in the button's text color.
private struct AlertKeyHint: View {
    let label: String
    let isLarge: Bool

    var body: some View {
        Text(label)
            .font(.system(size: isLarge ? 13 : 11, weight: isLarge ? .medium : .regular))
            .padding(.horizontal, isLarge ? 7 : 5)
            .frame(minHeight: isLarge ? 20 : 16)
            .overlay {
                RoundedRectangle(cornerRadius: isLarge ? 5 : 4, style: .continuous)
                    .strokeBorder(lineWidth: isLarge ? 1.5 : 1)
            }
            .opacity(0.65)
            .accessibilityHidden(true)
    }
}

private struct AlertPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
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
