import AppKit
import Observation
import SwiftUI
import JoinCore

struct AlertActions {
    let dismiss: () -> Void
    let snooze: (TimeInterval) -> Void
    let snoozeUntilEvent: () -> Void
    let join: (Meeting) -> Void
}

/// What one presentation of the alert shows. Shared by every screen's window. Only the meetings change while
/// it's up, as some of them are dismissed from the panel or leave the calendar.
@Observable
final class AlertSession {
    var meetings: [Meeting]
    let appearance: AlertAppearance
    let snoozeDurations: [TimeInterval]
    let actions: AlertActions
    let isDemo: Bool

    init(meetings: [Meeting], appearance: AlertAppearance, snoozeDurations: [TimeInterval], actions: AlertActions, isDemo: Bool = false) {
        self.meetings = meetings
        self.appearance = appearance
        self.snoozeDurations = snoozeDurations
        self.actions = actions
        self.isDemo = isDemo
    }
}

/// One borderless window per screen, above everything else, including other apps' full-screen Spaces.
final class AlertWindowController {
    /// Keys are ignored this long after the alert appears, so a keystroke the user was already typing
    /// in another app can't dismiss the alert or join a call by accident.
    private static let keyArmingDelay: TimeInterval = 0.75

    private enum KeyCode {
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
    }

    /// The alert on screen.
    private struct Presentation {
        let session: AlertSession
        let screens: AlertScreens
        /// System uptime when the alert became key; compared with each key event's own timestamp.
        let presentedUptime: TimeInterval
    }

    /// nil while no alert is up.
    private var presentation: Presentation?
    private var windows: [AlertWindow] = []
    private var screenObserver: NSObjectProtocol?
    private var keyMonitor: Any?

    init() {
        startObservingScreens()
    }

    private func startObservingScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildIfPresenting() }
        }
    }

    func present(session: AlertSession, screens: AlertScreens) {
        dismiss()
        buildWindows(for: session, on: screens)
        presentation = Presentation(session: session, screens: screens, presentedUptime: ProcessInfo.processInfo.systemUptime)
        installKeyMonitor()
    }

    func update(meetings: [Meeting]) {
        presentation?.session.meetings = meetings
    }

    func dismiss() {
        removeKeyMonitor()
        closeWindows()
        presentation = nil
    }

    /// The alert is a non-activating panel: it takes keyboard focus without making Join! the active
    /// app, which macOS 14+ no longer lets a background app do on its own. Keys are handled here
    /// rather than through SwiftUI shortcuts so Esc and Return work regardless of the responder chain.
    private func installKeyMonitor() {
        removeKeyMonitor()
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

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event must not reach the alert's views.
    /// Auto-repeats and keys pressed before the arming delay elapsed are swallowed, so holding a key
    /// that was already down in another app can neither dismiss the alert nor join a call. After
    /// the delay, keys other than Esc and Return pass through so Full Keyboard Access still works.
    private func handleKey(keyCode: UInt16, windowNumber: Int, timestamp: TimeInterval, isRepeat: Bool) -> Bool {
        guard let presentation, windows.contains(where: { $0.windowNumber == windowNumber }) else { return false }
        if isRepeat || timestamp - presentation.presentedUptime < Self.keyArmingDelay { return true }
        let session = presentation.session
        switch keyCode {
        case KeyCode.escape:
            session.actions.dismiss()
            return true
        case KeyCode.returnKey, KeyCode.keypadEnter:
            if let joinable = session.meetings.first(where: { $0.joinURL != nil }) {
                session.actions.join(joinable)
            }
            return true
        default:
            return false
        }
    }

    private func rebuildIfPresenting() {
        guard let presentation else { return }
        closeWindows()
        buildWindows(for: presentation.session, on: presentation.screens)
    }

    private func closeWindows() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
    }

    private func buildWindows(for session: AlertSession, on screens: AlertScreens) {
        windows = screens.targetScreens.map { screen in
            AlertWindow(screen: screen, session: session)
        }
        for (index, window) in windows.enumerated() {
            if index == 0 {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
    }
}

final class AlertWindow: NSPanel {
    init(screen: NSScreen, session: AlertSession) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        setFrame(screen.frame, display: false)
        let hosting = FirstMouseHostingView(rootView: AnyView(AlertRootView(session: session).ignoresSafeArea()))
        // The window is always exactly its screen; the content must not resize it.
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
}

extension AlertScreens {
    /// The screens this choice picks now, for the full-screen alert and the notification cards. `AlertScreens`
    /// picks by index: `NSScreen.screens` starts with the screen that has the menu bar, the main display.
    /// `NSScreen.main` would be the screen with the key window, which can be a secondary one, say while Join!'s
    /// Settings window sits there.
    var targetScreens: [NSScreen] {
        let screens = NSScreen.screens
        let pointer = NSEvent.mouseLocation
        let pointerIndex = screens.firstIndex { NSMouseInRect(pointer, $0.frame, false) }
        return targetIndices(screenCount: screens.count, pointerScreenIndex: pointerIndex).map { screens[$0] }
    }
}

/// Lets a click on a window that isn't key (the alert on a secondary display) hit its button directly. Not generic:
/// Swift 6.3's optimizer crashes on the deinit of a generic hosting view subclass when the deployment target is
/// below the SDK's (fixed in Swift 6.4).
final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
