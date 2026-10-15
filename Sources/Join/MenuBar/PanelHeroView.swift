import AppKit
import SwiftUI
import JoinCore

/// The single card at the top of the panel.
struct PanelHeroView: View {
    let hero: PanelHero
    let perform: (PanelAction) -> Void
    let dismissActions: PanelDismissActions

    var body: some View {
        switch hero {
        case .nothingToday(let detail):
            NothingTodayCard(detail: detail)
        case .next(let card):
            MeetingCard(card: card, style: .neutral, perform: perform, dismissActions: dismissActions)
        case .startingSoon(let card):
            MeetingCard(card: card, style: .startingSoon, perform: perform, dismissActions: dismissActions)
        case .now(let card):
            MeetingCard(card: card, style: .now, perform: perform, dismissActions: dismissActions)
        }
    }
}

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

private struct MeetingCard: View {
    enum Style {
        case neutral
        case startingSoon
        case now
    }

    let card: PanelCard
    let style: Style
    let perform: (PanelAction) -> Void
    let dismissActions: PanelDismissActions

    @State private var dismissAnchor = ViewAnchor()

    private var calendarColor: Color { Color(card.meeting.calendarColor) }
    /// The card's meeting is never a dismissed one (they don't take the card), so its button is Dismiss, asking
    /// by the same rule as a row's.
    private var dismissal: PanelRow.Dismissal { .dismissable(for: card.meeting) }

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

            switch card.detail {
            case .ongoing(let progress):
                PanelProgressBar(fraction: progress, color: calendarColor)
                    .padding(.top, 12)
            case .upcoming(let location, let overlap):
                if let location {
                    detailLine(symbol: "mappin", text: location, color: PanelColors.secondary)
                }
                if let overlap {
                    detailLine(symbol: "exclamationmark.triangle", text: overlap, color: PanelColors.warning)
                }
            }
            // Join or Directions leads; Dismiss sits at the bottom right, alone when there's nothing to open.
            HStack(spacing: 8) {
                if let action = card.action {
                    actionButton(action)
                } else {
                    Spacer(minLength: 0)
                }
                dismissButton
            }
            .padding(.top, 14)
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
    }

    /// Dismiss, with the crossed-out bell the dismissed rows show. A neutral button (`buttonFill`, `primary`
    /// label): quieter than the accent Join or Directions on the starting-soon and now cards, styled like the
    /// neutral one on the next card.
    ///
    /// The card that takes this one's place keeps Dismiss at the same right edge, but its height follows the
    /// new card's lines (location, overlap, progress): a shorter card, or No more meetings today, brings the
    /// switch or the list's rows under the pointer. So this button and every control that can move in below
    /// it (the switch's halves, the rows' Join or Directions, Dismiss and Restore) ignore a repeated click
    /// (`NSEvent.isRepeatedClick`): a double click acts once, never on what moves in.
    ///
    /// When it asks (`Dismissal.asksScope`, a repeating event) it opens Dismiss This Event / Dismiss All Future
    /// Events below itself instead, and the choice acts (`PanelDismissActions`); its look doesn't change.
    private var dismissButton: some View {
        Button {
            guard !NSEvent.isRepeatedClick else { return }
            dismissActions.click(dismissal, of: card.meeting, anchor: dismissAnchor.view)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: DismissSymbols.dismiss)
                    .font(.system(size: 12, weight: .medium))
                Text(DismissCopy.dismissTitle)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
        }
        .buttonStyle(PanelFillButtonStyle(
            fill: PanelColors.buttonFill,
            foreground: PanelColors.primary,
            cornerRadius: 8,
            hoverFill: PanelColors.buttonHoverFill
        ))
        .fixedSize()
        .background(AnchorView(anchor: dismissAnchor))
        .help(DismissCopy.cardDismissHelp(asksScope: dismissal.asksScope))
        .accessibilityLabel(DismissCopy.dismissAccessibilityLabel(for: card.meeting, asksScope: dismissal.asksScope))
        .modifier(DismissalAccessibilityActions(
            meeting: card.meeting,
            dismissal: dismissal,
            namesOneOffAction: false,
            actions: dismissActions
        ))
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
