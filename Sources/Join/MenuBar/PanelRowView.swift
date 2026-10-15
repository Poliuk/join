import AppKit
import SwiftUI
import JoinCore

/// "Tomorrow  Wed 7 Oct" followed by that day's rows.
@MainActor
struct PanelSectionView: View {
    enum Heading {
        /// A list heading: "Now", "Also now".
        case section
        /// A day under "Upcoming events": "Today", "Tomorrow Wed 7 Oct", with a hairline after it.
        case day
        /// Rows only, as under "Upcoming events" in the Today view.
        case none
    }

    let section: PanelSection
    let heading: Heading
    let perform: (PanelAction) -> Void
    let dismissActions: PanelDismissActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch heading {
            case .section:
                PanelSectionHeading(title: section.title, subtitle: section.subtitle)
            case .day:
                PanelDayHeading(title: section.title, subtitle: section.subtitle)
            case .none:
                EmptyView()
            }

            VStack(spacing: 2) {
                ForEach(section.rows) { row in
                    PanelRowView(row: row, perform: perform, dismissActions: dismissActions)
                }
            }
        }
        .padding(.horizontal, 6)
        // Rows without a heading follow "Upcoming events" as closely as rows follow their own heading.
        .padding(.top, heading == .none ? 0 : 2)
    }
}

/// A list heading in the panel: "Now", "Also now", "Upcoming events". The top of the list's hierarchy:
/// large and bold over small caps day labels (option B of the panel typography canvas, the user's pick).
struct PanelSectionHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.15)
                .foregroundStyle(PanelColors.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(PanelColors.secondary)
            }
        }
        .lineLimit(1)
        .frame(minHeight: 20)
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A day under "Upcoming events": a small caps label followed by a hairline, so the days read as parts
/// of the list rather than lists of their own. The caps are display only; VoiceOver reads the words.
struct PanelDayHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(PanelColors.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(PanelColors.tertiary)
            }
            Rectangle()
                .fill(PanelColors.separator)
                .frame(height: 1)
                .padding(.leading, 2)
                .accessibilityHidden(true)
        }
        .lineLimit(1)
        .frame(minHeight: 16)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What a row's Dismiss and Restore buttons do (`AppModel.dismiss`, `AppModel.restore`).
struct PanelDismissActions {
    let dismiss: (Meeting) -> Void
    let restore: (Meeting) -> Void
}

/// Start over end time, a calendar-colored bar, the title with an optional second line, and a button.
/// Under the pointer, a meeting that may alert offers Dismiss, and a dismissed one Restore.
@MainActor
struct PanelRowView: View {
    static let dismissButtonSize: CGFloat = 22

    let row: PanelRow
    let perform: (PanelAction) -> Void
    let dismissActions: PanelDismissActions

    @State private var isHovered = false

    private var meeting: Meeting { row.meeting }
    private var isDismissed: Bool { row.dismissal == .dismissed }
    /// Out-of-office blocks and dismissed meetings: tertiary title, regular-weight start time.
    private var isDimmed: Bool { row.isMuted || isDismissed }
    /// Shown under the pointer only. It never changes the row's height (it's shorter than the action
    /// button and the two time lines), and it goes before the action button, which stays put.
    private var showsDismissButton: Bool { isHovered && row.dismissal != nil }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(row.startTime)
                    .fontWeight(isDimmed ? .regular : .medium)
                    .foregroundStyle(isDimmed ? PanelColors.tertiary : PanelColors.strong)
                    .frame(height: 16)
                Text(row.endTime)
                    .foregroundStyle(row.isMuted ? PanelColors.tertiary : PanelColors.tertiary)
                    .frame(height: 16)
            }
            .font(.system(size: 12).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 60, alignment: .trailing)

            // A dismissed meeting keeps its calendar's color, faded; the bar is decorative, so its contrast is free.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(row.isMuted ? PanelColors.mutedBar : Color(meeting.calendarColor).opacity(isDismissed ? 0.4 : 1))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                Text(meeting.title)
                    .font(.system(size: 13, weight: isDimmed ? .medium : .semibold))
                    .foregroundStyle(isDimmed ? PanelColors.tertiary : PanelColors.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minHeight: 18)
                if let detail = row.detail {
                    detailView(detail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDismissButton || row.action != nil {
                HStack(spacing: 4) {
                    if showsDismissButton, let dismissal = row.dismissal {
                        dismissButton(dismissal)
                    }
                    if let action = row.action {
                        actionButton(action)
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if row.isMuted {
                PanelStripes()
                    .fill(PanelColors.stripe)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        // The button only shows under the pointer, so VoiceOver gets the same choice as an action.
        .modifier(DismissalAccessibilityAction(dismissal: row.dismissal, perform: toggleDismissal))
    }

    private func actionButton(_ action: PanelAction) -> some View {
        Button {
            perform(action)
        } label: {
            Image(systemName: action.symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(PanelFillButtonStyle(
            fill: PanelColors.rowButtonFill,
            foreground: PanelColors.primary,
            cornerRadius: 8,
            hoverFill: PanelColors.rowButtonHoverFill
        ))
        .help(action.accessibilityLabel(for: meeting))
        .accessibilityLabel(action.accessibilityLabel(for: meeting))
    }

    /// Dismiss (a cross), or Restore (a back arrow) on a dismissed row, in the same place on the row. The row
    /// itself can move: dismissing or restoring the card's meeting changes the card, and its height, and can
    /// add or remove the Now section above, as when a meeting in progress takes the card from, or gives it
    /// back to, one starting soon. So a double click acts once (`NSEvent.isRepeatedClick`), never on the row
    /// that moves in.
    private func dismissButton(_ dismissal: PanelRow.Dismissal) -> some View {
        let restores = dismissal == .dismissed
        return Button {
            guard !NSEvent.isRepeatedClick else { return }
            toggleDismissal()
        } label: {
            Image(systemName: restores ? "arrow.uturn.backward" : "xmark")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Self.dismissButtonSize, height: Self.dismissButtonSize)
        }
        .buttonStyle(PanelIconButtonStyle(cornerRadius: 6))
        .help(restores ? DismissCopy.restoreHelp : DismissCopy.rowDismissHelp)
        .accessibilityLabel(restores
            ? DismissCopy.restoreAccessibilityLabel(for: meeting)
            : DismissCopy.dismissAccessibilityLabel(for: meeting))
    }

    private func toggleDismissal() {
        switch row.dismissal {
        case .dismissable: dismissActions.dismiss(meeting)
        case .dismissed: dismissActions.restore(meeting)
        case nil: break
        }
    }

    @ViewBuilder
    private func detailView(_ detail: PanelRow.Detail) -> some View {
        switch detail {
        case .location(let text):
            iconLine(symbol: "mappin", text: text, color: PanelColors.secondary)
        case .overlap(let text):
            iconLine(symbol: "exclamationmark.triangle", text: text, color: PanelColors.warning)
        case .dismissed(let text):
            iconLine(symbol: "bell.slash", text: text, color: PanelColors.secondary)
        case .progress(let fraction, let left):
            HStack(spacing: 8) {
                PanelProgressBar(fraction: fraction, color: Color(meeting.calendarColor))
                Text(left)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(PanelColors.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: 16)
            }
            .padding(.top, 4)
        }
    }

    private func iconLine(symbol: String, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 12)
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 12))
        .foregroundStyle(color)
        .frame(height: 16)
    }
}

/// "Dismiss" on a row that may alert, "Restore" on a dismissed one, nothing on the others.
private struct DismissalAccessibilityAction: ViewModifier {
    let dismissal: PanelRow.Dismissal?
    let perform: () -> Void

    func body(content: Content) -> some View {
        // One branch for both states, so dismissing doesn't rebuild the row under the pointer.
        if let dismissal {
            content.accessibilityAction(named: dismissal == .dismissed ? DismissCopy.restoreTitle : DismissCopy.dismissTitle, perform)
        } else {
            content
        }
    }
}
