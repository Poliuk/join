import AppKit
import SwiftUI
import JoinCore

/// The drop-down panel: a header with today's date and two menus, then a scrolling body with one hero
/// card, the Today | 7 Days switch and the list. Its natural height is reported to the window, which
/// fits it up to a cap.
@MainActor
struct MenuBarPanelView: View {
    static let fadeHeight: CGFloat = 32
    /// How faint the last visible row gets while there is more to scroll to.
    static let fadeFloor: CGFloat = 0.4

    let context: MenuBarPanelContext
    @Environment(AppModel.self) private var model
    @State private var headerHeight: CGFloat = 0
    @State private var bodyHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: context)
                .background(measure(HeaderHeightKey.self))

            ScrollView(.vertical) {
                panelBody
                    .background(measure(BodyHeightKey.self))
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named(Self.scrollSpace)).minY)
                    })
            }
            .coordinateSpace(name: Self.scrollSpace)
            .scrollBounceBehavior(.basedOnSize)
            .background(measure(ViewportHeightKey.self))
            .mask(fadeMask)
        }
        .frame(width: MenuBarPanelWindow.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PanelFrost())
        .clipShape(RoundedRectangle(cornerRadius: MenuBarPanelWindow.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MenuBarPanelWindow.cornerRadius, style: .continuous)
                .strokeBorder(PanelColors.separator, lineWidth: 1)
        )
        .onPreferenceChange(HeaderHeightKey.self) { height in
            headerHeight = height
            context.naturalHeightChanged(headerHeight + bodyHeight)
        }
        .onPreferenceChange(BodyHeightKey.self) { height in
            bodyHeight = height
            context.naturalHeightChanged(headerHeight + bodyHeight)
        }
        .onPreferenceChange(ViewportHeightKey.self) { viewportHeight = $0 }
        .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
    }

    private static let scrollSpace = "panelScroll"

    @ViewBuilder
    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            let showsUpdate = model.updateChecker.offeredUpdate != nil
            if model.meetingStore.authorization == .authorized {
                let content = model.panelContent
                let pausedMessage = model.pausedMessage
                if let pausedMessage {
                    PausedBar(message: pausedMessage) { model.resume() }
                }
                updateBar(topPadding: pausedMessage == nil ? 10 : 8)
                let filter = content.filtered(by: model.preferences.panelListFilter)
                PanelHeroView(hero: content.hero, perform: model.perform)
                    .padding(.horizontal, 10)
                    .padding(.top, pausedMessage == nil && !showsUpdate ? 10 : 8)
                    .padding(.bottom, 2)
                if filter.isShown {
                    PanelFilterToggle(state: filter) { model.preferences.panelListFilter = $0 }
                        .padding(.top, 8)
                }
                // Only the switch's thumb slides; the list snaps, so the window resizes in one step.
                Group {
                    if let now = filter.now {
                        PanelSectionView(section: now, heading: .section, perform: model.perform)
                    }
                    if !filter.upcoming.isEmpty {
                        PanelSectionHeading(title: PanelFilterState.upcomingTitle)
                            .padding(.horizontal, 6)
                            .padding(.top, 2)
                        ForEach(filter.upcoming) { section in
                            PanelSectionView(section: section, heading: filter.showsDayHeadings ? .day : .none, perform: model.perform)
                        }
                    }
                }
                .transaction { $0.animation = nil }
            } else {
                updateBar(topPadding: 10)
                PermissionPrompt(authorization: model.meetingStore.authorization, topPadding: showsUpdate ? 8 : 10)
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shown while an update is on offer, whether or not the calendars can be read.
    @ViewBuilder
    private func updateBar(topPadding: CGFloat) -> some View {
        let checker = model.updateChecker
        if let update = checker.offeredUpdate {
            let install = checker.install
            let installUnavailable = install == .idle && !checker.canInstall
            UpdateBar(
                message: UpdateCopy.barMessage(version: update.version, install: install),
                buttonTitle: UpdateCopy.barButtonTitle(install: install),
                // Install waits for a check under way, which may change the offer.
                buttonEnabled: !installUnavailable && !(install == .idle && checker.isChecking),
                help: installUnavailable ? UpdateCopy.installFixtureNote : failureReason(install),
                action: model.performUpdateAction
            )
            .padding(.top, topPadding)
        }
    }

    private func failureReason(_ install: UpdateInstallState) -> String? {
        if case .failed(let failure) = install { return UpdateCopy.failureReason(failure) }
        return nil
    }

    /// Fades the list out at the bottom while there is more to scroll to. It fades into the frost, not
    /// into the glass, and only part way, so the last row stays legible.
    private var fadeMask: some View {
        let hidden = bodyHeight + scrollOffset - viewportHeight
        let strength = min(max(hidden / Self.fadeHeight, 0), 1)
        let lastRowOpacity = Double(1 - (1 - Self.fadeFloor) * strength)
        return VStack(spacing: 0) {
            Rectangle()
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(lastRowOpacity), location: 0.85),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.fadeHeight)
        }
    }

    private func measure<Key: PreferenceKey>(_ key: Key.Type) -> some View where Key.Value == CGFloat {
        GeometryReader { proxy in
            Color.clear.preference(key: key, value: proxy.size.height)
        }
    }
}

/// The frost between the glass and the content: it pins what's behind the text to a known surface while
/// some of the glass's color and depth still shows through. Opaque with Reduce Transparency, thicker
/// with Increase Contrast, lighter over the pre-Liquid Glass menu blur.
@MainActor
private struct PanelFrost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Rectangle()
            .fill(PanelColors.frost)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var opacity: Double {
        let workspace = NSWorkspace.shared
        if reduceTransparency || workspace.accessibilityDisplayShouldReduceTransparency { return 1 }
        if let override = model.panelFrostOverride { return override }
        if contrast == .increased || workspace.accessibilityDisplayShouldIncreaseContrast {
            return PanelPalette.increasedContrastFrostOpacity
        }
        return MenuBarPanelWindow.usesGlass ? PanelPalette.frostOpacity : PanelPalette.legacyMaterialFrostOpacity
    }
}

private struct HeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct BodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: Header

@MainActor
private struct PanelHeader: View {
    let context: MenuBarPanelContext
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(MenuBarPresenter.headerDate(model.now))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelColors.primary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if model.isFixture {
                    FixtureBadge()
                        .padding(.leading, 6)
                }
                Spacer(minLength: 8)
                // Paused, the bell is a pressed toggle that resumes; otherwise it opens the pause menu.
                HeaderButton(
                    symbol: model.isPaused ? "bell.slash" : "bell",
                    label: model.isPaused ? "Resume reminders" : "Pause reminders",
                    isOn: model.isPaused,
                    kind: model.isPaused ? .action(model.resume) : .menu(context.showPauseMenu)
                )
                HeaderButton(symbol: "gearshape", label: "Settings", kind: .menu(context.showAppMenu))
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 10)

            Rectangle()
                .fill(PanelColors.separator)
                .frame(height: 1)
        }
    }
}

/// "Fixture" next to the date when the app runs on fixture calendars, so it can't be taken for the real thing.
@MainActor
private struct FixtureBadge: View {
    var body: some View {
        Text("Fixture")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(PanelColors.badgeText)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(PanelColors.badgeFill))
            .fixedSize()
            .help("Join! is running on fixture calendars, not your own")
            .accessibilityLabel("Fixture calendars")
    }
}

/// A 28 pt icon button that opens an AppKit menu below itself, or acts directly.
@MainActor
private struct HeaderButton: View {
    enum Kind {
        case menu((NSView) -> Void)
        case action(() -> Void)
    }

    let symbol: String
    let label: String
    /// Drawn pressed and reported as selected, like the bell while reminders are paused.
    var isOn = false
    let kind: Kind

    @State private var anchor = ViewAnchor()
    @State private var isMenuOpen = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let active = isOn || isMenuOpen
        Button {
            switch kind {
            case .action(let perform):
                perform()
            case .menu(let open):
                guard let view = anchor.view else { return }
                isMenuOpen = true
                // Let the pressed look render before the menu's tracking loop takes over.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    open(view)
                    isMenuOpen = false
                }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(active ? PanelColors.strong : PanelColors.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? (isHovered ? PanelColors.buttonHoverFill : PanelColors.buttonFill) : (isHovered ? PanelColors.hoverFill : .clear))
                )
                // Filled while active (the paused bell, an open menu), so it gets the Increase Contrast edge.
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(active ? PanelColors.controlBorder : .clear, lineWidth: 1)
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(AnchorView(anchor: anchor))
        .panelHover($isHovered)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(isMenu ? "Opens a menu" : "")
    }

    private var isMenu: Bool {
        if case .menu = kind { return true }
        return false
    }
}

/// Holds the AppKit view behind a SwiftUI button, so a menu can be positioned against it.
@MainActor
private final class ViewAnchor {
    weak var view: NSView?
}

private struct AnchorView: NSViewRepresentable {
    let anchor: ViewAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

// MARK: Paused bar

@MainActor
private struct PausedBar: View {
    let message: String
    let resume: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 12))
                .foregroundStyle(PanelColors.secondary)
                .frame(width: 14, height: 14)
            Text(message)
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundStyle(PanelColors.strong)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: resume) {
                Text("Resume")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
            }
            .buttonStyle(PanelFillButtonStyle(
                fill: PanelColors.buttonFill,
                foreground: PanelColors.primary,
                cornerRadius: 6,
                hoverFill: PanelColors.buttonHoverFill
            ))
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .panelCard(cornerRadius: 10)
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }
}

// MARK: Update bar

/// "Join! 1.1.0 is available" with Install, then the download's progress, and Download Page after a
/// failed install or Show in Finder once the new copy waits in a folder. Laid out like the paused bar.
@MainActor
private struct UpdateBar: View {
    let message: String
    let buttonTitle: String?
    var buttonEnabled = true
    /// The button's tooltip: why an install failed, or why Install is off in a fixture run.
    let help: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 12))
                .foregroundStyle(PanelColors.secondary)
                .frame(width: 14, height: 14)
            // "Quit Join!, then move Join! 1.1.0 to Applications" doesn't fit beside its button on one line.
            Text(message)
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundStyle(PanelColors.strong)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let buttonTitle {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                }
                .buttonStyle(PanelFillButtonStyle(
                    fill: PanelColors.buttonFill,
                    foreground: PanelColors.primary,
                    cornerRadius: 6,
                    hoverFill: PanelColors.buttonHoverFill
                ))
                .disabled(!buttonEnabled)
                .opacity(buttonEnabled ? 1 : 0.5)
                .help(help ?? "")
            }
        }
        // As tall as with a button while there's none, so the bar doesn't jump as the download starts.
        .frame(minHeight: 24)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .panelCard(cornerRadius: 10)
        .padding(.horizontal, 10)
    }
}

// MARK: Calendar permission

@MainActor
private struct PermissionPrompt: View {
    @Environment(AppModel.self) private var model
    let authorization: CalendarAuthorization
    var topPadding: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Calendar access needed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelColors.primary)
            } icon: {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(PanelColors.secondary)
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(PanelColors.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Open System Settings") { model.openCalendarPrivacySettings() }
                Button("Check Again") { model.meetingStore.recheckAuthorization() }
            }
            .controlSize(.regular)
            .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard(cornerRadius: 12)
        .padding(.horizontal, 10)
        .padding(.top, topPadding)
    }

    private var message: String {
        switch authorization {
        case .notDetermined:
            return "Join! needs to read your calendars to alert you before meetings. Approve the permission request to continue."
        case .writeOnly:
            return "Join! has write-only access. Grant full calendar access in System Settings › Privacy & Security › Calendars."
        case .denied, .restricted, .authorized:
            return "Grant Join! full calendar access in System Settings › Privacy & Security › Calendars, then come back here."
        }
    }
}
