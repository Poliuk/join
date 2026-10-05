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
    private var windows: [AlertWindow] = []
    private var session: AlertSession?
    private var showOnAllScreens = true
    private var screenObserver: NSObjectProtocol?

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

    func present(session: AlertSession, showOnAllScreens: Bool) {
        dismiss()
        self.session = session
        self.showOnAllScreens = showOnAllScreens
        buildWindows()
    }

    func update(meetings: [Meeting]) {
        session?.meetings = meetings
    }

    func dismiss() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        session = nil
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
        let screens = showOnAllScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        windows = screens.map { screen in
            let window = AlertWindow(screen: screen, session: session)
            window.onCancel = { session.actions.dismiss() }
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
        for (index, window) in windows.enumerated() {
            if index == 0 {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
    }
}

final class AlertWindow: NSWindow {
    var onCancel: (() -> Void)?

    @MainActor
    init(screen: NSScreen, session: AlertSession) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        setFrame(screen.frame, display: false)
        contentView = NSHostingView(rootView: AlertRootView(session: session).ignoresSafeArea())
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
