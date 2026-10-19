import AppKit
import SwiftUI
import JoinCore

/// "Tomorrow  Wed 7 Oct" followed by that day's rows.
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
    let perform: (PanelAction, Meeting) -> Void
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
private struct PanelDayHeading: View {
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

/// What the card's and the rows' Dismiss and Restore buttons do (`AppModel.dismiss`, `AppModel.restore`), as
/// their `PanelRow.Dismissal` says, which JoinCore decides once. When there's no choice to make they act at once,
/// as they always have. When there is (`Dismissal.asksScope`: Dismiss on a repeating event, Restore on one
/// dismissed with its series) they open a menu of This Event and All Future Events below the button, shown like
/// the header's menus (`MenuBarPanelContext.showMenu`), so the panel stays open while it's up; the choice acts
/// and the panel stays.
struct PanelDismissActions {
    let dismiss: (Meeting, DismissScope) -> Void
    let restore: (Meeting, DismissScope) -> Void
    let showMenu: ([PanelMenuItem], NSView) -> Void

    /// What `dismissal`'s button does to `meeting` for `scope`: Dismiss, or Restore once it's dismissed.
    func perform(_ dismissal: PanelRow.Dismissal, of meeting: Meeting, scope: DismissScope) {
        if dismissal.isDismissed {
            restore(meeting, scope)
        } else {
            dismiss(meeting, scope)
        }
    }

    /// A click on `dismissal`'s button for `meeting`, whose view is `anchor`: it acts at once, or asks This Event
    /// or All Future Events when `dismissal.asksScope`. `menuOpen` follows the menu, for a button that would
    /// otherwise hide while it's up.
    func click(_ dismissal: PanelRow.Dismissal, of meeting: Meeting, anchor: NSView?, menuOpen: @escaping (Bool) -> Void = { _ in }) {
        // Without its button's view, which the button always has, it acts on this event alone.
        guard dismissal.asksScope, let anchor else {
            perform(dismissal, of: meeting, scope: .thisEvent)
            return
        }
        let items = DismissScope.allCases.map { scope in
            PanelMenuItem(title: dismissal.isDismissed ? DismissCopy.restoreChoice(scope) : DismissCopy.dismissChoice(scope)) {
                // With no room below the button (a row at the bottom of the screen), the menu opens over it,
                // so the second click of a double click could land on an item: it chooses nothing.
                guard !NSEvent.isRepeatedClick else { return }
                perform(dismissal, of: meeting, scope: scope)
            }
        }
        menuOpen(true)
        // Let the pressed look render before the menu's tracking loop takes over, as the header's buttons do.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            showMenu(items, anchor)
            menuOpen(false)
        }
    }
}

/// Start over end time, a calendar-colored bar, the title with an optional second line, and a button.
/// Under the pointer, a meeting that may alert offers Dismiss; a dismissed one always shows Restore.
struct PanelRowView: View {
    private static let dismissButtonSize: CGFloat = 22
    private static let actionButtonSize: CGFloat = 30

    let row: PanelRow
    let perform: (PanelAction, Meeting) -> Void
    let dismissActions: PanelDismissActions

    @State private var isHovered = false
    /// While a repeating event's Dismiss menu is up, its button stays, though the pointer has left the row
    /// for the menu.
    @State private var isMenuOpen = false
    @State private var dismissAnchor = ViewAnchor()

    private var meeting: Meeting { row.meeting }
    private var isDismissed: Bool { row.dismissal?.isDismissed ?? false }
    /// Out-of-office blocks and dismissed meetings: tertiary title, regular-weight start time.
    private var isDimmed: Bool { row.isMuted || isDismissed }
    /// Dismiss shows under the pointer only, to keep the list calm; Restore always shows on a dismissed row,
    /// so the way back is in view for as long as the meeting is listed (the user's ask). It never changes the
    /// row's height (it's shorter than the action button and the two time lines), and it goes before the
    /// action button, which stays put.
    private var showsDismissButton: Bool {
        switch row.dismissal {
        case .dismissed?: return true
        case .dismissable?: return isHovered || isMenuOpen
        case nil: return false
        }
    }

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
                    } else if showsDismissButton {
                        // The action button's place, kept empty: the bell sits in the same column on every
                        // row, with or without Join or Directions beside it (the user's ask, 2026-10-15).
                        Color.clear
                            .frame(width: Self.actionButtonSize, height: Self.actionButtonSize)
                            .accessibilityHidden(true)
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
        // The button only shows under the pointer, so VoiceOver gets the same choices as actions.
        .modifier(DismissalAccessibilityActions(
            meeting: meeting,
            dismissal: row.dismissal,
            namesOneOffAction: true,
            actions: dismissActions
        ))
    }

    /// Join or Directions. Dismissing the card can pull a row, even the dismissed meeting's own, up under the
    /// pointer, so the second click of a double click on the card's Dismiss must not open it
    /// (`NSEvent.isRepeatedClick`).
    private func actionButton(_ action: PanelAction) -> some View {
        Button {
            guard !NSEvent.isRepeatedClick else { return }
            perform(action, meeting)
        } label: {
            Image(systemName: action.symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: Self.actionButtonSize, height: Self.actionButtonSize)
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

    /// Dismiss (the card's crossed-out bell), or Restore (the bell, uncrossed) on a dismissed row, in the same place on the row. The row
    /// itself can move: dismissing or restoring the card's meeting changes the card, and its height, and can
    /// add or remove the Now section above, as when a meeting in progress takes the card from, or gives it
    /// back to, one starting soon. So a double click acts once (`NSEvent.isRepeatedClick`), never on the row
    /// that moves in. When it asks (`Dismissal.asksScope`) it opens This Event / All Future Events instead
    /// (`PanelDismissActions`).
    private func dismissButton(_ dismissal: PanelRow.Dismissal) -> some View {
        let restores = dismissal.isDismissed
        let asksScope = dismissal.asksScope
        return Button {
            guard !NSEvent.isRepeatedClick else { return }
            dismissActions.click(dismissal, of: meeting, anchor: dismissAnchor.view) { isMenuOpen = $0 }
        } label: {
            Image(systemName: restores ? DismissSymbols.restore : DismissSymbols.dismiss)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Self.dismissButtonSize, height: Self.dismissButtonSize)
        }
        .buttonStyle(PanelIconButtonStyle(cornerRadius: 6))
        .background(AnchorView(anchor: dismissAnchor))
        .help(restores ? DismissCopy.restoreHelp(asksScope: asksScope) : DismissCopy.rowDismissHelp(asksScope: asksScope))
        .accessibilityLabel(restores
            ? DismissCopy.restoreAccessibilityLabel(for: meeting, asksScope: asksScope)
            : DismissCopy.dismissAccessibilityLabel(for: meeting, asksScope: asksScope))
    }

    @ViewBuilder
    private func detailView(_ detail: PanelRow.Detail) -> some View {
        switch detail {
        case .location(let text):
            iconLine(symbol: "mappin", text: text, color: PanelColors.secondary)
        case .overlap(let text):
            iconLine(symbol: "exclamationmark.triangle", text: text, color: PanelColors.warning)
        case .dismissed(let text):
            iconLine(symbol: DismissSymbols.dismiss, text: text, color: PanelColors.secondary)
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

/// VoiceOver's actions for `meeting`'s Dismiss or Restore (`dismissal`; nil when there's nothing to dismiss):
/// when the button asks (`Dismissal.asksScope`), the menu's two choices, "Dismiss This Event" and "Dismiss All
/// Future Events" (or Restore's), so they don't need the menu; otherwise "Dismiss" or "Restore" when
/// `namesOneOffAction`, as on a row, whose Dismiss only shows under the pointer, and nothing on the card, whose
/// button is always there.
struct DismissalAccessibilityActions: ViewModifier {
    let meeting: Meeting
    let dismissal: PanelRow.Dismissal?
    let namesOneOffAction: Bool
    let actions: PanelDismissActions

    func body(content: Content) -> some View {
        // Only the actions vary, never the row: `content` stays one view in every state, so dismissing or
        // restoring (even a repeating event on its own, whose choices go from two to one) doesn't rebuild the
        // row under the pointer.
        content.accessibilityActions {
            if let dismissal {
                if dismissal.asksScope {
                    ForEach(DismissScope.allCases, id: \.self) { scope in
                        Button(title(scope, of: dismissal)) {
                            actions.perform(dismissal, of: meeting, scope: scope)
                        }
                    }
                } else if namesOneOffAction {
                    Button(dismissal.isDismissed ? DismissCopy.restoreTitle : DismissCopy.dismissTitle) {
                        actions.perform(dismissal, of: meeting, scope: .thisEvent)
                    }
                }
            }
        }
    }

    private func title(_ scope: DismissScope, of dismissal: PanelRow.Dismissal) -> String {
        dismissal.isDismissed ? DismissCopy.restoreChoice(scope) : DismissCopy.dismissChoice(scope)
    }
}
