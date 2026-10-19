import AppKit

/// An NSMenuItem that runs a closure, so menus can be built inline: the menu bar panel's and a notification
/// card's. Nonisolated like NSMenuItem, whose initializers it overrides; AppKit sends `run` on the main thread
/// when the item is chosen.
nonisolated final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        // AppKit sends menu actions on the main thread; this traps if that ever stops being true. The handler
        // is taken out first: it's main-actor isolated, so it's `Sendable`, where this nonisolated item isn't.
        let handler = self.handler
        MainActor.assumeIsolated { handler() }
    }
}
