import SwiftUI
import JoinCore

/// The single card at the top of the panel.
@MainActor
struct PanelHeroView: View {
    let hero: PanelHero
    let perform: (PanelAction) -> Void

    var body: some View {
        switch hero {
        case .nothingToday(let detail):
            NothingTodayCard(detail: detail)
        case .next(let card):
            MeetingCard(card: card, style: .neutral, perform: perform)
        case .startingSoon(let card):
            MeetingCard(card: card, style: .startingSoon, perform: perform)
        case .now(let card):
            MeetingCard(card: card, style: .now, perform: perform)
        }
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
                    .foregroundStyle(PanelColors.title)
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
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PanelColors.cardFill))
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

    let card: PanelCard
    let style: Style
    let perform: (PanelAction) -> Void

    private var calendarColor: Color { Color(card.meeting.calendarColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(card.label)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(style == .startingSoon ? PanelColors.accentText : PanelColors.heading)
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
                    .foregroundStyle(PanelColors.heroTitle)
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
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style == .startingSoon ? PanelColors.accentSoft : PanelColors.cardFill))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style == .startingSoon ? PanelColors.accentLine : PanelColors.cardBorder, lineWidth: 1)
        )
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
            fill: prominent ? PanelColors.accent : PanelColors.buttonFill,
            foreground: prominent ? .white : PanelColors.title,
            cornerRadius: 8
        ))
        .accessibilityLabel(action.accessibilityLabel(for: card.meeting))
    }
}
