import AppKit
import SwiftUI
import JoinCore

/// What a card's controls do (`NotificationCardController`).
struct NotificationCardActions {
    /// Join, or Dismiss with the ×; the menu's choices answer through `showMenu`.
    let answer: (AlertResponse) -> Void
    /// Opens the card's menu below `anchor`, their right edges aligned; returns once it closes.
    let showMenu: (NSView) -> Void
}

/// One notification card, 380 pt wide, on the menu bar panel's glass and frost: the calendar's color as a bar at
/// the left, the title, the live countdown with the time range, the location or the test card's note, and at the
/// right the Join split button, or the Snooze pull-down without a link. Under the pointer the hovered segment
/// brightens and a × shows at the top left, sticking out of the corner. A click on the card's body does nothing
/// (the user's 2026-10-16 rule). Light or dark follows the system, like the panel.
struct NotificationCardView: View {
    /// The window's coordinate space, which its pointer is tracked in (`NotificationCardWindowState.pointer`).
    nonisolated static let coordinateSpace = "notificationCard"
    static let cornerRadius = MenuBarPanelWindow.cornerRadius

    let card: NotificationCard
    let window: NotificationCardWindowState
    let actions: NotificationCardActions

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        let overhang = NotificationCardWindow.closeButtonOverhang
        // Redrawn as the countdown's words change, on whole minutes from the start.
        TimelineView(CountdownSchedule(start: card.meeting.start)) { context in
            NotificationCardContent(card: card, now: context.date, pointer: window.pointer, actions: actions)
        }
        .frame(width: NotificationCard.width, height: card.height)
        .background(PanelFrost())
        .clipShape(shape)
        .overlay(shape.strokeBorder(PanelColors.separator, lineWidth: 1))
        .padding(.top, overhang)
        .padding(.leading, overhang)
        .overlay(alignment: .topLeading) {
            // Shown under the pointer, and while VoiceOver or Full Keyboard Access is in the card.
            let shows = window.pointer != nil || window.isKey
            NotificationCardCloseButton(card: card, pointer: window.pointer) { actions.answer(.close) }
                .opacity(shows ? 1 : 0)
                .allowsHitTesting(shows)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .coordinateSpace(.named(Self.coordinateSpace))
    }
}

/// The card's moments of change: the start, give or take whole minutes, when "Starts in 5 min" becomes "Starts in
/// 4 min", "Starting now" or "Started 1 min ago". Nonisolated: SwiftUI asks for the entries off the main actor.
nonisolated private struct CountdownSchedule: TimelineSchedule {
    let start: Date

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        let minutes = (startDate.timeIntervalSince(start) / 60).rounded(.down)
        return sequence(first: start.addingTimeInterval(minutes * 60)) { $0.addingTimeInterval(60) }
    }
}

private struct NotificationCardContent: View {
    let card: NotificationCard
    let now: Date
    let pointer: CGPoint?
    let actions: NotificationCardActions

    var body: some View {
        let countdown = card.countdown(now: now)
        HStack(spacing: 0) {
            // Decorative, so its contrast is free, as on the panel's rows.
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(card.meeting.calendarColor))
                .frame(width: 4, height: card.height - 20)
                .accessibilityHidden(true)
            textColumn(countdown)
                .padding(.leading, 10)
            Spacer(minLength: 10)
            if let joinURL = card.joinURL {
                NotificationJoinButton(card: card, joinURL: joinURL, joinTitle: countdown.joinTitle, pointer: pointer, actions: actions)
            } else {
                NotificationSnoozeButton(card: card, pointer: pointer, actions: actions)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }

    /// The title, then the countdown with the time range (only the range is cut when it's long), then the location
    /// after a pin, or the test card's note. VoiceOver reads it as one element.
    private func textColumn(_ countdown: NotificationCard.Countdown) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PanelColors.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 0) {
                Text(countdown.text)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(countdown.tone == .warning ? PanelColors.warning : PanelColors.accentText)
                    .fixedSize()
                Text(" · ")
                    .fixedSize()
                Text(card.timeRange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 12))
            .foregroundStyle(PanelColors.secondary)
            if let detail = card.detail {
                HStack(spacing: 4) {
                    if case .location = detail {
                        Image(systemName: "mappin")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    Text(detail.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 12))
                .foregroundStyle(PanelColors.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel(now: now))
    }
}

/// Join with the video symbol, a divider, and a chevron that opens the card's menu: one 30 pt shape in the panel's
/// accent button colors, each segment brightening under the pointer. The chevron stays pressed while its menu is up.
private struct NotificationJoinButton: View {
    let card: NotificationCard
    let joinURL: URL
    /// "Join", then "Join now" from the start.
    let joinTitle: String
    let pointer: CGPoint?
    let actions: NotificationCardActions

    @State private var anchor = ViewAnchor()
    @State private var isMenuOpen = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 0) {
            PointerHoverReader(pointer: pointer) { isHovered in
                Button {
                    actions.answer(.join)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: PanelAction.join(joinURL).symbolName)
                            .font(.system(size: 12, weight: .medium))
                        Text(joinTitle)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                }
                .buttonStyle(NotificationSegmentStyle(
                    fill: PanelColors.accentButton,
                    hoverFill: PanelColors.accentButtonHover,
                    foreground: PanelColors.accentButtonLabel,
                    isHovered: isHovered
                ))
                .help(NotificationCard.joinHelp)
                .accessibilityLabel(card.joinAccessibilityLabel)
            }

            Rectangle()
                .fill(PanelColors.accentButtonLabel.opacity(0.3))
                .frame(width: 1)
                .padding(.vertical, 7)
                .accessibilityHidden(true)

            PointerHoverReader(pointer: pointer) { isHovered in
                Button {
                    openMenu()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 26, height: 30)
                }
                .buttonStyle(NotificationSegmentStyle(
                    fill: PanelColors.accentButton,
                    hoverFill: PanelColors.accentButtonHover,
                    foreground: PanelColors.accentButtonLabel,
                    isHovered: isHovered,
                    isHeld: isMenuOpen
                ))
                .help(NotificationCard.menuHelp)
                .accessibilityLabel(card.menuAccessibilityLabel)
                .accessibilityHint("Opens a menu")
            }
        }
        .background(PanelColors.accentButton)
        .clipShape(shape)
        .overlay(shape.strokeBorder(PanelColors.controlBorder, lineWidth: 1))
        .fixedSize()
        .background(AnchorView(anchor: anchor))
    }

    private func openMenu() {
        guard let view = anchor.view, !isMenuOpen else { return }
        isMenuOpen = true
        // Let the pressed look render before the menu's tracking loop takes over, as the panel's menus do.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            actions.showMenu(view)
            isMenuOpen = false
        }
    }
}

/// A card without a link: only the menu, as a neutral "Snooze" pull-down in the panel's button colors.
private struct NotificationSnoozeButton: View {
    let card: NotificationCard
    let pointer: CGPoint?
    let actions: NotificationCardActions

    @State private var anchor = ViewAnchor()
    @State private var isMenuOpen = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        PointerHoverReader(pointer: pointer) { isHovered in
            Button {
                openMenu()
            } label: {
                HStack(spacing: 6) {
                    Text(NotificationCard.snoozeMenuTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
            }
            .buttonStyle(NotificationSegmentStyle(
                fill: PanelColors.buttonFill,
                hoverFill: PanelColors.buttonHoverFill,
                foreground: PanelColors.primary,
                isHovered: isHovered,
                isHeld: isMenuOpen
            ))
            .help(NotificationCard.menuHelp)
            .accessibilityLabel(card.menuAccessibilityLabel)
            .accessibilityHint("Opens a menu")
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(PanelColors.controlBorder, lineWidth: 1))
        .fixedSize()
        .background(AnchorView(anchor: anchor))
    }

    private func openMenu() {
        guard let view = anchor.view, !isMenuOpen else { return }
        isMenuOpen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            actions.showMenu(view)
            isMenuOpen = false
        }
    }
}

/// The × at the card's top left: an 18 pt frosted circle, half outside the card's corner, as on macOS's own
/// notifications. Dismisses the card for good; the full-screen alert still comes.
private struct NotificationCardCloseButton: View {
    private static let size: CGFloat = 18

    let card: NotificationCard
    let pointer: CGPoint?
    let close: () -> Void

    var body: some View {
        PointerHoverReader(pointer: pointer) { isHovered in
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isHovered ? PanelColors.primary : PanelColors.secondary)
                    .frame(width: Self.size, height: Self.size)
                    .background(Circle().fill(PanelColors.frost))
                    .overlay(Circle().strokeBorder(PanelColors.separator, lineWidth: 1))
                    .contentShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
            }
            .buttonStyle(.plain)
            .help(NotificationCard.closeHelp)
            .accessibilityLabel(card.closeAccessibilityLabel)
        }
    }
}

/// One segment of a card's button: its fill brightens under the pointer, and it dims while pressed or while its menu
/// is up (`isHeld`).
private struct NotificationSegmentStyle: ButtonStyle {
    let fill: Color
    let hoverFill: Color
    let foreground: Color
    let isHovered: Bool
    var isHeld = false

    func makeBody(configuration: Configuration) -> some View {
        NotificationSegmentBody(configuration: configuration, style: self)
    }
}

private struct NotificationSegmentBody: View {
    let configuration: ButtonStyleConfiguration
    let style: NotificationSegmentStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lit = style.isHovered || style.isHeld
        configuration.label
            .foregroundStyle(style.foreground)
            .background(Rectangle().fill(lit ? style.hoverFill : style.fill))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed || style.isHeld ? 0.7 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: lit)
    }
}

/// Whether the pointer the card's window tracks is over `content`, which SwiftUI's own hover can't tell in a panel
/// that isn't key while another app is active.
private struct PointerHoverReader<Content: View>: View {
    let pointer: CGPoint?
    @ViewBuilder let content: (Bool) -> Content
    @State private var frame = CGRect.null

    var body: some View {
        content(pointer.map(frame.contains) ?? false)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(NotificationCardView.coordinateSpace))
            } action: { newFrame in
                frame = newFrame
            }
    }
}
