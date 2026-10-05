import AppKit
import Observation
import SwiftUI
import JoinCore

struct AlertActions {
    var dismiss: () -> Void
    var snooze: (TimeInterval) -> Void
    var snoozeUntilEvent: () -> Void
    var join: (Meeting) -> Void
}

/// What one presentation of the alert shows. Shared by every screen's window.
@MainActor
@Observable
final class AlertSession {
    var meetings: [Meeting]
    var appearance: AlertAppearance
    var snoozeDurations: [TimeInterval]
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
@MainActor
final class AlertWindowController {
    /// Keys are ignored this long after the alert appears, so a keystroke the user was already typing
    /// in another app can't dismiss the alert or join a call by accident.
    static let keyArmingDelay: TimeInterval = 0.75

    private enum KeyCode {
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
    }

    private var windows: [AlertWindow] = []
    private var session: AlertSession?
    private var screens: AlertScreens = .all
    private var screenObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    /// System uptime when the alert became key; compared with each key event's own timestamp.
    private var presentedUptime: TimeInterval = .infinity

    init() {
        startObservingScreens()
    }

    private func startObservingScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildIfPresenting() }
        }
    }

    var isPresenting: Bool { session != nil }

    func present(session: AlertSession, screens: AlertScreens) {
        dismiss()
        self.session = session
        self.screens = screens
        buildWindows()
        presentedUptime = ProcessInfo.processInfo.systemUptime
        installKeyMonitor()
    }

    func update(meetings: [Meeting]) {
        session?.meetings = meetings
    }

    func dismiss() {
        removeKeyMonitor()
        presentedUptime = .infinity
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        session = nil
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
        guard let session, windows.contains(where: { $0.windowNumber == windowNumber }) else { return false }
        if isRepeat || timestamp - presentedUptime < Self.keyArmingDelay { return true }
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
        guard session != nil else { return }
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        buildWindows()
    }

    private func buildWindows() {
        guard let session else { return }
        windows = Self.targetScreens(for: screens).map { screen in
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
    @MainActor
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
        contentView = FirstMouseHostingView(rootView: AnyView(AlertRootView(session: session).ignoresSafeArea()))
    }

    override var canBecomeKey: Bool { true }
}

extension AlertWindowController {
    static func targetScreens(for choice: AlertScreens) -> [NSScreen] {
        switch choice {
        case .all:
            return NSScreen.screens
        case .main:
            return [NSScreen.main ?? NSScreen.screens.first].compactMap { $0 }
        case .pointer:
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
            return [screen].compactMap { $0 }
        }
    }
}

/// Lets a click on a window that isn't key (the alert on a secondary display) hit its button directly.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
