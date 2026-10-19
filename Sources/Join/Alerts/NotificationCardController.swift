import AppKit
import QuartzCore
import SwiftUI
import JoinCore

/// Join!'s notification cards on screen, for `NotificationCoordinator`, which decides when each comes and goes.
/// Every screen Show on picks (`screens`) gets each card at its top right under the menu bar, one card per meeting,
/// stacked soonest first, at most `NotificationStack.maximumPerScreen` with the rest waiting their turn
/// (`NotificationStack`). While the pointer is over a screen's cards, or one of their menus is up, nothing on that
/// screen comes, goes or moves until half a second after it leaves; only the card answered goes at once. Cards slide
/// in from the right and out again, or only fade with Reduce Motion. A card plays the user's alert sound and is
/// announced to VoiceOver as it first comes on screen. Never takes the keyboard: Return and Esc act only on a card
/// VoiceOver or Full Keyboard Access made key.
final class NotificationCardController {
    private enum Motion {
        static let slideIn: TimeInterval = 0.3
        static let slideOut: TimeInterval = 0.2
        static let reflow: TimeInterval = 0.2
        /// With Reduce Motion: cards fade in and out where they stand, and move without animating.
        static let fade: TimeInterval = 0.2
    }

    /// How long changes stay held after the pointer leaves a screen's cards or their menu closes.
    private static let releaseDelay: TimeInterval = 0.5
    /// Keys are ignored this long after a card becomes key, as on the full-screen alert, so a keystroke meant for
    /// another app can't dismiss a card or join a call.
    private static let keyArmingDelay: TimeInterval = 0.75

    private enum KeyCode {
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
    }

    /// One card that's up or waiting for a slot.
    private struct Entry {
        let card: NotificationCard
        let playsSound: Bool
        /// Whether it has been on a screen yet: its sound and announcement come once, the first time.
        var hasAppeared = false
    }

    /// One target screen's cards, top to bottom, and what holds changes to them.
    private final class ScreenStack {
        let screen: NSScreen
        var windows: [NotificationCardWindow] = []
        var isMenuOpen = false
        /// Pending from when the pointer leaves the cards or a menu closes until changes may go ahead.
        var releaseTimer: Timer?

        init(screen: NSScreen) {
            self.screen = screen
        }

        var isPointerInside: Bool { windows.contains { $0.state.pointer != nil } }
        var isHeld: Bool { isPointerInside || isMenuOpen || releaseTimer != nil }
    }

    /// What the user chose on a card: Join, a snooze, At event start, or Dismiss (the × or the menu). The card
    /// has gone from every screen by then.
    var onAnswer: ((AlertResponse, NotificationCard) -> Void)?
    /// What a card's menu offers, worked out as it opens.
    var makeMenu: ((NotificationCard) -> NotificationMenu)?
    /// Show on: which screens get the cards. The cards up move over at once.
    var screens: AlertScreens = .main {
        didSet {
            if screens != oldValue { rebuild() }
        }
    }

    private var entries: [Entry] = []
    /// One per target screen while any card is up or waiting; picked again once none is.
    private var stacks: [ScreenStack] = []
    private let announcer = NotificationAnnouncer()
    private var screenObserver: NSObjectProtocol?
    private var keyMonitor: Any?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        installKeyMonitor()
    }

    /// The meetings whose cards are up or waiting for a slot.
    var shownMeetingIDs: [Meeting.ID] { entries.map(\.card.id) }

    /// Shows `card` on every target screen, with the user's alert sound when `playsSound`. A card already up for
    /// the same meeting (Test Notification's, clicked again) goes at once, and this one comes as a new card.
    func show(_ card: NotificationCard, playsSound: Bool) {
        if entries.contains(where: { $0.card.id == card.id }) {
            removeAtOnce(card.id)
        }
        entries.append(Entry(card: card, playsSound: playsSound))
        if stacks.isEmpty {
            stacks = screens.targetScreens.map(ScreenStack.init)
        }
        layoutAll()
    }

    /// Closes these meetings' cards: withdrawn, paused, closed automatically. On a screen whose cards are under
    /// the pointer they go once it leaves.
    func close(_ meetingIDs: [Meeting.ID]) {
        let ids = Set(meetingIDs)
        guard entries.contains(where: { ids.contains($0.card.id) }) else { return }
        entries.removeAll { ids.contains($0.card.id) }
        layoutAll()
    }

    // MARK: Answers

    /// The user's choice on `card`: every copy of it goes at once, then the coordinator acts on it. A card that
    /// was withdrawn while the pointer held it on screen still answers, as what's on screen says.
    private func answer(_ response: AlertResponse, card: NotificationCard) {
        let onScreen = stacks.contains { $0.windows.contains { $0.card.id == card.id } }
        guard onScreen || entries.contains(where: { $0.card.id == card.id }) else { return }
        removeAtOnce(card.id)
        layoutAll()
        onAnswer?(response, card)
    }

    /// Opens `card`'s menu below `anchor`, their right edges aligned, and holds its screen's cards while it's up.
    /// Returns once the menu closes, after the choice, if any, has acted.
    private func showMenu(for card: NotificationCard, below anchor: NSView) {
        guard let content = makeMenu?(card) else { return }
        let menu = NSMenu()
        for item in content.snoozes {
            menu.addItem(menuItem(item, for: card))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem(content.dismiss, for: card))
        menu.minimumWidth = NotificationMenu.minimumWidth

        let stack = stacks.first { $0.windows.contains { $0 === anchor.window } }
        stack?.isMenuOpen = true
        let x = anchor.bounds.maxX - menu.size.width
        let y = anchor.isFlipped ? anchor.bounds.maxY + NotificationMenu.gap : anchor.bounds.minY - NotificationMenu.gap
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: anchor)
        guard let stack else { return }
        stack.isMenuOpen = false
        // The windows may have missed the pointer leaving while the menu tracked it.
        let pointer = NSEvent.mouseLocation
        for window in stack.windows where !NSMouseInRect(pointer, window.frame, false) {
            window.state.pointer = nil
        }
        holdBriefly(stack)
    }

    private func menuItem(_ item: NotificationMenuItem, for card: NotificationCard) -> NSMenuItem {
        let menuItem = ClosureMenuItem(title: item.title) { [weak self] in
            self?.answer(item.response, card: card)
        }
        menuItem.toolTip = item.help
        menuItem.setAccessibilityLabel(item.accessibilityLabel)
        return menuItem
    }

    // MARK: Layout

    private func layoutAll() {
        for stack in stacks {
            layout(stack, animated: true)
        }
        dropStacksIfEmpty()
    }

    /// Brings `stack`'s windows in line with the cards: those gone slide out, those given a slot slide in, and the
    /// rest move to their places. Nothing happens while the stack is held.
    private func layout(_ stack: ScreenStack, animated: Bool) {
        guard !stack.isHeld else { return }
        let arranged = NotificationStack.arrange(entries.map(\.card), shown: Set(stack.windows.map(\.card.id))).shown
        let arrangedIDs = Set(arranged.map(\.id))
        var current: [Meeting.ID: NotificationCardWindow] = [:]
        for window in stack.windows {
            if arrangedIDs.contains(window.card.id) {
                current[window.card.id] = window
            } else {
                slideOut(window)
            }
        }

        let offsets = NotificationStack.offsets(heights: arranged.map(\.height))
        stack.windows = zip(arranged, offsets).map { card, offset in
            let frame = Self.frame(for: card, offset: offset, on: stack.screen)
            if let window = current[card.id] {
                move(window, to: frame, animated: animated)
                return window
            }
            let window = makeWindow(for: card, in: stack)
            slideIn(window, to: frame, animated: animated)
            didAppear(card)
            return window
        }
    }

    /// The window's frame for a card `offset` points below the top of the stack: the card's right edge
    /// `NotificationStack.screenMargin` in from the visible frame's (which leaves out a Dock at the right), its
    /// top under the menu bar however it's shown (`NotificationStack.topInset`), with the × overhang above and to
    /// the left.
    private static func frame(for card: NotificationCard, offset: Double, on screen: NSScreen) -> NSRect {
        let inset = NotificationStack.topInset(
            safeAreaTop: screen.safeAreaInsets.top,
            menuBarThickness: NSStatusBar.system.thickness,
            reservedTop: screen.frame.maxY - screen.visibleFrame.maxY
        )
        let overhang = NotificationCardWindow.closeButtonOverhang
        let cardTop = (screen.frame.maxY - inset - offset).rounded()
        let cardRight = (screen.visibleFrame.maxX - NotificationStack.screenMargin).rounded()
        return NSRect(
            x: cardRight - NotificationCard.width - overhang,
            y: cardTop - card.height,
            width: NotificationCard.width + overhang,
            height: card.height + overhang
        )
    }

    private func makeWindow(for card: NotificationCard, in stack: ScreenStack) -> NotificationCardWindow {
        let actions = NotificationCardActions(
            answer: { [weak self] response in self?.answer(response, card: card) },
            showMenu: { [weak self] anchor in self?.showMenu(for: card, below: anchor) }
        )
        let window = NotificationCardWindow(card: card) { state in
            NotificationCardView(card: card, window: state, actions: actions)
        }
        window.pointerInsideChanged = { [weak self, weak stack] inside in
            guard let self, let stack else { return }
            self.pointerInsideChanged(inside, in: stack)
        }
        return window
    }

    /// The first time a card is on screen: its sound, once however many screens show it, and its announcement.
    private func didAppear(_ card: NotificationCard) {
        guard let index = entries.firstIndex(where: { $0.card.id == card.id }), !entries[index].hasAppeared else { return }
        entries[index].hasAppeared = true
        if entries[index].playsSound {
            SystemSounds.playAlertSound()
        }
        announcer.announce(card.announcement(now: Date()))
    }

    /// Takes `meetingID`'s card off every screen now, whatever holds them: the user answered it, or it's being
    /// replaced. A screen the pointer was on, over that card, waits a moment before the others move up, so a
    /// second click doesn't land on the card that takes its place.
    private func removeAtOnce(_ meetingID: Meeting.ID) {
        entries.removeAll { $0.card.id == meetingID }
        for stack in stacks {
            guard let window = stack.windows.first(where: { $0.card.id == meetingID }) else { continue }
            let hadPointer = window.state.pointer != nil
            stack.windows.removeAll { $0 === window }
            slideOut(window)
            if hadPointer { holdBriefly(stack) }
        }
    }

    /// Drops the screens once no card is up or waiting, so the next card picks its screens afresh (Screen with
    /// the pointer).
    private func dropStacksIfEmpty() {
        guard entries.isEmpty, stacks.allSatisfy(\.windows.isEmpty) else { return }
        for stack in stacks {
            stack.releaseTimer?.invalidate()
        }
        stacks = []
    }

    /// Show on changed, or the screens did: every card moves to its place on the screens picked now, without
    /// sliding, sound or announcement.
    private func rebuild() {
        for stack in stacks {
            stack.releaseTimer?.invalidate()
            for window in stack.windows {
                window.orderOut(nil)
                window.close()
            }
        }
        stacks = entries.isEmpty ? [] : screens.targetScreens.map(ScreenStack.init)
        for stack in stacks {
            layout(stack, animated: false)
        }
    }

    // MARK: Holding changes under the pointer

    private func pointerInsideChanged(_ inside: Bool, in stack: ScreenStack) {
        if inside {
            stack.releaseTimer?.invalidate()
            stack.releaseTimer = nil
        } else if !stack.isPointerInside, !stack.isMenuOpen {
            holdBriefly(stack)
        }
    }

    /// Holds `stack` for `releaseDelay`, then lays it out unless the pointer came back meanwhile.
    private func holdBriefly(_ stack: ScreenStack) {
        stack.releaseTimer?.invalidate()
        stack.releaseTimer = Timer.scheduledTimer(withTimeInterval: Self.releaseDelay, repeats: false) { [weak self, weak stack] _ in
            MainActor.assumeIsolated {
                // A stack dropped meanwhile (its last card answered from its menu) has nothing left to lay out.
                guard let self, let stack, self.stacks.contains(where: { $0 === stack }) else { return }
                stack.releaseTimer = nil
                self.layout(stack, animated: true)
                self.dropStacksIfEmpty()
            }
        }
    }

    // MARK: Motion

    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// From just past the screen's right edge, fading in; with Reduce Motion it only fades in.
    private func slideIn(_ window: NotificationCardWindow, to frame: NSRect, animated: Bool) {
        let slides = animated && !reducesMotion
        window.setFrame(slides ? frame.offsetBy(dx: Self.slideDistance, dy: 0) : frame, display: false)
        window.alphaValue = animated ? 0 : 1
        window.orderFrontRegardless()
        keepMenuBarPanelInFront()
        guard animated else { return }
        Self.animate(duration: slides ? Motion.slideIn : Motion.fade, timing: .easeOut) {
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = 1
        }
    }

    /// Out to the right, fading, then closed; with Reduce Motion it only fades. It takes no more clicks meanwhile.
    private func slideOut(_ window: NotificationCardWindow) {
        window.pointerInsideChanged = nil
        window.ignoresMouseEvents = true
        let slides = !reducesMotion
        let frame = window.frame.offsetBy(dx: Self.slideDistance, dy: 0)
        Self.animate(duration: slides ? Motion.slideOut : Motion.fade, timing: .easeIn) {
            if slides { window.animator().setFrame(frame, display: true) }
            window.animator().alphaValue = 0
        } completion: {
            window.orderOut(nil)
            window.close()
        }
    }

    private func move(_ window: NotificationCardWindow, to frame: NSRect, animated: Bool) {
        guard window.frame != frame else { return }
        guard animated, !reducesMotion else {
            window.setFrame(frame, display: true)
            return
        }
        Self.animate(duration: Motion.reflow, timing: .easeInEaseOut) {
            window.animator().setFrame(frame, display: true)
        }
    }

    /// Far enough that a card slides in from beyond the screen's right edge.
    private static var slideDistance: CGFloat {
        NotificationCard.width + NotificationCardWindow.closeButtonOverhang + NotificationStack.screenMargin
    }

    private static func animate(
        duration: TimeInterval,
        timing: CAMediaTimingFunctionName,
        changes: () -> Void,
        completion: (@MainActor () -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: timing)
            changes()
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    /// The menu bar panel shares the cards' level: it stays above a card that comes while it's open.
    private func keepMenuBarPanelInFront() {
        for case let panel as MenuBarPanelWindow in NSApp.windows where panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    // MARK: Keys

    /// A card is key only when VoiceOver or Full Keyboard Access moves into it: then Return joins and Esc
    /// dismisses, as on the full-screen alert, after the same arming delay, and auto-repeats are swallowed.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let windowNumber = event.windowNumber
            let timestamp = event.timestamp
            let isRepeat = event.isARepeat
            let consumed = MainActor.assumeIsolated {
                self?.handleKey(keyCode: keyCode, windowNumber: windowNumber, timestamp: timestamp, isRepeat: isRepeat) ?? false
            }
            return consumed ? nil : event
        }
    }

    /// Returns true when the event must not reach the card's views.
    private func handleKey(keyCode: UInt16, windowNumber: Int, timestamp: TimeInterval, isRepeat: Bool) -> Bool {
        let windows = stacks.flatMap(\.windows)
        guard let window = windows.first(where: { $0.windowNumber == windowNumber }), window.isKeyWindow else { return false }
        if isRepeat || timestamp - window.becameKeyUptime < Self.keyArmingDelay { return true }
        switch keyCode {
        case KeyCode.escape:
            answer(.close, card: window.card)
            return true
        case KeyCode.returnKey, KeyCode.keypadEnter:
            guard window.card.joinURL != nil else { return false }
            answer(.join, card: window.card)
            return true
        default:
            return false
        }
    }
}
