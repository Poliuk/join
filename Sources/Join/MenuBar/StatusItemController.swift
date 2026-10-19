import AppKit
import SwiftUI
import JoinCore

/// Callbacks from the panel's SwiftUI content to the controller that owns its window.
struct MenuBarPanelContext {
    let naturalHeightChanged: (CGFloat) -> Void
    let showPauseMenu: (NSView) -> Void
    let showAppMenu: (NSView) -> Void
    /// A menu of choices below a button in the panel's content, like a repeating event's Dismiss: shown
    /// the way the header's menus are, so the panel stays open while it's up.
    let showMenu: ([PanelMenuItem], NSView) -> Void
}

/// One choice in a menu the panel's content opens (`MenuBarPanelContext.showMenu`).
struct PanelMenuItem {
    let title: String
    let action: @MainActor () -> Void
}

/// The menu bar item and the panel that drops down from it.
/// The panel is a borderless window sized to its SwiftUI content in both directions (SwiftUI's
/// MenuBarExtra grows but never shrinks), anchored under the item and capped to the screen.
final class StatusItemController: NSObject, NSWindowDelegate {
    private static let maxPanelHeight: CGFloat = 640
    /// Gap between the menu bar and the panel's top edge.
    private static let panelGap: CGFloat = 6
    /// Smallest distance kept between the panel and the screen's edges.
    private static let screenMargin: CGFloat = 8

    private enum KeyCode {
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        // The number row's 1 and 2 and the keypad's, matched by key so ⌘1 and ⌘2 work on layouts like
        // AZERTY, where those keys type "&" and "é".
        static let one: Set<UInt16> = [18, 83]
        static let two: Set<UInt16> = [19, 84]
    }

    /// A menu of ours that is up over the panel (`popUp`).
    private struct OpenMenu {
        /// So closing the panel can close the menu too.
        let menu: NSMenu
        /// Set when another window (an alert, Settings) takes the keyboard while the menu is up.
        var keyTaken = false
    }

    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var panel: MenuBarPanelWindow = makePanel()
    private var naturalHeight: CGFloat = 200
    private var openMenu: OpenMenu?
    private var monitors: [Any] = []
    /// When the panel last closed on its own (outside click, focus change), to tell a click on the
    /// item that already closed it on mouse-down from a click meant to open it.
    private var autoClosedAt = Date.distantPast
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(model: AppModel) {
        self.model = model
        super.init()
        configureButton()

        observeChanges(of: { [model] in
            _ = model.menuBarStatus
            _ = model.preferences.startingSoonPill
        }) { [weak self] in
            self?.updateButton()
        }
        observe(NotificationCenter.default, NSColor.systemColorsDidChangeNotification) { $0.updateButton() }
        observe(NotificationCenter.default, NSApplication.didResignActiveNotification) { $0.closeAutomatically() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.close() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { $0.close() }
        observeWindowsBecomingKey()
        updateButton()
    }

    private var isOpen: Bool { panel.isVisible }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    /// Safe to call while a header menu is open (an alert about to present closes the panel): the menu goes too.
    func close() {
        openMenu?.menu.cancelTrackingWithoutAnimation()
        guard isOpen else { return }
        removeMonitors()
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
    }

    private func open() {
        model.resetClock()
        panel.contentView?.layoutSubtreeIfNeeded()
        updatePanelFrame(reanchoring: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        // The button un-highlights itself when the click that opened the panel ends; set it afterwards.
        DispatchQueue.main.async {
            guard self.isOpen else { return }
            self.statusItem.button?.highlight(true)
        }
    }

    /// Clicking the item opens the panel when it's closed and closes it when it's open.
    @objc private func buttonClicked(_ sender: Any?) {
        if isOpen {
            close()
        } else if Date().timeIntervalSince(autoClosedAt) > 0.4 {
            open()
        }
    }

    /// Closes for a reason other than the item itself: an outside click, a focus or Space change.
    /// A mouse press on the status item is left to `buttonClicked`, which toggles.
    private func closeAutomatically() {
        guard isOpen, !pointerIsOnStatusItem else { return }
        close()
        autoClosedAt = Date()
    }

    private var pointerIsOnStatusItem: Bool {
        guard NSEvent.pressedMouseButtons != 0, let button = statusItem.button, let window = button.window else { return false }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.contains(NSEvent.mouseLocation)
    }

    // MARK: Status item

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(buttonClicked(_:))
        button.font = StatusItemImages.textFont
        button.toolTip = model.isFixture ? "Join! (fixture)" : "Join!"
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let status = model.menuBarStatus
        switch status.kind {
        case .startingSoon:
            button.image = StatusItemImages.pill(text: status.text, style: model.preferences.startingSoonPill)
            button.title = ""
        case .paused:
            button.image = StatusItemImages.symbol("bell.slash")
            button.title = ""
        case .inMeeting(let remaining):
            button.image = StatusItemImages.ring(remaining: remaining)
            button.title = status.text ?? ""
        case .idle, .later, .withinHour:
            button.image = StatusItemImages.symbol("calendar")
            button.title = status.text ?? ""
        }
        button.imagePosition = button.title.isEmpty ? .imageOnly : .imageLeading
        button.setAccessibilityLabel(model.isFixture ? "\(status.accessibilityLabel) (fixture)" : status.accessibilityLabel)
        if isOpen { button.highlight(true) }
    }

    // MARK: Panel window

    /// The callbacks hold the controller weakly: it owns the panel, whose hosting view holds them.
    private func makePanel() -> MenuBarPanelWindow {
        let context = MenuBarPanelContext(
            naturalHeightChanged: { [weak self] height in self?.naturalHeightDidChange(height) },
            showPauseMenu: { [weak self] anchor in
                guard let self else { return }
                popUp(makePauseMenu(), below: anchor)
            },
            showAppMenu: { [weak self] anchor in
                guard let self else { return }
                popUp(makeAppMenu(), below: anchor)
            },
            showMenu: { [weak self] items, anchor in
                guard let self else { return }
                popUp(makeMenu(items), below: anchor)
            }
        )
        let panel = MenuBarPanelWindow(rootView: MenuBarPanelView(context: context).environment(model))
        panel.delegate = self
        return panel
    }

    private func naturalHeightDidChange(_ height: CGFloat) {
        guard abs(height - naturalHeight) > 0.5 else { return }
        naturalHeight = height
        // Resizing the window from inside a SwiftUI layout pass re-enters layout; do it right after.
        DispatchQueue.main.async {
            guard self.isOpen else { return }
            self.updatePanelFrame(reanchoring: false)
        }
    }

    /// Hangs the panel under the status item: top edge anchored, height fitted to the content up to the
    /// space left on screen, nudged sideways to stay on screen. Once open, only the height follows: the
    /// item changes width with its text (pausing shrinks it to a bell), and the panel would jump with it.
    private func updatePanelFrame(reanchoring: Bool) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let width = MenuBarPanelWindow.width
        let top = min(anchor.minY, visible.maxY) - Self.panelGap
        let available = top - visible.minY - Self.screenMargin
        let height = max(80, min(naturalHeight.rounded(.up), Self.maxPanelHeight, available))
        let left = reanchoring || !panel.isVisible ? anchor.minX : panel.frame.minX
        let x = min(max(left, visible.minX + Self.screenMargin), visible.maxX - Self.screenMargin - width)
        let frame = NSRect(x: x.rounded(), y: (top - height).rounded(), width: width, height: height)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Another window took the keyboard (another app, Settings, an alert); a menu of ours doesn't count.
        if openMenu == nil { closeAutomatically() }
    }

    // MARK: Closing on outside clicks and keys

    private func installMonitors() {
        removeMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAutomatically() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated { self?.clickedInApp(windowNumber: windowNumber) }
            return event
        }) {
            monitors.append(local)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let keyCode = event.keyCode
            let windowNumber = event.windowNumber
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            let characters = event.charactersIgnoringModifiers?.lowercased()
            let consumed = MainActor.assumeIsolated {
                self?.handleKey(keyCode: keyCode, windowNumber: windowNumber, modifiers: modifiers, characters: characters) ?? false
            }
            return consumed ? nil : event
        }) {
            monitors.append(keys)
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// A click in another of our windows closes the panel; the status item's own click toggles it instead.
    private func clickedInApp(windowNumber: Int) {
        guard isOpen, windowNumber != panel.windowNumber else { return }
        if let buttonWindow = statusItem.button?.window, buttonWindow.windowNumber == windowNumber { return }
        closeAutomatically()
    }

    private func handleKey(keyCode: UInt16, windowNumber: Int, modifiers: NSEvent.ModifierFlags, characters: String?) -> Bool {
        guard isOpen, windowNumber == panel.windowNumber else { return false }
        if modifiers == .command {
            if KeyCode.one.contains(keyCode) { selectListFilter(.today); return true }
            if KeyCode.two.contains(keyCode) { selectListFilter(.week); return true }
            switch characters {
            case ",": model.openSettings(); return true
            case "q": model.quit(); return true
            case "w": close(); return true
            default: return false
            }
        }
        switch keyCode {
        case KeyCode.escape:
            close()
            return true
        case KeyCode.returnKey, KeyCode.keypadEnter:
            // The starting-soon and now cards open straight to their action.
            switch model.panelContent.hero {
            case .startingSoon(let card), .now(let card):
                guard let action = card.action else { return false }
                model.perform(action)
                return true
            case .next, .nothingToday:
                return false
            }
        default:
            return false
        }
    }

    /// ⌘1 and ⌘2 pick Today or 7 Days, like clicking the switch. When that half can't be picked (the
    /// switch is hidden, or nothing is left today) the panel beeps rather than doing nothing.
    private func selectListFilter(_ filter: PanelListFilter) {
        let state = model.panelContent.filtered(by: model.preferences.panelListFilter)
        let available = state.isShown && (filter == .week || state.isTodayAvailable)
        guard available else { return NSSound.beep() }
        withAnimation(PanelFilterToggle.selectionAnimation(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
            model.preferences.panelListFilter = filter
        }
    }

    // MARK: Menus

    private func makePauseMenu() -> NSMenu {
        let menu = NSMenu()
        if model.isPaused {
            menu.addItem(ClosureMenuItem(title: PauseCopy.resumeTitle) { [model] in model.resume() })
            menu.addItem(.separator())
        }
        for option in PauseOption.allCases {
            menu.addItem(ClosureMenuItem(title: option.title) { [model] in model.pause(option) })
        }
        return menu
    }

    private func makeAppMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: "Settings", keyEquivalent: ",") { [model] in model.openSettings() })
        menu.addItem(ClosureMenuItem(title: "Quit Join!", keyEquivalent: "q") { [model] in model.quit() })
        return menu
    }

    private func makeMenu(_ items: [PanelMenuItem]) -> NSMenu {
        let menu = NSMenu()
        for item in items {
            menu.addItem(ClosureMenuItem(title: item.title, handler: item.action))
        }
        return menu
    }

    /// Opens `menu` just below `anchor`, right edges aligned, like the design's header menus. While it's
    /// up, the panel doesn't close for losing the keyboard to it (`openMenu`).
    private func popUp(_ menu: NSMenu, below anchor: NSView) {
        guard isOpen else { return }
        menu.minimumWidth = 220
        let x = anchor.bounds.maxX - menu.size.width
        let y = anchor.isFlipped ? anchor.bounds.maxY + 4 : anchor.bounds.minY - 4
        openMenu = OpenMenu(menu: menu)
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: anchor)
        let keyTaken = openMenu?.keyTaken ?? false
        openMenu = nil
        guard isOpen else { return }
        // Taking the keyboard back from a window that appeared meanwhile would leave it deaf to Esc and Return.
        if keyTaken, let keyWindow = NSApp.keyWindow, keyWindow !== panel {
            close()
        } else if !panel.isKeyWindow {
            panel.makeKey()
        }
    }

    private func observeWindowsBecomingKey() {
        let token = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, self.openMenu != nil, let window, window !== self.panel, window.level != .popUpMenu else { return }
                self.openMenu?.keyTaken = true
            }
        }
        observers.append((NotificationCenter.default, token))
    }

    // MARK: Helpers

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (StatusItemController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }
}
