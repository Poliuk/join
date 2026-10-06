import AppKit
import SwiftUI
import JoinCore

/// The Today | 7 Days switch under the hero card. Today lists what's on now and what's still to start
/// today; 7 Days adds the following days. When nothing is left today, Today is dimmed and the week shows,
/// but the stored choice stays, so Today comes back by itself the next morning.
///
/// Drawn by hand rather than with a segmented Picker: built against an older SDK, the Picker draws
/// pre-Tahoe chrome, it can't share the panel's hover, and window snapshots drop its labels.
@MainActor
struct PanelFilterToggle: View {
    /// Each half of the 144 × 24 pt track; the thumb is inset 2 pt.
    static let segmentWidth: CGFloat = 72
    static let height: CGFloat = 24
    static let cornerRadius: CGFloat = 7
    static let inset: CGFloat = 2

    /// The thumb's slide, for a click and for ⌘1 / ⌘2 alike; none with Reduce Motion.
    static func selectionAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }

    let state: PanelFilterState
    let select: (PanelListFilter) -> Void

    @Namespace private var thumbSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            segment(.today)
            segment(.week)
        }
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(PanelColors.segmentTrack)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(PanelColors.segmentTrackEdge, lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show meetings")
    }

    private func segment(_ filter: PanelListFilter) -> some View {
        let isSelected = state.effective == filter
        let isEnabled = filter == .week || state.isTodayAvailable
        return Button {
            // A click on the segment already shown still stores it: in the evening, clicking 7 Days
            // makes it the choice even though the week was showing anyway.
            withAnimation(Self.selectionAnimation(reduceMotion: reduceMotion)) {
                select(filter)
            }
        } label: {
            Text(filter.title)
        }
        .buttonStyle(SegmentStyle(
            isSelected: isSelected,
            isEnabled: isEnabled,
            edge: filter == .today ? .leading : .trailing,
            thumbSpace: thumbSpace
        ))
        .disabled(!isEnabled)
        .help(isEnabled ? filter.tooltip : "")
        .accessibilityLabel(filter.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isEnabled ? filter.shortcut : "Nothing else today")
        // A disabled button may not show its own tooltip, so the dimmed Today's sits on a wrapper.
        .background(Color.clear.contentShape(Rectangle()).help(isEnabled ? "" : "Nothing else today"))
    }
}

private extension PanelListFilter {
    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "7 Days"
        }
    }

    var tooltip: String {
        switch self {
        case .today: return "Show today's meetings (⌘1)"
        case .week: return "Show today and the next 7 days (⌘2)"
        }
    }

    /// For VoiceOver, which doesn't read tooltips.
    var shortcut: String {
        switch self {
        case .today: return "Command-1"
        case .week: return "Command-2"
        }
    }
}

/// One half of the switch: the thumb under the selected one (it slides between them), a faint fill under
/// the pointer, a darker one while pressed. Only an enabled, unselected half reacts to the pointer.
private struct SegmentStyle: ButtonStyle {
    let isSelected: Bool
    let isEnabled: Bool
    let edge: HorizontalEdge
    let thumbSpace: Namespace.ID

    func makeBody(configuration: Configuration) -> some View {
        SegmentBody(configuration: configuration, style: self)
    }
}

private struct SegmentBody: View {
    let configuration: ButtonStyleConfiguration
    let style: SegmentStyle
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var reacts: Bool { style.isEnabled && !style.isSelected }

    /// With Increase Contrast the thumb's edge is drawn wider, so the chosen half keeps a 3:1 edge.
    private var thumbEdgeWidth: CGFloat {
        contrast == .increased || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0.5
    }

    var body: some View {
        let inset = PanelFilterToggle.inset
        let thumbShape = RoundedRectangle(cornerRadius: PanelFilterToggle.cornerRadius - inset, style: .continuous)
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(labelColor)
            .opacity(configuration.isPressed && reacts ? 0.7 : 1)
            .frame(width: PanelFilterToggle.segmentWidth - inset, height: PanelFilterToggle.height - 2 * inset)
            .background {
                if style.isSelected {
                    thumbShape
                        .fill(PanelColors.segmentThumb)
                        .overlay(thumbShape.strokeBorder(PanelColors.segmentThumbEdge, lineWidth: thumbEdgeWidth))
                        .shadow(color: PanelColors.segmentThumbShadow, radius: 1, y: 0.5)
                        .matchedGeometryEffect(id: "thumb", in: style.thumbSpace)
                } else if reacts && (configuration.isPressed || isHovered) {
                    thumbShape.fill(configuration.isPressed ? PanelColors.segmentPressed : PanelColors.segmentHover)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .padding(.vertical, inset)
            .padding(style.edge == .leading ? .leading : .trailing, inset)
            .contentShape(Rectangle())
            .modifier(SegmentHover(isActive: reacts, isHovered: $isHovered))
    }

    private var labelColor: Color {
        if style.isSelected { return PanelColors.primary }
        if !style.isEnabled { return PanelColors.segmentDisabled }
        return isHovered ? PanelColors.strong : PanelColors.secondary
    }
}

/// The panel's hover (fill and pointing hand) for a half that can be clicked; the selected and the
/// dimmed half keep the arrow.
private struct SegmentHover: ViewModifier {
    let isActive: Bool
    @Binding var isHovered: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.panelHover($isHovered)
        } else {
            content.onAppear { isHovered = false }
        }
    }
}
