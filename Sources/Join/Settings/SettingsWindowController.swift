import AppKit
import SwiftUI
import JoinCore

/// The toolbar's panes, one subject each. The raw values are what the `openSettings` script hook takes.
enum SettingsPane: String, CaseIterable {
    case general
    case calendars
    case fullScreenAlert
    case appearance

    /// Title-style, as macOS toolbar labels are.
    var title: String {
        switch self {
        case .general: return "General"
        case .calendars: return "Calendars"
        case .fullScreenAlert: return "Full-Screen Alert"
        case .appearance: return "Appearance"
        }
    }

    /// The bell is the panel's Pause full-screen alerts symbol.
    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .calendars: return "calendar"
        case .fullScreenAlert: return "bell"
        case .appearance: return "paintpalette"
        }
    }
}

extension NSUserInterfaceItemIdentifier {
    static let settingsWindow = NSUserInterfaceItemIdentifier("settings")
}

/// Hosts Settings in a plain AppKit window with the standard settings toolbar. SwiftUI's `Settings`
/// scene can't be opened reliably from a menu-bar-only app, so we own the window ourselves.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var tabs: SettingsTabViewController?

    /// `pane` nil keeps whichever pane was showing last.
    ///
    /// Puts the window in front of every app's windows, new or already open behind them, then asks for
    /// Join! to become the active app so the window gets the keyboard.
    ///
    /// Since macOS 14 activation is cooperative: `NSApp.activate()` is a request the system may turn
    /// down, and `activate(ignoringOtherApps:)` is deprecated, its flag ignored. Join! is seldom the
    /// active app when Settings opens, since its panel takes the keyboard without activating it. This
    /// used to ask for activation first, while Join! had no window on screen (the panel had just closed),
    /// then call `makeKeyAndOrderFront` alone. When the request was turned down, that left Settings
    /// behind the app in use: from an app that isn't active, it puts the window in front of the app's own
    /// windows only, below the active app's.
    ///
    /// Now `orderFrontRegardless` puts the window in front of every app's windows whatever becomes of
    /// the request, and the request waits for the next turn of the main queue. By then the window is on
    /// screen (the window server doesn't list a window ordered in until the current turn ends, and it
    /// may turn down a request from an app with no window on screen), and a menu that chose Settings
    /// has finished closing. After a click or a key in Join! (the gear menu, ⌘, in the panel) or a
    /// reopen from Finder, the system grants it and the window is key. When it doesn't (a script hook
    /// while the user is in another app), Settings still shows in front, and the first click on it
    /// activates Join!.
    func show(model: AppModel, pane: SettingsPane? = nil) {
        let isNew = window == nil
        if isNew { makeWindow(model: model) }
        guard let window, let tabs else { return }
        if let pane { tabs.select(pane) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.async { NSApp.activate() }
        // Otherwise AppKit focuses the first text field, e.g. the custom minutes, on opening.
        if isNew { window.makeFirstResponder(nil) }
    }

    private func makeWindow(model: AppModel) {
        let tabs = SettingsTabViewController(model: model)
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.backgroundColor = SettingsPalette.window
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.identifier = .settingsWindow
        window.title = tabs.windowTitle
        tabs.fitWindowToSelectedPane()
        window.center()
        self.tabs = tabs
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        // Ends editing, so a half-typed value is committed the same way as when the field loses focus.
        window?.makeFirstResponder(nil)
        // The shared color panel, opened from a color well in Settings, would outlive the window.
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.close() }
    }
}

/// One toolbar item per pane. The window keeps the panes' width and takes the selected pane's
/// height, scrolling only when that doesn't fit on screen.
private final class SettingsTabViewController: NSTabViewController {
    private let panes: [SettingsPane] = SettingsPane.allCases
    private let isFixture: Bool

    init(model: AppModel) {
        isFixture = model.isFixture
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        // Panes switch instantly: no crossfade, and the window takes the new height in one step.
        transitionOptions = []
        for pane in panes {
            let controller = SettingsPaneController(pane: pane, model: model)
            controller.onContentHeightChange = { [weak self, weak controller] in
                guard let self, let controller, controller === self.selectedPaneController else { return }
                self.fitWindowToSelectedPane()
            }
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
            item.identifier = pane.rawValue
            addTabViewItem(item)
        }
        // The window's title is bound to this one. Left nil, it would be the selected pane's.
        title = windowTitle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(_ pane: SettingsPane) {
        guard let index = panes.firstIndex(of: pane) else { return }
        selectedTabViewItemIndex = index
    }

    var selectedPane: SettingsPane {
        selectedPaneController?.pane ?? .general
    }

    var windowTitle: String {
        SettingsOptions.windowTitle(pane: selectedPane.title, isFixture: isFixture)
    }

    private var selectedPaneController: SettingsPaneController? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return tabViewItems[selectedTabViewItemIndex].viewController as? SettingsPaneController
    }

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        // Commits a field being edited and keeps focus from jumping to the next pane's first field.
        view.window?.makeFirstResponder(nil)
        // A pane keeps its views while hidden, but its color well stops taking the shared panel's colors, so
        // the panel would stay open changing nothing.
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.close() }
        super.tabView(tabView, willSelect: tabViewItem)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        title = windowTitle
        view.window?.title = windowTitle
        fitWindowToSelectedPane()
    }

    /// Keeps the window's top edge in place, and the whole window on its screen. Never animated, on a
    /// tab switch or when rows come and go inside a pane.
    func fitWindowToSelectedPane() {
        guard let window = view.window, let pane = selectedPaneController else { return }
        pane.view.layoutSubtreeIfNeeded()
        guard let contentHeight = pane.contentHeight, contentHeight > 0 else { return }

        let chrome = window.frame.height - window.contentLayoutRect.height
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
        var maxContentHeight = visible.map { $0.height - chrome - 40 } ?? contentHeight
        // Fixture runs can pretend the screen is short, to check the scrolling case on a tall display.
        if FixtureCalendarService.scenario != nil,
           let cap = ProcessInfo.processInfo.environment["JOIN_SETTINGS_MAX_HEIGHT"].flatMap(Double.init) {
            maxContentHeight = min(maxContentHeight, cap)
        }
        let height = min(contentHeight, max(maxContentHeight, 240)).rounded(.up)
        let size = NSSize(width: SettingsMetrics.paneWidth, height: height)

        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin.x = window.frame.minX
        frame.origin.y = window.frame.maxY - frame.height
        if let visible, frame.minY < visible.minY {
            frame.origin.y = min(visible.minY, visible.maxY - frame.height)
        }
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
    }
}

/// Hosts one pane's SwiftUI view and reports the height its content wants.
private final class SettingsPaneController: NSViewController {
    let pane: SettingsPane
    private let model: AppModel
    private(set) var contentHeight: CGFloat?
    var onContentHeightChange: (() -> Void)?

    init(pane: SettingsPane, model: AppModel) {
        self.pane = pane
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = pane.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let pane = self.pane
        let root = SettingsPaneScroll(onContentHeightChange: { [weak self] height in
            self?.contentHeightDidChange(height)
        }) {
            Self.content(for: pane)
        }
        .environment(model)

        let hostingView = NSHostingView(rootView: root)
        // The window is sized from the measured content height instead of Auto Layout.
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(x: 0, y: 0, width: SettingsMetrics.paneWidth, height: 400)
        hostingView.autoresizingMask = [.width, .height]
        view = hostingView
    }

    @ViewBuilder
    private static func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralTab()
        case .calendars: CalendarsTab()
        case .fullScreenAlert: FullScreenAlertTab()
        case .appearance: AppearanceTab()
        }
    }

    private var resizeScheduled = false

    /// SwiftUI reports a new height from inside its layout pass. Resizing the window right there
    /// (a clicked style preset adding the Tint strength row) left the window's content view out of
    /// step with its frame by the height change: the pane slid under the toolbar or below a gap.
    /// So the window follows on the next run-loop turn, once per batch of changes.
    private func contentHeightDidChange(_ height: CGFloat) {
        guard height > 0, height != contentHeight else { return }
        contentHeight = height
        guard !resizeScheduled else { return }
        resizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeScheduled = false
            self.onContentHeightChange?()
        }
    }
}
