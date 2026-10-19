import AppKit
import Observation
import SwiftUI
import JoinCore

/// What a card's SwiftUI content reads from its window: where the pointer is, which AppKit tracks (SwiftUI's
/// hover isn't reliable in a panel that isn't key, in an app that isn't active), and whether the window is key,
/// which only VoiceOver or Full Keyboard Access moving into it makes it.
@Observable
final class NotificationCardWindowState {
    /// The pointer in the content's coordinate space (`NotificationCardView.coordinateSpace`, from the top left),
    /// or nil while it's outside the window.
    var pointer: CGPoint?
    var isKey = false
}

/// One notification card on one screen: a small borderless panel at the top right that never activates Join!
/// and never takes the keyboard on its own, on every Space and over full-screen apps, under the menu bar panel
/// and the full-screen alert. A click doesn't make it key either (`NotificationCardHostingView`); its buttons
/// still work on the first click. The window is the card plus the × at its top left, which sticks out of the
/// card's corner (`closeButtonOverhang`).
final class NotificationCardWindow: NSPanel {
    /// How far the × at the card's top left sticks out of it, above and to the left, so its centre sits on the
    /// card's rounded corner.
    static let closeButtonOverhang: CGFloat = 5

    let card: NotificationCard
    let state = NotificationCardWindowState()
    /// System uptime when the window last became key, for the key monitor's arming delay.
    private(set) var becameKeyUptime: TimeInterval = 0
    /// Called as the pointer comes into the window (true) and leaves it (false).
    var pointerInsideChanged: ((Bool) -> Void)?

    init<Content: View>(card: NotificationCard, content: (NotificationCardWindowState) -> Content) {
        self.card = card
        let cardSize = NSSize(width: NotificationCard.width, height: card.height)
        let size = NSSize(width: cardSize.width + Self.closeButtonOverhang, height: cardSize.height + Self.closeButtonOverhang)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        // The menu bar panel's level: under the menus a card opens (`popUpMenu`) and the full-screen alert
        // (`screenSaver`). `NotificationCardController` orders the menu bar panel back above the cards.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        allowsToolTipsWhenApplicationIsInactive = true
        // Not drawn on a borderless window; VoiceOver and the snapshot hook read it. Never the event's title.
        title = NotificationCard.windowTitle

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        // The card's material behind its content, at the bottom right of the window, under the overhang.
        let background = MenuBarPanelWindow.makeBackground(around: NSView(), size: cardSize)
        background.frame.origin = NSPoint(x: Self.closeButtonOverhang, y: 0)
        container.addSubview(background)
        let hosting = NotificationCardHostingView(rootView: content(state))
        // The window is always exactly the card's size; the content must not resize it.
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.pointerChanged = { [weak self] pointer in self?.pointerDidChange(pointer) }
        container.addSubview(hosting)
        contentView = container
    }

    /// Only VoiceOver or Full Keyboard Access makes it key (`becomesKeyOnlyIfNeeded`): then Return joins and Esc
    /// dismisses (`NotificationCardController`).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        becameKeyUptime = ProcessInfo.processInfo.systemUptime
        state.isKey = true
        closeButtonVisibilityChanged()
    }

    override func resignKey() {
        super.resignKey()
        state.isKey = false
        closeButtonVisibilityChanged()
    }

    private func pointerDidChange(_ pointer: CGPoint?) {
        let wasInside = state.pointer != nil
        state.pointer = pointer
        guard wasInside != (pointer != nil) else { return }
        closeButtonVisibilityChanged()
        pointerInsideChanged?(pointer != nil)
    }

    /// The pointer left while a menu tracked it, so no exit came: the × goes, and with it its shadow.
    /// `pointerInsideChanged` isn't called; the caller holds the cards itself.
    func pointerLeftUnseen() {
        guard state.pointer != nil else { return }
        state.pointer = nil
        closeButtonVisibilityChanged()
    }

    /// The × comes and goes with the pointer and the keyboard: the window's shadow, which follows what it draws,
    /// is worked out again once SwiftUI has drawn the change.
    private func closeButtonVisibilityChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.invalidateShadow()
        }
    }
}

/// The card's content: buttons work on the first click (`FirstMouseHostingView`), a click never makes the panel
/// key, so the keyboard stays with the user's app, and the pointer is tracked whether or not Join! is active.
final class NotificationCardHostingView<Content: View>: FirstMouseHostingView<Content> {
    /// The pointer from the view's top left, or nil once it leaves.
    var pointerChanged: ((CGPoint?) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var needsPanelToBecomeKey: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // `activeAlways`: entered, moved and exited arrive while another app is active too.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        pointerChanged?(topLeftPoint(of: event))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        pointerChanged?(topLeftPoint(of: event))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        pointerChanged?(nil)
    }

    private func topLeftPoint(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }
}
