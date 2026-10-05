import AppKit
import SwiftUI

/// Hosts the Settings view in a plain AppKit window. SwiftUI's `Settings` scene can't be opened
/// reliably from a menu-bar-only app, so we own the window ourselves.
enum SettingsPane: String, CaseIterable {
    case general
    case calendars
    case appearance
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    /// `pane` nil keeps whichever pane was showing last.
    func show(model: AppModel, pane: SettingsPane? = nil) {
        let window = self.window ?? makeWindow(model: model)
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(model: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Join! Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView().environment(model))
        window.center()
        return window
    }
}
