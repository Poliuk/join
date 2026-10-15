import AppKit
import SwiftUI
import JoinCore

/// The single card at the top of the panel. A meeting's card shows a close button while the pointer is over
/// it, which dismisses the meeting: whatever comes next takes the card.
@MainActor
struct PanelHeroView: View {
    let hero: PanelHero
    let perform: (PanelAction) -> Void
    let dismiss: (Meeting) -> Void

    /// Whether the pointer is over the card. Tracked here rather than per card, so the card that takes a
    /// dismissed one's place under a still pointer carries on from it instead of starting afresh.
    @State private var isCardHovered = false
    /// Whether the pointer is over the close button. Where the button overhangs the card's corner, the
    /// pointer is off the card, and this alone keeps the button shown.
    @State private var isCloseHovered = false
    /// Set by a click on the close button while the pointer is over the card, cleared once it leaves: the
    /// next card comes in under a still pointer, and the second click of a double click must not dismiss it too.
    @State private var isCloseSuppressed = false

    var body: some View {
        VStack(spacing: 0) {
            switch hero {
            case .nothingToday(let detail):
                NothingTodayCard(detail: detail)
            case .next(let card):
                meetingCard(card, style: .neutral)
            case .startingSoon(let card):
                meetingCard(card, style: .startingSoon)
            case .now(let card):
                meetingCard(card, style: .now)
            }
        }
        .onHover { hovering in
            isCardHovered = hovering
            if !hovering { isCloseSuppressed = false }
        }
    }

    private func meetingCard(_ card: PanelCard, style: MeetingCard.Style) -> some View {
        MeetingCard(
            card: card,
            style: style,
            perform: perform,
            showsClose: (isCardHovered || isCloseHovered) && !isCloseSuppressed,
            isCloseHovered: $isCloseHovered,
            close: { close(card.meeting) },
            dismiss: { dismiss(card.meeting) }
        )
    }

    private func close(_ meeting: Meeting) {
        isCloseSuppressed = isCardHovered
        // The button goes away under the pointer, so its hover never ends on its own, and its reset of the
        // cursor on disappearing reads this already cleared: back to the arrow here, or the pointing hand stays.
        isCloseHovered = false
        NSCursor.arrow.set()
        dismiss(meeting)
    }
}

@MainActor
private struct NothingTodayCard: View {
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 15))
                .foregroundStyle(PanelColors.secondary)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("No more meetings today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelColors.primary)
                    .frame(minHeight: 18)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(PanelColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .panelCard(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct MeetingCard: View {
    enum Style {
        case neutral
        case startingSoon
        case now
    }

    /// Where the close button's center sits, inside the card's top-left corner: on the rounded edge, so the
    /// button overhangs the corner like a notification's. The card's 10 pt of panel padding keeps it unclipped.
    static let closeCenterInset: CGFloat = 4
    static let closeDiameter: CGFloat = 18
    /// Around the drawn circle, so the button is easier to hit than it is big.
    static let closeHitPadding: CGFloat = 2

    let card: PanelCard
    let style: Style
    let perform: (PanelAction) -> Void
    /// While the pointer is over the card or the button (`PanelHeroView` tracks it).
    let showsClose: Bool
    @Binding var isCloseHovered: Bool
    /// The close button.
    let close: () -> Void
    /// The card's Dismiss accessibility action, since the close button only shows under the pointer.
    let dismiss: () -> Void

    private var calendarColor: Color { Color(card.meeting.calendarColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(card.label)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(style == .startingSoon ? PanelColors.accentText : PanelColors.secondary)
                Spacer(minLength: 0)
                Text(card.timeRange)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(PanelColors.secondary)
            }
            .lineLimit(1)
            .frame(minHeight: 16)

            HStack(spacing: 8) {
                Circle()
                    .fill(calendarColor)
                    .frame(width: 8, height: 8)
                Text(card.meeting.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PanelColors.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minHeight: 22)
            .padding(.top, 6)

            if let location = card.location {
                detailLine(symbol: "mappin", text: location, color: PanelColors.secondary)
            }
            if let overlap = card.overlap {
                detailLine(symbol: "exclamationmark.triangle", text: overlap, color: PanelColors.warning)
            }
            if let progress = card.progress {
                PanelProgressBar(fraction: progress, color: calendarColor)
                    .padding(.top, 12)
            }
            if let action = card.action {
                actionButton(action)
                    .padding(.top, 14)
            }
        }
        .padding(14)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            ZStack {
                shape.fill(PanelColors.card)
                // The accent tint sits on the card, so in light mode it starts from white.
                if style == .startingSoon { shape.fill(PanelColors.accentSoft) }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style == .startingSoon ? PanelColors.accentLine : PanelColors.separator, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if showsClose {
                let offset = Self.closeCenterInset - Self.closeDiameter / 2 - Self.closeHitPadding
                closeButton
                    .offset(x: offset, y: offset)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: DismissCopy.dismissTitle, dismiss)
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
        }
        .buttonStyle(CardCloseButtonStyle(isHovered: isCloseHovered))
        .panelHover($isCloseHovered)
        .help(DismissCopy.cardDismissHelp)
        .accessibilityLabel(DismissCopy.dismissAccessibilityLabel(for: card.meeting))
    }

    private func detailLine(symbol: String, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .frame(width: 12)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(color)
        .frame(minHeight: 16)
        .padding(.top, 6)
        .padding(.leading, 16)
    }

    /// The starting-soon and now cards lead with an accent button; the next card's is neutral.
    private func actionButton(_ action: PanelAction) -> some View {
        let prominent = style != .neutral
        return Button {
            perform(action)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 13, weight: .medium))
                Text(action.title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
        }
        .buttonStyle(PanelFillButtonStyle(
            fill: prominent ? PanelColors.accentButton : PanelColors.buttonFill,
            foreground: prominent ? PanelColors.accentButtonLabel : PanelColors.primary,
            cornerRadius: 8,
            hoverFill: prominent ? PanelColors.accentButtonHover : PanelColors.buttonHoverFill
        ))
        .accessibilityLabel(action.accessibilityLabel(for: card.meeting))
    }
}

/// The card's close button: a small circle on the card's surface with the card's edge, its cross in secondary
/// ink, brighter under the pointer. The hover comes from the card, which also needs it (`PanelHeroView`).
private struct CardCloseButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        CardCloseButtonBody(configuration: configuration, isHovered: isHovered)
    }
}

private struct CardCloseButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .foregroundStyle(isHovered ? PanelColors.primary : PanelColors.secondary)
            .frame(width: MeetingCard.closeDiameter, height: MeetingCard.closeDiameter)
            .background(Circle().fill(isHovered ? PanelColors.cardButtonHover : PanelColors.cardButton))
            .overlay(Circle().strokeBorder(PanelColors.separator, lineWidth: 1))
            .padding(MeetingCard.closeHitPadding)
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }
}
