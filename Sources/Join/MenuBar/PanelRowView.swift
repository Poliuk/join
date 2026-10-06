import SwiftUI
import JoinCore

/// "Tomorrow  Wed 7 Oct" followed by that day's rows.
@MainActor
struct PanelSectionView: View {
    let section: PanelSection
    let perform: (PanelAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(section.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PanelColors.secondary)
                if let subtitle = section.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(PanelColors.tertiary)
                }
            }
            .lineLimit(1)
            .frame(minHeight: 16)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 2) {
                ForEach(section.rows) { row in
                    PanelRowView(row: row, perform: perform)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }
}

/// Start over end time, a calendar-colored bar, the title with an optional second line, and a button.
@MainActor
struct PanelRowView: View {
    let row: PanelRow
    let perform: (PanelAction) -> Void

    private var meeting: Meeting { row.meeting }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(row.startTime)
                    .foregroundStyle(row.isMuted ? PanelColors.tertiary : PanelColors.strong)
                    .frame(height: 16)
                Text(row.endTime)
                    .foregroundStyle(row.isMuted ? PanelColors.tertiary : PanelColors.tertiary)
                    .frame(height: 16)
            }
            .font(.system(size: 12).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 60, alignment: .trailing)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(row.isMuted ? PanelColors.mutedBar : Color(meeting.calendarColor))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                Text(meeting.title)
                    .font(.system(size: 13.5, weight: row.isMuted ? .medium : .semibold))
                    .foregroundStyle(row.isMuted ? PanelColors.tertiary : PanelColors.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minHeight: 18)
                if let detail = row.detail {
                    detailView(detail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let action = row.action {
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
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func detailView(_ detail: PanelRow.Detail) -> some View {
        switch detail {
        case .location(let text):
            iconLine(symbol: "mappin", text: text, color: PanelColors.secondary)
        case .overlap(let text):
            iconLine(symbol: "exclamationmark.triangle", text: text, color: PanelColors.warning)
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
