import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable {
    case general
    case calendars
    case appearance

    var title: String {
        switch self {
        case .general: return "General"
        case .calendars: return "Calendars"
        case .appearance: return "Appearance"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .calendars: return "calendar"
        case .appearance: return "circle.righthalf.filled"
        }
    }
}

/// Hosts Settings in a plain AppKit window with the standard settings toolbar. SwiftUI's `Settings`
/// scene can't be opened reliably from a menu-bar-only app, so we own the window ourselves.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var tabs: SettingsTabViewController?

    /// `pane` nil keeps whichever pane was showing last.
    func show(model: AppModel, pane: SettingsPane? = nil) {
        let isNew = window == nil
        if isNew { makeWindow(model: model) }
        guard let window, let tabs else { return }
        if let pane { tabs.select(pane) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
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
        window.title = tabs.selectedPane.title
        tabs.fitWindowToSelectedPane(animate: false)
        window.center()
        self.tabs = tabs
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        // Ends editing, so a half-typed value is committed the same way as when the field loses focus.
        window?.makeFirstResponder(nil)
    }
}

/// One toolbar item per pane. The window keeps the panes' width and takes the selected pane's
/// height, scrolling only when that doesn't fit on screen.
@MainActor
private final class SettingsTabViewController: NSTabViewController {
    private let panes: [SettingsPane] = SettingsPane.allCases

    init(model: AppModel) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = [.crossfade, .allowUserInteraction]
        for pane in panes {
            let controller = SettingsPaneController(pane: pane, model: model)
            controller.onContentHeightChange = { [weak self, weak controller] in
                guard let self, let controller, controller === self.selectedPaneController else { return }
                self.fitWindowToSelectedPane(animate: true)
            }
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
            item.identifier = pane.rawValue
            addTabViewItem(item)
        }
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

    private var selectedPaneController: SettingsPaneController? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return tabViewItems[selectedTabViewItemIndex].viewController as? SettingsPaneController
    }

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        // Commits a field being edited and keeps focus from jumping to the next pane's first field.
        view.window?.makeFirstResponder(nil)
        super.tabView(tabView, willSelect: tabViewItem)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = selectedPane.title
        fitWindowToSelectedPane(animate: true)
    }

    /// Keeps the window's top edge in place, and the whole window on its screen.
    func fitWindowToSelectedPane(animate: Bool) {
        guard let window = view.window, let pane = selectedPaneController else { return }
        pane.view.layoutSubtreeIfNeeded()
        guard let contentHeight = pane.contentHeight, contentHeight > 0 else { return }

        let chrome = window.frame.height - window.contentLayoutRect.height
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
        let maxContentHeight = visible.map { $0.height - chrome - 40 } ?? contentHeight
        let height = min(contentHeight, max(maxContentHeight, 240)).rounded(.up)
        let size = NSSize(width: SettingsMetrics.paneWidth, height: height)

        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin.x = window.frame.minX
        frame.origin.y = window.frame.maxY - frame.height
        if let visible, frame.minY < visible.minY {
            frame.origin.y = min(visible.minY, visible.maxY - frame.height)
        }
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }
}

/// Hosts one pane's SwiftUI view and reports the height its content wants.
@MainActor
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
        view = hostingView
    }

    @ViewBuilder
    private static func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralTab()
        case .calendars: CalendarsTab()
        case .appearance: AppearanceTab()
        }
    }

    private func contentHeightDidChange(_ height: CGFloat) {
        guard height > 0, height != contentHeight else { return }
        contentHeight = height
        onContentHeightChange?()
    }
}
